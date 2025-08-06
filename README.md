# Proxmox VE 관리 스크립트 모음
Proxmox VE 환경에서 사용할 수 있는 다양한 관리 스크립트 모음입니다.

<div align="center">
  <h3>🌍 언어 선택 / Language Selection</h3>
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

**⚠️ 중요: 이 스크립트를 사용하면 되돌리기가 어려우며 스냅샷백업이 되지 않습니다.**

**기능:**
- **LVM 통합**: local-lvm을 local에 통합
- **자동 리사이즈**: root 볼륨을 자동으로 확장
- **안전 검증**: 작업 전 시스템 상태 확인

**실행 방법:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/pve_lvm_resize.sh)"
```

### 3. DNSZI DDNS 자동 업데이트 도구
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

### 4. Supabase LXC 자동 설치 도구 ⚠️ **테스트 단계**

> **⚠️ 경고: 이 스크립트는 현재 테스트 단계입니다. 프로덕션 환경에서 사용하지 마세요!**
> 
> 테스트 목적으로만 사용하시고, 데이터 손실이나 시스템 문제가 발생할 수 있습니다.

Proxmox VE에서 LXC 컨테이너에 Supabase 개발 환경을 자동으로 설치하는 스크립트입니다.

**설치되는 서비스:**
- **Docker & Docker Compose**: 컨테이너 런타임 환경
- **Dockge** (포트 5001): Docker Compose 스택 웹 관리 도구
- **CloudCmd** (포트 8000): 웹 기반 파일 관리자
- **Supabase** (포트 3001, 8001): 오픈소스 Firebase 대안

**주요 기능:**
- **완전 자동화**: 대화형 설정으로 원클릭 설치
- **최신 버전**: 모든 컴포넌트 최신 버전 자동 설치
- **보안 강화**: 방화벽, fail2ban, 파일 권한 자동 설정
- **통합 테스트**: 설치 후 자동 검증 및 상태 확인
- **상세 로깅**: 전체 설치 과정 로깅 및 문제 해결 가이드

**시스템 요구사항:**
- Proxmox VE 7.0 이상
- 최소 8GB RAM (권장)
- 최소 50GB 디스크 공간 (권장)
- 인터넷 연결 필수

**실행 방법:**
```bash
# ⚠️ 테스트 환경에서만 사용하세요!
bash -c "$(curl -fsSL https://raw.githubusercontent.com/takesih/pve_script/main/supabase_lxc_installer.sh)"
```

**설치 후 접속:**
- Dockge 관리 패널: `http://컨테이너IP:5001`
- CloudCmd 파일 관리: `http://컨테이너IP:8000`
- Supabase Studio: `http://컨테이너IP:3001`
- Supabase API: `http://컨테이너IP:8001`

### 5. Proxmox ISO 커스터마이징 도구
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

<a href='https://ko-fi.com/R6R71ILZQL' target='_blank'><img height='36' style='border:0px;height:36px;' src='https://storage.ko-fi.com/cdn/kofi3.png?v=6' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a>



 