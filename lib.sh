#!/bin/bash
# =============================================================
#  Funciones auxiliares compartidas por todos los scripts.
#  Uso:  source "$(dirname "$0")/lib.sh"
# =============================================================

# Evita que "lib.sh" se ejecute directamente.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "lib.sh es una librería; cárgala con 'source lib.sh'." >&2
    exit 1
fi

# --- Colores (solo si la salida es un terminal) --------------
if [[ -t 1 ]]; then
    C_RESET='\033[0m'; C_RED='\033[0;31m'; C_GREEN='\033[0;32m'
    C_YELLOW='\033[0;33m'; C_BLUE='\033[0;34m'; C_BOLD='\033[1m'
else
    C_RESET=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_BOLD=''
fi

log_info()  { printf "${C_BLUE}[INFO]${C_RESET} %s\n" "$*"; }
log_ok()    { printf "${C_GREEN}[ OK ]${C_RESET} %s\n" "$*"; }
log_warn()  { printf "${C_YELLOW}[WARN]${C_RESET} %s\n" "$*" >&2; }
log_error() { printf "${C_RED}[ERROR]${C_RESET} %s\n" "$*" >&2; }
die()       { log_error "$*"; exit 1; }

# --- Utilidades ----------------------------------------------
require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        die "Este script necesita permisos de root. Ejecútalo con 'sudo $0'."
    fi
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

confirm() {
    # ASSUME_YES=1 fuerza la respuesta afirmativa (modo desatendido).
    if [[ "${ASSUME_YES:-0}" == "1" ]]; then
        return 0
    fi
    local reply
    read -r -p "${1:-¿Continuar?} [s/N]: " reply
    [[ "$reply" =~ ^[SsYy]$ ]]
}

# Detecta la interfaz física de salida (default route).
detect_phys_iface() {
    ip -4 route show default 2>/dev/null | awk '{print $5; exit}' || true
}

# Devuelve la primera IPv4 de una interfaz.
iface_ip() {
    ip -4 addr show "$1" 2>/dev/null \
        | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1 || true
}

# IP del host KVM, para mostrar la URL de VNC.
detect_server_ip() {
    if [[ -n "${SERVER_IP:-}" ]]; then
        echo "$SERVER_IP"
        return
    fi
    local ip phys
    ip="$(iface_ip "${BRIDGE_IFACE:-br0}")"
    if [[ -z "$ip" ]]; then
        phys="$(detect_phys_iface)"
        if [[ -n "$phys" ]]; then
            ip="$(iface_ip "$phys")"
        fi
    fi
    echo "${ip:-127.0.0.1}"
}

# ¿Está NetworkManager en ejecución?
nm_running() {
    command_exists nmcli && \
        [[ "$(nmcli -t -f RUNNING general status 2>/dev/null)" == "running" ]]
}

# Comprueba que hay conectividad tras el cambio.
# Uso: verify_connectivity <ip_objetivo>
verify_connectivity() {
    local target="${1:-}"
    [[ "${VERIFY_CONNECTIVITY:-1}" == "1" ]] || return 0
    [[ -n "$target" ]] || target="$(ip -4 route show default 2>/dev/null | awk '{print $3; exit}')"
    [[ -n "$target" ]] || target="1.1.1.1"
    command_exists ping || return 0
    ping -c1 -W3 "$target" >/dev/null 2>&1
}

# Crea el bridge de forma SEGURA e idempotente.
#   - Reutiliza el bridge si ya existe y tiene IP.
#   - Avisa y pide confirmación si se ejecuta por SSH.
#   - Usa NetworkManager (persistente) o, si no, config manual con rollback.
# Uso: ensure_bridge [bridge] [iface_fisica]
ensure_bridge() {
    local br="${1:-${BRIDGE_IFACE:-br0}}"
    local phys="${2:-${PHYS_IFACE:-}}"

    [[ -n "$phys" ]] || phys="$(detect_phys_iface)"
    [[ -n "$phys" ]] || die "No se pudo detectar la interfaz física de red."
    [[ "$phys" != "$br" ]] || die "La interfaz física y el bridge no pueden ser la misma ('$br')."

    # Idempotencia: si ya está montado y operativo, no tocamos nada.
    if ip link show "$br" >/dev/null 2>&1 && [[ -n "$(iface_ip "$br")" ]]; then
        log_info "El bridge '$br' ya existe y tiene IP ($(iface_ip "$br")); reutilizándolo."
        return 0
    fi

    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        log_warn "Sesión SSH detectada: reconfigurar la red podría cortar tu conexión."
        confirm "¿Continuar igualmente?" || die "Cancelado por el usuario."
    fi

    local backend="${BRIDGE_BACKEND:-auto}"
    if [[ "$backend" == "auto" ]]; then
        if nm_running; then backend="nmcli"; else backend="manual"; fi
    fi

    case "$backend" in
        nmcli)  bridge_via_nmcli "$br" "$phys" ;;
        manual) bridge_manual    "$br" "$phys" ;;
        *)      die "BRIDGE_BACKEND inválido: '$backend' (usa auto|nmcli|manual)." ;;
    esac

    log_ok "Bridge '$br' listo (IP: $(iface_ip "$br"))."
}

