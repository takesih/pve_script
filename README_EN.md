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

### 4. Proxmox ISO Customization Tool
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