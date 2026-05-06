
#!/bin/bash

# --- 1. SELECCIÓN DE INTERFAZ DE RED ---
echo "--- DETECTANDO INTERFACES DISPONIBLES ---"
INTERFACES=($(ls /sys/class/net | grep -v lo))

echo "Interfaces encontradas:"
count=1
for i in "${INTERFACES[@]}"; do
    echo "$count) $i"
    ((count++))
done

echo ""
read -p "Escribe el NOMBRE de la interfaz que quieres usar (ej: br0): " IFACE_NAME

# Validamos que la interfaz existe y tiene IP
IP_SERV=$(ip -4 addr show "$IFACE_NAME" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)

if [ -z "$IP_SERV" ]; then
    echo "❌ Error: La interfaz '$IFACE_NAME' no es válida o no tiene IP asignada."
    exit 1
fi

# LIMPIEZA CRÍTICA: Si usas br0, la interfaz física (enp1s0) no debe tener la misma IP
# Buscamos si IFACE_NAME es un bridge y quién es su interfaz física
if [ -d "/sys/class/net/$IFACE_NAME/bridge" ]; then
    PHYS_IFACE=$(ip link show | grep "master $IFACE_NAME" | awk -F': ' '{print $2}' | head -n1)
    if [ ! -z "$PHYS_IFACE" ]; then
        echo "🧹 Limpiando IPs residuales en interfaz física: $PHYS_IFACE"
        sudo ip addr flush dev "$PHYS_IFACE"
    fi
fi

echo "✅ Interfaz seleccionada: $IFACE_NAME con IP: $IP_SERV"
sleep 1

# --- 2. VARIABLES DEL DOMINIO ---
REALM="TECNOLOBATO.LOCAL"
DOMAIN="TECNOLOBATO"
ADMIN_PASS='TecnoLobato2026!'

echo "--- CONFIGURANDO CONTROLADOR DE DOMINIO (SAMBA AD DC) ---"

# 3. Identidad del sistema
hostnamectl set-hostname servidor
# Limpiamos el archivo hosts para evitar resoluciones antiguas
sed -i "/servidor/d" /etc/hosts
echo "127.0.0.1 localhost" > /etc/hosts
echo "$IP_SERV servidor.$REALM servidor" >> /etc/hosts

# 4. Instalación de paquetes
apt update
DEBIAN_FRONTEND=noninteractive apt install -y samba krb5-config krb5-user smbclient winbind acl attr

# 5. Limpieza previa de Samba
systemctl stop smbd nmbd winbind samba-ad-dc 2>/dev/null
systemctl disable smbd nmbd winbind samba-ad-dc 2>/dev/null
[ -f /etc/samba/smb.conf ] && mv /etc/samba/smb.conf /etc/samba/smb.conf.bak
rm -rf /var/lib/samba/private/*
rm -rf /var/cache/samba/*

# 6. Provisión del Dominio
samba-tool domain provision \
  --server-role=dc --use-rfc2307 --dns-backend=SAMBA_INTERNAL \
  --realm=$REALM --domain=$DOMAIN --adminpass="$ADMIN_PASS" --option="dns forwarder = 8.8.8.8"

# 7. Configuración de Kerberos
ln -sf /var/lib/samba/private/krb5.conf /etc/krb5.conf

# 8. Configuración CRÍTICA de DNS (Resolv.conf)
# Esto permite que el servidor se encuentre a sí mismo
chattr -i /etc/resolv.conf 2>/dev/null
echo "domain $REALM" > /etc/resolv.conf
echo "search $REALM" >> /etc/resolv.conf
echo "nameserver 127.0.0.1" >> /etc/resolv.conf
# Opcional: bloquear para que NetworkManager no lo sobrescriba
# chattr +i /etc/resolv.conf 

# 9. Activación del servicio
systemctl unmask samba-ad-dc
systemctl enable samba-ad-dc
systemctl start samba-ad-dc

# 10. Creación de Objetos (OU y Usuario)
echo "⏳ Esperando 10 segundos a que el AD DC levante..."
sleep 10
samba-tool ou create "OU=tecnolobato,DC=${DOMAIN,,},DC=local" 2>/dev/null
samba-tool user add "usuario_test" "$ADMIN_PASS" --userou="OU=tecnolobato" 2>/dev/null

echo "------------------------------------------------------------"
echo "🚀 ¡DOMINIO LISTO!"
echo "Interfaz activa: $IFACE_NAME | IP: $IP_SERV"
echo "Dominio: $REALM"
echo "------------------------------------------------------------"
echo "⚠️ IMPORTANTE EN WINDOWS:"
echo "1. Cambia el DNS de tu tarjeta de red a: $IP_SERV"
echo "2. Desactiva el Firewall de Windows para la primera prueba."
echo "3. Une el equipo al dominio: $REALM"
echo "------------------------------------------------------------"