# --- Backend NetworkManager (persistente, no pelea con NM) -----
bridge_via_nmcli() {
    local br="$1" phys="$2"
    local port="${br}-port"
    local orig_conn
    orig_conn="$(nmcli -t -g GENERAL.CONNECTION device show "$phys" 2>/dev/null | head -n1)"
    if [[ "$orig_conn" == "--" ]]; then
        orig_conn=""
    fi

    log_info "Creando bridge '$br' con NetworkManager sobre '$phys'..."

    # Evita duplicados si quedaron conexiones de un intento previo.
    nmcli connection delete "$br" "$port" >/dev/null 2>&1 || true

    # 1. El puerto (interfaz física esclavizada al bridge).
    #    Un puerto esclavo no lleva configuración IP propia.
    if ! nmcli connection add type ethernet ifname "$phys" con-name "$port" \
            master "$br" slave-type bridge \
            connection.autoconnect yes >/dev/null; then
        die "No se pudo crear el puerto '$port'."
    fi

    # 2. El bridge (DHCP; hereda la MAC del puerto, así conserva la IP).
    if ! nmcli connection add type bridge ifname "$br" con-name "$br" \
            ipv4.method auto ipv6.method ignore \
            bridge.stp no connection.autoconnect yes >/dev/null; then
        nmcli connection delete "$port" >/dev/null 2>&1 || true
        die "No se pudo crear el bridge '$br'."
    fi

    # 3. Activar y verificar; si falla, revertir a la conexión original.
    log_info "Activando '$br'..."
    if ! nmcli connection up "$br" >/dev/null 2>&1; then
        _bridge_rollback_nm "$br" "$port" "$orig_conn"
        die "No se pudo activar '$br'. Configuración de red restaurada."
    fi

    if ! verify_connectivity; then
        log_warn "Sin conectividad tras crear '$br'."
        _bridge_rollback_nm "$br" "$port" "$orig_conn"
        die "Revertido: la red quedó como estaba."
    fi
}

_bridge_rollback_nm() {
    local br="$1" port="$2" orig_conn="$3"
    log_warn "Revirtiendo el bridge con NetworkManager..."
    nmcli connection down "$br" >/dev/null 2>&1 || true
    nmcli connection delete "$br" "$port" >/dev/null 2>&1 || true
    if [[ -n "$orig_conn" ]]; then
        nmcli connection up "$orig_conn" >/dev/null 2>&1 || true
    fi
}

# --- Backend manual (con conservación de IP/MAC y rollback) ----
bridge_manual() {
    local br="$1" phys="$2"
    local ip_cidr gw mac
    ip_cidr="$(ip -4 -o addr show "$phys" 2>/dev/null | awk '{print $4; exit}')"
    gw="$(ip -4 route show default 2>/dev/null | awk '{print $3; exit}')"
    mac="$(cat "/sys/class/net/$phys/address" 2>/dev/null || true)"

    log_info "Creando bridge '$br' manualmente sobre '$phys'..."
    ip link add name "$br" type bridge || die "No se pudo crear el bridge."
    ip link set "$br" up
    if [[ -n "$mac" ]]; then
        ip link set "$br" address "$mac"
    fi
    ip link set "$phys" up
    ip link set "$phys" master "$br" || {
        ip link del "$br" 2>/dev/null || true
        die "No se pudo esclavizar '$phys'."
    }

    # Conserva la IP y la ruta por defecto en el bridge.
    if [[ -n "$ip_cidr" ]]; then
        ip addr flush dev "$phys"
        ip addr add "$ip_cidr" dev "$br"
    fi
    if [[ -n "$gw" ]]; then
        ip route replace default via "$gw" dev "$br"
    fi

    if ! verify_connectivity "$gw"; then
        log_warn "Sin conectividad; revirtiendo cambios de red..."
        _bridge_rollback_manual "$br" "$phys" "$ip_cidr" "$gw"
        die "Revertido: la red quedó como estaba."
    fi
}

_bridge_rollback_manual() {
    local br="$1" phys="$2" ip_cidr="$3" gw="$4"
    ip route del default 2>/dev/null || true
    ip addr flush dev "$br" 2>/dev/null || true
    ip link set "$phys" nomaster 2>/dev/null || true
    ip link del "$br" 2>/dev/null || true
    if [[ -n "$ip_cidr" ]]; then
        ip addr add "$ip_cidr" dev "$phys"
    fi
    if [[ -n "$gw" ]]; then
        ip route replace default via "$gw" dev "$phys"
    fi
}

# Dado el nombre de una VM, imprime el puerto VNC TCP (ej: 5901).
vnc_tcp_port() {
    local vm="$1" display port
    display="$(virsh domdisplay "$vm" 2>/dev/null || true)"
    port="${display##*:}"
    if [[ "$port" =~ ^[0-9]+$ ]]; then
        if (( port >= 5900 )); then
            echo "$port"
        else
            echo $((5900 + port))
        fi
    fi
}

# Espera a que libvirt conozca el puerto VNC de la VM (hasta 10s).
wait_for_vnc() {
    local vm="$1" port="" i
    for i in {1..10}; do
        port="$(vnc_tcp_port "$vm")"
        if [[ -n "$port" ]]; then
            echo "$port"
            return 0
        fi
        sleep 1
    done
    return 1
}

# Muestra la info de conexión VNC de una VM.
show_vnc_info() {
    local vm="$1" port
    port="$(wait_for_vnc "$vm")" || { log_warn "VNC aún no disponible para '$vm'."; return; }
    log_ok "VM '$vm' lista. VNC -> $(detect_server_ip):${port}  (o display ${port})"
}
