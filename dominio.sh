#!/bin/bash
# =============================================================
#  dominio.sh - Provisiona un Samba AD DC sobre una interfaz dada
#  Uso:  sudo ./dominio.sh [interfaz]
#        sudo BRIDGE_IFACE=br0 ./dominio.sh
# =============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "$SCRIPT_DIR/config.sh"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

require_root

# --- 1. Selección de interfaz de red -------------------------
IFACE_NAME="${1:-${BRIDGE_IFACE:-}}"

if [[ -z "$IFACE_NAME" ]]; then
    log_info "Interfaces disponibles:"
    INTERFACES=()
    for _if in /sys/class/net/*; do
        _name="$(basename "$_if")"
        [[ "$_name" == "lo" ]] || INTERFACES+=("$_name")
    done
    select IFACE_NAME in "${INTERFACES[@]}"; do
        if [[ -n "$IFACE_NAME" ]]; then
            break
        fi
        log_warn "Selección no válida."
    done
fi

IP_SERV="$(iface_ip "$IFACE_NAME")"
[[ -n "$IP_SERV" ]] || die "La interfaz '$IFACE_NAME' no existe o no tiene IP asignada."

# Si es un bridge, limpiamos IPs residuales SOLO si la interfaz física aún
# tiene una IP (si el bridge está bien montado, no debería tener ninguna).
if [[ -d "/sys/class/net/$IFACE_NAME/bridge" ]]; then
    PHYS="$(ip link show | grep "master $IFACE_NAME" | awk -F': ' '{print $2}' | head -n1 || true)"
    if [[ -n "$PHYS" && -n "$(iface_ip "$PHYS")" ]]; then
        log_warn "La interfaz física '$PHYS' tiene IP ($(iface_ip "$PHYS")); la libero (el bridge ya la tiene)."
        ip addr flush dev "$PHYS"
    fi
fi
log_ok "Interfaz seleccionada: $IFACE_NAME ($IP_SERV)"

# --- 2. Configurar identidad del host ------------------------
HOSTNAME_SHORT="servidor"
hostnamectl set-hostname "$HOSTNAME_SHORT"
if ! grep -q "servidor.$REALM" /etc/hosts; then
    sed -i "/[[:space:]]servidor\(\.$REALM\)\?$/d" /etc/hosts 2>/dev/null || true
    printf '127.0.0.1 localhost\n%s %s.%s %s\n' \
        "$IP_SERV" "$HOSTNAME_SHORT" "$REALM" "$HOSTNAME_SHORT" >> /etc/hosts
fi
log_ok "Host configurado como ${HOSTNAME_SHORT}.${REALM}"

# --- 3. Instalación de paquetes ------------------------------
log_info "Instalando Samba AD DC y dependencias..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq samba krb5-config krb5-user smbclient winbind \
    samba-ad-provision python3-samba acl attr

# --- 4. Limpieza previa de Samba -----------------------------
# Salvaguarda: no borrar un dominio ya provisionado sin confirmarlo.
if [[ -f /var/lib/samba/private/sam.ldb ]]; then
    log_warn "Ya existe un dominio provisionado en este equipo."
    log_warn "Continuar RE-PROVISIONARÁ y BORRARÁ la base de datos, usuarios y OUs actuales."
    confirm "¿Reprovisionar el dominio de todos modos?" || die "Cancelado: no se tocó el dominio existente."
fi

systemctl stop smbd nmbd winbind samba-ad-dc 2>/dev/null || true
systemctl disable smbd nmbd winbind 2>/dev/null || true
if [[ -f /etc/samba/smb.conf ]]; then
    mv /etc/samba/smb.conf "/etc/samba/smb.conf.bak.$(date +%Y%m%d%H%M%S)"
fi
rm -rf /var/lib/samba/private/* /var/cache/samba/*

# --- 5. Provisión del dominio --------------------------------
log_info "Provisionando el dominio ${REALM} (${DOMAIN})..."
samba-tool domain provision \
    --server-role=dc \
    --use-rfc2307 \
    --dns-backend=SAMBA_INTERNAL \
    --realm="$REALM" \
    --domain="$DOMAIN" \
    --adminpass="$ADMIN_PASS" \
    --option="dns forwarder = ${DNS_FORWARDER}" \
    --option="bind interfaces only = yes" \
    --option="interfaces = lo ${IFACE_NAME}"

# --- 6. Kerberos ---------------------------------------------
ln -sf /var/lib/samba/private/krb5.conf /etc/krb5.conf

# --- 7. DNS / resolv.conf ------------------------------------
chattr -i /etc/resolv.conf 2>/dev/null || true
{
    echo "domain $REALM"
    echo "search $REALM"
    echo "nameserver 127.0.0.1"
} > /etc/resolv.conf

# --- 8. Activar el servicio ----------------------------------
systemctl unmask samba-ad-dc
systemctl enable samba-ad-dc
systemctl start samba-ad-dc

# --- 9. Crear OU y usuario de prueba -------------------------
log_info "Esperando a que el AD DC arranque..."
sleep 10

OU_NAME="tecnolobato"
if ! samba-tool ou list 2>/dev/null | grep -qix "OU=${OU_NAME}"; then
    samba-tool ou create "OU=${OU_NAME},${BASE_DN}"
    log_ok "OU 'OU=${OU_NAME}' creada."
else
    log_info "La OU 'OU=${OU_NAME}' ya existe."
fi

if ! samba-tool user list 2>/dev/null | grep -qx "usuario_test"; then
    samba-tool user create "usuario_test" "$ADMIN_PASS" --userou="OU=${OU_NAME}"
    log_ok "Usuario 'usuario_test' creado."
else
    log_info "El usuario 'usuario_test' ya existe."
fi

# --- 10. Resumen ---------------------------------------------
cat <<EOF

${C_GREEN}${C_BOLD}🚀 ¡DOMINIO LISTO!${C_RESET}
  Interfaz : $IFACE_NAME
  IP       : $IP_SERV
  Dominio  : $REALM
  Base DN  : $BASE_DN

${C_YELLOW}⚠️  Pasos en el cliente Windows:${C_RESET}
  1. Configura el DNS de la tarjeta de red en: $IP_SERV
  2. Desactiva el firewall de Windows para la primera prueba.
  3. Une el equipo al dominio: $REALM

EOF
