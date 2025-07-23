# Proxmox VE 관리 스크립트 모음
Proxmox VE 환경에서 사용할 수 있는 다양한 관리 스크립트 모음입니다.

<div align="center">
  <h3>🌍 언어 선택 / Language Selection / 语言选择 / 言語選択 / Selección de idioma / Sélection de langue / Sprachauswahl / Выбор языка / Seleção de idioma / اختيار اللغة</h3>
  <a href="#korean">🇰🇷 한국어</a> |
  <a href="#english">🇺🇸 English</a> |
  <a href="#chinese">🇨🇳 中文</a> |
  <a href="#japanese">🇯🇵 日本語</a> |
  <a href="#spanish">🇪🇸 Español</a> |
  <a href="#french">🇫🇷 Français</a> |
  <a href="#german">🇩🇪 Deutsch</a> |
  <a href="#russian">🇷🇺 Русский</a> |
  <a href="#portuguese">🇵🇹 Português</a> |
  <a href="#arabic">🇸🇦 العربية</a>
</div>

---

## 🇰🇷 한국어 <a name="korean"></a>

### 스크립트 목록

#### 1. VM Bridge DHCP 설정 도구
vmbr0 브리지를 DHCP 모드로 변환하거나 백업에서 복원하는 스크립트입니다.

**기능:**
- **DHCP 변환**: vmbr0를 정적 IP에서 DHCP 모드로 변환
- **백업 복원**: 이전 설정을 백업에서 복원
- **자동 백업**: 변경 전 자동으로 현재 설정을 백업

**실행 방법:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_vmbr0_dhcp.sh)"
```

#### 2. LVM 리사이즈 도구
local-lvm을 local에 통합하여 디스크 공간을 최적화하는 스크립트입니다.

**기능:**
- **LVM 통합**: local-lvm을 local에 통합
- **자동 리사이즈**: root 볼륨을 자동으로 확장
- **안전 검증**: 작업 전 시스템 상태 확인

**실행 방법:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_lvm_resize.sh)"
```

#### 3. DNSZI DDNS 자동 업데이트 도구
DNSZI 서비스를 위한 DDNS 자동 업데이트를 설정하는 스크립트입니다.

**기능:**
- **자동 설치**: cron 서비스 자동 설치 및 설정
- **부팅 시 업데이트**: 시스템 부팅 시 자동 DDNS 업데이트
- **정기 업데이트**: 3시간마다 자동 DDNS 업데이트
- **간편 제거**: 설정 완전 제거 기능

**실행 방법:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/dnszi_ddns_setup.sh)"
```

#### 4. Proxmox ISO 커스터마이징 도구
Proxmox 8.4 ISO에 Realtek R8168 랜카드 드라이버를 통합하는 스크립트입니다.

**기능:**
- **ISO 다운로드**: 공식 Proxmox 8.4 ISO 자동 다운로드
- **드라이버 통합**: Realtek R8168 드라이버를 initrd에 통합
- **부트 메뉴**: 커스텀 부트 메뉴 생성
- **패키징**: 새로운 ISO 파일 생성

**실행 방법:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/proxmox_iso_customize.sh)"
```

---

## 🇺🇸 English <a name="english"></a>

### Script List

#### 1. VM Bridge DHCP Configuration Tool
Script to convert vmbr0 bridge to DHCP mode or restore from backup.

**Features:**
- **DHCP Conversion**: Convert vmbr0 from static IP to DHCP mode
- **Backup Restoration**: Restore previous settings from backup
- **Auto Backup**: Automatically backup current settings before changes

**Execution:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_vmbr0_dhcp.sh)"
```

#### 2. LVM Resize Tool
Script to integrate local-lvm into local for disk space optimization.

**Features:**
- **LVM Integration**: Integrate local-lvm into local
- **Auto Resize**: Automatically extend root volume
- **Safety Verification**: Check system status before operation

**Execution:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_lvm_resize.sh)"
```

#### 3. DNSZI DDNS Auto Update Tool
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

#### 4. Proxmox ISO Customization Tool
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

## 🇨🇳 中文 <a name="chinese"></a>

### 脚本列表

#### 1. VM桥接DHCP配置工具
将vmbr0桥接转换为DHCP模式或从备份恢复的脚本。

**功能：**
- **DHCP转换**：将vmbr0从静态IP转换为DHCP模式
- **备份恢复**：从备份恢复之前的设置
- **自动备份**：更改前自动备份当前设置

