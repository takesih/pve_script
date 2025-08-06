#!/bin/bash

# Supabase LXC Installer Input Functions
# 이 파일은 사용자 입력 관련 함수들을 포함합니다.

# 설정 파일과 유틸리티 로드
source "$(dirname "$0")/config.sh"
source "$(dirname "$0")/utils.sh"

# LXC 컨테이너 설정 입력 함수
collect_lxc_settings() {
    log "INFO" "=== LXC 컨테이너 설정 ==="
    
    # 사용 가능한 컨테이너 ID 찾기
    local next_id=100
    local max_attempts=1000
    local attempts=0
    
    log "DEBUG" "Searching for available container ID starting from $next_id"
    
    # pct 명령어가 사용 가능한지 확인
    if ! command -v pct >/dev/null 2>&1; then
        log "ERROR" "pct command not found. This script must be run on Proxmox VE."
        exit 1
    fi
    
    while [ $attempts -lt $max_attempts ]; do
        # pct status 명령어가 실패하면 해당 ID가 사용 가능한 것으로 간주
        if ! pct status "$next_id" >/dev/null 2>&1; then
            log "DEBUG" "Found available container ID: $next_id"
            break
        fi
        ((next_id++))
        ((attempts++))
        if [ $((attempts % 100)) -eq 0 ]; then
            log "DEBUG" "Checked $attempts IDs, current: $next_id"
        fi
    done
    
    if [ $attempts -ge $max_attempts ]; then
        log "ERROR" "사용 가능한 컨테이너 ID를 찾을 수 없습니다."
        exit 1
    fi
    
    log "DEBUG" "Starting user input collection"
    log "INFO" "Please enter the following information (press Enter for defaults):"
    
    LXC_ID=$(prompt_input "Container ID" "$next_id" "")
    if [ -z "$LXC_ID" ]; then
        log "ERROR" "Container ID cannot be empty"
        exit 1
    fi
    log "DEBUG" "Container ID set to: $LXC_ID"
    
    LXC_NAME=$(prompt_input "Container Name" "supabase-dev" "")
    if [ -z "$LXC_NAME" ]; then
        log "ERROR" "Container Name cannot be empty"
        exit 1
    fi
    log "DEBUG" "Container Name set to: $LXC_NAME"
    
    LXC_MEMORY=$(prompt_input "Memory Size (MB)" "$DEFAULT_LXC_MEMORY" "validate_memory")
    if [ -z "$LXC_MEMORY" ]; then
        log "ERROR" "Memory Size cannot be empty"
        exit 1
    fi
    log "DEBUG" "Memory set to: $LXC_MEMORY"
    
    LXC_CORES=$(prompt_input "CPU Cores" "$DEFAULT_LXC_CORES" "validate_cpu_cores")
    if [ -z "$LXC_CORES" ]; then
        log "ERROR" "CPU Cores cannot be empty"
        exit 1
    fi
    log "DEBUG" "CPU Cores set to: $LXC_CORES"
    
    LXC_DISK=$(prompt_input "Disk Size (GB)" "$DEFAULT_LXC_DISK" "validate_disk_size")
    if [ -z "$LXC_DISK" ]; then
        log "ERROR" "Disk Size cannot be empty"
        exit 1
    fi
    log "DEBUG" "Disk Size set to: $LXC_DISK"
    
    # 사용 가능한 스토리지 풀 표시
    echo -e "\n${YELLOW}Available Storage Pools:${NC}"
    if ! pvesm status | grep -E "^[a-zA-Z]" | awk '{print "  - " $1 " (" $2 ")"}'; then
        log "WARN" "Failed to get storage pools, using default"
    fi
    LXC_STORAGE=$(prompt_input "Storage Pool" "$DEFAULT_LXC_STORAGE" "")
    if [ -z "$LXC_STORAGE" ]; then
        log "ERROR" "Storage Pool cannot be empty"
        exit 1
    fi
    log "DEBUG" "Storage Pool set to: $LXC_STORAGE"
    
    log "INFO" "LXC 설정 완료: ID=$LXC_ID, 이름=$LXC_NAME, 메모리=${LXC_MEMORY}MB, CPU=${LXC_CORES}코어, 디스크=${LXC_DISK}GB"
}

