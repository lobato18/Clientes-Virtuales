#!/bin/bash
# =============================================================
#  create_vm.sh - Crea el bridge y una VM desde una ISO
#  Uso:  sudo ./create_vm.sh
# =============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "$SCRIPT_DIR/config.sh"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

require_root
command_exists virt-install || die "virt-install no está instalado (paquete virtinst)."

read -r -p "Introduce el nombre de la VM: " VM_NAME
[[ -n "$VM_NAME" ]] || die "El nombre de la VM no puede estar vacío."

read -r -p "Introduce la ruta de la ISO: " ISO_PATH
[[ -f "$ISO_PATH" ]] || die "No existe el archivo ISO: $ISO_PATH"

if command_exists virsh && virsh dominfo "$VM_NAME" >/dev/null 2>&1; then
    die "Ya existe una VM llamada '$VM_NAME'."
fi

# 1. Bridge idempotente (no rompe la red si ya existe).
ensure_bridge "${BRIDGE_IFACE}" "${PHYS_IFACE}"

# 2. Crear la VM conectada al bridge.
DISK_PATH="${STORAGE_DIR}/${VM_NAME}.qcow2"
DISK_SPEC="path=${DISK_PATH},size=${VM_DISK_GB},format=qcow2"

log_info "Creando la VM '$VM_NAME'..."
virt-install \
    --name "$VM_NAME" \
    --ram "$VM_RAM" \
    --vcpus "$VM_VCPUS" \
    --disk "$DISK_SPEC" \
    --os-variant "$OS_VARIANT" \
    --network bridge="${BRIDGE_IFACE}",model=e1000e \
    --graphics vnc,listen=0.0.0.0,port=-1 \
    --noautoconsole \
    --cdrom "$ISO_PATH" \
    --boot hd,cdrom

show_vnc_info "$VM_NAME"
