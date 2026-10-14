#!/bin/bash
# =============================================================
#  gestion_usuarios.sh - Crea una OU (si hace falta) y un usuario
#  Uso:  sudo ./gestion_usuarios.sh
# =============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "$SCRIPT_DIR/config.sh"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

require_root
command_exists samba-tool || die "samba-tool no está disponible. ¿Ejecutaste dominio.sh?"

printf "%s\n" "============================================================"
printf "%s\n" "   GESTOR DE USUARIOS Y UNIDADES ORGANIZATIVAS (SAMBA AD)   "
printf "%s\n" "============================================================"

read -r -p "Nombre de la Unidad Organizativa (ej: Ventas): " OU_NAME
[[ -n "$OU_NAME" ]] || die "El nombre de la OU no puede estar vacío."
OU_DN="OU=${OU_NAME},${BASE_DN}"

if samba-tool ou list 2>/dev/null | grep -qix "OU=${OU_NAME}"; then
    log_warn "La OU '$OU_NAME' ya existe."
    if ! confirm "¿Unir al nuevo usuario a esta OU existente?"; then
        die "Operación cancelada por el usuario."
    fi
else
    log_info "Creando nueva Unidad Organizativa: $OU_NAME..."
    samba-tool ou create "$OU_DN"
    log_ok "OU creada con éxito."
fi

echo "------------------------------------------------------------"

read -r -p "Nombre del nuevo usuario (login): " USER_NAME
[[ -n "$USER_NAME" ]] || die "El nombre de usuario no puede estar vacío."
read -r -s -p "Contraseña para $USER_NAME: " USER_PASS
echo ""

log_info "Creando usuario '$USER_NAME' en '$OU_DN'..."
if samba-tool user create "$USER_NAME" "$USER_PASS" --userou="OU=${OU_NAME}"; then
    echo "------------------------------------------------------------"
    log_ok "¡ÉXITO TOTAL!"
    echo "   Usuario:   $USER_NAME"
    echo "   Ubicación: $OU_DN"
    echo "------------------------------------------------------------"
else
    die "Error al crear el usuario. Revisa que el nombre no esté duplicado."
fi
