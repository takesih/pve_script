# Proxmox VE 管理脚本集合
Proxmox VE 环境中可使用的各种管理脚本集合。

<div align="center">
  <h3>🌍 语言选择</h3>
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

## 脚本列表

### 1. VM桥接DHCP配置工具
将vmbr0桥接转换为DHCP模式或从备份恢复的脚本。

**功能：**
- **DHCP转换**：将vmbr0从静态IP转换为DHCP模式
- **备份恢复**：从备份恢复之前的设置
- **自动备份**：更改前自动备份当前设置

**执行方法：**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_vmbr0_dhcp.sh)"
```

### 2. LVM调整大小工具
将local-lvm集成到local中以优化磁盘空间的脚本。

**⚠️ 重要：使用此脚本后难以恢复，且快照备份将无法工作。**

**功能：**
- **LVM集成**：将local-lvm集成到local
- **自动调整大小**：自动扩展根卷
- **安全验证**：操作前检查系统状态

**执行方法：**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_lvm_resize.sh)"
```

### 3. DNSZI DDNS自动更新工具
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

### 4. Supabase LXC自动安装工具 ⚠️ **测试阶段**

> **⚠️ 警告：此脚本目前处于测试阶段。请勿在生产环境中使用！**
> 
> 仅用于测试目的，可能会发生数据丢失或系统问题。

在Proxmox VE的LXC容器中自动安装Supabase开发环境的脚本。

**安装的服务：**
- **Docker & Docker Compose**：容器运行时环境
- **Dockge**（端口5001）：Docker Compose堆栈Web管理工具
- **CloudCmd**（端口8000）：基于Web的文件管理器
- **Supabase**（端口3001, 8001）：开源Firebase替代方案

**主要功能：**
- **完全自动化**：通过交互式设置一键安装
- **最新版本**：自动安装最新组件版本
- **安全增强**：自动防火墙、fail2ban、文件权限设置
- **集成测试**：安装后自动验证和状态检查
- **详细日志**：完整安装过程日志和故障排除指南

**系统要求：**
- Proxmox VE 7.0或更高版本
- 最少8GB RAM（推荐）
- 最少50GB磁盘空间（推荐）
- 需要互联网连接

**执行方法：**
```bash
# ⚠️ 仅在测试环境中使用！
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/supabase_lxc_installer.sh)"
```

**安装后访问：**
- Dockge管理面板：`http://容器IP:5001`
- CloudCmd文件管理：`http://容器IP:8000`
- Supabase Studio：`http://容器IP:3001`
- Supabase API：`http://容器IP:8001`

### 5. Proxmox ISO定制工具
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

<a href='https://ko-fi.com/R6R71ILZQL' target='_blank'><img height='36' style='border:0px;height:36px;' src='https://storage.ko-fi.com/cdn/kofi3.png?v=6' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a> 