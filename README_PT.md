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

**⚠️ Importante: Usar este script torna difícil reverter e backups de snapshot não funcionarão.**

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

### 4. Instalador Automático Supabase LXC ⚠️ **Fase de Teste**

> **⚠️ Aviso: Este script está atualmente em fase de teste. Não usar em ambiente de produção!**
> 
> Usar apenas para fins de teste. Pode ocorrer perda de dados ou problemas no sistema.

Script para instalar automaticamente o ambiente de desenvolvimento Supabase em um contêiner LXC no Proxmox VE.

**Serviços Instalados:**
- **Docker & Docker Compose**: Ambiente de execução de contêineres
- **Dockge** (Porta 5001): Ferramenta de gerenciamento web de stacks Docker Compose
- **CloudCmd** (Porta 8000): Gerenciador de arquivos baseado na web
- **Supabase** (Porta 3001, 8001): Alternativa open-source ao Firebase

**Recursos Principais:**
- **Totalmente Automatizado**: Instalação com um clique com configuração interativa
- **Versões Mais Recentes**: Instalação automática das versões mais recentes dos componentes
- **Segurança Aprimorada**: Configuração automática de firewall, fail2ban, permissões de arquivo
- **Testes de Integração**: Verificação automática e verificação de status após instalação
- **Log Detalhado**: Log completo do processo de instalação e guia de solução de problemas

**Requisitos do Sistema:**
- Proxmox VE 7.0 ou superior
- Mínimo 8GB RAM (recomendado)
- Mínimo 50GB espaço em disco (recomendado)
- Conexão com internet necessária

**Execução:**
```bash
# ⚠️ Usar apenas em ambiente de teste!
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/supabase_lxc_installer.sh)"
```

**Acesso Após Instalação:**
- Painel de Gerenciamento Dockge: `http://IP-Contêiner:5001`
- Gerenciador de Arquivos CloudCmd: `http://IP-Contêiner:8000`
- Supabase Studio: `http://IP-Contêiner:3001`
- Supabase API: `http://IP-Contêiner:8001`

### 5. Ferramenta de Configuração de Tamanho LVM-Thin ⚠️ **EM TESTE - NÃO USAR**
Script para redimensionar diretórios LVM e LVM-thin após a instalação do Proxmox.

**⚠️ AVISO: Este script está atualmente em teste e pode destruir seu sistema. NÃO USE!**

**Recursos:**
- **Configuração de Tamanho Flexível**: Configuração automática/personalizada/baseada em porcentagem
- **Redimensionamento do Volume Root**: Suporte seguro para expansão/redução
- **Reconfiguração LVM-Thin**: Recriar volume de dados existente como LVM-thin
- **Sobre-provisionamento**: Utilização eficiente do espaço com 95% de sobre-provisionamento
- **Confirmação Passo a Passo**: Operação segura com confirmação do usuário

**Opções de Configuração de Tamanho:**
1. **Automático**: Root 20GB, Data espaço restante
2. **Personalizado**: Tamanhos especificados pelo usuário
3. **Porcentagem**: Root 30%, Data 70%

**Execução:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_lvm_thin_setup.sh)"
```

**🚨 CRÍTICO: Este script está em teste e pode causar perda de dados do sistema. NÃO use em ambientes de produção!**

### 5. Ferramenta de Personalização ISO Proxmox
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

### 6. Ferramenta de Monitoramento de Temperatura Proxmox VE ⚠️ **EM TESTE - NÃO USAR**
Script para adicionar monitoramento em tempo real de temperatura de CPU e disco ao painel do Proxmox VE.

**⚠️ AVISO: Este script está atualmente em teste e pode danificar seu sistema. NÃO USE!**

**Recursos:**
- **Detecção de Sensores de Hardware**: Detecção automática de sensores usando lm-sensors
- **Monitoramento de Temperatura CPU**: Exibição em tempo real da temperatura da CPU
- **Monitoramento de Temperatura do Disco**: Exibição da temperatura do disco via dados SMART
- **Integração ao Painel**: Informações de temperatura na interface web do Proxmox
- **Backup Automático**: Backup automático dos arquivos originais antes da modificação
- **Modificação Segura**: Modificação segura da API e interface web do Proxmox

**Execução:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_temperature_monitor.sh)"
```

**🚨 CRÍTICO: Este script está em teste e modifica arquivos do sistema Proxmox. NÃO use em ambientes de produção!**

**Notas Importantes:**
- Funciona apenas em hardware físico (VMs não têm sensores de temperatura)
- Modifica arquivos do sistema Proxmox (backups automáticos são criados)
- Requer atualização da interface web após instalação (Ctrl+F5)

---

<a href='https://ko-fi.com/R6R71ILZQL' target='_blank'><img height='36' style='border:0px;height:36px;' src='https://storage.ko-fi.com/cdn/kofi3.png?v=6' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a> 