#!/bin/bash
# =============================================================
#  crear_cliente.sh - Despliega un cliente desde un disco base
#  Uso:  sudo ./crear_cliente.sh
# =============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "$SCRIPT_DIR/config.sh"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

require_root
command_exists virt-install || die "virt-install no está instalado (paquete virtinst)."

TEMPLATE="${TEMPLATE:-/srv/pxe/templates/windows10_base.qcow2}"

echo "=== SISTEMA DE DESPLIEGUE RÁPIDO DE CLIENTES ==="

read -r -p "Nombre del nuevo cliente: " VM_NAME
[[ -n "$VM_NAME" ]] || die "El nombre no puede estar vacío."

if virsh dominfo "$VM_NAME" >/dev/null 2>&1; then
    die "Ya existe una VM llamada '$VM_NAME'."
fi
[[ -f "$TEMPLATE" ]] || die "No existe el disco base: $TEMPLATE"

read -r -p "IP para anotar (ej: 172.16.2.80, opcional): " VM_IP

log_info "Copiando disco base..."
cp "$TEMPLATE" "${STORAGE_DIR}/${VM_NAME}.qcow2"

ensure_bridge "${BRIDGE_IFACE}" "${PHYS_IFACE}"

log_info "Creando la VM '$VM_NAME'..."
virt-install \
    --name "$VM_NAME" \
    --ram "$VM_RAM" \
    --vcpus "$VM_VCPUS" \
    --disk path="${STORAGE_DIR}/${VM_NAME}.qcow2",format=qcow2 \
    --os-variant "$OS_VARIANT" \
    --network bridge="${BRIDGE_IFACE}",model=e1000 \
    --graphics vnc,listen=0.0.0.0,port=-1 \
    --import \
    --noautoconsole

show_vnc_info "$VM_NAME"
if [[ -n "$VM_IP" ]]; then
    echo "IP configurada para el cliente: $VM_IP"
fi
