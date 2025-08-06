# Supabase LXC Auto Installer

Proxmox VE 환경에서 LXC 컨테이너에 Docker, Dockge, CloudCmd, Supabase를 자동으로 설치하는 모듈화된 스크립트입니다.

## 📁 프로젝트 구조

```
supabase_installer/
├── config.sh              # 설정 변수 및 검증 함수
├── utils.sh               # 공통 유틸리티 함수
├── input.sh               # 사용자 입력 관련 함수
├── docker.sh              # Docker 설치 관련 함수
├── supabase_installer.sh  # 메인 스크립트
└── README.md              # 이 파일
```

## 🚀 주요 기능

- **모듈화된 구조**: 기능별로 분리된 스크립트 파일
- **개선된 사용자 입력**: 타임아웃 및 오류 처리
- **자동 환경 검증**: Proxmox VE 환경 및 권한 확인
- **Docker 자동 설치**: 최신 버전 자동 다운로드 및 설치
- **LXC 컨테이너 관리**: 자동 컨테이너 생성 및 설정

## 📋 요구사항

- Proxmox VE 8.x 이상
- Root 권한
- 인터넷 연결
- 최소 8GB RAM (권장)
- 최소 20GB 디스크 공간 (권장)

## 🛠️ 설치 방법

1. **스크립트 다운로드**
   ```bash
   git clone https://github.com/takesih/pve_script.git
   cd pve_script/supabase_installer
   ```

2. **실행 권한 부여**
   ```bash
   chmod +x supabase_installer.sh
   ```

3. **스크립트 실행**
   ```bash
   sudo ./supabase_installer.sh
   ```

## 📝 사용법

스크립트 실행 시 다음 정보를 입력해야 합니다:

### LXC 컨테이너 설정
- **Container ID**: 컨테이너 ID (기본값: 자동 선택)
- **Container Name**: 컨테이너 이름 (기본값: supabase-dev)
- **Memory Size**: 메모리 크기 MB (기본값: 4096)
- **CPU Cores**: CPU 코어 수 (기본값: 2)
- **Disk Size**: 디스크 크기 GB (기본값: 20)
- **Storage Pool**: 스토리지 풀 (기본값: local-lvm)

### 네트워크 설정
- **Bridge Interface**: 브리지 인터페이스 (기본값: vmbr0)
- **IP Configuration**: DHCP 또는 고정 IP
- **DNS Server**: DNS 서버 (기본값: 8.8.8.8)

### 서비스 포트 설정
- **Dockge Port**: Dockge 포트 (기본값: 5001)
- **CloudCmd Port**: CloudCmd 포트 (기본값: 8000)
- **Supabase Studio Port**: Supabase Studio 포트 (기본값: 3001)

## 🔧 모듈 설명

### config.sh
- 모든 설정 변수 정의
- 기본값 설정
- 검증 함수들 (IP, 포트, 메모리 등)

### utils.sh
- 로깅 함수
- 진행 상황 표시
- 사용자 입력 함수 (개선된 버전)
- 오류 처리 및 정리 함수

### input.sh
- LXC 컨테이너 설정 입력
- 네트워크 설정 입력
- 서비스 포트 설정 입력
- Supabase 환경변수 설정

### docker.sh
- Docker 저장소 추가
- Docker Engine 설치
- Docker Compose 설치
- Docker 권한 설정 및 최적화

## 🐛 문제 해결

### 스크립트가 멈추는 경우
- 30초 타임아웃이 설정되어 있어 자동으로 기본값을 사용합니다
- 로그 파일을 확인하여 오류 원인을 파악하세요

### 권한 오류
- Root 권한으로 실행해야 합니다
- `sudo ./supabase_installer.sh` 명령어를 사용하세요

### 네트워크 오류
- 인터넷 연결을 확인하세요
- 방화벽 설정을 확인하세요

## 📊 로그 파일

로그 파일은 `/var/log/supabase_installer.log`에 저장됩니다.

## 🤝 기여하기

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📄 라이선스

이 프로젝트는 MIT 라이선스 하에 배포됩니다.

## 🙏 감사의 말

- [Proxmox VE](https://www.proxmox.com/) - 가상화 플랫폼
- [Docker](https://www.docker.com/) - 컨테이너 플랫폼
- [Supabase](https://supabase.com/) - 오픈소스 Firebase 대안
- [Dockge](https://dockge.kuma.pet/) - Docker Compose 관리 도구
- [CloudCmd](https://cloudcmd.io/) - 웹 기반 파일 관리자 