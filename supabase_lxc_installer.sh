#!/bin/bash

# Supabase LXC Auto Installer for Proxmox VE
# 이 스크립트는 Proxmox VE 환경에서 LXC 컨테이너에 Docker, Dockge, CloudCmd, Supabase를 자동 설치합니다.

echo "=================================="
echo "Supabase LXC Auto Installer for Proxmox VE"
echo "V 241208175200"
echo "=================================="

set -euo pipefail  # 오류 발생 시 스크립트 중단

# 전역 변수
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
TEMP_DIR="/tmp/supabase_installer"
LOG_FILE="/var/log/supabase_installer.log"

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# LXC 설정 변수
LXC_ID=""
LXC_NAME=""
LXC_MEMORY=""
LXC_CORES=""
LXC_DISK=""
LXC_STORAGE=""

# 네트워크 설정 변수
LXC_IP=""
LXC_GATEWAY=""
LXC_DNS=""
LXC_BRIDGE=""

# 서비스 설정 변수
DOMAIN=""
DOCKGE_PORT=""
CLOUDCMD_PORT=""
SUPABASE_STUDIO_PORT=""

# Supabase 환경변수
POSTGRES_PASSWORD=""
JWT_SECRET=""
ANON_KEY=""
SERVICE_ROLE_KEY=""
API_EXTERNAL_URL=""
SUPABASE_PUBLIC_URL=""

# 로깅 함수
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message"
            echo "[$timestamp] [INFO] $message" >> "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message"
            echo "[$timestamp] [WARN] $message" >> "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message"
            echo "[$timestamp] [ERROR] $message" >> "$LOG_FILE"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} $message"
            echo "[$timestamp] [DEBUG] $message" >> "$LOG_FILE"
            ;;
    esac
}

# 진행 상황 표시 함수
show_progress() {
    local current=$1
    local total=$2
    local message=$3
    
    local percent=$((current * 100 / total))
    local filled=$((percent / 2))
    local empty=$((50 - filled))
    
    printf "\r${BLUE}[%3d%%]${NC} [" "$percent"
    printf "%*s" "$filled" | tr ' ' '='
    printf "%*s" "$empty" | tr ' ' '-'
    printf "] %s" "$message"
    
    if [ "$current" -eq "$total" ]; then
        echo
    fi
}

# 임시 파일 정리 함수
cleanup_temp_files() {
    log "INFO" "임시 파일들을 정리하는 중..."
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        log "INFO" "임시 디렉토리 삭제 완료: $TEMP_DIR"
    fi
}

# 스크립트 종료 시 정리 함수 실행
trap cleanup_temp_files EXIT INT TERM

# Proxmox VE 환경 확인 함수
check_proxmox_environment() {
    log "INFO" "Proxmox VE 환경을 확인하는 중..."
    
    # Proxmox VE 설치 확인
    if ! command -v pct &> /dev/null; then
        log "ERROR" "Proxmox VE가 설치되지 않았거나 pct 명령어를 찾을 수 없습니다."
        log "ERROR" "이 스크립트는 Proxmox VE 환경에서만 실행할 수 있습니다."
        exit 1
    fi
    
    # Proxmox VE 버전 확인
    local pve_version=$(pveversion | head -n1 | cut -d'/' -f2)
    log "INFO" "Proxmox VE 버전: $pve_version"
    
    # 필수 명령어 확인 및 자동 설치
    local required_commands=("curl" "wget" "tar" "unzip")
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [ ${#missing_commands[@]} -gt 0 ]; then
        log "INFO" "누락된 필수 명령어들을 자동 설치합니다: ${missing_commands[*]}"
        if ! apt update && apt install -y "${missing_commands[@]}"; then
            log "ERROR" "필수 패키지 설치에 실패했습니다: ${missing_commands[*]}"
            log "INFO" "수동으로 설치하세요: apt update && apt install -y ${missing_commands[*]}"
            exit 1
        fi
        log "INFO" "필수 패키지 설치 완료: ${missing_commands[*]}"
    fi
    
    log "INFO" "Proxmox VE 환경 확인 완료"
}

# 권한 확인 함수
check_permissions() {
    log "INFO" "권한을 확인하는 중..."
    
    # root 권한 확인
    if [ "$EUID" -ne 0 ]; then
        log "ERROR" "이 스크립트는 root 권한으로 실행해야 합니다."
        log "INFO" "다음 명령어로 실행하세요: sudo $0"
        exit 1
    fi
    
    # 스토리지 풀 접근 권한 확인
    if ! pvesm status &> /dev/null; then
        log "ERROR" "Proxmox VE 스토리지에 접근할 수 없습니다."
        exit 1
    fi
    
    log "INFO" "권한 확인 완료"
}

# 시스템 리소스 확인 함수
check_system_resources() {
    log "INFO" "시스템 리소스를 확인하는 중..."
    
    # 메모리 확인 (최소 8GB 권장)
    local total_memory=$(free -m | awk 'NR==2{printf "%.0f", $2}')
    if [ "$total_memory" -lt 8192 ]; then
        log "WARN" "시스템 메모리가 부족할 수 있습니다. (현재: ${total_memory}MB, 권장: 8192MB 이상)"
    fi
    
    # 디스크 공간 확인 (최소 50GB 권장)
    local available_space=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
    if [ "$available_space" -lt 50 ]; then
        log "WARN" "디스크 공간이 부족할 수 있습니다. (현재: ${available_space}GB, 권장: 50GB 이상)"
    fi
    
    log "INFO" "시스템 리소스 확인 완료"
}

# 네트워크 연결 확인 함수
check_network_connectivity() {
    log "INFO" "네트워크 연결을 확인하는 중..."
    
    # 인터넷 연결 확인
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        log "ERROR" "인터넷 연결을 확인할 수 없습니다."
        exit 1
    fi
    
    # GitHub 접근 확인 (Supabase 설정 파일 다운로드용)
    if ! curl -s --connect-timeout 5 https://github.com &> /dev/null; then
        log "ERROR" "GitHub에 접근할 수 없습니다. 방화벽 설정을 확인하세요."
        exit 1
    fi
    
    # Docker Hub 접근 확인
    if ! curl -s --connect-timeout 5 https://hub.docker.com &> /dev/null; then
        log "ERROR" "Docker Hub에 접근할 수 없습니다. 방화벽 설정을 확인하세요."
        exit 1
    fi
    
    log "INFO" "네트워크 연결 확인 완료"
}

# 메인 환경 검증 함수
check_environment() {
    log "INFO" "=== 환경 검증 시작 ==="
    
    show_progress 1 4 "Proxmox VE 환경 확인 중..."
    check_proxmox_environment
    
    show_progress 2 4 "권한 확인 중..."
    check_permissions
    
    show_progress 3 4 "시스템 리소스 확인 중..."
    check_system_resources
    
    show_progress 4 4 "네트워크 연결 확인 중..."
    check_network_connectivity
    
    log "INFO" "=== 환경 검증 완료 ==="
}

# 입력값 검증 함수들
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra ADDR <<< "$ip"
        for i in "${ADDR[@]}"; do
            if [[ $i -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

validate_port() {
    local port=$1
    if [[ $port =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        return 0
    fi
    return 1
}

validate_memory() {
    local memory=$1
    if [[ $memory =~ ^[0-9]+$ ]] && [ "$memory" -ge 1024 ]; then
        return 0
    fi
    return 1
}

validate_disk_size() {
    local disk=$1
    if [[ $disk =~ ^[0-9]+$ ]] && [ "$disk" -ge 10 ]; then
        return 0
    fi
    return 1
}

validate_cpu_cores() {
    local cores=$1
    if [[ $cores =~ ^[0-9]+$ ]] && [ "$cores" -ge 1 ] && [ "$cores" -le 32 ]; then
        return 0
    fi
    return 1
}

# 사용자 입력 함수
prompt_input() {
    local prompt_text=$1
    local default_value=$2
    local validation_func=$3
    local input_value
    
    while true; do
        if [ -n "$default_value" ]; then
            echo -ne "${BLUE}$prompt_text${NC} [기본값: $default_value]: "
        else
            echo -ne "${BLUE}$prompt_text${NC}: "
        fi
        
        read -r input_value
        
        # 빈 입력시 기본값 사용
        if [ -z "$input_value" ] && [ -n "$default_value" ]; then
            input_value=$default_value
        fi
        
        # 검증 함수가 있으면 검증 수행
        if [ -n "$validation_func" ]; then
            if $validation_func "$input_value"; then
                echo "$input_value"
                return 0
            else
                log "ERROR" "잘못된 입력값입니다. 다시 입력해주세요."
                continue
            fi
        else
            echo "$input_value"
            return 0
        fi
    done
}

# LXC 컨테이너 설정 입력 함수
collect_lxc_settings() {
    log "INFO" "=== LXC 컨테이너 설정 ==="
    
    # 사용 가능한 컨테이너 ID 찾기
    local next_id=100
    while pct status $next_id &>/dev/null; do
        ((next_id++))
    done
    
    LXC_ID=$(prompt_input "컨테이너 ID" "$next_id" "")
    LXC_NAME=$(prompt_input "컨테이너 이름" "supabase-dev" "")
    LXC_MEMORY=$(prompt_input "메모리 크기 (MB)" "4096" "validate_memory")
    LXC_CORES=$(prompt_input "CPU 코어 수" "2" "validate_cpu_cores")
    LXC_DISK=$(prompt_input "디스크 크기 (GB)" "20" "validate_disk_size")
    
    # 사용 가능한 스토리지 풀 표시
    echo -e "\n${YELLOW}사용 가능한 스토리지 풀:${NC}"
    pvesm status | grep -E "^[a-zA-Z]" | awk '{print "  - " $1 " (" $2 ")"}'
    LXC_STORAGE=$(prompt_input "스토리지 풀" "local-lvm" "")
    
    log "INFO" "LXC 설정 완료: ID=$LXC_ID, 이름=$LXC_NAME, 메모리=${LXC_MEMORY}MB, CPU=${LXC_CORES}코어, 디스크=${LXC_DISK}GB"
}

# 네트워크 설정 입력 함수
collect_network_settings() {
    log "INFO" "=== 네트워크 설정 ==="
    
    # 사용 가능한 브리지 인터페이스 표시
    echo -e "\n${YELLOW}사용 가능한 브리지 인터페이스:${NC}"
    ip link show | grep -E "^[0-9]+: vmbr" | awk -F': ' '{print "  - " $2}' | cut -d'@' -f1
    LXC_BRIDGE=$(prompt_input "브리지 인터페이스" "vmbr0" "")
    
    echo -e "\n${YELLOW}IP 설정 방식을 선택하세요:${NC}"
    echo "1) DHCP (자동 할당)"
    echo "2) 고정 IP"
    
    local ip_choice
    while true; do
        echo -ne "${BLUE}선택 [1-2]${NC}: "
        read -r ip_choice
        case $ip_choice in
            1)
                LXC_IP="dhcp"
                LXC_GATEWAY=""
                break
                ;;
            2)
                LXC_IP=$(prompt_input "IP 주소 (예: 192.168.1.100/24)" "" "")
                LXC_GATEWAY=$(prompt_input "게이트웨이" "192.168.1.1" "validate_ip")
                break
                ;;
            *)
                log "ERROR" "1 또는 2를 선택해주세요."
                ;;
        esac
    done
    
    LXC_DNS=$(prompt_input "DNS 서버" "8.8.8.8" "validate_ip")
    
    log "INFO" "네트워크 설정 완료: 브리지=$LXC_BRIDGE, IP=$LXC_IP, 게이트웨이=$LXC_GATEWAY, DNS=$LXC_DNS"
}

# 서비스 포트 설정 입력 함수
collect_service_settings() {
    log "INFO" "=== 서비스 포트 설정 ==="
    
    DOCKGE_PORT=$(prompt_input "Dockge 포트" "5001" "validate_port")
    CLOUDCMD_PORT=$(prompt_input "CloudCmd 포트" "8000" "validate_port")
    SUPABASE_STUDIO_PORT=$(prompt_input "Supabase Studio 포트" "3001" "validate_port")
    
    # 도메인 설정
    if [ "$LXC_IP" = "dhcp" ]; then
        DOMAIN=$(prompt_input "도메인/호스트명 (DHCP 사용시 나중에 설정)" "localhost" "")
    else
        local container_ip=$(echo "$LXC_IP" | cut -d'/' -f1)
        DOMAIN=$(prompt_input "도메인/호스트명" "$container_ip" "")
    fi
    
    log "INFO" "서비스 설정 완료: Dockge=$DOCKGE_PORT, CloudCmd=$CLOUDCMD_PORT, Supabase Studio=$SUPABASE_STUDIO_PORT"
}

# Supabase 환경변수 설정 함수
collect_supabase_settings() {
    log "INFO" "=== Supabase 환경변수 설정 ==="
    
    # 데이터베이스 비밀번호
    echo -e "\n${YELLOW}PostgreSQL 데이터베이스 비밀번호를 설정하세요.${NC}"
    echo "비어있으면 자동으로 강력한 비밀번호를 생성합니다."
    POSTGRES_PASSWORD=$(prompt_input "PostgreSQL 비밀번호" "" "")
    
    if [ -z "$POSTGRES_PASSWORD" ]; then
        POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
        log "INFO" "자동 생성된 PostgreSQL 비밀번호: $POSTGRES_PASSWORD"
    fi
    
    # JWT 시크릿 자동 생성
    JWT_SECRET=$(openssl rand -base64 64 | tr -d "=+/" | cut -c1-64)
    log "INFO" "JWT 시크릿이 자동 생성되었습니다."
    
    # API 키 자동 생성 (Supabase 형식)
    ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.$(echo '{"iss":"supabase","ref":"localhost","role":"anon","iat":1641916800,"exp":2000000000}' | base64 -w 0 | tr -d '=')"
    SERVICE_ROLE_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.$(echo '{"iss":"supabase","ref":"localhost","role":"service_role","iat":1641916800,"exp":2000000000}' | base64 -w 0 | tr -d '=')"
    
    # API URL 설정
    API_EXTERNAL_URL="http://${DOMAIN}:8001"
    SUPABASE_PUBLIC_URL="http://${DOMAIN}:8001"
    
    # SMTP 설정 (선택사항)
    echo -e "\n${YELLOW}SMTP 이메일 설정 (선택사항)${NC}"
    echo "이메일 인증 기능을 사용하려면 SMTP 설정을 입력하세요. 건너뛰려면 Enter를 누르세요."
    
    local smtp_host=$(prompt_input "SMTP 호스트" "" "")
    if [ -n "$smtp_host" ]; then
        SMTP_HOST=$smtp_host
        SMTP_PORT=$(prompt_input "SMTP 포트" "587" "validate_port")
        SMTP_USER=$(prompt_input "SMTP 사용자명" "" "")
        SMTP_PASS=$(prompt_input "SMTP 비밀번호" "" "")
    fi
    
    log "INFO" "Supabase 환경변수 설정 완료"
}

# 설정 확인 함수
confirm_settings() {
    log "INFO" "=== 설정 확인 ==="
    
    echo -e "\n${YELLOW}=== 입력된 설정 정보 ===${NC}"
    echo -e "${BLUE}LXC 컨테이너:${NC}"
    echo "  - ID: $LXC_ID"
    echo "  - 이름: $LXC_NAME"
    echo "  - 메모리: ${LXC_MEMORY}MB"
    echo "  - CPU: ${LXC_CORES}코어"
    echo "  - 디스크: ${LXC_DISK}GB"
    echo "  - 스토리지: $LXC_STORAGE"
    
    echo -e "\n${BLUE}네트워크:${NC}"
    echo "  - 브리지: $LXC_BRIDGE"
    echo "  - IP: $LXC_IP"
    echo "  - 게이트웨이: $LXC_GATEWAY"
    echo "  - DNS: $LXC_DNS"
    
    echo -e "\n${BLUE}서비스 포트:${NC}"
    echo "  - Dockge: $DOCKGE_PORT"
    echo "  - CloudCmd: $CLOUDCMD_PORT"
    echo "  - Supabase Studio: $SUPABASE_STUDIO_PORT"
    echo "  - 도메인: $DOMAIN"
    
    echo -e "\n${BLUE}Supabase:${NC}"
    echo "  - PostgreSQL 비밀번호: [설정됨]"
    echo "  - JWT 시크릿: [자동 생성됨]"
    echo "  - API URL: $API_EXTERNAL_URL"
    
    if [ -n "$SMTP_HOST" ]; then
        echo -e "\n${BLUE}SMTP 설정:${NC}"
        echo "  - 호스트: $SMTP_HOST"
        echo "  - 포트: $SMTP_PORT"
        echo "  - 사용자: $SMTP_USER"
    fi
    
    echo -e "\n${YELLOW}위 설정으로 설치를 진행하시겠습니까?${NC}"
    while true; do
        echo -ne "${BLUE}계속 진행하시겠습니까? [y/N]${NC}: "
        read -r confirm
        case $confirm in
            [Yy]|[Yy][Ee][Ss])
                return 0
                ;;
            [Nn]|[Nn][Oo]|"")
                log "INFO" "설치가 취소되었습니다."
                exit 0
                ;;
            *)
                log "ERROR" "y 또는 n을 입력해주세요."
                ;;
        esac
    done
}

