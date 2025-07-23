# Proxmox VE Verwaltungsskripte Sammlung
Eine Sammlung verschiedener Verwaltungsskripte für die Proxmox VE Umgebung.

<div align="center">
  <h3>🌍 Sprachauswahl</h3>
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

## Skriptliste

### 1. VM Bridge DHCP Konfigurations-Tool
Skript zum Konvertieren des vmbr0-Bridges in den DHCP-Modus oder zur Wiederherstellung aus dem Backup.

**Funktionen:**
- **DHCP-Konvertierung**: vmbr0 von statischer IP in DHCP-Modus konvertieren
- **Backup-Wiederherstellung**: Vorherige Einstellungen aus dem Backup wiederherstellen
- **Automatisches Backup**: Automatisches Backup der aktuellen Einstellungen vor Änderungen

**Ausführung:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_vmbr0_dhcp.sh)"
```

### 2. LVM Resize-Tool
Skript zur Integration von local-lvm in local zur Optimierung des Festplattenspeichers.

**Funktionen:**
- **LVM-Integration**: local-lvm in local integrieren
- **Auto-Resize**: Root-Volume automatisch erweitern
- **Sicherheitsüberprüfung**: Systemstatus vor der Operation überprüfen

**Ausführung:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_lvm_resize.sh)"
```

### 3. DNSZI DDNS Auto-Update-Tool
Skript zur Konfiguration der automatischen DDNS-Aktualisierung für den DNSZI-Service.

**Funktionen:**
- **Automatische Installation**: Automatische Installation und Konfiguration des Cron-Services
- **Boot-Update**: Automatische DDNS-Aktualisierung beim Systemstart
- **Regelmäßige Updates**: Automatische DDNS-Aktualisierung alle 3 Stunden
- **Einfache Entfernung**: Vollständige Entfernungsfunktionalität

**Ausführung:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/dnszi_ddns_setup.sh)"
```

### 4. Proxmox ISO Anpassungs-Tool
Skript zur Integration des Realtek R8168 Netzwerkadapter-Treibers in das Proxmox 8.4 ISO.

**Funktionen:**
- **ISO-Download**: Automatischer Download des offiziellen Proxmox 8.4 ISO
- **Treiber-Integration**: Realtek R8168-Treiber in initrd integrieren
- **Boot-Menü**: Benutzerdefiniertes Boot-Menü erstellen
- **Verpackung**: Neues ISO-Datei generieren

**Ausführung:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/proxmox_iso_customize.sh)"
```

---

<script type="text/javascript" src="https://cdnjs.buymeacoffee.com/1.0.0/button.prod.min.js" data-name="bmc-button" data-slug="takesih" data-color="#FF5F5F" data-emoji=""  data-font="Cookie" data-text="Buy me a coffee" data-outline-color="#000000" data-font-color="#ffffff" data-coffee-color="#FFDD00" ></script> 