#!/bin/bash 

#!/bin/bash

read -p "Introduce el nombre de la VM: " VM_NAME
read -p "Introduce la ruta de la ISO: " ISO_PATH

# 1. Crear el puente y activarlo
sudo ip link add name br0 type bridge
sudo ip link set dev br0 up

sudo dhclient -r enp1s0 2>/dev/null
sudo ip addr flush dev enp1s0

# 2. Esclavizar la interfaz física al puente
sudo ip link set enp1s0 up
sudo ip link set dev enp1s0 master br0

# 3. CRÍTICO: El host ahora debe pedir IP a través del puente
# Esto evita que tu PC se quede sin internet al ejecutar el script.
sudo dhclient br0 

# 4. Crear la VM conectada al bridge
sudo virt-install \
--name "$VM_NAME" \
--ram 4096 \
--vcpus 2 \
--disk size=30,format=qcow2 \
--os-variant win10 \
--network=default,model=e1000e \
--graphics vnc,listen=0.0.0.0,port=5901 \
--noautoconsole \
--cdrom "$ISO_PATH" \
--boot hd,cdrom