# 사용자 입력 수집 메인 함수
collect_user_input() {
    log "INFO" "=== 사용자 설정 입력 시작 ==="
    
    echo -e "\n${GREEN}Supabase LXC 자동 설치 프로그램${NC}"
    echo -e "${YELLOW}이 프로그램은 Proxmox VE에서 LXC 컨테이너에 다음 서비스들을 설치합니다:${NC}"
    echo "  - Docker & Docker Compose"
    echo "  - Dockge (Docker Compose 관리 도구)"
    echo "  - CloudCmd (웹 기반 파일 관리자)"
    echo "  - Supabase (오픈소스 Firebase 대안)"
    echo ""
    
    collect_lxc_settings
    collect_network_settings
    collect_service_settings
    collect_supabase_settings
    confirm_settings
    
    log "INFO" "=== 사용자 설정 입력 완료 ==="
}

# LXC 템플릿 다운로드 함수
download_lxc_template() {
    log "INFO" "Ubuntu 22.04 LTS 템플릿을 확인하는 중..."
    
    local template_name="ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
    local template_path="/var/lib/vz/template/cache/$template_name"
    
    # 템플릿이 이미 존재하는지 확인
    if [ -f "$template_path" ]; then
        log "INFO" "Ubuntu 22.04 템플릿이 이미 존재합니다."
        return 0
    fi
    
    log "INFO" "Ubuntu 22.04 템플릿을 다운로드하는 중..."
    if ! pveam download local $template_name; then
        log "ERROR" "템플릿 다운로드에 실패했습니다."
        return 1
    fi
    
    log "INFO" "템플릿 다운로드 완료"
    return 0
}

# LXC 컨테이너 생성 함수
create_lxc_container() {
    log "INFO" "=== LXC 컨테이너 생성 시작 ==="
    
    # 컨테이너 ID 중복 확인
    if pct status "$LXC_ID" &>/dev/null; then
        log "ERROR" "컨테이너 ID $LXC_ID가 이미 사용 중입니다."
        return 1
    fi
    
    # 템플릿 다운로드
    if ! download_lxc_template; then
        return 1
    fi
    
    log "INFO" "LXC 컨테이너를 생성하는 중... (ID: $LXC_ID, 이름: $LXC_NAME)"
    
    # 네트워크 설정 구성
    local net_config="name=eth0,bridge=$LXC_BRIDGE,firewall=1"
    if [ "$LXC_IP" != "dhcp" ]; then
        net_config="$net_config,ip=$LXC_IP,gw=$LXC_GATEWAY"
    else
        net_config="$net_config,ip=dhcp"
    fi
    
    # 컨테이너 생성 명령어 구성
    local create_cmd=(
        pct create "$LXC_ID"
        "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
        --hostname "$LXC_NAME"
        --memory "$LXC_MEMORY"
        --cores "$LXC_CORES"
        --rootfs "$LXC_STORAGE:$LXC_DISK"
        --net0 "$net_config"
        --nameserver "$LXC_DNS"
        --features nesting=1
        --unprivileged 1
        --onboot 1
        --start 1
    )
    
    # 컨테이너 생성 실행
    if ! "${create_cmd[@]}"; then
        log "ERROR" "LXC 컨테이너 생성에 실패했습니다."
        return 1
    fi
    
    log "INFO" "LXC 컨테이너가 성공적으로 생성되었습니다."
    
    # 컨테이너 시작 대기
    log "INFO" "컨테이너 시작을 대기하는 중..."
    local wait_count=0
    while [ $wait_count -lt 30 ]; do
        if pct status "$LXC_ID" | grep -q "running"; then
            break
        fi
        sleep 2
        ((wait_count++))
    done
    
    if [ $wait_count -ge 30 ]; then
        log "ERROR" "컨테이너 시작 시간이 초과되었습니다."
        return 1
    fi
    
    log "INFO" "컨테이너가 성공적으로 시작되었습니다."
    return 0
}

# 컨테이너 내부 명령 실행 함수
exec_in_container() {
    local cmd="$1"
    if ! pct exec "$LXC_ID" -- bash -c "$cmd"; then
        log "ERROR" "컨테이너 내부 명령 실행 실패: $cmd"
        return 1
    fi
    return 0
}

# 기본 패키지 업데이트 및 설치 함수
install_basic_packages() {
    log "INFO" "=== 기본 패키지 설치 시작 ==="
    
    log "INFO" "패키지 목록을 업데이트하는 중..."
    if ! exec_in_container "apt update"; then
        return 1
    fi
    
    log "INFO" "시스템 패키지를 업그레이드하는 중..."
    if ! exec_in_container "DEBIAN_FRONTEND=noninteractive apt upgrade -y"; then
        return 1
    fi
    
    log "INFO" "필수 패키지들을 설치하는 중..."
    local packages=(
        "curl"
        "wget"
        "gnupg"
        "lsb-release"
        "ca-certificates"
        "software-properties-common"
        "apt-transport-https"
        "unzip"
        "tar"
        "git"
        "nano"
        "htop"
        "ufw"
        "openssl"
    )
    
    local package_list=$(IFS=' '; echo "${packages[*]}")
    if ! exec_in_container "DEBIAN_FRONTEND=noninteractive apt install -y $package_list"; then
        return 1
    fi
    
    log "INFO" "기본 패키지 설치 완료"
    return 0
}

# 컨테이너 네트워크 설정 함수
configure_container_network() {
    log "INFO" "=== 컨테이너 네트워크 설정 ==="
    
    # DHCP 사용시 실제 IP 주소 확인
    if [ "$LXC_IP" = "dhcp" ]; then
        log "INFO" "DHCP로 할당된 IP 주소를 확인하는 중..."
        local actual_ip
        local wait_count=0
        
        while [ $wait_count -lt 30 ]; do
            actual_ip=$(pct exec "$LXC_ID" -- ip route get 8.8.8.8 | awk '{print $7; exit}' 2>/dev/null)
            if [ -n "$actual_ip" ] && validate_ip "$actual_ip"; then
                LXC_IP="$actual_ip"
                DOMAIN="$actual_ip"
                API_EXTERNAL_URL="http://${DOMAIN}:8001"
                SUPABASE_PUBLIC_URL="http://${DOMAIN}:8001"
                log "INFO" "할당된 IP 주소: $actual_ip"
                break
            fi
            sleep 2
            ((wait_count++))
        done
        
        if [ $wait_count -ge 30 ]; then
            log "WARN" "IP 주소 확인에 실패했습니다. 나중에 수동으로 설정해야 합니다."
            LXC_IP="unknown"
        fi
    fi
    
    # 방화벽 기본 설정
    log "INFO" "기본 방화벽 규칙을 설정하는 중..."
    exec_in_container "ufw --force reset"
    exec_in_container "ufw default deny incoming"
    exec_in_container "ufw default allow outgoing"
    exec_in_container "ufw allow 22/tcp"  # SSH
    
    log "INFO" "네트워크 설정 완료"
    return 0
}

# 시스템 최적화 함수
optimize_system() {
    log "INFO" "=== 시스템 최적화 ==="
    
    # 스왑 설정 최적화
    log "INFO" "스왑 설정을 최적화하는 중..."
    exec_in_container "echo 'vm.swappiness=10' >> /etc/sysctl.conf"
    
    # 파일 디스크립터 제한 증가
    log "INFO" "파일 디스크립터 제한을 증가시키는 중..."
    exec_in_container "echo '* soft nofile 65536' >> /etc/security/limits.conf"
    exec_in_container "echo '* hard nofile 65536' >> /etc/security/limits.conf"
    
    # 커널 매개변수 최적화
    log "INFO" "커널 매개변수를 최적화하는 중..."
    exec_in_container "echo 'net.core.somaxconn = 65536' >> /etc/sysctl.conf"
    exec_in_container "echo 'net.ipv4.tcp_max_syn_backlog = 65536' >> /etc/sysctl.conf"
    
    log "INFO" "시스템 최적화 완료"
    return 0
}

# LXC 컨테이너 설정 메인 함수
setup_lxc_container() {
    log "INFO" "=== LXC 컨테이너 설정 시작 ==="
    
    show_progress 1 4 "LXC 컨테이너 생성 중..."
    if ! create_lxc_container; then
        return 1
    fi
    
    show_progress 2 4 "기본 패키지 설치 중..."
    if ! install_basic_packages; then
        return 1
    fi
    
    show_progress 3 4 "네트워크 설정 중..."
    if ! configure_container_network; then
        return 1
    fi
    
    show_progress 4 4 "시스템 최적화 중..."
    if ! optimize_system; then
        return 1
    fi
    
    log "INFO" "=== LXC 컨테이너 설정 완료 ==="
    return 0
}

# Docker GPG 키 및 저장소 추가 함수
add_docker_repository() {
    log "INFO" "Docker 공식 저장소를 추가하는 중..."
    
    # Docker GPG 키 추가
    if ! exec_in_container "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg"; then
        log "ERROR" "Docker GPG 키 추가에 실패했습니다."
        return 1
    fi
    
    # Docker 저장소 추가
    local repo_cmd='echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list'
    if ! exec_in_container "$repo_cmd"; then
        log "ERROR" "Docker 저장소 추가에 실패했습니다."
        return 1
    fi
    
    # 패키지 목록 업데이트
    if ! exec_in_container "apt update"; then
        log "ERROR" "패키지 목록 업데이트에 실패했습니다."
        return 1
    fi
    
    log "INFO" "Docker 저장소 추가 완료"
    return 0
}

# Docker Engine 설치 함수
install_docker_engine() {
    log "INFO" "Docker Engine을 설치하는 중..."
    
    # 이전 Docker 버전 제거
    exec_in_container "apt remove -y docker docker-engine docker.io containerd runc" 2>/dev/null || true
    
    # Docker Engine 설치
    local docker_packages="docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
    if ! exec_in_container "DEBIAN_FRONTEND=noninteractive apt install -y $docker_packages"; then
        log "ERROR" "Docker Engine 설치에 실패했습니다."
        return 1
    fi
    
    # Docker 서비스 시작 및 활성화
    if ! exec_in_container "systemctl start docker"; then
        log "ERROR" "Docker 서비스 시작에 실패했습니다."
        return 1
    fi
    
    if ! exec_in_container "systemctl enable docker"; then
        log "ERROR" "Docker 서비스 자동 시작 설정에 실패했습니다."
        return 1
    fi
    
    # Docker 버전 확인
    local docker_version=$(pct exec "$LXC_ID" -- docker --version 2>/dev/null)
    log "INFO" "설치된 Docker 버전: $docker_version"
    
    log "INFO" "Docker Engine 설치 완료"
    return 0
}

# Docker Compose 설치 함수
install_docker_compose() {
    log "INFO" "Docker Compose를 설치하는 중..."
    
    # 최신 Docker Compose 버전 확인
    local compose_version
    compose_version=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')
    
    if [ -z "$compose_version" ]; then
        log "WARN" "최신 버전 확인에 실패했습니다. 기본 버전을 사용합니다."
        compose_version="v2.24.0"
    fi
    
    log "INFO" "Docker Compose 버전 $compose_version 을 설치합니다."
    
    # Docker Compose 바이너리 다운로드
    local compose_url="https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-linux-x86_64"
    if ! exec_in_container "curl -L '$compose_url' -o /usr/local/bin/docker-compose"; then
        log "ERROR" "Docker Compose 다운로드에 실패했습니다."
        return 1
    fi
    
    # 실행 권한 부여
    if ! exec_in_container "chmod +x /usr/local/bin/docker-compose"; then
        log "ERROR" "Docker Compose 실행 권한 설정에 실패했습니다."
        return 1
    fi
    
    # 심볼릭 링크 생성
    exec_in_container "ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose" 2>/dev/null || true
    
    # Docker Compose 버전 확인
    local compose_installed_version=$(pct exec "$LXC_ID" -- docker-compose --version 2>/dev/null)
    log "INFO" "설치된 Docker Compose 버전: $compose_installed_version"
    
    log "INFO" "Docker Compose 설치 완료"
    return 0
}

# Docker 사용자 권한 설정 함수
configure_docker_permissions() {
    log "INFO" "Docker 사용자 권한을 설정하는 중..."
    
    # docker 그룹이 없으면 생성
    exec_in_container "groupadd -f docker"
    
    # root 사용자를 docker 그룹에 추가
    if ! exec_in_container "usermod -aG docker root"; then
        log "WARN" "Docker 그룹 추가에 실패했습니다. 수동으로 설정이 필요할 수 있습니다."
    fi
    
    # Docker 소켓 권한 설정
    if ! exec_in_container "chmod 666 /var/run/docker.sock"; then
        log "WARN" "Docker 소켓 권한 설정에 실패했습니다."
    fi
    
    log "INFO" "Docker 권한 설정 완료"
    return 0
}

# Docker 설치 검증 함수
verify_docker_installation() {
    log "INFO" "Docker 설치를 검증하는 중..."
    
    # Docker 서비스 상태 확인
    if ! exec_in_container "systemctl is-active docker"; then
        log "ERROR" "Docker 서비스가 실행되지 않고 있습니다."
        return 1
    fi
    
    # Docker 명령어 테스트
    if ! exec_in_container "docker run --rm hello-world"; then
        log "ERROR" "Docker 테스트 컨테이너 실행에 실패했습니다."
        return 1
    fi
    
    # Docker Compose 명령어 테스트
    if ! exec_in_container "docker-compose --version"; then
        log "ERROR" "Docker Compose 명령어 실행에 실패했습니다."
        return 1
    fi
    
    log "INFO" "Docker 설치 검증 완료"
    return 0
}

# Docker 설정 최적화 함수
optimize_docker_configuration() {
    log "INFO" "Docker 설정을 최적화하는 중..."
    
    # Docker daemon 설정 파일 생성
    local daemon_config='{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 65536,
      "Soft": 65536
    }
  }
}'
    
    if ! exec_in_container "mkdir -p /etc/docker"; then
        log "WARN" "Docker 설정 디렉토리 생성에 실패했습니다."
    fi
    
    if ! exec_in_container "echo '$daemon_config' > /etc/docker/daemon.json"; then
        log "WARN" "Docker daemon 설정 파일 생성에 실패했습니다."
    fi
    
    # Docker 서비스 재시작
    if ! exec_in_container "systemctl restart docker"; then
        log "WARN" "Docker 서비스 재시작에 실패했습니다."
    fi
    
    log "INFO" "Docker 설정 최적화 완료"
    return 0
}

# Docker 설치 메인 함수
install_docker() {
    log "INFO" "=== Docker 설치 시작 ==="
    
    show_progress 1 6 "Docker 저장소 추가 중..."
    if ! add_docker_repository; then
        return 1
    fi
    
    show_progress 2 6 "Docker Engine 설치 중..."
    if ! install_docker_engine; then
        return 1
    fi
    
    show_progress 3 6 "Docker Compose 설치 중..."
    if ! install_docker_compose; then
        return 1
    fi
    
    show_progress 4 6 "Docker 권한 설정 중..."
    if ! configure_docker_permissions; then
        return 1
    fi
    
    show_progress 5 6 "Docker 설정 최적화 중..."
    if ! optimize_docker_configuration; then
        return 1
    fi
    
    show_progress 6 6 "Docker 설치 검증 중..."
    if ! verify_docker_installation; then
        return 1
    fi
    
    log "INFO" "=== Docker 설치 완료 ==="
    return 0
}

