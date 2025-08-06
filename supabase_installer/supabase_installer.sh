#!/bin/bash

# Supabase LXC Auto Installer for Proxmox VE
# 이 스크립트는 Proxmox VE 환경에서 LXC 컨테이너에 Docker, Dockge, CloudCmd, Supabase를 자동 설치합니다.

# 스크립트 디렉토리 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# 원격 실행 여부 확인 및 모듈 다운로드
if [[ "${BASH_SOURCE[0]}" == *"curl"* ]] || [[ "${BASH_SOURCE[0]}" == *"wget"* ]] || [[ ! -f "$SCRIPT_DIR/config.sh" ]]; then
    # 원격 실행이거나 로컬 모듈이 없는 경우 임시 디렉토리 생성
    TEMP_SCRIPT_DIR="/tmp/supabase_installer_scripts"
    mkdir -p "$TEMP_SCRIPT_DIR"
    cd "$TEMP_SCRIPT_DIR"
    
    # 로그 함수 정의
    log() {
        local level=$1
        shift
        local message="$*"
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        
        case $level in
            "INFO")
                echo -e "\033[0;32m[INFO]\033[0m $message"
                ;;
            "WARN")
                echo -e "\033[1;33m[WARN]\033[0m $message"
                ;;
            "ERROR")
                echo -e "\033[0;31m[ERROR]\033[0m $message"
                ;;
            "DEBUG")
                echo -e "\033[0;34m[DEBUG]\033[0m $message"
                ;;
        esac
    }
    
    # 모듈 다운로드 함수
    download_module() {
        local module_name="$1"
        local module_url="https://raw.githubusercontent.com/takesih/pve_script/main/supabase_installer/$module_name"
        
        log "INFO" "모듈 다운로드 중: $module_name"
        if curl -fsSL "$module_url" -o "$module_name"; then
            log "INFO" "모듈 다운로드 완료: $module_name"
            return 0
        else
            log "ERROR" "모듈 다운로드 실패: $module_name"
            return 1
        fi
    }
    
    # 필요한 모듈들 다운로드
    log "INFO" "필요한 모듈들을 다운로드하는 중..."
    for module in config.sh utils.sh input.sh docker.sh; do
        if ! download_module "$module"; then
            log "ERROR" "모듈 다운로드에 실패했습니다: $module"
            exit 1
        fi
    done
    
    # 모듈들 로드
    source "$TEMP_SCRIPT_DIR/config.sh"
    source "$TEMP_SCRIPT_DIR/utils.sh"
    source "$TEMP_SCRIPT_DIR/input.sh"
    source "$TEMP_SCRIPT_DIR/docker.sh"
else
    # 로컬 실행인 경우
    source "$SCRIPT_DIR/config.sh"
    source "$SCRIPT_DIR/utils.sh"
    source "$SCRIPT_DIR/input.sh"
    source "$SCRIPT_DIR/docker.sh"
fi

# 스크립트 시작
echo "=================================="
echo "Supabase LXC Auto Installer for Proxmox VE"
echo "V 250807070929"
echo "=================================="

# 오류 처리 설정
set -eE
trap 'handle_error ${LINENO} "$BASH_COMMAND"' ERR
trap 'cleanup_on_error' EXIT INT TERM

# 로그 파일 초기화
mkdir -p "$(dirname "$LOG_FILE")"
echo "=== Supabase LXC Installer 시작 ===" > "$LOG_FILE"

# 설치 시작 시간 기록
echo $(date +%s) > /tmp/install_start_time

log "DEBUG" "오류 처리 시스템이 설정되었습니다."
log "INFO" "Supabase LXC Auto Installer를 시작합니다..."
log "INFO" "스크립트 위치: $SCRIPT_DIR"
log "INFO" "임시 디렉토리: $TEMP_DIR"
log "INFO" "로그 파일: $LOG_FILE"

# 환경 검증 함수
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

# 메인 함수
main() {
    # 환경 검증
    check_environment
    
    # 사용자 입력 수집
    collect_user_input
    
    # LXC 컨테이너 생성
    if ! create_lxc_container; then
        log "ERROR" "LXC 컨테이너 생성에 실패했습니다."
        exit 1
    fi
    
    # 기본 패키지 설치
    if ! install_basic_packages; then
        log "ERROR" "기본 패키지 설치에 실패했습니다."
        exit 1
    fi
    
    # Docker 설치
    if ! install_docker; then
        log "ERROR" "Docker 설치에 실패했습니다."
        exit 1
    fi
    
    log "INFO" "=== 설치 완료 ==="
    log "INFO" "컨테이너 ID: $LXC_ID"
    log "INFO" "컨테이너 이름: $LXC_NAME"
    log "INFO" "IP 주소: $LXC_IP"
    
    echo -e "\n${GREEN}🎉 설치가 완료되었습니다! 🎉${NC}"
    echo -e "${BLUE}컨테이너 정보:${NC}"
    echo -e "  - ID: ${YELLOW}$LXC_ID${NC}"
    echo -e "  - 이름: ${YELLOW}$LXC_NAME${NC}"
    echo -e "  - IP: ${YELLOW}$LXC_IP${NC}"
    echo ""
    echo -e "${BLUE}다음 단계:${NC}"
    echo -e "  1. 컨테이너에 접속: ${YELLOW}pct enter $LXC_ID${NC}"
    echo -e "  2. Docker 상태 확인: ${YELLOW}docker ps${NC}"
    echo -e "  3. 서비스 설치 계속..."
}

# 스크립트 실행
main "$@" 