**执行方法：**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_vmbr0_dhcp.sh)"
```

#### 2. LVM调整大小工具
将local-lvm集成到local中以优化磁盘空间的脚本。

**功能：**
- **LVM集成**：将local-lvm集成到local
- **自动调整大小**：自动扩展根卷
- **安全验证**：操作前检查系统状态

**执行方法：**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_lvm_resize.sh)"
```

#### 3. DNSZI DDNS自动更新工具
为DNSZI服务配置DDNS自动更新的脚本。

**功能：**
- **自动安装**：自动安装和配置cron服务
- **启动时更新**：系统启动时自动DDNS更新
- **定期更新**：每3小时自动DDNS更新
- **简易移除**：完全移除功能

**执行方法：**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/dnszi_ddns_setup.sh)"
```

#### 4. Proxmox ISO定制工具
将Realtek R8168网卡驱动程序集成到Proxmox 8.4 ISO中的脚本。

**功能：**
- **ISO下载**：自动下载官方Proxmox 8.4 ISO
- **驱动程序集成**：将Realtek R8168驱动程序集成到initrd
- **启动菜单**：创建自定义启动菜单
- **打包**：生成新的ISO文件

**执行方法：**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/proxmox_iso_customize.sh)"
```

---

## 🇯🇵 日本語 <a name="japanese"></a>

### スクリプト一覧

#### 1. VMブリッジDHCP設定ツール
vmbr0ブリッジをDHCPモードに変換またはバックアップから復元するスクリプトです。

**機能：**
- **DHCP変換**：vmbr0を静的IPからDHCPモードに変換
- **バックアップ復元**：以前の設定をバックアップから復元
- **自動バックアップ**：変更前に現在の設定を自動バックアップ

**実行方法：**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_vmbr0_dhcp.sh)"
```

#### 2. LVMリサイズツール
local-lvmをlocalに統合してディスク容量を最適化するスクリプトです。

**機能：**
- **LVM統合**：local-lvmをlocalに統合
- **自動リサイズ**：rootボリュームを自動拡張
- **安全検証**：作業前にシステム状態を確認

**実行方法：**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_lvm_resize.sh)"
```

#### 3. DNSZI DDNS自動更新ツール
DNSZIサービスのためのDDNS自動更新を設定するスクリプトです。

**機能：**
- **自動インストール**：cronサービスの自動インストールと設定
- **起動時更新**：システム起動時に自動DDNS更新
- **定期更新**：3時間ごとに自動DDNS更新
- **簡単削除**：設定完全削除機能

**実行方法：**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/dnszi_ddns_setup.sh)"
```

#### 4. Proxmox ISOカスタマイズツール
Proxmox 8.4 ISOにRealtek R8168ネットワークカードドライバーを統合するスクリプトです。

**機能：**
- **ISOダウンロード**：公式Proxmox 8.4 ISOの自動ダウンロード
- **ドライバー統合**：Realtek R8168ドライバーをinitrdに統合
- **ブートメニュー**：カスタムブートメニュー作成
- **パッケージング**：新しいISOファイル生成

**実行方法：**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/proxmox_iso_customize.sh)"
```

---

## 🇪🇸 Español <a name="spanish"></a>

### Lista de Scripts

#### 1. Herramienta de Configuración DHCP para Bridge VM
Script para convertir el bridge vmbr0 al modo DHCP o restaurar desde backup.

**Características:**
- **Conversión DHCP**: Convertir vmbr0 de IP estática a modo DHCP
- **Restauración de Backup**: Restaurar configuraciones anteriores desde backup
- **Backup Automático**: Hacer backup automático de la configuración actual antes de cambios

**Ejecución:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_vmbr0_dhcp.sh)"
```

#### 2. Herramienta de Redimensionamiento LVM
Script para integrar local-lvm en local para optimizar el espacio en disco.

**Características:**
- **Integración LVM**: Integrar local-lvm en local
- **Auto Redimensionamiento**: Extender automáticamente el volumen root
- **Verificación de Seguridad**: Verificar estado del sistema antes de la operación

**Ejecución:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_lvm_resize.sh)"
```

#### 3. Herramienta de Actualización Automática DDNS DNSZI
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

#### 4. Herramienta de Personalización ISO Proxmox
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

## 🇫🇷 Français <a name="french"></a>

### Liste des Scripts