# Dockge 최신 버전 확인 함수
get_latest_dockge_version() {
    log "INFO" "Dockge 최신 버전을 확인하는 중..."
    
    local latest_version
    latest_version=$(curl -s https://api.github.com/repos/louislam/dockge/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')
    
    if [ -z "$latest_version" ]; then
        log "WARN" "최신 버전 확인에 실패했습니다. 기본 버전을 사용합니다."
        echo "1.4.2"
    else
        echo "$latest_version"
    fi
}

# Dockge 디렉토리 구조 생성 함수
create_dockge_directories() {
    log "INFO" "Dockge 디렉토리 구조를 생성하는 중..."
    
    # Dockge 메인 디렉토리 생성
    if ! exec_in_container "mkdir -p /opt/dockge"; then
        log "ERROR" "Dockge 디렉토리 생성에 실패했습니다."
        return 1
    fi
    
    # 스택 디렉토리 생성
    if ! exec_in_container "mkdir -p /opt/dockge/stacks"; then
        log "ERROR" "스택 디렉토리 생성에 실패했습니다."
        return 1
    fi
    
    # 데이터 디렉토리 생성
    if ! exec_in_container "mkdir -p /opt/dockge/data"; then
        log "ERROR" "데이터 디렉토리 생성에 실패했습니다."
        return 1
    fi
    
    log "INFO" "Dockge 디렉토리 구조 생성 완료"
    return 0
}

# Dockge Docker Compose 파일 생성 함수
create_dockge_compose() {
    log "INFO" "Dockge Docker Compose 파일을 생성하는 중..."
    
    local dockge_version=$(get_latest_dockge_version)
    log "INFO" "사용할 Dockge 버전: $dockge_version"
    
    # Dockge compose.yaml 파일 내용
    local compose_content="version: '3.8'

services:
  dockge:
    image: louislam/dockge:$dockge_version
    restart: unless-stopped
    ports:
      - \"$DOCKGE_PORT:5001\"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./data:/app/data
      - ./stacks:/opt/stacks
    environment:
      - DOCKGE_STACKS_DIR=/opt/stacks
    networks:
      - dockge_network

networks:
  dockge_network:
    driver: bridge"
    
    # compose.yaml 파일 생성
    if ! exec_in_container "cat > /opt/dockge/compose.yaml << 'EOF'
$compose_content
EOF"; then
        log "ERROR" "Dockge compose.yaml 파일 생성에 실패했습니다."
        return 1
    fi
    
    log "INFO" "Dockge Docker Compose 파일 생성 완료"
    return 0
}

# Dockge 환경변수 파일 생성 함수
create_dockge_env() {
    log "INFO" "Dockge 환경변수 파일을 생성하는 중..."
    
    local env_content="# Dockge Configuration
DOCKGE_STACKS_DIR=/opt/stacks
DOCKGE_PORT=$DOCKGE_PORT
DOCKGE_HOST=0.0.0.0

# Security Settings
DOCKGE_DISABLE_STATS=false
DOCKGE_ENABLE_AUTH=false

# Logging
DOCKGE_LOG_LEVEL=info"
    
    # .env 파일 생성
    if ! exec_in_container "cat > /opt/dockge/.env << 'EOF'
$env_content
EOF"; then
        log "ERROR" "Dockge .env 파일 생성에 실패했습니다."
        return 1
    fi
    
    log "INFO" "Dockge 환경변수 파일 생성 완료"
    return 0
}

# Dockge 서비스 시작 함수
start_dockge_service() {
    log "INFO" "Dockge 서비스를 시작하는 중..."
    
    # Dockge 컨테이너 시작
    if ! exec_in_container "cd /opt/dockge && docker-compose up -d"; then
        log "ERROR" "Dockge 서비스 시작에 실패했습니다."
        return 1
    fi
    
    # 서비스 시작 대기
    log "INFO" "Dockge 서비스 시작을 대기하는 중..."
    local wait_count=0
    while [ $wait_count -lt 30 ]; do
        if exec_in_container "docker ps | grep -q dockge"; then
            break
        fi
        sleep 2
        ((wait_count++))
    done
    
    if [ $wait_count -ge 30 ]; then
        log "ERROR" "Dockge 서비스 시작 시간이 초과되었습니다."
        return 1
    fi
    
    log "INFO" "Dockge 서비스가 성공적으로 시작되었습니다."
    return 0
}

# Dockge 서비스 검증 함수
verify_dockge_installation() {
    log "INFO" "Dockge 설치를 검증하는 중..."
    
    # 컨테이너 상태 확인
    if ! exec_in_container "docker ps | grep -q dockge"; then
        log "ERROR" "Dockge 컨테이너가 실행되지 않고 있습니다."
        return 1
    fi
    
    # 포트 접근 확인
    local wait_count=0
    while [ $wait_count -lt 30 ]; do
        if exec_in_container "curl -s http://localhost:$DOCKGE_PORT > /dev/null"; then
            break
        fi
        sleep 2
        ((wait_count++))
    done
    
    if [ $wait_count -ge 30 ]; then
        log "ERROR" "Dockge 웹 인터페이스에 접근할 수 없습니다."
        return 1
    fi
    
    log "INFO" "Dockge 설치 검증 완료"
    return 0
}

# Dockge 방화벽 설정 함수
configure_dockge_firewall() {
    log "INFO" "Dockge 방화벽 규칙을 설정하는 중..."
    
    # Dockge 포트 허용
    if ! exec_in_container "ufw allow $DOCKGE_PORT/tcp"; then
        log "WARN" "Dockge 포트 방화벽 설정에 실패했습니다."
    fi
    
    log "INFO" "Dockge 방화벽 설정 완료"
    return 0
}

# Dockge 자동 시작 설정 함수
configure_dockge_autostart() {
    log "INFO" "Dockge 자동 시작을 설정하는 중..."
    
    # systemd 서비스 파일 생성
    local service_content="[Unit]
Description=Dockge Docker Compose Manager
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/dockge
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target"
    
    if ! exec_in_container "cat > /etc/systemd/system/dockge.service << 'EOF'
$service_content
EOF"; then
        log "WARN" "Dockge systemd 서비스 파일 생성에 실패했습니다."
        return 0
    fi
    
    # 서비스 활성화
    if ! exec_in_container "systemctl daemon-reload"; then
        log "WARN" "systemd 데몬 리로드에 실패했습니다."
    fi
    
    if ! exec_in_container "systemctl enable dockge.service"; then
        log "WARN" "Dockge 서비스 자동 시작 설정에 실패했습니다."
    fi
    
    log "INFO" "Dockge 자동 시작 설정 완료"
    return 0
}

# Dockge 설치 메인 함수
install_dockge() {
    log "INFO" "=== Dockge 설치 시작 ==="
    
    show_progress 1 7 "Dockge 디렉토리 생성 중..."
    if ! create_dockge_directories; then
        return 1
    fi
    
    show_progress 2 7 "Dockge Compose 파일 생성 중..."
    if ! create_dockge_compose; then
        return 1
    fi
    
    show_progress 3 7 "Dockge 환경변수 설정 중..."
    if ! create_dockge_env; then
        return 1
    fi
    
    show_progress 4 7 "Dockge 서비스 시작 중..."
    if ! start_dockge_service; then
        return 1
    fi
    
    show_progress 5 7 "Dockge 설치 검증 중..."
    if ! verify_dockge_installation; then
        return 1
    fi
    
    show_progress 6 7 "Dockge 방화벽 설정 중..."
    if ! configure_dockge_firewall; then
        return 1
    fi
    
    show_progress 7 7 "Dockge 자동 시작 설정 중..."
    if ! configure_dockge_autostart; then
        return 1
    fi
    
    log "INFO" "=== Dockge 설치 완료 ==="
    log "INFO" "Dockge 웹 인터페이스: http://$DOMAIN:$DOCKGE_PORT"
    return 0
}

# 임시 디렉토리 생성 함수
create_temp_directories() {
    log "INFO" "임시 디렉토리를 생성하는 중..."
    
    # 호스트에서 임시 디렉토리 생성
    if [ ! -d "$TEMP_DIR" ]; then
        mkdir -p "$TEMP_DIR"
        log "INFO" "호스트 임시 디렉토리 생성: $TEMP_DIR"
    fi
    
    # 컨테이너 내부에 임시 디렉토리 생성
    if ! exec_in_container "mkdir -p /tmp/supabase_installer"; then
        log "ERROR" "컨테이너 임시 디렉토리 생성에 실패했습니다."
        return 1
    fi
    
    if ! exec_in_container "mkdir -p /tmp/supabase_installer/supabase"; then
        log "ERROR" "Supabase 임시 디렉토리 생성에 실패했습니다."
        return 1
    fi
    
    if ! exec_in_container "mkdir -p /tmp/supabase_installer/temp_files"; then
        log "ERROR" "임시 파일 디렉토리 생성에 실패했습니다."
        return 1
    fi
    
    log "INFO" "임시 디렉토리 생성 완료"
    return 0
}

# Supabase 설정 파일 다운로드 함수
download_supabase_configs() {
    log "INFO" "=== Supabase 설정 파일 다운로드 시작 ==="
    
    local base_url="https://raw.githubusercontent.com/supabase/supabase/master/docker"
    local temp_supabase_dir="/tmp/supabase_installer/supabase"
    
    # docker-compose.yml 다운로드
    log "INFO" "Supabase docker-compose.yml 파일을 다운로드하는 중..."
    if ! exec_in_container "curl -fsSL '$base_url/docker-compose.yml' -o '$temp_supabase_dir/docker-compose.yml'"; then
        log "ERROR" "docker-compose.yml 다운로드에 실패했습니다."
        return 1
    fi
    
    # .env.example 다운로드
    log "INFO" "Supabase .env.example 파일을 다운로드하는 중..."
    if ! exec_in_container "curl -fsSL '$base_url/.env.example' -o '$temp_supabase_dir/.env.example'"; then
        log "ERROR" ".env.example 다운로드에 실패했습니다."
        return 1
    fi
    
    # volumes 디렉토리 다운로드
    log "INFO" "Supabase volumes 설정을 다운로드하는 중..."
    if ! exec_in_container "mkdir -p '$temp_supabase_dir/volumes'"; then
        log "ERROR" "volumes 디렉토리 생성에 실패했습니다."
        return 1
    fi
    
    # volumes 내부 파일들 다운로드
    local volume_files=(
        "api/kong.yml"
        "db/init/data.sql"
        "db/realtime.sql"
        "logs/vector.yml"
    )
    
    for file in "${volume_files[@]}"; do
        local file_dir=$(dirname "$file")
        if ! exec_in_container "mkdir -p '$temp_supabase_dir/volumes/$file_dir'"; then
            log "WARN" "volumes/$file_dir 디렉토리 생성에 실패했습니다."
            continue
        fi
        
        if ! exec_in_container "curl -fsSL '$base_url/volumes/$file' -o '$temp_supabase_dir/volumes/$file'"; then
            log "WARN" "volumes/$file 다운로드에 실패했습니다."
        fi
    done
    
    log "INFO" "Supabase 설정 파일 다운로드 완료"
    return 0
}

# 다운로드된 파일 검증 함수
verify_downloaded_files() {
    log "INFO" "다운로드된 파일들을 검증하는 중..."
    
    local temp_supabase_dir="/tmp/supabase_installer/supabase"
    local required_files=(
        "docker-compose.yml"
        ".env.example"
    )
    
    for file in "${required_files[@]}"; do
        if ! exec_in_container "[ -f '$temp_supabase_dir/$file' ]"; then
            log "ERROR" "필수 파일이 누락되었습니다: $file"
            return 1
        fi
        
        # 파일 크기 확인 (빈 파일 체크)
        local file_size=$(pct exec "$LXC_ID" -- stat -c%s "$temp_supabase_dir/$file" 2>/dev/null)
        if [ "$file_size" -eq 0 ]; then
            log "ERROR" "파일이 비어있습니다: $file"
            return 1
        fi
    done
    
    log "INFO" "다운로드된 파일 검증 완료"
    return 0
}

# 설정 파일 백업 함수
backup_config_files() {
    log "INFO" "설정 파일을 백업하는 중..."
    
    local temp_supabase_dir="/tmp/supabase_installer/supabase"
    local backup_dir="/tmp/supabase_installer/backup"
    
    if ! exec_in_container "mkdir -p '$backup_dir'"; then
        log "WARN" "백업 디렉토리 생성에 실패했습니다."
        return 0
    fi
    
    # 원본 파일들 백업
    if ! exec_in_container "cp -r '$temp_supabase_dir' '$backup_dir/original'"; then
        log "WARN" "설정 파일 백업에 실패했습니다."
        return 0
    fi
    
    log "INFO" "설정 파일 백업 완료"
    return 0
}

# 임시 파일 정리 함수 (향상된 버전)
cleanup_temp_files_enhanced() {
    log "INFO" "임시 파일들을 정리하는 중..."
    
    # 컨테이너 내부 임시 파일 정리
    if pct status "$LXC_ID" | grep -q "running"; then
        exec_in_container "rm -rf /tmp/supabase_installer" 2>/dev/null || true
        log "INFO" "컨테이너 내부 임시 파일 정리 완료"
    fi
    
    # 호스트 임시 파일 정리
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        log "INFO" "호스트 임시 파일 정리 완료: $TEMP_DIR"
    fi
    
    log "INFO" "모든 임시 파일 정리 완료"
}

# 오류 발생시 정리 함수
cleanup_on_error() {
    log "ERROR" "오류가 발생했습니다. 임시 파일을 정리합니다..."
    cleanup_temp_files_enhanced
    
    # 생성된 컨테이너가 있다면 정리 옵션 제공 (LXC_ID가 비어있지 않고 숫자인 경우만)
    if [ -n "$LXC_ID" ] && [[ "$LXC_ID" =~ ^[0-9]+$ ]] && pct status "$LXC_ID" &>/dev/null; then
        echo -e "\n${YELLOW}생성된 LXC 컨테이너 (ID: $LXC_ID)를 삭제하시겠습니까?${NC}"
        echo -ne "${BLUE}컨테이너 삭제 [y/N]${NC}: "
        read -r cleanup_container
        
        case $cleanup_container in
            [Yy]|[Yy][Ee][Ss])
                log "INFO" "LXC 컨테이너를 삭제하는 중..."
                pct stop "$LXC_ID" 2>/dev/null || true
                pct destroy "$LXC_ID" 2>/dev/null || true
                log "INFO" "LXC 컨테이너 삭제 완료"
                ;;
            *)
                log "INFO" "LXC 컨테이너는 유지됩니다. (ID: $LXC_ID)"
                ;;
        esac
    fi
}

# 향상된 trap 설정
setup_enhanced_trap() {
    # 기존 trap 함수를 오류 처리용으로 변경
    trap cleanup_on_error EXIT INT TERM
}

# 임시 파일 관리 시스템 초기화 함수
initialize_temp_file_system() {
    log "INFO" "=== 임시 파일 관리 시스템 초기화 ==="
    
    show_progress 1 4 "향상된 trap 설정 중..."
    setup_enhanced_trap
    
    show_progress 2 4 "임시 디렉토리 생성 중..."
    if ! create_temp_directories; then
        return 1
    fi
    
    show_progress 3 4 "Supabase 설정 파일 다운로드 중..."
    if ! download_supabase_configs; then
        return 1
    fi
    
    show_progress 4 4 "다운로드된 파일 검증 중..."
    if ! verify_downloaded_files; then
        return 1
    fi
    
    # 설정 파일 백업
    backup_config_files
    
    log "INFO" "=== 임시 파일 관리 시스템 초기화 완료 ==="
    return 0
}

# CloudCmd 스택 디렉토리 생성 함수
create_cloudcmd_stack_directory() {
    log "INFO" "CloudCmd 스택 디렉토리를 생성하는 중..."
    
    # CloudCmd 스택 디렉토리 생성
    if ! exec_in_container "mkdir -p /opt/dockge/stacks/cloudcmd"; then
        log "ERROR" "CloudCmd 스택 디렉토리 생성에 실패했습니다."
        return 1
    fi
    
    # CloudCmd 데이터 디렉토리 생성
    if ! exec_in_container "mkdir -p /opt/dockge/stacks/cloudcmd/data"; then
        log "ERROR" "CloudCmd 데이터 디렉토리 생성에 실패했습니다."
        return 1
    fi
    
    log "INFO" "CloudCmd 스택 디렉토리 생성 완료"
    return 0
}

