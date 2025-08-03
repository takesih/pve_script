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

### 4. Herramienta de Configuración de Tamaño LVM-Thin ⚠️ **EN PRUEBAS - NO USAR**
Script para redimensionar directorios LVM y LVM-thin después de la instalación de Proxmox.

**⚠️ ADVERTENCIA: Este script está actualmente en pruebas y puede destruir su sistema. ¡NO LO USE!**

**Características:**
- **Configuración de Tamaño Flexible**: Configuración automática/personalizada/basada en porcentajes
- **Redimensionamiento de Volumen Root**: Soporte seguro para expansión/reducción
- **Reconfiguración LVM-Thin**: Recrear volumen de datos existente como LVM-thin
- **Sobre-aprovisionamiento**: Utilización eficiente del espacio con 95% de sobre-aprovisionamiento
- **Confirmación Paso a Paso**: Operación segura con confirmación del usuario

**Opciones de Configuración de Tamaño:**
1. **Automático**: Root 20GB, Data espacio restante
2. **Personalizado**: Tamaños especificados por el usuario
3. **Porcentaje**: Root 30%, Data 70%

**Ejecución:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_lvm_thin_setup.sh)"
```

**🚨 CRÍTICO: Este script está en pruebas y puede causar pérdida de datos del sistema. ¡NO use en entornos de producción!**

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