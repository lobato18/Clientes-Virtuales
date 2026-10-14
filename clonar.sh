#!/bin/bash
# =============================================================
#  clonar.sh - Clona una VM plantilla con virt-clone
#  Uso:  sudo ./clonar.sh [plantilla] [nueva]
# =============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "$SCRIPT_DIR/config.sh"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

require_root
command_exists virt-clone || die "virt-clone no está instalado (paquete virtinst)."

echo "=== SISTEMA DE CLONACIÓN RÁPIDA DE CLIENTES ==="
echo "Máquinas virtuales detectadas:"
virsh list --all

TEMPLATE_NAME="${1:-}"
NEW_VM_NAME="${2:-}"
[[ -n "$TEMPLATE_NAME" ]] || read -r -p "Nombre de la VM PLANTILLA: " TEMPLATE_NAME
[[ -n "$NEW_VM_NAME" ]] || read -r -p "Nombre para el NUEVO CLIENTE: " NEW_VM_NAME

virsh dominfo "$TEMPLATE_NAME" >/dev/null 2>&1 \
    || die "La plantilla '$TEMPLATE_NAME' no existe."
if virsh dominfo "$NEW_VM_NAME" >/dev/null 2>&1; then
    die "Ya existe una VM llamada '$NEW_VM_NAME'."
fi

# Pausa la plantilla para obtener una copia consistente.
ESTADO="$(virsh domstate "$TEMPLATE_NAME")"
if [[ "$ESTADO" == "running" ]]; then
    log_info "Pausando la plantilla para clonar de forma consistente..."
    virsh suspend "$TEMPLATE_NAME"
fi

cleanup() {
    if [[ "$ESTADO" == "running" ]]; then
        virsh resume "$TEMPLATE_NAME" 2>/dev/null || true
    fi
}
trap cleanup EXIT

log_info "Clonando '$TEMPLATE_NAME' en '$NEW_VM_NAME'..."
virt-clone \
    --original "$TEMPLATE_NAME" \
    --name "$NEW_VM_NAME" \
    --file "${STORAGE_DIR}/${NEW_VM_NAME}.qcow2"

log_info "Iniciando '$NEW_VM_NAME'..."
virsh start "$NEW_VM_NAME"

show_vnc_info "$NEW_VM_NAME"
cat <<EOF

${C_YELLOW}Recuerda: cambia el nombre del equipo dentro del sistema invitado
para evitar conflictos de SID/identidad en ${REALM}.${C_RESET}
EOF
