# Proxmox VM Bridge DHCP Configuration Tool

Proxmox VE에서 vmbr0 브리지를 DHCP 모드로 변환하거나 백업에서 복원하는 스크립트입니다.

## 기능

- **DHCP 변환**: vmbr0를 정적 IP에서 DHCP 모드로 변환
- **백업 복원**: 이전 설정을 백업에서 복원
- **자동 백업**: 변경 전 자동으로 현재 설정을 백업

## 설치 및 실행

### 방법 1: curl을 사용한 직접 실행

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_vmbr0_dhcp.sh)"
```



 