# CloudCmd Docker Compose 파일 생성 함수
create_cloudcmd_compose() {
    log "INFO" "CloudCmd Docker Compose 파일을 생성하는 중..."
    
    # CloudCmd compose.yaml 파일 내용
    local compose_content="version: '3.8'

services:
  cloudcmd:
    image: coderaiser/cloudcmd:latest
    restart: unless-stopped
    ports:
      - \"$CLOUDCMD_PORT:8000\"
    volumes:
      - /:/mnt/fs:ro
      - ./data:/root
    environment:
      - CLOUDCMD_ROOT=/mnt/fs
      - CLOUDCMD_EDITOR=dword
      - CLOUDCMD_TERMINAL=true
      - CLOUDCMD_CONSOLE=true
      - CLOUDCMD_AUTH=false
      - CLOUDCMD_USERNAME=admin
      - CLOUDCMD_PASSWORD=
    networks:
      - cloudcmd_network
    command: [\"--no-auth\", \"--no-server\", \"--port\", \"8000\"]

networks:
  cloudcmd_network:
    driver: bridge"
    
    # compose.yaml 파일 생성
    if ! exec_in_container "cat > /opt/dockge/stacks/cloudcmd/compose.yaml << 'EOF'
$compose_content
EOF"; then
        log "ERROR" "CloudCmd compose.yaml 파일 생성에 실패했습니다."
        return 1
    fi
    
    log "INFO" "CloudCmd Docker Compose 파일 생성 완료"
    return 0
}

# CloudCmd 환경변수 파일 생성 함수
create_cloudcmd_env() {
    log "INFO" "CloudCmd 환경변수 파일을 생성하는 중..."
    
    local env_content="# CloudCmd Configuration
CLOUDCMD_PORT=$CLOUDCMD_PORT
CLOUDCMD_ROOT=/mnt/fs
CLOUDCMD_EDITOR=dword
CLOUDCMD_TERMINAL=true
CLOUDCMD_CONSOLE=true
CLOUDCMD_AUTH=false

# Security Settings (disabled for ease of use)
CLOUDCMD_USERNAME=admin
CLOUDCMD_PASSWORD=

# UI Settings
CLOUDCMD_SHOW_CONFIG=true
CLOUDCMD_SHOW_KEYS_PANEL=true
CLOUDCMD_SHOW_HIDDEN_FILES=true

# Performance Settings
CLOUDCMD_BUFFER_SIZE=64
CLOUDCMD_COMPRESSION=true"
    
    # .env 파일 생성
    if ! exec_in_container "cat > /opt/dockge/stacks/cloudcmd/.env << 'EOF'
$env_content
EOF"; then
        log "ERROR" "CloudCmd .env 파일 생성에 실패했습니다."
        return 1
    fi
    
    log "INFO" "CloudCmd 환경변수 파일 생성 완료"
    return 0
}

# CloudCmd 설정 파일 생성 함수
create_cloudcmd_config() {
    log "INFO" "CloudCmd 설정 파일을 생성하는 중..."
    
    # CloudCmd 설정 JSON 파일 내용
    local config_content='{
    "auth": false,
    "username": "admin",
    "password": "",
    "root": "/mnt/fs",
    "editor": "dword",
    "packer": "tar",
    "zip": true,
    "buffer": true,
    "dirStorage": true,
    "online": false,
    "open": false,
    "cache": true,
    "showConfig": true,
    "showKeysPanel": true,
    "showHiddenFiles": true,
    "oneFilePanel": false,
    "terminal": true,
    "console": true,
    "syncConsoleCWD": true,
    "contact": false,
    "configDialog": true,
    "confirmCopy": true,
    "confirmMove": true,
    "confirmDelete": true,
    "vim": false,
    "columns": "name-size-date",
    "export": false,
    "import": false,
    "log": false
}'
    
    # 설정 파일 생성
    if ! exec_in_container "cat > /opt/dockge/stacks/cloudcmd/data/.cloudcmd.json << 'EOF'
$config_content
EOF"; then
        log "WARN" "CloudCmd 설정 파일 생성에 실패했습니다. 기본 설정을 사용합니다."
    fi
    
    log "INFO" "CloudCmd 설정 파일 생성 완료"
    return 0
}

# CloudCmd 방화벽 설정 함수
configure_cloudcmd_firewall() {
    log "INFO" "CloudCmd 방화벽 규칙을 설정하는 중..."
    
    # CloudCmd 포트 허용
    if ! exec_in_container "ufw allow $CLOUDCMD_PORT/tcp"; then
        log "WARN" "CloudCmd 포트 방화벽 설정에 실패했습니다."
    fi
    
    log "INFO" "CloudCmd 방화벽 설정 완료"
    return 0
}

# CloudCmd 스택 시작 함수
start_cloudcmd_stack() {
    log "INFO" "CloudCmd 스택을 시작하는 중..."
    
    # CloudCmd 스택 시작
    if ! exec_in_container "cd /opt/dockge/stacks/cloudcmd && docker-compose up -d"; then
        log "ERROR" "CloudCmd 스택 시작에 실패했습니다."
        return 1
    fi
    
    # 서비스 시작 대기
    log "INFO" "CloudCmd 서비스 시작을 대기하는 중..."
    local wait_count=0
    while [ $wait_count -lt 30 ]; do
        if exec_in_container "docker ps | grep -q cloudcmd"; then
            break
        fi
        sleep 2
        ((wait_count++))
    done
    
    if [ $wait_count -ge 30 ]; then
        log "ERROR" "CloudCmd 서비스 시작 시간이 초과되었습니다."
        return 1
    fi
    
    log "INFO" "CloudCmd 스택이 성공적으로 시작되었습니다."
    return 0
}

# CloudCmd 설치 검증 함수
verify_cloudcmd_installation() {
    log "INFO" "CloudCmd 설치를 검증하는 중..."
    
    # 컨테이너 상태 확인
    if ! exec_in_container "docker ps | grep -q cloudcmd"; then
        log "ERROR" "CloudCmd 컨테이너가 실행되지 않고 있습니다."
        return 1
    fi
    
    # 포트 접근 확인
    local wait_count=0
    while [ $wait_count -lt 30 ]; do
        if exec_in_container "curl -s http://localhost:$CLOUDCMD_PORT > /dev/null"; then
            break
        fi
        sleep 2
        ((wait_count++))
    done
    
    if [ $wait_count -ge 30 ]; then
        log "ERROR" "CloudCmd 웹 인터페이스에 접근할 수 없습니다."
        return 1
    fi
    
    log "INFO" "CloudCmd 설치 검증 완료"
    return 0
}

# CloudCmd 권한 설정 함수
configure_cloudcmd_permissions() {
    log "INFO" "CloudCmd 권한을 설정하는 중..."
    
    # CloudCmd 데이터 디렉토리 권한 설정
    if ! exec_in_container "chmod 755 /opt/dockge/stacks/cloudcmd/data"; then
        log "WARN" "CloudCmd 데이터 디렉토리 권한 설정에 실패했습니다."
    fi
    
    # 설정 파일 권한 설정
    if ! exec_in_container "chmod 644 /opt/dockge/stacks/cloudcmd/.env"; then
        log "WARN" "CloudCmd 환경변수 파일 권한 설정에 실패했습니다."
    fi
    
    log "INFO" "CloudCmd 권한 설정 완료"
    return 0
}

# CloudCmd 스택 생성 메인 함수
setup_cloudcmd_stack() {
    log "INFO" "=== CloudCmd 스택 생성 시작 ==="
    
    show_progress 1 8 "CloudCmd 스택 디렉토리 생성 중..."
    if ! create_cloudcmd_stack_directory; then
        return 1
    fi
    
    show_progress 2 8 "CloudCmd Compose 파일 생성 중..."
    if ! create_cloudcmd_compose; then
        return 1
    fi
    
    show_progress 3 8 "CloudCmd 환경변수 설정 중..."
    if ! create_cloudcmd_env; then
        return 1
    fi
    
    show_progress 4 8 "CloudCmd 설정 파일 생성 중..."
    if ! create_cloudcmd_config; then
        return 1
    fi
    
    show_progress 5 8 "CloudCmd 권한 설정 중..."
    if ! configure_cloudcmd_permissions; then
        return 1
    fi
    
    show_progress 6 8 "CloudCmd 방화벽 설정 중..."
    if ! configure_cloudcmd_firewall; then
        return 1
    fi
    
    show_progress 7 8 "CloudCmd 스택 시작 중..."
    if ! start_cloudcmd_stack; then
        return 1
    fi
    
    show_progress 8 8 "CloudCmd 설치 검증 중..."
    if ! verify_cloudcmd_installation; then
        return 1
    fi
    
    log "INFO" "=== CloudCmd 스택 생성 완료 ==="
    log "INFO" "CloudCmd 웹 인터페이스: http://$DOMAIN:$CLOUDCMD_PORT"
    return 0
}

# Supabase 스택 디렉토리 생성 함수
create_supabase_stack_directory() {
    log "INFO" "Supabase 스택 디렉토리를 생성하는 중..."
    
    # Supabase 스택 디렉토리 생성
    if ! exec_in_container "mkdir -p /opt/dockge/stacks/supabase"; then
        log "ERROR" "Supabase 스택 디렉토리 생성에 실패했습니다."
        return 1
    fi
    
    # Supabase 볼륨 디렉토리 생성
    if ! exec_in_container "mkdir -p /opt/dockge/stacks/supabase/volumes"; then
        log "ERROR" "Supabase 볼륨 디렉토리 생성에 실패했습니다."
        return 1
    fi
    
    log "INFO" "Supabase 스택 디렉토리 생성 완료"
    return 0
}

# JWT 키 생성 함수
generate_jwt_keys() {
    log "INFO" "JWT 키를 생성하는 중..."
    
    # JWT 시크릿이 이미 설정되어 있지 않으면 생성
    if [ -z "$JWT_SECRET" ]; then
        JWT_SECRET=$(openssl rand -base64 64 | tr -d "=+/" | cut -c1-64)
    fi
    
    # Supabase JWT 키 생성 (실제 JWT 토큰 형식)
    local header='{"alg":"HS256","typ":"JWT"}'
    local anon_payload='{"iss":"supabase","ref":"localhost","role":"anon","iat":1641916800,"exp":2000000000}'
    local service_payload='{"iss":"supabase","ref":"localhost","role":"service_role","iat":1641916800,"exp":2000000000}'
    
    # Base64 인코딩 (URL-safe)
    local header_b64=$(echo -n "$header" | base64 -w 0 | tr '+/' '-_' | tr -d '=')
    local anon_payload_b64=$(echo -n "$anon_payload" | base64 -w 0 | tr '+/' '-_' | tr -d '=')
    local service_payload_b64=$(echo -n "$service_payload" | base64 -w 0 | tr '+/' '-_' | tr -d '=')
    
    # HMAC 서명 생성
    local anon_signature=$(echo -n "${header_b64}.${anon_payload_b64}" | openssl dgst -sha256 -hmac "$JWT_SECRET" -binary | base64 -w 0 | tr '+/' '-_' | tr -d '=')
    local service_signature=$(echo -n "${header_b64}.${service_payload_b64}" | openssl dgst -sha256 -hmac "$JWT_SECRET" -binary | base64 -w 0 | tr '+/' '-_' | tr -d '=')
    
    # 최종 JWT 토큰
    ANON_KEY="${header_b64}.${anon_payload_b64}.${anon_signature}"
    SERVICE_ROLE_KEY="${header_b64}.${service_payload_b64}.${service_signature}"
    
    log "INFO" "JWT 키 생성 완료"
    return 0
}

# Supabase 환경변수 파일 생성 함수
create_supabase_env() {
    log "INFO" "Supabase 환경변수 파일을 생성하는 중..."
    
    # JWT 키 생성
    generate_jwt_keys
    
    local env_content="############
# Secrets
# YOU MUST CHANGE THESE BEFORE GOING INTO PRODUCTION
############

POSTGRES_PASSWORD=$POSTGRES_PASSWORD
JWT_SECRET=$JWT_SECRET
ANON_KEY=$ANON_KEY
SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY

############
# Database
############

POSTGRES_HOST=db
POSTGRES_DB=postgres
POSTGRES_PORT=5432
# default user is postgres

############
# API Proxy
############

KONG_HTTP_PORT=8001
KONG_HTTPS_PORT=8444

############
# API
############

API_EXTERNAL_URL=$API_EXTERNAL_URL
SUPABASE_PUBLIC_URL=$SUPABASE_PUBLIC_URL

# PostgREST
PGRST_DB_SCHEMAS=public,storage,graphql_public
PGRST_DB_ANON_ROLE=anon
PGRST_DB_USE_LEGACY_GUCS=false
PGRST_APP_SETTINGS_JWT_SECRET=$JWT_SECRET
PGRST_APP_SETTINGS_JWT_EXP=3600

############
# Auth
############

## General
SITE_URL=$SUPABASE_PUBLIC_URL
ADDITIONAL_REDIRECT_URLS=
JWT_EXPIRY=3600
DISABLE_SIGNUP=false
API_EXTERNAL_URL=$API_EXTERNAL_URL

## Mailer Config
MAILER_URLPATHS_CONFIRMATION=\"/auth/v1/verify\"
MAILER_URLPATHS_INVITE=\"/auth/v1/verify\"
MAILER_URLPATHS_RECOVERY=\"/auth/v1/verify\"
MAILER_URLPATHS_EMAIL_CHANGE=\"/auth/v1/verify\"

## Email auth
ENABLE_EMAIL_SIGNUP=true
ENABLE_EMAIL_AUTOCONFIRM=false"
    
    # SMTP 설정이 있으면 추가
    if [ -n "$SMTP_HOST" ]; then
        env_content="$env_content

############
# SMTP
############

SMTP_ADMIN_EMAIL=admin@example.com
SMTP_HOST=$SMTP_HOST
SMTP_PORT=$SMTP_PORT
SMTP_USER=$SMTP_USER
SMTP_PASS=$SMTP_PASS
SMTP_SENDER_NAME=Supabase"
    else
        env_content="$env_content

############
# SMTP (Disabled)
############

SMTP_ADMIN_EMAIL=
SMTP_HOST=
SMTP_PORT=587
SMTP_USER=
SMTP_PASS=
SMTP_SENDER_NAME="
    fi
    
    env_content="$env_content

############
# Phone auth
############

ENABLE_PHONE_SIGNUP=true
ENABLE_PHONE_AUTOCONFIRM=true

############
# Storage
############

STORAGE_BACKEND=file
GLOBAL_S3_BUCKET=supabase-storage
REGION=us-east-1
STORAGE_S3_REGION=us-east-1

############
# Functions
############

FUNCTIONS_VERIFY_JWT=false

############
# Logs
############

LOGFLARE_API_KEY=your-super-secret-and-long-logflare-key
LOGFLARE_URL=https://api.logflare.app

############
# Analytics
############

ENABLE_ANALYTICS=false

############
# Studio
############

STUDIO_DEFAULT_ORGANIZATION=Default Organization
STUDIO_DEFAULT_PROJECT=Default Project
STUDIO_PORT=$SUPABASE_STUDIO_PORT
SUPABASE_PUBLIC_URL=$SUPABASE_PUBLIC_URL"
    
    # .env 파일 생성
    if ! exec_in_container "cat > /opt/dockge/stacks/supabase/.env << 'EOF'
$env_content
EOF"; then
        log "ERROR" "Supabase .env 파일 생성에 실패했습니다."
        return 1
    fi
    
    log "INFO" "Supabase 환경변수 파일 생성 완료"
    return 0
}

# Supabase Docker Compose 파일 수정 함수
modify_supabase_compose() {
    log "INFO" "Supabase Docker Compose 파일을 수정하는 중..."
    
    local temp_supabase_dir="/tmp/supabase_installer/supabase"
    local stack_dir="/opt/dockge/stacks/supabase"
    
    # 다운로드된 compose 파일을 스택 디렉토리로 복사
    if ! exec_in_container "cp '$temp_supabase_dir/docker-compose.yml' '$stack_dir/compose.yaml'"; then
        log "ERROR" "Supabase compose 파일 복사에 실패했습니다."
        return 1
    fi
    
    # Studio 포트 수정
    if ! exec_in_container "sed -i 's/3000:3000/$SUPABASE_STUDIO_PORT:3000/' '$stack_dir/compose.yaml'"; then
        log "WARN" "Studio 포트 수정에 실패했습니다."
    fi
    
    # Kong 포트 수정 (API Gateway)
    if ! exec_in_container "sed -i 's/8000:8000/8001:8000/' '$stack_dir/compose.yaml'"; then
        log "WARN" "Kong 포트 수정에 실패했습니다."
    fi
    
    log "INFO" "Supabase Docker Compose 파일 수정 완료"
    return 0
}

# Supabase 볼륨 파일 복사 함수
copy_supabase_volumes() {
    log "INFO" "Supabase 볼륨 파일들을 복사하는 중..."
    
    local temp_supabase_dir="/tmp/supabase_installer/supabase"
    local stack_dir="/opt/dockge/stacks/supabase"
    
    # volumes 디렉토리가 존재하면 복사
    if exec_in_container "[ -d '$temp_supabase_dir/volumes' ]"; then
        if ! exec_in_container "cp -r '$temp_supabase_dir/volumes'/* '$stack_dir/volumes/' 2>/dev/null || true"; then
            log "WARN" "일부 볼륨 파일 복사에 실패했습니다."
        fi
    fi
    
    log "INFO" "Supabase 볼륨 파일 복사 완료"
    return 0
}

# Supabase 방화벽 설정 함수
configure_supabase_firewall() {
    log "INFO" "Supabase 방화벽 규칙을 설정하는 중..."
    
    # Supabase Studio 포트 허용
    if ! exec_in_container "ufw allow $SUPABASE_STUDIO_PORT/tcp"; then
        log "WARN" "Supabase Studio 포트 방화벽 설정에 실패했습니다."
    fi
    
    # Kong API Gateway 포트 허용
    if ! exec_in_container "ufw allow 8001/tcp"; then
        log "WARN" "Kong API Gateway 포트 방화벽 설정에 실패했습니다."
    fi
    
    log "INFO" "Supabase 방화벽 설정 완료"
    return 0
}

