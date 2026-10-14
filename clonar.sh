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

# virt-clone exige que la máquina original esté APAGADA. Si está encendida,
# se apaga (recuerda su estado para reiniciarla al terminar).
ESTADO="$(virsh domstate "$TEMPLATE_NAME")"
WAS_RUNNING=0
if [[ "$ESTADO" == "running" ]]; then
    WAS_RUNNING=1
    log_warn "La plantilla '$TEMPLATE_NAME' está encendida; virt-clone requiere que esté apagada."
    confirm "¿Apagarla ahora para clonar?" || die "Apaga la plantilla manualmente e inténtalo de nuevo."

    virsh shutdown "$TEMPLATE_NAME" >/dev/null 2>&1 || true
    for _ in {1..30}; do
        [[ "$(virsh domstate "$TEMPLATE_NAME" 2>/dev/null)" == "running" ]] || break
        sleep 1
    done
    if [[ "$(virsh domstate "$TEMPLATE_NAME" 2>/dev/null)" == "running" ]]; then
        log_warn "No se apagó por ACPI (tiempo agotado)."
        confirm "¿Forzar apagado (destroy)?" || die "Cancelado."
        virsh destroy "$TEMPLATE_NAME"
    fi
fi

log_info "Clonando '$TEMPLATE_NAME' en '$NEW_VM_NAME'..."
virt-clone \
    --original "$TEMPLATE_NAME" \
    --name "$NEW_VM_NAME" \
    --file "${STORAGE_DIR}/${NEW_VM_NAME}.qcow2"

log_info "Iniciando '$NEW_VM_NAME'..."
virsh start "$NEW_VM_NAME"

if [[ "$WAS_RUNNING" == "1" ]]; then
    virsh start "$TEMPLATE_NAME" >/dev/null 2>&1 || true
    log_info "Plantilla '$TEMPLATE_NAME' reiniciada."
fi

show_vnc_info "$NEW_VM_NAME"
cat <<EOF

${C_YELLOW}Recuerda: cambia el nombre del equipo dentro del sistema invitado
para evitar conflictos de SID/identidad en ${REALM}.${C_RESET}
EOF
