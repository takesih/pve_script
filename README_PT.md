# Coleção de Scripts de Gerenciamento Proxmox VE
Uma coleção de vários scripts de gerenciamento para o ambiente Proxmox VE.

<div align="center">
  <h3>🌍 Seleção de Idioma</h3>
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

### 1. Ferramenta de Configuração DHCP para Bridge VM
Script para converter o bridge vmbr0 para modo DHCP ou restaurar do backup.

**Recursos:**
- **Conversão DHCP**: Converter vmbr0 de IP estático para modo DHCP
- **Restauração de Backup**: Restaurar configurações anteriores do backup
- **Backup Automático**: Backup automático das configurações atuais antes das alterações

**Execução:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_vmbr0_dhcp.sh)"
```

### 2. Ferramenta de Redimensionamento LVM
Script para integrar local-lvm em local para otimizar o espaço em disco.

**Recursos:**
- **Integração LVM**: Integrar local-lvm em local
- **Auto Redimensionamento**: Estender automaticamente o volume root
- **Verificação de Segurança**: Verificar estado do sistema antes da operação

**Execução:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_lvm_resize.sh)"
```

### 3. Ferramenta de Atualização Automática DDNS DNSZI
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

### 4. Ferramenta de Personalização ISO Proxmox
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

<script type="text/javascript" src="https://cdnjs.buymeacoffee.com/1.0.0/button.prod.min.js" data-name="bmc-button" data-slug="takesih" data-color="#FF5F5F" data-emoji=""  data-font="Cookie" data-text="Buy me a coffee" data-outline-color="#000000" data-font-color="#ffffff" data-coffee-color="#FFDD00" ></script> 