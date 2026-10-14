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
    local reply
    read -r -p "${1:-¿Continuar?} [s/N]: " reply
    [[ "$reply" =~ ^[SsYy]$ ]]
}

# Detecta la interfaz física de salida (default route).
detect_phys_iface() {
    ip -4 route show default 2>/dev/null | awk '{print $5; exit}'
}

# Devuelve la primera IPv4 de una interfaz.
iface_ip() {
    ip -4 addr show "$1" 2>/dev/null \
        | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1
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
        [[ -n "$phys" ]] && ip="$(iface_ip "$phys")"
    fi
    echo "${ip:-127.0.0.1}"
}

# Crea un bridge de forma idempotente y esclaviza la interfaz física.
# Uso: ensure_bridge [bridge] [iface_fisica]
ensure_bridge() {
    local br="${1:-${BRIDGE_IFACE:-br0}}"
    local phys="${2:-${PHYS_IFACE:-}}"

    if [[ -z "$phys" ]]; then
        phys="$(detect_phys_iface)"
    fi
    [[ -n "$phys" ]] || die "No se pudo detectar la interfaz física de red."

    if [[ "$phys" == "$br" ]]; then
        die "La interfaz física y el bridge no pueden ser la misma ('$br')."
    fi

    if ! ip link show "$br" >/dev/null 2>&1; then
        log_info "Creando bridge '$br' sobre '$phys'..."
        ip link add name "$br" type bridge || die "No se pudo crear el bridge."
    else
        log_info "El bridge '$br' ya existe; reutilizándolo."
    fi

    ip link set "$br" up
    ip link set "$phys" up

    if ! ip link show "$phys" | grep -q "master $br"; then
        ip link set "$phys" master "$br" || die "No se pudo esclavizar '$phys'."
    else
        log_info "'$phys' ya está esclavizada a '$br'."
    fi

    # Si el bridge no tiene IP, la hereda de la interfaz física/DHCP.
    if [[ -z "$(iface_ip "$br")" ]]; then
        log_info "Solicitando IP para '$br' vía DHCP..."
        if command_exists dhclient; then
            dhclient -r "$phys" 2>/dev/null || true
            dhclient "$br" || log_warn "dhclient no asignó IP; configura una IP estática."
        else
            log_warn "dhclient no está instalado; asigna una IP a '$br' manualmente."
        fi
    fi

    log_ok "Bridge '$br' listo (IP: $(iface_ip "$br"))"
}

# Dado el nombre de una VM, imprime el puerto VNC TCP (ej: 5901).
vnc_tcp_port() {
    local vm="$1" display port
    display="$(virsh domdisplay "$vm" 2>/dev/null)"
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
        [[ -n "$port" ]] && { echo "$port"; return 0; }
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
