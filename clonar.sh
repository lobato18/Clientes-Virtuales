#!/bin/bash

# Configuración de rutas
STORAGE_DIR="/var/lib/libvirt/images"
SERVER_IP="172.16.230.20"  # Tu IP del servidor Samba/KVM

echo "=== SISTEMA DE CLONACIÓN RÁPIDA DE CLIENTES ==="

# 1. Datos de entrada
read -p "Introduce el nombre de la VM PLANTILLA (la que ya existe): " TEMPLATE_NAME
read -p "Introduce el nombre para el NUEVO CLIENTE: " NEW_VM_NAME

# Verificar si la plantilla existe
if ! sudo virsh dominfo "$TEMPLATE_NAME" > /dev/null 2>&1; then
    echo "ERROR: La plantilla '$TEMPLATE_NAME' no existe."
    exit 1
fi

# 2. Clonación automática con virt-clone
echo "Clonando $TEMPLATE_NAME en $NEW_VM_NAME..."

# virt-clone se encarga de copiar el disco (.qcow2) y crear el nuevo XML
sudo virt-clone \
  --original "$TEMPLATE_NAME" \
  --name "$NEW_VM_NAME" \
  --file "$STORAGE_DIR/$NEW_VM_NAME.qcow2"

# 3. Iniciar la nueva máquina
echo "Iniciando $NEW_VM_NAME..."
sudo virsh start "$NEW_VM_NAME"

# 4. Obtener puerto VNC para conectar
# Buscamos el puerto dinámico que asigna KVM
PORT_DISPLAY=$(sudo virsh domdisplay "$NEW_VM_NAME" | cut -d: -f3)

echo "-----------------------------------------------"
echo "¡VM CLONADA CON ÉXITO!"
echo "1. Conéctate por VNC a: $SERVER_IP:$PORT_DISPLAY"
echo "2. RECUERDA: Cambia el nombre del equipo dentro de Windows"
echo "   para evitar conflictos de SID en tecnolobato.one"
echo "-----------------------------------------------"