# Supabase 스택 시작 함수
start_supabase_stack() {
    log "INFO" "Supabase 스택을 시작하는 중..."
    
    # Supabase 스택 시작 (백그라운드에서)
    if ! exec_in_container "cd /opt/dockge/stacks/supabase && docker-compose up -d"; then
        log "ERROR" "Supabase 스택 시작에 실패했습니다."
        return 1
    fi
    
    # 서비스 시작 대기 (Supabase는 시작 시간이 오래 걸림)
    log "INFO" "Supabase 서비스들이 시작되기를 대기하는 중... (최대 2분)"
    local wait_count=0
    while [ $wait_count -lt 60 ]; do
        local running_containers=$(pct exec "$LXC_ID" -- docker ps --format "table {{.Names}}" | grep -E "(supabase|postgres|kong)" | wc -l)
        if [ "$running_containers" -ge 3 ]; then
            break
        fi
        sleep 2
        ((wait_count++))
        
        # 진행 상황 표시
        if [ $((wait_count % 10)) -eq 0 ]; then
            log "INFO" "Supabase 서비스 시작 대기 중... ($((wait_count * 2))초 경과)"
        fi
    done
    
    if [ $wait_count -ge 60 ]; then
        log "WARN" "Supabase 서비스 시작 시간이 초과되었습니다. 백그라운드에서 계속 시작 중일 수 있습니다."
    else
        log "INFO" "Supabase 스택이 성공적으로 시작되었습니다."
    fi
    
    return 0
}

# Supabase 설치 검증 함수
verify_supabase_installation() {
    log "INFO" "Supabase 설치를 검증하는 중..."
    
    # 주요 컨테이너들이 실행 중인지 확인
    local required_containers=("postgres" "kong" "supabase")
    local running_count=0
    
    for container in "${required_containers[@]}"; do
        if exec_in_container "docker ps | grep -q $container"; then
            ((running_count++))
        fi
    done
    
    if [ $running_count -lt 2 ]; then
        log "WARN" "일부 Supabase 컨테이너가 실행되지 않고 있습니다. ($running_count/3)"
        log "INFO" "서비스가 아직 시작 중일 수 있습니다. 나중에 다시 확인해주세요."
    else
        log "INFO" "Supabase 주요 서비스들이 실행 중입니다."
    fi
    
    # Studio 접근 확인 (타임아웃 짧게)
    local wait_count=0
    while [ $wait_count -lt 15 ]; do
        if exec_in_container "curl -s --connect-timeout 2 http://localhost:$SUPABASE_STUDIO_PORT > /dev/null 2>&1"; then
            log "INFO" "Supabase Studio에 접근 가능합니다."
            break
        fi
        sleep 2
        ((wait_count++))
    done
    
    if [ $wait_count -ge 15 ]; then
        log "WARN" "Supabase Studio에 즉시 접근할 수 없습니다. 서비스가 완전히 시작되면 접근 가능합니다."
    fi
    
    log "INFO" "Supabase 설치 검증 완료"
    return 0
}

# Supabase 권한 설정 함수
configure_supabase_permissions() {
    log "INFO" "Supabase 권한을 설정하는 중..."
    
    # 환경변수 파일 권한 설정 (보안상 중요)
    if ! exec_in_container "chmod 600 /opt/dockge/stacks/supabase/.env"; then
        log "WARN" "Supabase 환경변수 파일 권한 설정에 실패했습니다."
    fi
    
    # 볼륨 디렉토리 권한 설정
    if ! exec_in_container "chmod -R 755 /opt/dockge/stacks/supabase/volumes"; then
        log "WARN" "Supabase 볼륨 디렉토리 권한 설정에 실패했습니다."
    fi
    
    log "INFO" "Supabase 권한 설정 완료"
    return 0
}

# Supabase 스택 생성 메인 함수
setup_supabase_stack() {
    log "INFO" "=== Supabase 스택 생성 시작 ==="
    
    show_progress 1 9 "Supabase 스택 디렉토리 생성 중..."
    if ! create_supabase_stack_directory; then
        return 1
    fi
    
    show_progress 2 9 "Supabase 환경변수 생성 중..."
    if ! create_supabase_env; then
        return 1
    fi
    
    show_progress 3 9 "Supabase Compose 파일 수정 중..."
    if ! modify_supabase_compose; then
        return 1
    fi
    
    show_progress 4 9 "Supabase 볼륨 파일 복사 중..."
    if ! copy_supabase_volumes; then
        return 1
    fi
    
    show_progress 5 9 "Supabase 권한 설정 중..."
    if ! configure_supabase_permissions; then
        return 1
    fi
    
    show_progress 6 9 "Supabase 방화벽 설정 중..."
    if ! configure_supabase_firewall; then
        return 1
    fi
    
    show_progress 7 9 "Supabase 스택 시작 중..."
    if ! start_supabase_stack; then
        return 1
    fi
    
    show_progress 8 9 "Supabase 설치 검증 중..."
    if ! verify_supabase_installation; then
        return 1
    fi
    
    show_progress 9 9 "Supabase 스택 생성 완료..."
    
    log "INFO" "=== Supabase 스택 생성 완료 ==="
    log "INFO" "Supabase Studio: http://$DOMAIN:$SUPABASE_STUDIO_PORT"
    log "INFO" "Supabase API: http://$DOMAIN:8001"
    return 0
}

# 모든 서비스 상태 확인 함수
check_all_services_status() {
    log "INFO" "모든 서비스 상태를 확인하는 중..."
    
    local services_status=()
    
    # Dockge 상태 확인
    if exec_in_container "docker ps | grep -q dockge"; then
        services_status+=("Dockge: ✓ 실행 중")
    else
        services_status+=("Dockge: ✗ 중지됨")
    fi
    
    # CloudCmd 상태 확인
    if exec_in_container "docker ps | grep -q cloudcmd"; then
        services_status+=("CloudCmd: ✓ 실행 중")
    else
        services_status+=("CloudCmd: ✗ 중지됨")
    fi
    
    # Supabase 서비스들 상태 확인
    local supabase_services=("postgres" "kong" "supabase")
    local supabase_running=0
    
    for service in "${supabase_services[@]}"; do
        if exec_in_container "docker ps | grep -q $service"; then
            ((supabase_running++))
        fi
    done
    
    services_status+=("Supabase: ✓ $supabase_running/3 서비스 실행 중")
    
    # 상태 출력
    for status in "${services_status[@]}"; do
        log "INFO" "$status"
    done
    
    return 0
}

# 서비스 포트 접근성 확인 함수
check_service_accessibility() {
    log "INFO" "서비스 포트 접근성을 확인하는 중..."
    
    local services=(
        "Dockge:$DOCKGE_PORT"
        "CloudCmd:$CLOUDCMD_PORT"
        "Supabase Studio:$SUPABASE_STUDIO_PORT"
        "Supabase API:8001"
    )
    
    for service_info in "${services[@]}"; do
        local service_name=$(echo "$service_info" | cut -d':' -f1)
        local service_port=$(echo "$service_info" | cut -d':' -f2)
        
        if exec_in_container "timeout 5 bash -c '</dev/tcp/localhost/$service_port' 2>/dev/null"; then
            log "INFO" "$service_name (포트 $service_port): ✓ 접근 가능"
        else
            log "WARN" "$service_name (포트 $service_port): ✗ 접근 불가 (아직 시작 중일 수 있음)"
        fi
    done
    
    return 0
}

# 서비스 로그 확인 함수
check_service_logs() {
    log "INFO" "서비스 로그를 확인하는 중..."
    
    # Dockge 로그 확인
    log "DEBUG" "Dockge 로그 (최근 5줄):"
    exec_in_container "cd /opt/dockge && docker-compose logs --tail=5 dockge 2>/dev/null || echo '로그를 가져올 수 없습니다.'"
    
    # CloudCmd 로그 확인
    log "DEBUG" "CloudCmd 로그 (최근 5줄):"
    exec_in_container "cd /opt/dockge/stacks/cloudcmd && docker-compose logs --tail=5 cloudcmd 2>/dev/null || echo '로그를 가져올 수 없습니다.'"
    
    # Supabase 주요 서비스 로그 확인
    log "DEBUG" "Supabase 로그 (최근 3줄):"
    exec_in_container "cd /opt/dockge/stacks/supabase && docker-compose logs --tail=3 2>/dev/null || echo '로그를 가져올 수 없습니다.'"
    
    return 0
}

# 서비스 재시작 함수
restart_failed_services() {
    log "INFO" "실패한 서비스들을 재시작하는 중..."
    
    local restart_needed=false
    
    # Dockge 재시작 확인
    if ! exec_in_container "docker ps | grep -q dockge"; then
        log "WARN" "Dockge가 중지되어 있습니다. 재시작을 시도합니다..."
        if exec_in_container "cd /opt/dockge && docker-compose restart"; then
            log "INFO" "Dockge 재시작 성공"
        else
            log "ERROR" "Dockge 재시작 실패"
        fi
        restart_needed=true
    fi
    
    # CloudCmd 재시작 확인
    if ! exec_in_container "docker ps | grep -q cloudcmd"; then
        log "WARN" "CloudCmd가 중지되어 있습니다. 재시작을 시도합니다..."
        if exec_in_container "cd /opt/dockge/stacks/cloudcmd && docker-compose restart"; then
            log "INFO" "CloudCmd 재시작 성공"
        else
            log "ERROR" "CloudCmd 재시작 실패"
        fi
        restart_needed=true
    fi
    
    # Supabase 재시작 확인 (주요 서비스만)
    local supabase_running=$(pct exec "$LXC_ID" -- docker ps --format "table {{.Names}}" | grep -E "(postgres|kong)" | wc -l)
    if [ "$supabase_running" -lt 2 ]; then
        log "WARN" "Supabase 주요 서비스가 부족합니다. 재시작을 시도합니다..."
        if exec_in_container "cd /opt/dockge/stacks/supabase && docker-compose restart"; then
            log "INFO" "Supabase 재시작 시작됨 (완료까지 시간이 걸릴 수 있습니다)"
        else
            log "ERROR" "Supabase 재시작 실패"
        fi
        restart_needed=true
    fi
    
    if ! $restart_needed; then
        log "INFO" "모든 서비스가 정상적으로 실행 중입니다."
    fi
    
    return 0
}

# 서비스 상태 대기 함수
wait_for_services() {
    log "INFO" "모든 서비스가 완전히 시작되기를 대기하는 중..."
    
    local max_wait=60  # 최대 2분 대기
    local wait_count=0
    
    while [ $wait_count -lt $max_wait ]; do
        local ready_services=0
        
        # 각 서비스 준비 상태 확인
        if exec_in_container "curl -s --connect-timeout 2 http://localhost:$DOCKGE_PORT > /dev/null 2>&1"; then
            ((ready_services++))
        fi
        
        if exec_in_container "curl -s --connect-timeout 2 http://localhost:$CLOUDCMD_PORT > /dev/null 2>&1"; then
            ((ready_services++))
        fi
        
        if exec_in_container "curl -s --connect-timeout 2 http://localhost:$SUPABASE_STUDIO_PORT > /dev/null 2>&1"; then
            ((ready_services++))
        fi
        
        # 3개 서비스 모두 준비되면 완료
        if [ $ready_services -ge 3 ]; then
            log "INFO" "모든 서비스가 준비되었습니다!"
            return 0
        fi
        
        # 진행 상황 표시
        if [ $((wait_count % 10)) -eq 0 ]; then
            log "INFO" "서비스 준비 대기 중... ($ready_services/3 준비됨, $((wait_count * 2))초 경과)"
        fi
        
        sleep 2
        ((wait_count++))
    done
    
    log "WARN" "일부 서비스가 아직 준비되지 않았습니다. 백그라운드에서 계속 시작 중일 수 있습니다."
    return 0
}

# 서비스 헬스체크 함수
perform_health_check() {
    log "INFO" "서비스 헬스체크를 수행하는 중..."
    
    local health_status=()
    
    # Dockge 헬스체크
    if exec_in_container "curl -s http://localhost:$DOCKGE_PORT/api/info 2>/dev/null | grep -q 'dockge'"; then
        health_status+=("Dockge API: ✓ 정상")
    else
        health_status+=("Dockge API: ⚠ 응답 없음")
    fi
    
    # CloudCmd 헬스체크
    if exec_in_container "curl -s http://localhost:$CLOUDCMD_PORT 2>/dev/null | grep -q 'Cloud Commander'"; then
        health_status+=("CloudCmd: ✓ 정상")
    else
        health_status+=("CloudCmd: ⚠ 응답 없음")
    fi
    
    # Supabase API 헬스체크
    if exec_in_container "curl -s http://localhost:8001/rest/v1/ 2>/dev/null | grep -q 'OpenAPI'"; then
        health_status+=("Supabase API: ✓ 정상")
    else
        health_status+=("Supabase API: ⚠ 응답 없음")
    fi
    
    # Supabase Studio 헬스체크
    if exec_in_container "curl -s http://localhost:$SUPABASE_STUDIO_PORT 2>/dev/null | grep -q 'Supabase'"; then
        health_status+=("Supabase Studio: ✓ 정상")
    else
        health_status+=("Supabase Studio: ⚠ 응답 없음")
    fi
    
    # 헬스체크 결과 출력
    for status in "${health_status[@]}"; do
        if [[ $status == *"✓"* ]]; then
            log "INFO" "$status"
        else
            log "WARN" "$status"
        fi
    done
    
    return 0
}

# 서비스 시작 및 상태 확인 메인 함수
start_and_verify_services() {
    log "INFO" "=== 서비스 시작 및 상태 확인 시작 ==="
    
    show_progress 1 6 "모든 서비스 상태 확인 중..."
    check_all_services_status
    
    show_progress 2 6 "실패한 서비스 재시작 중..."
    restart_failed_services
    
    show_progress 3 6 "서비스 준비 상태 대기 중..."
    wait_for_services
    
    show_progress 4 6 "서비스 포트 접근성 확인 중..."
    check_service_accessibility
    
    show_progress 5 6 "서비스 헬스체크 수행 중..."
    perform_health_check
    
    show_progress 6 6 "서비스 로그 확인 중..."
    check_service_logs
    
    log "INFO" "=== 서비스 시작 및 상태 확인 완료 ==="
    return 0
}

# 설치 요약 정보 생성 함수
generate_installation_summary() {
    log "INFO" "설치 요약 정보를 생성하는 중..."
    
    local summary_file="/opt/dockge/installation_summary.txt"
    local summary_content="# Supabase LXC 설치 요약
설치 일시: $(date '+%Y-%m-%d %H:%M:%S')
설치 스크립트: Supabase LXC Auto Installer

## LXC 컨테이너 정보
- 컨테이너 ID: $LXC_ID
- 컨테이너 이름: $LXC_NAME
- IP 주소: $LXC_IP
- 메모리: ${LXC_MEMORY}MB
- CPU 코어: $LXC_CORES
- 디스크: ${LXC_DISK}GB

## 서비스 접속 정보
- Dockge (Docker 관리): http://$DOMAIN:$DOCKGE_PORT
- CloudCmd (파일 관리): http://$DOMAIN:$CLOUDCMD_PORT
- Supabase Studio: http://$DOMAIN:$SUPABASE_STUDIO_PORT
- Supabase API: http://$DOMAIN:8001

## Supabase 인증 정보
- JWT Secret: $JWT_SECRET
- Anonymous Key: $ANON_KEY
- Service Role Key: $SERVICE_ROLE_KEY
- PostgreSQL 비밀번호: $POSTGRES_PASSWORD

## 중요 디렉토리
- Dockge 설치 경로: /opt/dockge
- CloudCmd 스택: /opt/dockge/stacks/cloudcmd
- Supabase 스택: /opt/dockge/stacks/supabase
- 로그 파일: $LOG_FILE

## 관리 명령어
- 모든 서비스 상태 확인: docker ps
- Dockge 재시작: cd /opt/dockge && docker-compose restart
- CloudCmd 재시작: cd /opt/dockge/stacks/cloudcmd && docker-compose restart
- Supabase 재시작: cd /opt/dockge/stacks/supabase && docker-compose restart

## 방화벽 설정
- SSH (22/tcp): 허용
- Dockge ($DOCKGE_PORT/tcp): 허용
- CloudCmd ($CLOUDCMD_PORT/tcp): 허용
- Supabase Studio ($SUPABASE_STUDIO_PORT/tcp): 허용
- Supabase API (8001/tcp): 허용"
    
    # SMTP 설정이 있으면 추가
    if [ -n "$SMTP_HOST" ]; then
        summary_content="$summary_content

## SMTP 설정
- SMTP 호스트: $SMTP_HOST
- SMTP 포트: $SMTP_PORT
- SMTP 사용자: $SMTP_USER"
    fi
    
    # 요약 파일 생성
    if ! exec_in_container "cat > '$summary_file' << 'EOF'
$summary_content
EOF"; then
        log "WARN" "설치 요약 파일 생성에 실패했습니다."
    else
        log "INFO" "설치 요약 파일 생성 완료: $summary_file"
    fi
    
    return 0
}

