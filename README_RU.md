# Коллекция скриптов управления Proxmox VE
Коллекция различных скриптов управления для среды Proxmox VE.

<div align="center">
  <h3>🌍 Выбор языка</h3>
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

## Список скриптов

### 1. Инструмент настройки DHCP для VM Bridge
Скрипт для преобразования моста vmbr0 в режим DHCP или восстановления из резервной копии.

**Функции:**
- **Преобразование DHCP**: Преобразование vmbr0 из статического IP в режим DHCP
- **Восстановление из резервной копии**: Восстановление предыдущих настроек из резервной копии
- **Автоматическое резервное копирование**: Автоматическое резервное копирование текущих настроек перед изменениями

**Выполнение:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_vmbr0_dhcp.sh)"
```

### 2. Инструмент изменения размера LVM
Скрипт для интеграции local-lvm в local для оптимизации дискового пространства.

**Функции:**
- **Интеграция LVM**: Интеграция local-lvm в local
- **Автоматическое изменение размера**: Автоматическое расширение корневого тома
- **Проверка безопасности**: Проверка состояния системы перед операцией

**Выполнение:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_lvm_resize.sh)"
```

### 3. Инструмент автоматического обновления DDNS DNSZI
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

### 4. Инструмент настройки ISO Proxmox
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

<a href="https://www.buymeacoffee.com/takesih" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-red.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a> 