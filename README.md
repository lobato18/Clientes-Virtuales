# Clientes-Virtuales

Infraestructura de red profesional basada en software libre: **Samba 4 AD DC**
(controlador de dominio) sobre **Ubuntu Server** y virtualización de clientes con
**KVM/QEMU + libvirt**, con conectividad directa de capa 2 mediante un **bridge**.

Alternativa de código abierto a Windows Server para centralizar identidades,
DNS y administración jerárquica por Unidades Organizativas (OU).

## 📁 Estructura del repositorio

| Archivo                | Descripción                                                        |
|------------------------|--------------------------------------------------------------------|
| `config.sh`            | **Configuración central** (dominio, contraseñas, rutas, red).      |
| `lib.sh`               | Funciones comunes (logs, bridge, VNC, comprobaciones).             |
| `dominio.sh`           | Configura y provisiona el Samba AD DC.                             |
| `create_vm.sh`         | Crea el bridge y una VM desde una ISO de instalación.              |
| `clonar.sh`            | Clona una VM plantilla con `virt-clone`.                           |
| `crear_cliente.sh`     | Despliega un cliente desde un disco base ya preparado.             |
| `crear_usuarios.sh`    | Alta rápida de usuarios en una OU.                                 |
| `gestion_usuarios.sh`  | Crea una OU (si hace falta) y da de alta un usuario.               |
| `import_iso.sh`        | Extrae kernel/initrd de una ISO para arranque PXE.                 |
| `instruciones`         | Guía de orden de ejecución y resolución de problemas.              |
| `presentacion.html`    | Presentación del proyecto.                                         |

## ⚙️ Configuración

Todos los scripts leen sus variables desde `config.sh`. Para no editar el archivo,
puedes exportar variables antes de ejecutar:

```bash
sudo ADMIN_PASS='OtraClave!' REALM=MIEMPRESA.LOCAL ./dominio.sh
```

Variables principales: `REALM`, `DOMAIN`, `ADMIN_PASS`, `DNS_FORWARDER`,
`BRIDGE_IFACE`, `STORAGE_DIR`, `VM_RAM`, `VM_VCPUS`, `VM_DISK_GB`, `SERVER_IP`.

> ⚠️ **Seguridad:** cambia `ADMIN_PASS` antes de usar en producción. No la dejes
> en texto plano en un repositorio compartido.

## 🚀 Orden de ejecución

```bash
# 1. Provisionar el controlador de dominio (crea el bridge y el AD DC)
sudo ./dominio.sh br0

# 2. Crear la VM maestra/plantilla desde una ISO
sudo ./create_vm.sh

# 3. Clonar la plantilla tantas veces como clientes necesites
sudo ./clonar.sh Windows10_Base Cliente01

# 4. Gestión de identidades
sudo ./crear_usuarios.sh
sudo ./gestion_usuarios.sh
```

## 🌐 1. Configuración del servidor (bridge + dominio)

`dominio.sh`:

1. Detecta/valida la interfaz de red y limpia IPs residuales del bridge.
2. Configura el nombre de host y `/etc/hosts`.
3. Instala `samba`, `krb5`, `winbind`, `samba-ad-provision`, etc.
4. Provisiona el dominio con DNS interno y `dns forwarder`.
5. Enlaza Kerberos y ajusta `/etc/resolv.conf` a `127.0.0.1`.
6. Habilita y arranca `samba-ad-dc`.
7. Crea la OU `tecnolobato` y el usuario `usuario_test` si no existen.

## 🖥️ 2. Automatización de virtualización

La creación del bridge es **idempotente** (`ensure_bridge` en `lib.sh`): si `br0`
ya existe lo reutiliza y solo esclaviza la interfaz física si hace falta, evitando
dejar el host sin red.

| Script             | Uso                                                        |
|--------------------|------------------------------------------------------------|
| `create_vm.sh`     | Crea bridge + VM nueva desde ISO.                          |
| `clonar.sh`        | Clona una plantilla (pausa/reanuda la original si corre).  |
| `crear_cliente.sh` | Copia un disco base y arranca el cliente (`--import`).     |

En todos los casos el script muestra la URL VNC real asignada dinámicamente
(`--graphics vnc,port=-1`).

## 🛠️ 3. Administración del directorio

```bash
# Añadir usuario
sudo samba-tool user create nombre 'Contraseña123!' --userou="OU=tecnolobato"

# Borrar usuario
sudo samba-tool user delete nombre

# Añadir a administradores
sudo samba-tool group addmembers "Domain Admins" nombre

# Crear / eliminar OU
sudo samba-tool ou create "OU=Alumnos,${BASE_DN}"
sudo samba-tool ou delete "OU=Alumnos,${BASE_DN}"
```

## 🔧 Resolución de problemas

- **Sin red tras crear el bridge:** vuelve a ejecutar `ensure_bridge` (vía
  `dominio.sh`) o asigna IP manualmente al bridge.
- **`samba-tool` no encontrado:** ejecuta primero `dominio.sh`.
- **VNC rechazado:** verifica que la VM esté arrancada (`virsh list`) y usa el
  puerto que muestra el script.
- **IPs cambiantes:** define `SERVER_IP` y usa reservas DHCP para que los accesos
  VNC no se rompan.

## 📝 Descripción técnica

Se implementa una alternativa libre a Windows Server con Samba 4 AD DC. La
virtualización KVM/QEMU despliega los clientes y un bridge de red otorga
conectividad de capa 2 a cada VM. La infraestructura centraliza seguridad,
identidades, resolución de nombres (DNS) y administración jerárquica mediante OU,
todo gestionado desde la terminal de Linux.