# 접속 정보 출력 함수
display_access_information() {
    log "INFO" "=== 설치 완료 및 접속 정보 ==="
    
    echo ""
    echo -e "${GREEN}🎉 Supabase LXC 자동 설치가 완료되었습니다! 🎉${NC}"
    echo ""
    
    echo -e "${BLUE}📋 LXC 컨테이너 정보${NC}"
    echo -e "   컨테이너 ID: ${YELLOW}$LXC_ID${NC}"
    echo -e "   컨테이너 이름: ${YELLOW}$LXC_NAME${NC}"
    echo -e "   IP 주소: ${YELLOW}$LXC_IP${NC}"
    echo -e "   리소스: ${YELLOW}${LXC_MEMORY}MB RAM, ${LXC_CORES} CPU 코어, ${LXC_DISK}GB 디스크${NC}"
    echo ""
    
    echo -e "${BLUE}🌐 웹 서비스 접속 정보${NC}"
    echo -e "   ${GREEN}Dockge (Docker 관리)${NC}"
    echo -e "   └─ URL: ${YELLOW}http://$DOMAIN:$DOCKGE_PORT${NC}"
    echo -e "   └─ 설명: Docker Compose 스택을 웹에서 관리할 수 있습니다"
    echo ""
    
    echo -e "   ${GREEN}CloudCmd (파일 관리)${NC}"
    echo -e "   └─ URL: ${YELLOW}http://$DOMAIN:$CLOUDCMD_PORT${NC}"
    echo -e "   └─ 설명: 웹 브라우저에서 파일 시스템을 관리할 수 있습니다"
    echo -e "   └─ 인증: 비활성화됨 (보안상 필요시 설정 변경)"
    echo ""
    
    echo -e "   ${GREEN}Supabase Studio${NC}"
    echo -e "   └─ URL: ${YELLOW}http://$DOMAIN:$SUPABASE_STUDIO_PORT${NC}"
    echo -e "   └─ 설명: Supabase 데이터베이스 및 API 관리 인터페이스"
    echo ""
    
    echo -e "   ${GREEN}Supabase API${NC}"
    echo -e "   └─ URL: ${YELLOW}http://$DOMAIN:8001${NC}"
    echo -e "   └─ 설명: REST API 엔드포인트"
    echo ""
    
    echo -e "${BLUE}🔑 Supabase 인증 정보${NC}"
    echo -e "   ${GREEN}Anonymous Key:${NC}"
    echo -e "   ${YELLOW}$ANON_KEY${NC}"
    echo ""
    echo -e "   ${GREEN}Service Role Key:${NC}"
    echo -e "   ${YELLOW}$SERVICE_ROLE_KEY${NC}"
    echo ""
    echo -e "   ${GREEN}PostgreSQL 비밀번호:${NC}"
    echo -e "   ${YELLOW}$POSTGRES_PASSWORD${NC}"
    echo ""
    
    if [ -n "$SMTP_HOST" ]; then
        echo -e "${BLUE}📧 SMTP 설정${NC}"
        echo -e "   호스트: ${YELLOW}$SMTP_HOST:$SMTP_PORT${NC}"
        echo -e "   사용자: ${YELLOW}$SMTP_USER${NC}"
        echo ""
    fi
    
    echo -e "${BLUE}🛠️ 관리 정보${NC}"
    echo -e "   설치 요약 파일: ${YELLOW}/opt/dockge/installation_summary.txt${NC}"
    echo -e "   로그 파일: ${YELLOW}$LOG_FILE${NC}"
    echo -e "   Dockge 설치 경로: ${YELLOW}/opt/dockge${NC}"
    echo ""
    
    echo -e "${BLUE}🔧 유용한 명령어${NC}"
    echo -e "   컨테이너 접속: ${YELLOW}pct enter $LXC_ID${NC}"
    echo -e "   모든 서비스 상태: ${YELLOW}docker ps${NC}"
    echo -e "   서비스 재시작: ${YELLOW}cd /opt/dockge && docker-compose restart${NC}"
    echo ""
    
    echo -e "${GREEN}✅ 다음 단계:${NC}"
    echo -e "   1. 웹 브라우저에서 Dockge에 접속하여 모든 스택이 실행 중인지 확인"
    echo -e "   2. Supabase Studio에 접속하여 데이터베이스 설정"
    echo -e "   3. 필요시 방화벽 규칙 추가 조정"
    echo -e "   4. 프로덕션 사용시 보안 설정 강화"
    echo ""
    
    return 0
}

# 관리자 계정 정보 출력 함수
display_admin_credentials() {
    log "INFO" "관리자 계정 정보를 출력하는 중..."
    
    echo -e "${BLUE}👤 관리자 계정 정보${NC}"
    echo -e "   ${GREEN}Dockge:${NC} 별도 인증 없음 (로컬 접근)"
    echo -e "   ${GREEN}CloudCmd:${NC} 인증 비활성화됨"
    echo -e "   ${GREEN}Supabase:${NC} 위의 API 키 사용"
    echo ""
    
    echo -e "${YELLOW}⚠️ 보안 권장사항:${NC}"
    echo -e "   • 프로덕션 환경에서는 각 서비스에 인증을 활성화하세요"
    echo -e "   • 방화벽에서 불필요한 포트 접근을 제한하세요"
    echo -e "   • 정기적으로 비밀번호와 API 키를 변경하세요"
    echo -e "   • SSL/TLS 인증서를 설정하여 HTTPS를 사용하세요"
    echo ""
    
    return 0
}

# 최종 정리 함수
final_cleanup() {
    log "INFO" "최종 정리를 수행하는 중..."
    
    # 임시 파일 정리 (성공적인 설치 완료)
    cleanup_temp_files_enhanced
    
    # 설치 완료 마커 생성
    if ! exec_in_container "touch /opt/dockge/.installation_complete"; then
        log "WARN" "설치 완료 마커 생성에 실패했습니다."
    fi
    
    # 설치 완료 시간 기록
    if ! exec_in_container "echo 'Installation completed at: $(date)' > /opt/dockge/.installation_date"; then
        log "WARN" "설치 완료 시간 기록에 실패했습니다."
    fi
    
    log "INFO" "최종 정리 완료"
    return 0
}

# 설치 성공 통계 출력 함수
display_installation_stats() {
    log "INFO" "설치 통계를 출력하는 중..."
    
    local end_time=$(date +%s)
    local start_time_file="/tmp/install_start_time"
    local duration="알 수 없음"
    
    if [ -f "$start_time_file" ]; then
        local start_time=$(cat "$start_time_file")
        local elapsed=$((end_time - start_time))
        local minutes=$((elapsed / 60))
        local seconds=$((elapsed % 60))
        duration="${minutes}분 ${seconds}초"
        rm -f "$start_time_file"
    fi
    
    echo -e "${BLUE}📊 설치 통계${NC}"
    echo -e "   설치 소요 시간: ${YELLOW}$duration${NC}"
    echo -e "   설치된 서비스: ${YELLOW}4개 (Docker, Dockge, CloudCmd, Supabase)${NC}"
    echo -e "   생성된 컨테이너: ${YELLOW}$(pct exec "$LXC_ID" -- docker ps --format "table {{.Names}}" | wc -l)개${NC}"
    echo -e "   사용 중인 포트: ${YELLOW}$DOCKGE_PORT, $CLOUDCMD_PORT, $SUPABASE_STUDIO_PORT, 8001${NC}"
    echo ""
    
    return 0
}

# 접속 정보 출력 및 최종 정리 메인 함수
display_final_information() {
    log "INFO" "=== 접속 정보 출력 및 최종 정리 시작 ==="
    
    show_progress 1 5 "설치 요약 정보 생성 중..."
    generate_installation_summary
    
    show_progress 2 5 "접속 정보 출력 중..."
    display_access_information
    
    show_progress 3 5 "관리자 계정 정보 출력 중..."
    display_admin_credentials
    
    show_progress 4 5 "설치 통계 출력 중..."
    display_installation_stats
    
    show_progress 5 5 "최종 정리 수행 중..."
    final_cleanup
    
    log "INFO" "=== 접속 정보 출력 및 최종 정리 완료 ==="
    return 0
}

# 방화벽 규칙 설정 함수
configure_firewall_rules() {
    log "INFO" "방화벽 규칙을 설정하는 중..."
    
    # UFW 상태 확인 및 초기화
    if ! exec_in_container "ufw --force reset"; then
        log "WARN" "UFW 초기화에 실패했습니다."
    fi
    
    # 기본 정책 설정
    exec_in_container "ufw default deny incoming"
    exec_in_container "ufw default allow outgoing"
    
    # 필수 포트 허용
    local required_ports=(
        "22/tcp"     # SSH
        "$DOCKGE_PORT/tcp"        # Dockge
        "$CLOUDCMD_PORT/tcp"      # CloudCmd
        "$SUPABASE_STUDIO_PORT/tcp"  # Supabase Studio
        "8001/tcp"   # Supabase API (Kong)
    )
    
    for port in "${required_ports[@]}"; do
        if exec_in_container "ufw allow $port"; then
            log "INFO" "포트 $port 허용됨"
        else
            log "WARN" "포트 $port 허용 실패"
        fi
    done
    
    # 로컬 루프백 허용
    exec_in_container "ufw allow from 127.0.0.1"
    exec_in_container "ufw allow from ::1"
    
    # 컨테이너 내부 네트워크 허용 (Docker)
    exec_in_container "ufw allow from 172.16.0.0/12"
    
    # UFW 활성화
    if exec_in_container "ufw --force enable"; then
        log "INFO" "방화벽이 활성화되었습니다."
    else
        log "WARN" "방화벽 활성화에 실패했습니다."
    fi
    
    # 방화벽 상태 확인
    log "INFO" "현재 방화벽 규칙:"
    exec_in_container "ufw status numbered" || log "WARN" "방화벽 상태 확인 실패"
    
    return 0
}

# 파일 권한 설정 함수
configure_file_permissions() {
    log "INFO" "중요 파일들의 권한을 설정하는 중..."
    
    # Supabase 환경변수 파일 (매우 중요한 보안 정보 포함)
    if exec_in_container "[ -f /opt/dockge/stacks/supabase/.env ]"; then
        exec_in_container "chmod 600 /opt/dockge/stacks/supabase/.env"
        exec_in_container "chown root:root /opt/dockge/stacks/supabase/.env"
        log "INFO" "Supabase .env 파일 권한 설정 완료 (600)"
    fi
    
    # Dockge 환경변수 파일
    if exec_in_container "[ -f /opt/dockge/.env ]"; then
        exec_in_container "chmod 644 /opt/dockge/.env"
        exec_in_container "chown root:root /opt/dockge/.env"
        log "INFO" "Dockge .env 파일 권한 설정 완료 (644)"
    fi
    
    # CloudCmd 환경변수 파일
    if exec_in_container "[ -f /opt/dockge/stacks/cloudcmd/.env ]"; then
        exec_in_container "chmod 644 /opt/dockge/stacks/cloudcmd/.env"
        exec_in_container "chown root:root /opt/dockge/stacks/cloudcmd/.env"
        log "INFO" "CloudCmd .env 파일 권한 설정 완료 (644)"
    fi
    
    # Docker Compose 파일들
    local compose_files=(
        "/opt/dockge/compose.yaml"
        "/opt/dockge/stacks/cloudcmd/compose.yaml"
        "/opt/dockge/stacks/supabase/compose.yaml"
    )
    
    for file in "${compose_files[@]}"; do
        if exec_in_container "[ -f '$file' ]"; then
            exec_in_container "chmod 644 '$file'"
            exec_in_container "chown root:root '$file'"
        fi
    done
    
    # 설치 요약 파일
    if exec_in_container "[ -f /opt/dockge/installation_summary.txt ]"; then
        exec_in_container "chmod 600 /opt/dockge/installation_summary.txt"
        exec_in_container "chown root:root /opt/dockge/installation_summary.txt"
        log "INFO" "설치 요약 파일 권한 설정 완료 (600)"
    fi
    
    # 디렉토리 권한 설정
    exec_in_container "chmod 755 /opt/dockge"
    exec_in_container "chmod 755 /opt/dockge/stacks"
    exec_in_container "chmod 755 /opt/dockge/stacks/cloudcmd"
    exec_in_container "chmod 755 /opt/dockge/stacks/supabase"
    
    log "INFO" "파일 권한 설정 완료"
    return 0
}

# Docker 소켓 권한 최소화 함수
configure_docker_socket_permissions() {
    log "INFO" "Docker 소켓 권한을 설정하는 중..."
    
    # Docker 소켓 권한 확인
    local socket_perms=$(pct exec "$LXC_ID" -- stat -c "%a" /var/run/docker.sock 2>/dev/null)
    log "INFO" "현재 Docker 소켓 권한: $socket_perms"
    
    # Docker 그룹 확인
    if ! exec_in_container "getent group docker"; then
        log "WARN" "Docker 그룹이 존재하지 않습니다."
        return 1
    fi
    
    # Docker 소켓 그룹 소유권 설정
    if exec_in_container "chgrp docker /var/run/docker.sock"; then
        log "INFO" "Docker 소켓 그룹 소유권 설정 완료"
    else
        log "WARN" "Docker 소켓 그룹 소유권 설정 실패"
    fi
    
    # Docker 소켓 권한 설정 (그룹 읽기/쓰기 허용)
    if exec_in_container "chmod 660 /var/run/docker.sock"; then
        log "INFO" "Docker 소켓 권한 설정 완료 (660)"
    else
        log "WARN" "Docker 소켓 권한 설정 실패"
    fi
    
    return 0
}

# 컨테이너 보안 설정 함수
configure_container_security() {
    log "INFO" "컨테이너 보안 설정을 구성하는 중..."
    
    # AppArmor 프로필 확인
    if exec_in_container "which aa-status"; then
        log "INFO" "AppArmor가 설치되어 있습니다."
        exec_in_container "aa-status" || log "WARN" "AppArmor 상태 확인 실패"
    else
        log "INFO" "AppArmor가 설치되지 않았습니다."
    fi
    
    # 시스템 리소스 제한 설정
    log "INFO" "시스템 리소스 제한을 설정하는 중..."
    
    # 메모리 오버커밋 방지
    exec_in_container "echo 'vm.overcommit_memory = 2' >> /etc/sysctl.conf"
    exec_in_container "echo 'vm.overcommit_ratio = 80' >> /etc/sysctl.conf"
    
    # 네트워크 보안 강화
    exec_in_container "echo 'net.ipv4.conf.all.send_redirects = 0' >> /etc/sysctl.conf"
    exec_in_container "echo 'net.ipv4.conf.default.send_redirects = 0' >> /etc/sysctl.conf"
    exec_in_container "echo 'net.ipv4.conf.all.accept_redirects = 0' >> /etc/sysctl.conf"
    exec_in_container "echo 'net.ipv4.conf.default.accept_redirects = 0' >> /etc/sysctl.conf"
    
    # 커널 매개변수 적용
    exec_in_container "sysctl -p" || log "WARN" "커널 매개변수 적용 실패"
    
    log "INFO" "컨테이너 보안 설정 완료"
    return 0
}

# 로그 파일 보안 설정 함수
configure_log_security() {
    log "INFO" "로그 파일 보안을 설정하는 중..."
    
    # 로그 디렉토리 권한 설정
    if exec_in_container "[ -d /var/log ]"; then
        exec_in_container "chmod 755 /var/log"
    fi
    
    # Docker 로그 권한 설정
    if exec_in_container "[ -d /var/lib/docker/containers ]"; then
        exec_in_container "chmod -R 640 /var/lib/docker/containers/*/\*.log 2>/dev/null || true"
    fi
    
    # 로그 로테이션 설정
    local logrotate_config="/etc/logrotate.d/supabase-installer"
    local logrotate_content="$LOG_FILE {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 640 root root
}"
    
    if ! exec_in_container "cat > '$logrotate_config' << 'EOF'
$logrotate_content
EOF"; then
        log "WARN" "로그 로테이션 설정 실패"
    else
        log "INFO" "로그 로테이션 설정 완료"
    fi
    
    return 0
}

# 네트워크 보안 강화 함수
configure_network_security() {
    log "INFO" "네트워크 보안을 강화하는 중..."
    
    # fail2ban 설치 및 설정 (SSH 보호)
    if exec_in_container "apt install -y fail2ban"; then
        log "INFO" "fail2ban 설치 완료"
        
        # fail2ban SSH 설정
        local fail2ban_config="[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600"
        
        if exec_in_container "cat > /etc/fail2ban/jail.local << 'EOF'
$fail2ban_config
EOF"; then
            exec_in_container "systemctl enable fail2ban"
            exec_in_container "systemctl start fail2ban"
            log "INFO" "fail2ban 설정 완료"
        fi
    else
        log "WARN" "fail2ban 설치 실패"
    fi
    
    # TCP SYN 쿠키 활성화
    exec_in_container "echo 'net.ipv4.tcp_syncookies = 1' >> /etc/sysctl.conf"
    
    # ICMP 리다이렉트 비활성화
    exec_in_container "echo 'net.ipv4.conf.all.accept_source_route = 0' >> /etc/sysctl.conf"
    exec_in_container "echo 'net.ipv4.conf.default.accept_source_route = 0' >> /etc/sysctl.conf"
    
    log "INFO" "네트워크 보안 강화 완료"
    return 0
}

