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

**⚠️ Wichtig: Die Verwendung dieses Skripts macht eine Rückgängigmachung schwierig und Snapshot-Backups funktionieren nicht.**

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

### 4. Supabase LXC Auto-Installer ⚠️ **Testphase**

> **⚠️ Warnung: Dieses Skript befindet sich derzeit in der Testphase. Nicht in Produktionsumgebung verwenden!**
> 
> Nur zu Testzwecken verwenden. Datenverlust oder Systemprobleme können auftreten.

Skript zur automatischen Installation der Supabase-Entwicklungsumgebung in einem LXC-Container auf Proxmox VE.

**Installierte Services:**
- **Docker & Docker Compose**: Container-Laufzeitumgebung
- **Dockge** (Port 5001): Docker Compose Stack Web-Management-Tool
- **CloudCmd** (Port 8000): Web-basierter Dateimanager
- **Supabase** (Port 3001, 8001): Open-Source Firebase-Alternative

**Hauptfunktionen:**
- **Vollautomatisiert**: Ein-Klick-Installation mit interaktiver Einrichtung
- **Neueste Versionen**: Automatische Installation der neuesten Komponentenversionen
- **Sicherheit verbessert**: Automatische Firewall-, fail2ban-, Dateiberechtigungseinrichtung
- **Integrationstests**: Automatische Verifizierung und Statusprüfung nach Installation
- **Detaillierte Protokollierung**: Vollständige Installationsprozess-Protokollierung und Fehlerbehebungsanleitung

**Systemanforderungen:**
- Proxmox VE 7.0 oder höher
- Mindestens 8GB RAM (empfohlen)
- Mindestens 50GB Festplattenspeicher (empfohlen)
- Internetverbindung erforderlich

**Ausführung:**
```bash
# ⚠️ Nur in Testumgebung verwenden!
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/supabase_lxc_installer.sh)"
```

**Zugriff nach Installation:**
- Dockge Management Panel: `http://Container-IP:5001`
- CloudCmd Dateimanager: `http://Container-IP:8000`
- Supabase Studio: `http://Container-IP:3001`
- Supabase API: `http://Container-IP:8001`

### 5. LVM-Thin Größenkonfigurations-Tool ⚠️ **IM TEST - NICHT VERWENDEN**
Skript zur Größenänderung von LVM-Verzeichnissen und LVM-thin nach der Proxmox-Installation.

**⚠️ WARNUNG: Dieses Skript befindet sich derzeit im Test und kann Ihr System zerstören. VERWENDEN SIE ES NICHT!**

**Funktionen:**
- **Flexible Größenkonfiguration**: Automatische/benutzerdefinierte/prozentbasierte Größeneinstellungen
- **Root-Volume-Größenänderung**: Sichere Unterstützung für Erweiterung/Verkleinerung
- **LVM-Thin-Rekonfiguration**: Bestehendes Datenvolume als LVM-thin neu erstellen
- **Über-Bereitstellung**: Effiziente Speichernutzung mit 95% Über-Bereitstellung
- **Schrittweise Bestätigung**: Sichere Operation mit Benutzerbestätigung

**Größenkonfigurationsoptionen:**
1. **Automatisch**: Root 20GB, Data verbleibender Speicher
2. **Benutzerdefiniert**: Vom Benutzer angegebene Größen
3. **Prozentsatz**: Root 30%, Data 70%

**Ausführung:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_lvm_thin_setup.sh)"
```

**🚨 KRITISCH: Dieses Skript befindet sich im Test und kann zu Systemdatenverlust führen. NICHT in Produktionsumgebungen verwenden!**

### 5. Proxmox ISO Anpassungs-Tool
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

### 6. Proxmox VE Temperaturüberwachungs-Tool ⚠️ **IM TEST - NICHT VERWENDEN**
Skript zum Hinzufügen von Echtzeit-CPU- und Festplatten-Temperaturüberwachung zum Proxmox VE Dashboard.

**⚠️ WARNUNG: Dieses Skript befindet sich derzeit im Test und kann Ihr System beschädigen. VERWENDEN SIE ES NICHT!**

**Funktionen:**
- **Hardware-Sensor-Erkennung**: Automatische Sensor-Erkennung mit lm-sensors
- **CPU-Temperaturüberwachung**: Echtzeit-CPU-Temperaturanzeige
- **Festplatten-Temperaturüberwachung**: Festplattentemperatur-Anzeige über SMART-Daten
- **Dashboard-Integration**: Temperaturinformationen in Proxmox Web-Interface
- **Automatische Sicherung**: Automatische Sicherung der Originaldateien vor Änderung
- **Sichere Änderung**: Sichere Änderung der Proxmox API und Web-Interface

**Ausführung:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_temperature_monitor.sh)"
```

**🚨 KRITISCH: Dieses Skript befindet sich im Test und ändert Proxmox-Systemdateien. NICHT in Produktionsumgebungen verwenden!**

**Wichtige Hinweise:**
- Funktioniert nur auf physischer Hardware (VMs haben keine Temperatursensoren)
- Ändert Proxmox-Systemdateien (automatische Backups werden erstellt)
- Erfordert Web-Interface-Aktualisierung nach Installation (Ctrl+F5)

---

<a href='https://ko-fi.com/R6R71ILZQL' target='_blank'><img height='36' style='border:0px;height:36px;' src='https://storage.ko-fi.com/cdn/kofi3.png?v=6' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a> 