#### 1. Outil de Configuration DHCP pour Bridge VM
Script pour convertir le bridge vmbr0 en mode DHCP ou restaurer depuis une sauvegarde.

**Fonctionnalités :**
- **Conversion DHCP** : Convertir vmbr0 d'IP statique en mode DHCP
- **Restauration de Sauvegarde** : Restaurer les paramètres précédents depuis la sauvegarde
- **Sauvegarde Automatique** : Sauvegarde automatique des paramètres actuels avant les modifications

**Exécution :**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_vmbr0_dhcp.sh)"
```

#### 2. Outil de Redimensionnement LVM
Script pour intégrer local-lvm dans local pour optimiser l'espace disque.

**Fonctionnalités :**
- **Intégration LVM** : Intégrer local-lvm dans local
- **Auto Redimensionnement** : Étendre automatiquement le volume root
- **Vérification de Sécurité** : Vérifier l'état du système avant l'opération

**Exécution :**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_lvm_resize.sh)"
```

#### 3. Outil de Mise à Jour Automatique DDNS DNSZI
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

#### 4. Outil de Personnalisation ISO Proxmox
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

## 🇩🇪 Deutsch <a name="german"></a>

### Skriptliste

#### 1. VM Bridge DHCP Konfigurations-Tool
Skript zum Konvertieren des vmbr0-Bridges in den DHCP-Modus oder zur Wiederherstellung aus dem Backup.

**Funktionen:**
- **DHCP-Konvertierung**: vmbr0 von statischer IP in DHCP-Modus konvertieren
- **Backup-Wiederherstellung**: Vorherige Einstellungen aus dem Backup wiederherstellen
- **Automatisches Backup**: Automatisches Backup der aktuellen Einstellungen vor Änderungen

**Ausführung:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_vmbr0_dhcp.sh)"
```

#### 2. LVM Resize-Tool
Skript zur Integration von local-lvm in local zur Optimierung des Festplattenspeichers.

**Funktionen:**
- **LVM-Integration**: local-lvm in local integrieren
- **Auto-Resize**: Root-Volume automatisch erweitern
- **Sicherheitsüberprüfung**: Systemstatus vor der Operation überprüfen

**Ausführung:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_lvm_resize.sh)"
```

#### 3. DNSZI DDNS Auto-Update-Tool
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

#### 4. Proxmox ISO Anpassungs-Tool
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

## 🇷🇺 Русский <a name="russian"></a>

### Список скриптов

#### 1. Инструмент настройки DHCP для VM Bridge
Скрипт для преобразования моста vmbr0 в режим DHCP или восстановления из резервной копии.

**Функции:**
- **Преобразование DHCP**: Преобразование vmbr0 из статического IP в режим DHCP
- **Восстановление из резервной копии**: Восстановление предыдущих настроек из резервной копии
- **Автоматическое резервное копирование**: Автоматическое резервное копирование текущих настроек перед изменениями

**Выполнение:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_vmbr0_dhcp.sh)"
```

#### 2. Инструмент изменения размера LVM
Скрипт для интеграции local-lvm в local для оптимизации дискового пространства.

**Функции:**
- **Интеграция LVM**: Интеграция local-lvm в local
- **Автоматическое изменение размера**: Автоматическое расширение корневого тома
- **Проверка безопасности**: Проверка состояния системы перед операцией

**Выполнение:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_lvm_resize.sh)"
```

#### 3. Инструмент автоматического обновления DDNS DNSZI
Скрипт для настройки автоматического обновления DDNS для сервиса DNSZI.

**Функции:**
- **Автоматическая установка**: Автоматическая установка и настройка сервиса cron
- **Обновление при загрузке**: Автоматическое обновление DDNS при загрузке системы
- **Регулярное обновление**: Автоматическое обновление DDNS каждые 3 часа
- **Простое удаление**: Функция полного удаления

**Выполнение:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/dnszi_ddns_setup.sh)"
```

#### 4. Инструмент настройки ISO Proxmox
Скрипт для интеграции драйвера сетевой карты Realtek R8168 в ISO Proxmox 8.4.

**Функции:**
- **Загрузка ISO**: Автоматическая загрузка официального ISO Proxmox 8.4
- **Интеграция драйверов**: Интеграция драйвера Realtek R8168 в initrd
- **Меню загрузки**: Создание пользовательского меню загрузки
- **Упаковка**: Генерация нового ISO файла

**Выполнение:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/proxmox_iso_customize.sh)"
```