# 보안 감사 로그 설정 함수
configure_security_audit() {
    log "INFO" "보안 감사 로그를 설정하는 중..."
    
    # auditd 설치 및 설정
    if exec_in_container "apt install -y auditd"; then
        log "INFO" "auditd 설치 완료"
        
        # 중요 파일 감시 규칙 추가
        local audit_rules="# Supabase 보안 감사 규칙
-w /opt/dockge/stacks/supabase/.env -p wa -k supabase-env
-w /opt/dockge/ -p wa -k dockge-config
-w /var/run/docker.sock -p wa -k docker-socket
-w /etc/passwd -p wa -k passwd-changes
-w /etc/shadow -p wa -k shadow-changes"
        
        if exec_in_container "cat >> /etc/audit/rules.d/supabase.rules << 'EOF'
$audit_rules
EOF"; then
            exec_in_container "systemctl enable auditd"
            exec_in_container "systemctl start auditd"
            log "INFO" "보안 감사 로그 설정 완료"
        fi
    else
        log "WARN" "auditd 설치 실패"
    fi
    
    return 0
}

# 보안 설정 검증 함수
verify_security_configuration() {
    log "INFO" "보안 설정을 검증하는 중..."
    
    local security_checks=()
    
    # 방화벽 상태 확인
    if exec_in_container "ufw status | grep -q 'Status: active'"; then
        security_checks+=("방화벽: ✓ 활성화됨")
    else
        security_checks+=("방화벽: ✗ 비활성화됨")
    fi
    
    # 중요 파일 권한 확인
    local env_perms=$(pct exec "$LXC_ID" -- stat -c "%a" /opt/dockge/stacks/supabase/.env 2>/dev/null)
    if [ "$env_perms" = "600" ]; then
        security_checks+=("Supabase .env 권한: ✓ 안전함 (600)")
    else
        security_checks+=("Supabase .env 권한: ⚠ 확인 필요 ($env_perms)")
    fi
    
    # Docker 소켓 권한 확인
    local socket_perms=$(pct exec "$LXC_ID" -- stat -c "%a" /var/run/docker.sock 2>/dev/null)
    if [ "$socket_perms" = "660" ]; then
        security_checks+=("Docker 소켓 권한: ✓ 안전함 (660)")
    else
        security_checks+=("Docker 소켓 권한: ⚠ 확인 필요 ($socket_perms)")
    fi
    
    # fail2ban 상태 확인
    if exec_in_container "systemctl is-active fail2ban"; then
        security_checks+=("fail2ban: ✓ 실행 중")
    else
        security_checks+=("fail2ban: ⚠ 실행되지 않음")
    fi
    
    # 보안 검증 결과 출력
    log "INFO" "보안 설정 검증 결과:"
    for check in "${security_checks[@]}"; do
        if [[ $check == *"✓"* ]]; then
            log "INFO" "$check"
        else
            log "WARN" "$check"
        fi
    done
    
    return 0
}

# 보안 설정 메인 함수
configure_security_settings() {
    log "INFO" "=== 보안 설정 및 방화벽 구성 시작 ==="
    
    show_progress 1 8 "방화벽 규칙 설정 중..."
    configure_firewall_rules
    
    show_progress 2 8 "파일 권한 설정 중..."
    configure_file_permissions
    
    show_progress 3 8 "Docker 소켓 권한 설정 중..."
    configure_docker_socket_permissions
    
    show_progress 4 8 "컨테이너 보안 설정 중..."
    configure_container_security
    
    show_progress 5 8 "로그 파일 보안 설정 중..."
    configure_log_security
    
    show_progress 6 8 "네트워크 보안 강화 중..."
    configure_network_security
    
    show_progress 7 8 "보안 감사 로그 설정 중..."
    configure_security_audit
    
    show_progress 8 8 "보안 설정 검증 중..."
    verify_security_configuration
    
    log "INFO" "=== 보안 설정 및 방화벽 구성 완료 ==="
    return 0
}

# 전역 오류 처리 함수
handle_error() {
    local exit_code=$?
    local line_number=$1
    local command="$2"
    
    log "ERROR" "스크립트 실행 중 오류가 발생했습니다."
    log "ERROR" "종료 코드: $exit_code"
    log "ERROR" "오류 발생 라인: $line_number"
    log "ERROR" "실행된 명령어: $command"
    
    # 스택 트레이스 출력
    log "ERROR" "호출 스택:"
    local frame=0
    while caller $frame; do
        ((frame++))
    done | while read line func file; do
        log "ERROR" "  $file:$line $func()"
    done
    
    # 시스템 상태 정보 수집
    collect_system_state_on_error
    
    # 오류 발생 시 정리 작업
    cleanup_on_error
    
    exit $exit_code
}

# 시스템 상태 정보 수집 함수
collect_system_state_on_error() {
    log "INFO" "오류 발생 시 시스템 상태 정보를 수집하는 중..."
    
    local error_log="/tmp/supabase_installer_error_$(date +%Y%m%d_%H%M%S).log"
    
    {
        echo "=== 오류 발생 시 시스템 상태 정보 ==="
        echo "시간: $(date)"
        echo "스크립트: $0"
        echo "사용자: $(whoami)"
        echo "작업 디렉토리: $(pwd)"
        echo ""
        
        echo "=== 시스템 정보 ==="
        uname -a 2>/dev/null || echo "uname 명령어 실행 실패"
        echo ""
        
        echo "=== 메모리 사용량 ==="
        free -h 2>/dev/null || echo "free 명령어 실행 실패"
        echo ""
        
        echo "=== 디스크 사용량 ==="
        df -h 2>/dev/null || echo "df 명령어 실행 실패"
        echo ""
        
        echo "=== 프로세스 목록 ==="
        ps aux 2>/dev/null || echo "ps 명령어 실행 실패"
        echo ""
        
        if [ -n "$LXC_ID" ] && pct status "$LXC_ID" &>/dev/null; then
            echo "=== LXC 컨테이너 상태 ==="
            pct status "$LXC_ID" 2>/dev/null || echo "LXC 상태 확인 실패"
            echo ""
            
            echo "=== 컨테이너 내부 프로세스 ==="
            pct exec "$LXC_ID" -- ps aux 2>/dev/null || echo "컨테이너 프로세스 확인 실패"
            echo ""
            
            echo "=== Docker 컨테이너 상태 ==="
            pct exec "$LXC_ID" -- docker ps -a 2>/dev/null || echo "Docker 컨테이너 상태 확인 실패"
            echo ""
        fi
        
        echo "=== 최근 로그 (마지막 50줄) ==="
        if [ -f "$LOG_FILE" ]; then
            tail -50 "$LOG_FILE" 2>/dev/null || echo "로그 파일 읽기 실패"
        else
            echo "로그 파일이 존재하지 않습니다: $LOG_FILE"
        fi
        
    } > "$error_log" 2>&1
    
    log "INFO" "오류 상태 정보가 저장되었습니다: $error_log"
    
    # 오류 로그를 메인 로그에도 추가
    if [ -f "$error_log" ]; then
        echo "" >> "$LOG_FILE"
        echo "=== 오류 발생 시 시스템 상태 ===" >> "$LOG_FILE"
        cat "$error_log" >> "$LOG_FILE" 2>/dev/null
    fi
}

# 진행 상황 로깅 강화 함수
log_progress_detail() {
    local step=$1
    local total=$2
    local message=$3
    local detail="$4"
    
    # 기본 진행 상황 표시
    show_progress "$step" "$total" "$message"
    
    # 상세 로그 기록
    log "INFO" "[$step/$total] $message"
    if [ -n "$detail" ]; then
        log "DEBUG" "$detail"
    fi
    
    # 진행률 계산 및 기록
    local percent=$((step * 100 / total))
    log "DEBUG" "전체 진행률: $percent%"
}

# 설치 실패 시 롤백 함수
rollback_installation() {
    log "WARN" "설치 실패로 인한 롤백을 시작합니다..."
    
    local rollback_steps=()
    
    # 실행 중인 Docker 컨테이너 중지
    if [ -n "$LXC_ID" ] && pct status "$LXC_ID" | grep -q "running"; then
        log "INFO" "Docker 컨테이너들을 중지하는 중..."
        
        # Supabase 스택 중지
        if exec_in_container "[ -f /opt/dockge/stacks/supabase/compose.yaml ]"; then
            exec_in_container "cd /opt/dockge/stacks/supabase && docker-compose down" 2>/dev/null || true
            rollback_steps+=("Supabase 스택 중지됨")
        fi
        
        # CloudCmd 스택 중지
        if exec_in_container "[ -f /opt/dockge/stacks/cloudcmd/compose.yaml ]"; then
            exec_in_container "cd /opt/dockge/stacks/cloudcmd && docker-compose down" 2>/dev/null || true
            rollback_steps+=("CloudCmd 스택 중지됨")
        fi
        
        # Dockge 중지
        if exec_in_container "[ -f /opt/dockge/compose.yaml ]"; then
            exec_in_container "cd /opt/dockge && docker-compose down" 2>/dev/null || true
            rollback_steps+=("Dockge 중지됨")
        fi
        
        # 모든 Docker 컨테이너 강제 중지
        exec_in_container "docker stop \$(docker ps -q)" 2>/dev/null || true
        exec_in_container "docker rm \$(docker ps -aq)" 2>/dev/null || true
        rollback_steps+=("모든 Docker 컨테이너 정리됨")
    fi
    
    # 롤백 결과 출력
    if [ ${#rollback_steps[@]} -gt 0 ]; then
        log "INFO" "롤백 완료된 항목들:"
        for step in "${rollback_steps[@]}"; do
            log "INFO" "  - $step"
        done
    else
        log "INFO" "롤백할 항목이 없습니다."
    fi
    
    log "INFO" "롤백 완료"
}

# 로그 파일 관리 함수
manage_log_files() {
    log "INFO" "로그 파일을 관리하는 중..."
    
    # 로그 파일 크기 확인
    if [ -f "$LOG_FILE" ]; then
        local log_size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo "0")
        local log_size_mb=$((log_size / 1024 / 1024))
        
        log "DEBUG" "현재 로그 파일 크기: ${log_size_mb}MB"
        
        # 로그 파일이 10MB를 초과하면 백업
        if [ "$log_size_mb" -gt 10 ]; then
            local backup_log="${LOG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
            cp "$LOG_FILE" "$backup_log" 2>/dev/null || true
            echo "=== 로그 파일 백업됨: $(date) ===" > "$LOG_FILE"
            log "INFO" "로그 파일이 백업되었습니다: $backup_log"
        fi
    fi
    
    # 오래된 로그 파일 정리 (7일 이상)
    find "$(dirname "$LOG_FILE")" -name "$(basename "$LOG_FILE").backup.*" -mtime +7 -delete 2>/dev/null || true
    find "/tmp" -name "supabase_installer_error_*.log" -mtime +7 -delete 2>/dev/null || true
    
    log "INFO" "로그 파일 관리 완료"
}

# 성능 모니터링 함수
monitor_performance() {
    local operation="$1"
    local start_time=$(date +%s.%N)
    
    # 작업 실행
    "$@"
    local exit_code=$?
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
    
    log "DEBUG" "성능 모니터링 - $operation: ${duration}초 소요 (종료 코드: $exit_code)"
    
    return $exit_code
}

# 시스템 리소스 모니터링 함수
monitor_system_resources() {
    log "DEBUG" "시스템 리소스 모니터링..."
    
    # 메모리 사용량
    local memory_info=$(free | awk 'NR==2{printf "%.1f%%", $3*100/$2}' 2>/dev/null || echo "N/A")
    log "DEBUG" "메모리 사용률: $memory_info"
    
    # 디스크 사용량
    local disk_info=$(df / | awk 'NR==2{printf "%.1f%%", $3*100/$2}' 2>/dev/null || echo "N/A")
    log "DEBUG" "디스크 사용률: $disk_info"
    
    # 로드 평균
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | xargs 2>/dev/null || echo "N/A")
    log "DEBUG" "로드 평균: $load_avg"
    
    # LXC 컨테이너 리소스 (있는 경우)
    if [ -n "$LXC_ID" ] && pct status "$LXC_ID" | grep -q "running"; then
        local container_memory=$(pct exec "$LXC_ID" -- free | awk 'NR==2{printf "%.1f%%", $3*100/$2}' 2>/dev/null || echo "N/A")
        log "DEBUG" "컨테이너 메모리 사용률: $container_memory"
    fi
}

# 로깅 시스템 최종 설정 함수
finalize_logging_system() {
    log "INFO" "로깅 시스템을 최종 설정하는 중..."
    
    # 로그 파일 관리
    manage_log_files
    
    # 최종 시스템 리소스 모니터링
    monitor_system_resources
    
    # 로그 파일 권한 설정
    if [ -f "$LOG_FILE" ]; then
        chmod 644 "$LOG_FILE" 2>/dev/null || true
        chown root:root "$LOG_FILE" 2>/dev/null || true
    fi
    
    # 설치 성공 로그 기록
    log "INFO" "=== 설치 성공적으로 완료 ==="
    log "INFO" "설치 완료 시간: $(date)"
    log "INFO" "총 로그 라인 수: $(wc -l < "$LOG_FILE" 2>/dev/null || echo "N/A")"
    
    # 로그 요약 생성
    generate_log_summary
    
    log "INFO" "로깅 시스템 최종 설정 완료"
}

# 로그 요약 생성 함수
generate_log_summary() {
    log "INFO" "로그 요약을 생성하는 중..."
    
    if [ ! -f "$LOG_FILE" ]; then
        log "WARN" "로그 파일이 존재하지 않습니다."
        return 1
    fi
    
    local summary_file="/opt/dockge/installation_log_summary.txt"
    
    {
        echo "# 설치 로그 요약"
        echo "생성 시간: $(date)"
        echo "로그 파일: $LOG_FILE"
        echo ""
        
        echo "## 통계"
        echo "총 로그 라인 수: $(wc -l < "$LOG_FILE")"
        echo "INFO 메시지: $(grep -c '\[INFO\]' "$LOG_FILE" 2>/dev/null || echo "0")"
        echo "WARN 메시지: $(grep -c '\[WARN\]' "$LOG_FILE" 2>/dev/null || echo "0")"
        echo "ERROR 메시지: $(grep -c '\[ERROR\]' "$LOG_FILE" 2>/dev/null || echo "0")"
        echo "DEBUG 메시지: $(grep -c '\[DEBUG\]' "$LOG_FILE" 2>/dev/null || echo "0")"
        echo ""
        
        echo "## 주요 단계"
        grep -E '\[INFO\].*===.*===' "$LOG_FILE" 2>/dev/null | sed 's/.*\[INFO\] /- /' || echo "주요 단계 정보 없음"
        echo ""
        
        echo "## 경고 메시지"
        grep '\[WARN\]' "$LOG_FILE" 2>/dev/null | tail -10 | sed 's/.*\[WARN\] /- /' || echo "경고 메시지 없음"
        echo ""
        
        echo "## 오류 메시지"
        grep '\[ERROR\]' "$LOG_FILE" 2>/dev/null | tail -5 | sed 's/.*\[ERROR\] /- /' || echo "오류 메시지 없음"
        
    } > "$summary_file" 2>/dev/null
    
    if [ -f "$summary_file" ]; then
        log "INFO" "로그 요약 파일 생성 완료: $summary_file"
    else
        log "WARN" "로그 요약 파일 생성 실패"
    fi
}

# 향상된 trap 설정 (오류 처리 포함)
setup_error_handling() {
    # 오류 발생 시 handle_error 함수 호출
    set -eE  # 오류 발생 시 즉시 종료, ERR 트랩 상속
    trap 'handle_error ${LINENO} "$BASH_COMMAND"' ERR
    
    # 스크립트 종료 시 정리 작업
    trap 'cleanup_on_error' EXIT INT TERM
    
    log "DEBUG" "오류 처리 시스템이 설정되었습니다."
}

# 통합 테스트 함수들