# 네트워크 설정 입력 함수
collect_network_settings() {
    log "INFO" "=== 네트워크 설정 ==="
    
    # 사용 가능한 브리지 인터페이스 표시
    echo -e "\n${YELLOW}Available Bridge Interfaces:${NC}"
    ip link show | grep -E "^[0-9]+: vmbr" | awk -F': ' '{print "  - " $2}' | cut -d'@' -f1 || log "WARN" "Failed to get bridge interfaces"
    LXC_BRIDGE=$(prompt_input "Bridge Interface" "$DEFAULT_LXC_BRIDGE" "")
    if [ -z "$LXC_BRIDGE" ]; then
        log "ERROR" "Bridge Interface cannot be empty"
        exit 1
    fi
    
    echo -e "\n${YELLOW}IP Configuration Method:${NC}"
    echo "1) DHCP (Auto Assignment)"
    echo "2) Static IP"
    
    local ip_choice
    while true; do
        printf "Select [1-2]: "
        if ! read -r -t 30 ip_choice; then
            log "DEBUG" "Using default DHCP configuration"
            LXC_IP="dhcp"
            LXC_GATEWAY=""
            break
        fi
        
        case $ip_choice in
            1)
                LXC_IP="dhcp"
                LXC_GATEWAY=""
                break
                ;;
            2)
                LXC_IP=$(prompt_input "IP Address (e.g., 192.168.1.100/24)" "" "")
                if [ -z "$LXC_IP" ]; then
                    log "ERROR" "IP Address cannot be empty"
                    exit 1
                fi
                LXC_GATEWAY=$(prompt_input "Gateway" "192.168.1.1" "validate_ip")
                if [ -z "$LXC_GATEWAY" ]; then
                    log "ERROR" "Gateway cannot be empty"
                    exit 1
                fi
                break
                ;;
            *)
                log "ERROR" "Please select 1 or 2."
                ;;
        esac
    done
    
    LXC_DNS=$(prompt_input "DNS Server" "$DEFAULT_DNS" "validate_ip")
    if [ -z "$LXC_DNS" ]; then
        log "ERROR" "DNS Server cannot be empty"
        exit 1
    fi
    
    log "INFO" "네트워크 설정 완료: 브리지=$LXC_BRIDGE, IP=$LXC_IP, 게이트웨이=$LXC_GATEWAY, DNS=$LXC_DNS"
}

# 서비스 포트 설정 입력 함수
collect_service_settings() {
    log "INFO" "=== 서비스 포트 설정 ==="
    
    DOCKGE_PORT=$(prompt_input "Dockge Port" "$DEFAULT_DOCKGE_PORT" "validate_port")
    if [ -z "$DOCKGE_PORT" ]; then
        log "ERROR" "Dockge Port cannot be empty"
        exit 1
    fi
    
    CLOUDCMD_PORT=$(prompt_input "CloudCmd Port" "$DEFAULT_CLOUDCMD_PORT" "validate_port")
    if [ -z "$CLOUDCMD_PORT" ]; then
        log "ERROR" "CloudCmd Port cannot be empty"
        exit 1
    fi
    
    SUPABASE_STUDIO_PORT=$(prompt_input "Supabase Studio Port" "$DEFAULT_SUPABASE_STUDIO_PORT" "validate_port")
    if [ -z "$SUPABASE_STUDIO_PORT" ]; then
        log "ERROR" "Supabase Studio Port cannot be empty"
        exit 1
    fi
    
    # 도메인 설정
    if [ "$LXC_IP" = "dhcp" ]; then
        DOMAIN=$(prompt_input "Domain/Hostname (will be set later for DHCP)" "$DEFAULT_DOMAIN" "")
    else
        container_ip=$(echo "$LXC_IP" | cut -d'/' -f1)
        DOMAIN=$(prompt_input "Domain/Hostname" "$container_ip" "")
    fi
    
    if [ -z "$DOMAIN" ]; then
        log "ERROR" "Domain/Hostname cannot be empty"
        exit 1
    fi
    
    log "INFO" "서비스 설정 완료: Dockge=$DOCKGE_PORT, CloudCmd=$CLOUDCMD_PORT, Supabase Studio=$SUPABASE_STUDIO_PORT"
}

# Supabase 환경변수 설정 함수
collect_supabase_settings() {
    log "INFO" "=== Supabase 환경변수 설정 ==="
    
    # 데이터베이스 비밀번호
    echo -e "\n${YELLOW}Set PostgreSQL database password.${NC}"
    echo "Leave empty to auto-generate a strong password."
    POSTGRES_PASSWORD=$(prompt_input "PostgreSQL Password" "" "")
    
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
    echo -e "\n${YELLOW}SMTP Email Settings (Optional)${NC}"
    echo "Enter SMTP settings for email authentication. Press Enter to skip."
    
    smtp_host=$(prompt_input "SMTP Host" "" "")
    if [ -n "$smtp_host" ]; then
        SMTP_HOST=$smtp_host
        SMTP_PORT=$(prompt_input "SMTP Port" "587" "validate_port")
        SMTP_USER=$(prompt_input "SMTP Username" "" "")
        SMTP_PASS=$(prompt_input "SMTP Password" "" "")
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
        if ! read -r -t 30 confirm; then
            log "DEBUG" "Using default 'no' for confirmation"
            log "INFO" "설치가 취소되었습니다."
            exit 0
        fi
        
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