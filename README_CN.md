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

### 4. LVM-Thin大小配置工具 ⚠️ **测试中 - 禁止使用**
Proxmox安装完成后调整LVM目录和LVM-thin大小的脚本。

**⚠️ 警告：此脚本目前正在测试中，可能会破坏您的系统。请勿使用！**

**功能：**
- **灵活的大小配置**：自动/自定义/百分比基础的大小设置
- **根卷调整大小**：安全的扩展/收缩支持
- **LVM-Thin重新配置**：将现有数据卷重新创建为LVM-thin
- **过度配置**：95%过度配置实现高效空间利用
- **分步确认**：通过用户确认进行安全操作

**大小配置选项：**
1. **自动设置**：根卷20GB，数据卷剩余空间
2. **自定义设置**：用户指定大小
3. **百分比设置**：根卷30%，数据卷70%

**执行方法：**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_lvm_thin_setup.sh)"
```

**🚨 重要：此脚本正在测试中，可能导致系统数据丢失。请勿在生产环境中使用！**

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