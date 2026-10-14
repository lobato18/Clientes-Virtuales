#!/bin/bash
# =============================================================
#  crear_usuarios.sh - Alta rápida de usuarios en una OU
#  Uso:  sudo ./crear_usuarios.sh
# =============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "$SCRIPT_DIR/config.sh"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

require_root
command_exists samba-tool || die "samba-tool no está disponible. ¿Ejecutaste dominio.sh?"

OU_NAME="${OU_NAME:-tecnolobato}"

printf "%s\n" "===================================================="
printf "%s\n" "    GESTOR DE ALTA DE USUARIOS - ${DOMAIN}          "
printf "%s\n" "===================================================="

read -r -p "Nombre del nuevo usuario (ej: lobato01): " NEW_USER
[[ -n "$NEW_USER" ]] || die "El nombre de usuario no puede estar vacío."

read -r -s -p "Contraseña para $NEW_USER: " USER_PASS
echo ""

if ! samba-tool ou list 2>/dev/null | grep -qi "OU=${OU_NAME},"; then
    log_info "La OU 'OU=${OU_NAME}' no existe; creándola..."
    samba-tool ou create "OU=${OU_NAME},${BASE_DN}"
fi

log_info "Registrando a '$NEW_USER' en 'OU=${OU_NAME}'..."
if samba-tool user create "$NEW_USER" "$USER_PASS" --userou="OU=${OU_NAME}"; then
    echo "----------------------------------------------------"
    log_ok "El usuario '$NEW_USER' ha sido creado."
    echo "   Ubicación: OU=${OU_NAME},${BASE_DN}"
    echo "----------------------------------------------------"
else
    die "No se pudo crear el usuario. ¿Ya existe o el AD no está activo?"
fi
