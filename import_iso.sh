#!/bin/bash
# =============================================================
#  import_iso.sh - Extrae kernel/initrd de una ISO al arranque PXE
#  Uso:  sudo ./import_iso.sh /ruta/a/la.iso nombre_os
# =============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "$SCRIPT_DIR/config.sh"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

require_root

ISO_PATH="${1:-}"
OS_NAME="${2:-}"
if [[ -z "$ISO_PATH" || -z "$OS_NAME" ]]; then
    echo "Uso: sudo $0 /ruta/a/la.iso nombre_os"
    exit 1
fi
[[ -f "$ISO_PATH" ]] || die "No existe la ISO: $ISO_PATH"
command_exists tftp >/dev/null 2>&1 || true

MOUNT_POINT="/mnt/iso_tmp"
TARGET_DIR="${TFTP_DIR}/${OS_NAME}"
mkdir -p "$MOUNT_POINT" "$TARGET_DIR"

cleanup() { mountpoint -q "$MOUNT_POINT" && umount "$MOUNT_POINT" || true; }
trap cleanup EXIT

log_info "Montando la ISO..."
mount -o loop,ro "$ISO_PATH" "$MOUNT_POINT"

log_info "Extrayendo kernel e initrd..."
VMLINUZ="$(find "$MOUNT_POINT" -name 'vmlinuz*' -print -quit)"
INITRD="$(find "$MOUNT_POINT" -name 'initrd*' -print -quit)"
[[ -n "$VMLINUZ" ]] || die "No se encontró 'vmlinuz' dentro de la ISO."
[[ -n "$INITRD" ]] || die "No se encontró 'initrd' dentro de la ISO."

cp "$VMLINUZ" "$TARGET_DIR/vmlinuz"
cp "$INITRD" "$TARGET_DIR/initrd"

MENU_FILE="${TFTP_DIR}/pxelinux.cfg/default"
mkdir -p "$(dirname "$MENU_FILE")"
if [[ ! -f "$MENU_FILE" ]]; then
    cat > "$MENU_FILE" <<EOF
DEFAULT menu.c32
PROMPT 0
TIMEOUT 300
ONTIMEOUT local

MENU TITLE --- Menu de Instalacion PXE ---
EOF
fi

SERVER_IP="$(detect_server_ip)"
{
    echo ""
    echo "LABEL $OS_NAME"
    echo "    MENU LABEL Instalar $OS_NAME"
    echo "    KERNEL $OS_NAME/vmlinuz"
    echo "    APPEND initrd=$OS_NAME/initrd boot=casper netboot=nfs nfsroot=${SERVER_IP}:${PXE_ISO_DIR}/${OS_NAME}"
} >> "$MENU_FILE"

log_ok "$OS_NAME añadido al servidor PXE (nfsroot=${SERVER_IP}:${PXE_ISO_DIR}/${OS_NAME})."