# 서비스 연결 테스트 함수
test_service_connectivity() {
    log "INFO" "서비스 연결 테스트를 수행하는 중..."
    
    local test_results=()
    local failed_tests=0
    
    # Dockge 연결 테스트
    if exec_in_container "curl -s --connect-timeout 10 http://localhost:$DOCKGE_PORT > /dev/null"; then
        test_results+=("Dockge 연결: ✓ 성공")
    else
        test_results+=("Dockge 연결: ✗ 실패")
        ((failed_tests++))
    fi
    
    # CloudCmd 연결 테스트
    if exec_in_container "curl -s --connect-timeout 10 http://localhost:$CLOUDCMD_PORT > /dev/null"; then
        test_results+=("CloudCmd 연결: ✓ 성공")
    else
        test_results+=("CloudCmd 연결: ✗ 실패")
        ((failed_tests++))
    fi
    
    # Supabase Studio 연결 테스트
    if exec_in_container "curl -s --connect-timeout 10 http://localhost:$SUPABASE_STUDIO_PORT > /dev/null"; then
        test_results+=("Supabase Studio 연결: ✓ 성공")
    else
        test_results+=("Supabase Studio 연결: ✗ 실패")
        ((failed_tests++))
    fi
    
    # Supabase API 연결 테스트
    if exec_in_container "curl -s --connect-timeout 10 http://localhost:8001/rest/v1/ > /dev/null"; then
        test_results+=("Supabase API 연결: ✓ 성공")
    else
        test_results+=("Supabase API 연결: ✗ 실패")
        ((failed_tests++))
    fi
    
    # 테스트 결과 출력
    for result in "${test_results[@]}"; do
        if [[ $result == *"✓"* ]]; then
            log "INFO" "$result"
        else
            log "ERROR" "$result"
        fi
    done
    
    return $failed_tests
}

# 데이터베이스 연결 테스트 함수
test_database_connectivity() {
    log "INFO" "데이터베이스 연결 테스트를 수행하는 중..."
    
    # PostgreSQL 컨테이너가 실행 중인지 확인
    if ! exec_in_container "docker ps | grep -q postgres"; then
        log "ERROR" "PostgreSQL 컨테이너가 실행되지 않고 있습니다."
        return 1
    fi
    
    # 데이터베이스 연결 테스트
    local db_test_cmd="docker exec \$(docker ps | grep postgres | awk '{print \$1}') psql -U postgres -d postgres -c 'SELECT version();'"
    
    if exec_in_container "$db_test_cmd" > /dev/null 2>&1; then
        log "INFO" "PostgreSQL 데이터베이스 연결: ✓ 성공"
        return 0
    else
        log "ERROR" "PostgreSQL 데이터베이스 연결: ✗ 실패"
        return 1
    fi
}

# API 기능 테스트 함수
test_api_functionality() {
    log "INFO" "API 기능 테스트를 수행하는 중..."
    
    local api_tests=0
    local api_failures=0
    
    # Supabase REST API 테스트
    ((api_tests++))
    if exec_in_container "curl -s -H 'apikey: $ANON_KEY' http://localhost:8001/rest/v1/ | grep -q 'OpenAPI'"; then
        log "INFO" "Supabase REST API: ✓ 정상 응답"
    else
        log "ERROR" "Supabase REST API: ✗ 응답 없음"
        ((api_failures++))
    fi
    
    # Auth API 테스트
    ((api_tests++))
    if exec_in_container "curl -s http://localhost:8001/auth/v1/settings | grep -q 'external'"; then
        log "INFO" "Supabase Auth API: ✓ 정상 응답"
    else
        log "ERROR" "Supabase Auth API: ✗ 응답 없음"
        ((api_failures++))
    fi
    
    # Storage API 테스트
    ((api_tests++))
    if exec_in_container "curl -s -H 'apikey: $ANON_KEY' http://localhost:8001/storage/v1/bucket | grep -q '\[\]'"; then
        log "INFO" "Supabase Storage API: ✓ 정상 응답"
    else
        log "WARN" "Supabase Storage API: ⚠ 응답 확인 불가 (정상일 수 있음)"
    fi
    
    log "INFO" "API 테스트 완료: $((api_tests - api_failures))/$api_tests 성공"
    return $api_failures
}

# 파일 시스템 테스트 함수
test_filesystem_integrity() {
    log "INFO" "파일 시스템 무결성 테스트를 수행하는 중..."
    
    local fs_tests=0
    local fs_failures=0
    
    # 중요 디렉토리 존재 확인
    local important_dirs=(
        "/opt/dockge"
        "/opt/dockge/stacks/cloudcmd"
        "/opt/dockge/stacks/supabase"
    )
    
    for dir in "${important_dirs[@]}"; do
        ((fs_tests++))
        if exec_in_container "[ -d '$dir' ]"; then
            log "INFO" "디렉토리 존재 확인 ($dir): ✓"
        else
            log "ERROR" "디렉토리 존재 확인 ($dir): ✗"
            ((fs_failures++))
        fi
    done
    
    # 중요 파일 존재 확인
    local important_files=(
        "/opt/dockge/compose.yaml"
        "/opt/dockge/stacks/cloudcmd/compose.yaml"
        "/opt/dockge/stacks/supabase/compose.yaml"
        "/opt/dockge/stacks/supabase/.env"
    )
    
    for file in "${important_files[@]}"; do
        ((fs_tests++))
        if exec_in_container "[ -f '$file' ]"; then
            log "INFO" "파일 존재 확인 ($file): ✓"
        else
            log "ERROR" "파일 존재 확인 ($file): ✗"
            ((fs_failures++))
        fi
    done
    
    # 파일 권한 확인
    ((fs_tests++))
    local env_perms=$(pct exec "$LXC_ID" -- stat -c "%a" /opt/dockge/stacks/supabase/.env 2>/dev/null)
    if [ "$env_perms" = "600" ]; then
        log "INFO" "Supabase .env 파일 권한: ✓ 안전함 (600)"
    else
        log "WARN" "Supabase .env 파일 권한: ⚠ $env_perms (600 권장)"
        ((fs_failures++))
    fi
    
    log "INFO" "파일 시스템 테스트 완료: $((fs_tests - fs_failures))/$fs_tests 성공"
    return $fs_failures
}

# 성능 테스트 함수
test_performance() {
    log "INFO" "기본 성능 테스트를 수행하는 중..."
    
    # 메모리 사용량 확인
    local container_memory=$(pct exec "$LXC_ID" -- free -m | awk 'NR==2{printf "%.1f", $3*100/$2}' 2>/dev/null || echo "0")
    log "INFO" "컨테이너 메모리 사용률: ${container_memory}%"
    
    # 디스크 사용량 확인
    local disk_usage=$(pct exec "$LXC_ID" -- df / | awk 'NR==2{printf "%.1f", $3*100/$2}' 2>/dev/null || echo "0")
    log "INFO" "컨테이너 디스크 사용률: ${disk_usage}%"
    
    # Docker 컨테이너 수 확인
    local container_count=$(pct exec "$LXC_ID" -- docker ps | wc -l)
    log "INFO" "실행 중인 Docker 컨테이너 수: $((container_count - 1))"
    
    # 응답 시간 테스트
    local response_time=$(pct exec "$LXC_ID" -- curl -s -w "%{time_total}" -o /dev/null http://localhost:$DOCKGE_PORT 2>/dev/null || echo "0")
    log "INFO" "Dockge 응답 시간: ${response_time}초"
    
    return 0
}

# 보안 설정 테스트 함수
test_security_configuration() {
    log "INFO" "보안 설정 테스트를 수행하는 중..."
    
    local security_tests=0
    local security_failures=0
    
    # 방화벽 상태 확인
    ((security_tests++))
    if exec_in_container "ufw status | grep -q 'Status: active'"; then
        log "INFO" "방화벽 상태: ✓ 활성화됨"
    else
        log "ERROR" "방화벽 상태: ✗ 비활성화됨"
        ((security_failures++))
    fi
    
    # 필수 포트 허용 확인
    local required_ports=("22" "$DOCKGE_PORT" "$CLOUDCMD_PORT" "$SUPABASE_STUDIO_PORT" "8001")
    for port in "${required_ports[@]}"; do
        ((security_tests++))
        if exec_in_container "ufw status | grep -q '$port'"; then
            log "INFO" "포트 $port 방화벽 규칙: ✓ 설정됨"
        else
            log "WARN" "포트 $port 방화벽 규칙: ⚠ 설정되지 않음"
            ((security_failures++))
        fi
    done
    
    # fail2ban 상태 확인
    ((security_tests++))
    if exec_in_container "systemctl is-active fail2ban" > /dev/null 2>&1; then
        log "INFO" "fail2ban 상태: ✓ 실행 중"
    else
        log "WARN" "fail2ban 상태: ⚠ 실행되지 않음"
        ((security_failures++))
    fi
    
    log "INFO" "보안 설정 테스트 완료: $((security_tests - security_failures))/$security_tests 성공"
    return $security_failures
}

# 통합 테스트 메인 함수
perform_integration_test() {
    log "INFO" "=== 통합 테스트 시작 ==="
    
    local total_failures=0
    
    show_progress 1 6 "서비스 연결 테스트 중..."
    test_service_connectivity
    total_failures=$((total_failures + $?))
    
    show_progress 2 6 "데이터베이스 연결 테스트 중..."
    test_database_connectivity
    total_failures=$((total_failures + $?))
    
    show_progress 3 6 "API 기능 테스트 중..."
    test_api_functionality
    total_failures=$((total_failures + $?))
    
    show_progress 4 6 "파일 시스템 무결성 테스트 중..."
    test_filesystem_integrity
    total_failures=$((total_failures + $?))
    
    show_progress 5 6 "성능 테스트 중..."
    test_performance
    total_failures=$((total_failures + $?))
    
    show_progress 6 6 "보안 설정 테스트 중..."
    test_security_configuration
    total_failures=$((total_failures + $?))
    
    # 테스트 결과 요약
    if [ $total_failures -eq 0 ]; then
        log "INFO" "=== 통합 테스트 완료: 모든 테스트 통과 ✓ ==="
        return 0
    else
        log "WARN" "=== 통합 테스트 완료: $total_failures 개의 테스트 실패 ⚠ ==="
        return 1
    fi
}

# 스크립트 최적화 함수
optimize_script_performance() {
    log "INFO" "스크립트 성능을 최적화하는 중..."
    
    # 불필요한 프로세스 정리
    exec_in_container "apt autoremove -y" > /dev/null 2>&1 || true
    exec_in_container "apt autoclean" > /dev/null 2>&1 || true
    
    # Docker 이미지 정리
    exec_in_container "docker system prune -f" > /dev/null 2>&1 || true
    
    # 로그 파일 압축
    if [ -f "$LOG_FILE" ]; then
        gzip -c "$LOG_FILE" > "${LOG_FILE}.gz" 2>/dev/null || true
    fi
    
    log "INFO" "스크립트 성능 최적화 완료"
}

# 설치 검증 리포트 생성 함수
generate_verification_report() {
    log "INFO" "설치 검증 리포트를 생성하는 중..."
    
    local report_file="/opt/dockge/installation_verification_report.txt"
    
    {
        echo "# Supabase LXC 설치 검증 리포트"
        echo "생성 시간: $(date)"
        echo "스크립트 버전: Supabase LXC Auto Installer v1.0"
        echo ""
        
        echo "## 설치 환경"
        echo "- 호스트 OS: $(uname -a)"
        echo "- Proxmox VE 버전: $(pveversion | head -n1)"
        echo "- LXC 컨테이너 ID: $LXC_ID"
        echo "- 컨테이너 이름: $LXC_NAME"
        echo "- 컨테이너 IP: $LXC_IP"
        echo ""
        
        echo "## 설치된 서비스"
        echo "- Docker: $(pct exec "$LXC_ID" -- docker --version 2>/dev/null || echo '확인 불가')"
        echo "- Docker Compose: $(pct exec "$LXC_ID" -- docker-compose --version 2>/dev/null || echo '확인 불가')"
        echo "- Dockge: 설치됨 (포트 $DOCKGE_PORT)"
        echo "- CloudCmd: 설치됨 (포트 $CLOUDCMD_PORT)"
        echo "- Supabase: 설치됨 (Studio 포트 $SUPABASE_STUDIO_PORT, API 포트 8001)"
        echo ""
        
        echo "## 실행 중인 컨테이너"
        pct exec "$LXC_ID" -- docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "컨테이너 정보 확인 불가"
        echo ""
        
        echo "## 리소스 사용량"
        echo "- 메모리: $(pct exec "$LXC_ID" -- free -h | grep Mem | awk '{print $3 "/" $2}' 2>/dev/null || echo '확인 불가')"
        echo "- 디스크: $(pct exec "$LXC_ID" -- df -h / | tail -1 | awk '{print $3 "/" $2 " (" $5 " 사용)"}' 2>/dev/null || echo '확인 불가')"
        echo ""
        
        echo "## 보안 설정"
        echo "- 방화벽: $(exec_in_container "ufw status | head -1" 2>/dev/null || echo '확인 불가')"
        echo "- fail2ban: $(exec_in_container "systemctl is-active fail2ban" 2>/dev/null || echo '비활성화')"
        echo "- 파일 권한: $(pct exec "$LXC_ID" -- stat -c "%a" /opt/dockge/stacks/supabase/.env 2>/dev/null || echo '확인 불가')"
        echo ""
        
        echo "## 접속 정보"
        echo "- Dockge: http://$DOMAIN:$DOCKGE_PORT"
        echo "- CloudCmd: http://$DOMAIN:$CLOUDCMD_PORT"
        echo "- Supabase Studio: http://$DOMAIN:$SUPABASE_STUDIO_PORT"
        echo "- Supabase API: http://$DOMAIN:8001"
        echo ""
        
        echo "## 권장 사항"
        echo "- 정기적으로 Docker 이미지 업데이트"
        echo "- 백업 계획 수립"
        echo "- 모니터링 시스템 구축"
        echo "- SSL/TLS 인증서 설정"
        
    } > "$report_file" 2>/dev/null
    
    if [ -f "$report_file" ]; then
        log "INFO" "설치 검증 리포트 생성 완료: $report_file"
    else
        log "WARN" "설치 검증 리포트 생성 실패"
    fi
}

# 메인 함수
main() {
    # 로그 파일 초기화
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "=== Supabase LXC Installer 시작 ===" > "$LOG_FILE"
    
    # 설치 시작 시간 기록
    echo $(date +%s) > /tmp/install_start_time
    
    # 오류 처리 시스템 설정
    setup_error_handling
    
    log "INFO" "Supabase LXC Auto Installer를 시작합니다..."
    log "INFO" "스크립트 위치: $SCRIPT_DIR"
    log "INFO" "임시 디렉토리: $TEMP_DIR"
    log "INFO" "로그 파일: $LOG_FILE"
    
    # 환경 검증
    check_environment
    
    # 사용자 입력 수집
    collect_user_input
    
    # LXC 컨테이너 생성 및 설정
    if ! setup_lxc_container; then
        log "ERROR" "LXC 컨테이너 설정에 실패했습니다."
        exit 1
    fi
    
    # Docker 설치
    if ! install_docker; then
        log "ERROR" "Docker 설치에 실패했습니다."
        exit 1
    fi
    
    # Dockge 설치
    if ! install_dockge; then
        log "ERROR" "Dockge 설치에 실패했습니다."
        exit 1
    fi
    
    # 임시 파일 관리 시스템 초기화
    if ! initialize_temp_file_system; then
        log "ERROR" "임시 파일 관리 시스템 초기화에 실패했습니다."
        exit 1
    fi
    
    # CloudCmd 스택 생성
    if ! setup_cloudcmd_stack; then
        log "ERROR" "CloudCmd 스택 생성에 실패했습니다."
        exit 1
    fi
    
    # Supabase 스택 생성
    if ! setup_supabase_stack; then
        log "ERROR" "Supabase 스택 생성에 실패했습니다."
        exit 1
    fi
    
    # 서비스 시작 및 상태 확인
    if ! start_and_verify_services; then
        log "ERROR" "서비스 시작 및 상태 확인에 실패했습니다."
        exit 1
    fi
    
    # 접속 정보 출력 및 최종 정리
    if ! display_final_information; then
        log "ERROR" "접속 정보 출력에 실패했습니다."
        exit 1
    fi
    
    # 보안 설정 및 방화벽 구성
    if ! configure_security_settings; then
        log "ERROR" "보안 설정에 실패했습니다."
        exit 1
    fi
    
    # 오류 처리 및 로깅 시스템 최종 설정
    finalize_logging_system
    
    # 최종 통합 테스트 수행
    if ! perform_integration_test; then
        log "WARN" "통합 테스트에서 일부 문제가 발견되었습니다. 설치는 완료되었지만 확인이 필요합니다."
    fi
    
    # 스크립트 성능 최적화
    optimize_script_performance
    
    # 설치 검증 리포트 생성
    generate_verification_report
    
    log "INFO" "Supabase LXC 자동 설치가 성공적으로 완료되었습니다!"
    # install_docker
    # install_dockge
    # setup_cloudcmd_stack
    # setup_supabase_stack
    # start_services
    # display_access_info
}

# 스크립트 실행
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
    main "$@"
fi