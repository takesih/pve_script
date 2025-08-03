# Collection de Scripts de Gestion Proxmox VE
Une collection de divers scripts de gestion pour l'environnement Proxmox VE.

<div align="center">
  <h3>🌍 Sélection de Langue</h3>
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

## Liste des Scripts

### 1. Outil de Configuration DHCP pour Bridge VM
Script pour convertir le bridge vmbr0 en mode DHCP ou restaurer depuis une sauvegarde.

**Fonctionnalités :**
- **Conversion DHCP** : Convertir vmbr0 d'IP statique en mode DHCP
- **Restauration de Sauvegarde** : Restaurer les paramètres précédents depuis la sauvegarde
- **Sauvegarde Automatique** : Sauvegarde automatique des paramètres actuels avant les modifications

**Exécution :**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_vmbr0_dhcp.sh)"
```

### 2. Outil de Redimensionnement LVM
Script pour intégrer local-lvm dans local pour optimiser l'espace disque.

**Fonctionnalités :**
- **Intégration LVM** : Intégrer local-lvm dans local
- **Auto Redimensionnement** : Étendre automatiquement le volume root
- **Vérification de Sécurité** : Vérifier l'état du système avant l'opération

**Exécution :**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_lvm_resize.sh)"
```

### 3. Outil de Mise à Jour Automatique DDNS DNSZI
Script pour configurer la mise à jour automatique DDNS pour le service DNSZI.

**Fonctionnalités :**
- **Installation Automatique** : Installation et configuration automatique du service cron
- **Mise à Jour au Démarrage** : Mise à jour automatique DDNS au démarrage du système
- **Mise à Jour Régulière** : Mise à jour automatique DDNS toutes les 3 heures
- **Suppression Facile** : Fonctionnalité de suppression complète

**Exécution :**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/dnszi_ddns_setup.sh)"
```

### 4. Outil de Configuration LVM-Thin ⚠️ **EN TEST - NE PAS UTILISER**
Script pour convertir LVM existant en LVM-thin ou configurer une nouvelle configuration LVM-thin.

**⚠️ AVERTISSEMENT : Ce script est actuellement en test et peut détruire votre système. NE L'UTILISEZ PAS !**

**Fonctionnalités :**
- **Conversion LVM-Thin** : Convertir automatiquement LVM existant en LVM-thin
- **Nouvelle Configuration** : Créer un nouveau pool et volume LVM-thin
- **Sauvegarde Automatique** : Option pour sauvegarder les données existantes
- **Détection Intelligente** : Détecter si LVM-thin est déjà configuré

**Exécution :**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_lvm_thin_setup.sh)"
```

**🚨 CRITIQUE : Ce script est en test et peut causer une perte de données système. N'UTILISEZ PAS dans des environnements de production !**

### 5. Outil de Personnalisation ISO Proxmox
Script pour intégrer le pilote de carte réseau Realtek R8168 dans l'ISO Proxmox 8.4.

**Fonctionnalités :**
- **Téléchargement ISO** : Téléchargement automatique de l'ISO officiel Proxmox 8.4
- **Intégration de Pilotes** : Intégrer le pilote Realtek R8168 dans initrd
- **Menu de Démarrage** : Créer un menu de démarrage personnalisé
- **Emballage** : Générer un nouveau fichier ISO

**Exécution :**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/proxmox_iso_customize.sh)"
```

---

<a href='https://ko-fi.com/R6R71ILZQL' target='_blank'><img height='36' style='border:0px;height:36px;' src='https://storage.ko-fi.com/cdn/kofi3.png?v=6' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a> 