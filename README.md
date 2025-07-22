# Proxmox VE 관리 스크립트 모음
Proxmox VE 환경에서 사용할 수 있는 다양한 관리 스크립트 모음입니다.


## 스크립트 목록
### 1. VM Bridge DHCP 설정 도구
vmbr0 브리지를 DHCP 모드로 변환하거나 백업에서 복원하는 스크립트입니다.

**기능:**
- **DHCP 변환**: vmbr0를 정적 IP에서 DHCP 모드로 변환
- **백업 복원**: 이전 설정을 백업에서 복원
- **자동 백업**: 변경 전 자동으로 현재 설정을 백업

**실행 방법:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_vmbr0_dhcp.sh)"
```

### 2. LVM 리사이즈 도구
local-lvm을 local에 통합하여 디스크 공간을 최적화하는 스크립트입니다.

**기능:**
- **LVM 통합**: local-lvm을 local에 통합
- **자동 리사이즈**: root 볼륨을 자동으로 확장
- **안전 검증**: 작업 전 시스템 상태 확인

**실행 방법:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_lvm_resize.sh)"
```



 