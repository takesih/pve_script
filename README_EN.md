# Proxmox VE Management Scripts Collection
A collection of various management scripts for Proxmox VE environment.

<div align="center">
  <h3>🌍 Language Selection</h3>
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

## Script List

### 1. VM Bridge DHCP Configuration Tool
Script to convert vmbr0 bridge to DHCP mode or restore from backup.

**Features:**
- **DHCP Conversion**: Convert vmbr0 from static IP to DHCP mode
- **Backup Restoration**: Restore previous settings from backup
- **Auto Backup**: Automatically backup current settings before changes

**Execution:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_vmbr0_dhcp.sh)"
```

### 2. LVM Resize Tool
Script to integrate local-lvm into local for disk space optimization.

**⚠️ Important: Using this script makes it difficult to revert and snapshot backups will not work.**

**Features:**
- **LVM Integration**: Integrate local-lvm into local
- **Auto Resize**: Automatically extend root volume
- **Safety Verification**: Check system status before operation

**Execution:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_lvm_resize.sh)"
```

### 3. DNSZI DDNS Auto Update Tool
Script to configure DDNS automatic update for DNSZI service.

**Features:**
- **Auto Installation**: Automatic cron service installation and configuration
- **Boot Update**: Automatic DDNS update on system boot
- **Regular Update**: Automatic DDNS update every 3 hours
- **Easy Removal**: Complete removal functionality

**Execution:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/dnszi_ddns_setup.sh)"
```

### 4. Supabase LXC Auto Installer ⚠️ **Testing Phase**

> **⚠️ Warning: This script is currently in testing phase. Do not use in production environment!**
> 
> Use for testing purposes only. Data loss or system issues may occur.

Script to automatically install Supabase development environment in LXC container on Proxmox VE.

**Installed Services:**
- **Docker & Docker Compose**: Container runtime environment
- **Dockge** (Port 5001): Docker Compose stack web management tool
- **CloudCmd** (Port 8000): Web-based file manager
- **Supabase** (Port 3001, 8001): Open-source Firebase alternative

**Key Features:**
- **Fully Automated**: One-click installation with interactive setup
- **Latest Versions**: Automatic installation of latest component versions
- **Security Enhanced**: Automatic firewall, fail2ban, file permission setup
- **Integration Testing**: Automatic verification and status check after installation
- **Detailed Logging**: Complete installation process logging and troubleshooting guide

**System Requirements:**
- Proxmox VE 7.0 or higher
- Minimum 8GB RAM (recommended)
- Minimum 50GB disk space (recommended)
- Internet connection required

**Execution:**
```bash
# ⚠️ Use only in testing environment!
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/supabase_lxc_installer.sh)"
```

**Access After Installation:**
- Dockge Management Panel: `http://ContainerIP:5001`
- CloudCmd File Manager: `http://ContainerIP:8000`
- Supabase Studio: `http://ContainerIP:3001`
- Supabase API: `http://ContainerIP:8001`

### 5. Proxmox ISO Customization Tool
Script to integrate Realtek R8168 network card driver into Proxmox 8.4 ISO.

**Features:**
- **ISO Download**: Automatic download of official Proxmox 8.4 ISO
- **Driver Integration**: Integrate Realtek R8168 driver into initrd
- **Boot Menu**: Create custom boot menu
- **Packaging**: Generate new ISO file

**Execution:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/proxmox_iso_customize.sh)"
```



---

<a href='https://ko-fi.com/R6R71ILZQL' target='_blank'><img height='36' style='border:0px;height:36px;' src='https://storage.ko-fi.com/cdn/kofi3.png?v=6' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a> 