---

## 🇵🇹 Português <a name="portuguese"></a>

### Lista de Scripts

#### 1. Ferramenta de Configuração DHCP para Bridge VM
Script para converter o bridge vmbr0 para modo DHCP ou restaurar do backup.

**Recursos:**
- **Conversão DHCP**: Converter vmbr0 de IP estático para modo DHCP
- **Restauração de Backup**: Restaurar configurações anteriores do backup
- **Backup Automático**: Backup automático das configurações atuais antes das alterações

**Execução:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_vmbr0_dhcp.sh)"
```

#### 2. Ferramenta de Redimensionamento LVM
Script para integrar local-lvm em local para otimizar o espaço em disco.

**Recursos:**
- **Integração LVM**: Integrar local-lvm em local
- **Auto Redimensionamento**: Estender automaticamente o volume root
- **Verificação de Segurança**: Verificar estado do sistema antes da operação

**Execução:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_lvm_resize.sh)"
```

#### 3. Ferramenta de Atualização Automática DDNS DNSZI
Script para configurar a atualização automática DDNS para o serviço DNSZI.

**Recursos:**
- **Instalação Automática**: Instalação e configuração automática do serviço cron
- **Atualização de Inicialização**: Atualização automática DDNS na inicialização do sistema
- **Atualização Regular**: Atualização automática DDNS a cada 3 horas
- **Remoção Fácil**: Funcionalidade de remoção completa

**Execução:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/dnszi_ddns_setup.sh)"
```

#### 4. Ferramenta de Personalização ISO Proxmox
Script para integrar o driver da placa de rede Realtek R8168 no ISO Proxmox 8.4.

**Recursos:**
- **Download ISO**: Download automático do ISO oficial Proxmox 8.4
- **Integração de Drivers**: Integrar driver Realtek R8168 no initrd
- **Menu de Inicialização**: Criar menu de inicialização personalizado
- **Empacotamento**: Gerar novo arquivo ISO

**Execução:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/proxmox_iso_customize.sh)"
```

---

## 🇸🇦 العربية <a name="arabic"></a>

### قائمة البرامج النصية

#### 1. أداة إعداد DHCP لجسر VM
سكريبت لتحويل جسر vmbr0 إلى وضع DHCP أو الاستعادة من النسخة الاحتياطية.

**الميزات:**
- **تحويل DHCP**: تحويل vmbr0 من IP ثابت إلى وضع DHCP
- **استعادة النسخة الاحتياطية**: استعادة الإعدادات السابقة من النسخة الاحتياطية
- **النسخ الاحتياطي التلقائي**: نسخ احتياطي تلقائي للإعدادات الحالية قبل التغييرات

**التنفيذ:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_vmbr0_dhcp.sh)"
```

#### 2. أداة تغيير حجم LVM
سكريبت لدمج local-lvm في local لتحسين مساحة القرص.

**الميزات:**
- **دمج LVM**: دمج local-lvm في local
- **تغيير الحجم التلقائي**: توسيع حجم الجذر تلقائياً
- **التحقق من الأمان**: التحقق من حالة النظام قبل العملية

**التنفيذ:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_lvm_resize.sh)"
```

#### 3. أداة التحديث التلقائي DDNS DNSZI
سكريبت لتكوين التحديث التلقائي DDNS لخدمة DNSZI.

**الميزات:**
- **التثبيت التلقائي**: تثبيت وتكوين تلقائي لخدمة cron
- **تحديث التمهيد**: تحديث DDNS تلقائي عند تشغيل النظام
- **التحديث المنتظم**: تحديث DDNS تلقائي كل 3 ساعات
- **الإزالة السهلة**: وظيفة الإزالة الكاملة

**التنفيذ:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/dnszi_ddns_setup.sh)"
```

#### 4. أداة تخصيص ISO Proxmox
سكريبت لدمج برنامج تشغيل بطاقة الشبكة Realtek R8168 في ISO Proxmox 8.4.

**الميزات:**
- **تحميل ISO**: تحميل تلقائي لـ ISO الرسمي Proxmox 8.4
- **دمج برامج التشغيل**: دمج برنامج تشغيل Realtek R8168 في initrd
- **قائمة التمهيد**: إنشاء قائمة تمهيد مخصصة
- **التعبئة**: إنشاء ملف ISO جديد

**التنفيذ:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/proxmox_iso_customize.sh)"
```



 