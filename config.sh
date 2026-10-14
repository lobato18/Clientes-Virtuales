#!/bin/bash
# =============================================================
#  Configuración central del proyecto Clientes-Virtuales
#  Todos los scripts cargan este archivo. Edítalo o exporta
#  las variables por entorno para no tocar los scripts.
#  Ejemplo:  ADMIN_PASS='OtraClave!' ./dominio.sh
# =============================================================

# --- Dominio / Samba AD DC -----------------------------------
# Realm en MAYÚSCULAS y dominio NetBIOS sin puntos.
export REALM="${REALM:-TECNOLOBATO.LOCAL}"
export DOMAIN="${DOMAIN:-TECNOLOBATO}"
export ADMIN_PASS="${ADMIN_PASS:-TecnoLobato2026!}"
export DNS_FORWARDER="${DNS_FORWARDER:-8.8.8.8}"

# --- Infraestructura de virtualización (KVM/libvirt) ---------
export STORAGE_DIR="${STORAGE_DIR:-/var/lib/libvirt/images}"
export BRIDGE_IFACE="${BRIDGE_IFACE:-br0}"
export PHYS_IFACE="${PHYS_IFACE:-}"

# Backend para crear el bridge: auto (recomendado), nmcli o manual.
export BRIDGE_BACKEND="${BRIDGE_BACKEND:-auto}"
# Verificar conectividad tras crear el bridge y revertir si falla (1/0).
export VERIFY_CONNECTIVITY="${VERIFY_CONNECTIVITY:-1}"
export OS_VARIANT="${OS_VARIANT:-win10}"
export VM_RAM="${VM_RAM:-4096}"
export VM_VCPUS="${VM_VCPUS:-2}"
export VM_DISK_GB="${VM_DISK_GB:-30}"

# IP del host que ejecuta KVM, usada solo para mostrar la URL de VNC.
# Si no se define, se detecta automáticamente en lib.sh.
export SERVER_IP="${SERVER_IP:-}"

# --- PXE -----------------------------------------------------
export TFTP_DIR="${TFTP_DIR:-/var/lib/tftpboot}"
export PXE_ISO_DIR="${PXE_ISO_DIR:-/srv/pxe/isos}"

# --- Derivados (no editar) -----------------------------------
export DOMAIN_LC="${DOMAIN,,}"
export BASE_DN="DC=${DOMAIN_LC},DC=local"
