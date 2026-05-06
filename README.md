# Clientes-Virtuales
Este proyecto consiste en el diseño, despliegue y administración de una infraestructura de red profesional basada en software libre, combinando virtualización de alto rendimiento con servicios de directorio activo corporativo.
🚀 Proyecto: Infraestructura de Red con Samba AD DC y Virtualización KVM

Este documento recoge la configuración completa, scripts de automatización y procedimientos de administración para un entorno de red basado en Ubuntu Server, gestionando identidades mediante Samba 4 y máquinas virtuales mediante KVM.
🌐 1. Configuración del Servidor (Bridge y Dominio)

Este script (dominio_final.sh) configura automáticamente la red en modo puente, instala los requisitos y provisiona el dominio.
Bash

#!/bin/bash
# --- 1. CONFIGURACIÓN AUTOMÁTICA DE RED (BRIDGE) ---
PHYS_IFACE=$(ip -4 route | grep default | awk '{print $5}' | head -n1)
IP_ACTUAL=$(ip -4 addr show "$PHYS_IFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)
GW_ACTUAL=$(ip -4 route | grep default | awk '{print $3}' | head -n1)

echo "🌐 Configurando Bridge br0 sobre $PHYS_IFACE..."
sudo ip link add name br0 type bridge 2>/dev/null
sudo ip link set br0 up
sudo ip addr flush dev "$PHYS_IFACE"
sudo ip link set "$PHYS_IFACE" master br0
sudo ip addr add "$IP_ACTUAL/24" dev br0
sudo ip route add default via "$GW_ACTUAL" dev br0

# --- 2. PREPARACIÓN DEL ENTORNO ---
REALM="TECNOLOBATO.LOCAL"
DOMAIN="TECNOLOBATO"
ADMIN_PASS='TecnoLobato2026!'

echo "🛑 Desactivando servicios que bloquean el puerto 53..."
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved
sudo rm -f /etc/resolv.conf
echo "nameserver 127.0.0.1" > /etc/resolv.conf
echo "search $REALM" >> /etc/resolv.conf

# --- 3. INSTALACIÓN Y PROVISIÓN ---
echo "⚙️ Instalando Samba AD DC y esquemas necesarios..."
sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt install -y samba krb5-config krb5-user smbclient winbind samba-ad-provision python3-samba

sudo systemctl stop smbd nmbd winbind samba-ad-dc 2>/dev/null
sudo rm -f /etc/samba/smb.conf
sudo rm -rf /var/lib/samba/private/*

echo "🔨 Proviniendo el dominio..."
sudo samba-tool domain provision \
  --server-role=dc \
  --use-rfc2307 \
  --dns-backend=SAMBA_INTERNAL \
  --realm="$REALM" \
  --domain="$DOMAIN" \
  --adminpass="$ADMIN_PASS" \
  --option="dns forwarder = 8.8.8.8" \
  --option="bind interfaces only = yes" \
  --option="interfaces = lo br0"

# --- 4. ARRANQUE Y PERSISTENCIA ---
sudo ln -sf /var/lib/samba/private/krb5.conf /etc/krb5.conf
sudo systemctl unmask samba-ad-dc
sudo systemctl enable samba-ad-dc
sudo systemctl start samba-ad-dc

echo "✅ TODO LISTO. IP del Servidor: $IP_ACTUAL"

🖥️ 2. Automatización de Virtualización (Clonación)

Script (clonar.sh) para duplicar estaciones de trabajo de forma segura.
Bash

#!/bin/bash
echo "Máquinas virtuales detectadas:"
sudo virsh list --all

read -p "Introduce el nombre de la VM a clonar: " VM_ORIGINAL
read -p "Introduce el nombre para la nueva VM: " VM_NUEVA

ESTADO=$(sudo virsh domstate "$VM_ORIGINAL")

if [ "$ESTADO" = "running" ]; then
    echo "⚠️ Pausando VM para clonar..."
    sudo virsh suspend "$VM_ORIGINAL"
fi

sudo virt-clone \
  --original "$VM_ORIGINAL" \
  --name "$VM_NUEVA" \
  --file /var/lib/libvirt/images/"$VM_NUEVA".qcow2

if [ "$ESTADO" = "running" ]; then
    sudo virsh resume "$VM_ORIGINAL"
fi
echo "✅ Clonación finalizada."

🛠️ 3. Guía de Administración del Directorio
Gestión de Usuarios y Grupos

    Añadir Usuario:
    sudo samba-tool user add "nombre" "Contraseña123!"

      

    Borrar Usuario:
    sudo samba-tool user delete "nombre"

      

    Asignar Administrador:
    sudo samba-tool group addmembers "Domain Admins" "nombre"

      

Unidades Organizativas (OU)

    Crear OU:
    sudo samba-tool ou create "OU=Alumnos,DC=TECNOLOBATO,DC=LOCAL"

      

    Eliminar OU:
    sudo samba-tool ou delete "OU=Alumnos,DC=TECNOLOBATO,DC=LOCAL"

      

📝 4. Descripción Técnica del Proyecto

Este proyecto implementa una alternativa de código abierto a Windows Server mediante Samba 4 AD DC[cite: 1]. Utiliza virtualización KVM/QEMU para el despliegue de clientes, optimizando el uso de recursos mediante un Bridge de red que otorga conectividad directa a nivel de capa 2 a cada VM[cite: 1].

La infraestructura centraliza la seguridad, las identidades y la resolución de nombres (DNS), permitiendo la administración jerárquica mediante Unidades Organizativas y el control total desde la terminal de Linux[cite: 1].
