# Colección de Scripts de Gestión Proxmox VE
Una colección de varios scripts de gestión para el entorno Proxmox VE.

<div align="center">
  <h3>🌍 Selección de Idioma</h3>
  <a href="README.md">🇰🇷 한국어</a> |
  <a href="README_EN.md">🇺🇸 English</a> |
  <a href="README_CN.md">🇨🇳 中文</a> |
  <a href="README_JP.md">🇯🇵 日本語</a> |
  <a href="README_ES.md">🇪🇸 Español</a> |
  <a href="README_FR.md">🇫🇷 Français</a> |
  <a href="README_DE.md">🇩🇪 Deutsch</a> |
  <a href="README_RU.md">🇷🇺 Русский</a> |
  <a href="README_PT.md">🇵🇹 Português</a> |
  <a href="README_AR.md">🇸🇦 العربية</a>
</div>

---

## Lista de Scripts

### 1. Herramienta de Configuración DHCP para Bridge VM
Script para convertir el bridge vmbr0 al modo DHCP o restaurar desde backup.

**Características:**
- **Conversión DHCP**: Convertir vmbr0 de IP estática a modo DHCP
- **Restauración de Backup**: Restaurar configuraciones anteriores desde backup
- **Backup Automático**: Hacer backup automático de la configuración actual antes de cambios

**Ejecución:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_vmbr0_dhcp.sh)"
```

### 2. Herramienta de Redimensionamiento LVM
Script para integrar local-lvm en local para optimizar el espacio en disco.

**⚠️ Importante: Usar este script hace difícil revertir y las copias de seguridad de instantáneas no funcionarán.**

**Características:**
- **Integración LVM**: Integrar local-lvm en local
- **Auto Redimensionamiento**: Extender automáticamente el volumen root
- **Verificación de Seguridad**: Verificar estado del sistema antes de la operación

**Ejecución:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_lvm_resize.sh)"
```

### 3. Herramienta de Actualización Automática DDNS DNSZI
Script para configurar la actualización automática DDNS para el servicio DNSZI.

**Características:**
- **Instalación Automática**: Instalación y configuración automática del servicio cron
- **Actualización de Arranque**: Actualización automática DDNS al arrancar el sistema
- **Actualización Regular**: Actualización automática DDNS cada 3 horas
- **Eliminación Fácil**: Funcionalidad de eliminación completa

**Ejecución:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/dnszi_ddns_setup.sh)"
```

### 4. Instalador Automático Supabase LXC ⚠️ **Fase de Pruebas**

> **⚠️ Advertencia: Este script está actualmente en fase de pruebas. ¡No usar en entorno de producción!**
> 
> Usar solo para propósitos de prueba. Puede ocurrir pérdida de datos o problemas del sistema.

Script para instalar automáticamente el entorno de desarrollo Supabase en un contenedor LXC en Proxmox VE.

**Servicios Instalados:**
- **Docker & Docker Compose**: Entorno de ejecución de contenedores
- **Dockge** (Puerto 5001): Herramienta de gestión web de stacks Docker Compose
- **CloudCmd** (Puerto 8000): Gestor de archivos basado en web
- **Supabase** (Puerto 3001, 8001): Alternativa de código abierto a Firebase

**Características Principales:**
- **Completamente Automatizado**: Instalación con un clic con configuración interactiva
- **Últimas Versiones**: Instalación automática de las últimas versiones de componentes
- **Seguridad Mejorada**: Configuración automática de firewall, fail2ban, permisos de archivos
- **Pruebas de Integración**: Verificación automática y comprobación de estado después de la instalación
- **Registro Detallado**: Registro completo del proceso de instalación y guía de solución de problemas

**Requisitos del Sistema:**
- Proxmox VE 7.0 o superior
- Mínimo 8GB RAM (recomendado)
- Mínimo 50GB espacio en disco (recomendado)
- Conexión a internet requerida

**Ejecución:**
```bash
# ⚠️ ¡Usar solo en entorno de pruebas!
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/supabase_lxc_installer.sh)"
```

**Acceso Después de la Instalación:**
- Panel de Gestión Dockge: `http://IP-Contenedor:5001`
- Gestor de Archivos CloudCmd: `http://IP-Contenedor:8000`
- Supabase Studio: `http://IP-Contenedor:3001`
- Supabase API: `http://IP-Contenedor:8001`

### 5. Herramienta de Personalización ISO Proxmox
Script para integrar el controlador de tarjeta de red Realtek R8168 en el ISO de Proxmox 8.4.

**Características:**
- **Descarga ISO**: Descarga automática del ISO oficial de Proxmox 8.4
- **Integración de Controladores**: Integrar controlador Realtek R8168 en initrd
- **Menú de Arranque**: Crear menú de arranque personalizado
- **Empaquetado**: Generar nuevo archivo ISO

**Ejecución:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/proxmox_iso_customize.sh)"
```



---

<a href='https://ko-fi.com/R6R71ILZQL' target='_blank'><img height='36' style='border:0px;height:36px;' src='https://storage.ko-fi.com/cdn/kofi3.png?v=6' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a> 