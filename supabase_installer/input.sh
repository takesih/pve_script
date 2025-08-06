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
    
    # Container ID 입력
    while true; do
        printf "Container ID [default: %s]: " "$next_id"
        if ! read -r LXC_ID; then
            LXC_ID="$next_id"
            break
        fi
        
        if [ -z "$LXC_ID" ]; then
            LXC_ID="$next_id"
            break
        fi
        
        if [[ "$LXC_ID" =~ ^[0-9]+$ ]]; then
            break
        else
            echo "Invalid input. Please enter a number."
        fi
    done
    log "DEBUG" "Container ID set to: $LXC_ID"
    
    # Container Name 입력
    while true; do
        printf "Container Name [default: supabase-dev]: "
        if ! read -r LXC_NAME; then
            LXC_NAME="supabase-dev"
            break
        fi
        
        if [ -z "$LXC_NAME" ]; then
            LXC_NAME="supabase-dev"
            break
        fi
        
        if [[ "$LXC_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            break
        else
            echo "Invalid input. Please use only letters, numbers, hyphens, and underscores."
        fi
    done
    log "DEBUG" "Container Name set to: $LXC_NAME"
    
    # Memory 입력
    while true; do
        printf "Memory Size (MB) [default: %s]: " "$DEFAULT_LXC_MEMORY"
        if ! read -r LXC_MEMORY; then
            LXC_MEMORY="$DEFAULT_LXC_MEMORY"
            break
        fi
        
        if [ -z "$LXC_MEMORY" ]; then
            LXC_MEMORY="$DEFAULT_LXC_MEMORY"
            break
        fi
        
        if validate_memory "$LXC_MEMORY"; then
            break
        else
            echo "Invalid input. Please enter a number >= 1024."
        fi
    done
    log "DEBUG" "Memory set to: $LXC_MEMORY"
    
    # CPU Cores 입력
    while true; do
        printf "CPU Cores [default: %s]: " "$DEFAULT_LXC_CORES"
        if ! read -r LXC_CORES; then
            LXC_CORES="$DEFAULT_LXC_CORES"
            break
        fi
        
        if [ -z "$LXC_CORES" ]; then
            LXC_CORES="$DEFAULT_LXC_CORES"
            break
        fi
        
        if validate_cpu_cores "$LXC_CORES"; then
            break
        else
            echo "Invalid input. Please enter a number >= 1."
        fi
    done
    log "DEBUG" "CPU Cores set to: $LXC_CORES"
    
    # Disk Size 입력
    while true; do
        printf "Disk Size (GB) [default: %s]: " "$DEFAULT_LXC_DISK"
        if ! read -r LXC_DISK; then
            LXC_DISK="$DEFAULT_LXC_DISK"
            break
        fi
        
        if [ -z "$LXC_DISK" ]; then
            LXC_DISK="$DEFAULT_LXC_DISK"
            break
        fi
        
        if validate_disk_size "$LXC_DISK"; then
            break
        else
            echo "Invalid input. Please enter a number >= 10."
        fi
    done
    log "DEBUG" "Disk Size set to: $LXC_DISK"
    
    # 사용 가능한 스토리지 풀 표시
    echo -e "\n${YELLOW}Available Storage Pools:${NC}"
    if ! pvesm status | grep -E "^[a-zA-Z]" | awk '{print "  - " $1 " (" $2 ")"}'; then
        log "WARN" "Failed to get storage pools, using default"
    fi
    
    # Storage Pool 입력
    while true; do
        printf "Storage Pool [default: %s]: " "$DEFAULT_LXC_STORAGE"
        if ! read -r LXC_STORAGE; then
            LXC_STORAGE="$DEFAULT_LXC_STORAGE"
            break
        fi
        
        if [ -z "$LXC_STORAGE" ]; then
            LXC_STORAGE="$DEFAULT_LXC_STORAGE"
            break
        fi
        
        if [ -n "$LXC_STORAGE" ]; then
            break
        fi
    done
    log "DEBUG" "Storage Pool set to: $LXC_STORAGE"
    
    log "INFO" "LXC 설정 완료: ID=$LXC_ID, 이름=$LXC_NAME, 메모리=${LXC_MEMORY}MB, CPU=${LXC_CORES}코어, 디스크=${LXC_DISK}GB"
}

# 네트워크 설정 입력 함수
collect_network_settings() {
    log "INFO" "=== 네트워크 설정 ==="
    
    # 사용 가능한 브리지 인터페이스 표시
    echo -e "\n${YELLOW}Available Bridge Interfaces:${NC}"
    ip link show | grep -E "^[0-9]+: vmbr" | awk -F': ' '{print "  - " $2}' | cut -d'@' -f1 || log "WARN" "Failed to get bridge interfaces"
    
    # Bridge Interface 입력
    while true; do
        printf "Bridge Interface [default: %s]: " "$DEFAULT_LXC_BRIDGE"
        if ! read -r LXC_BRIDGE; then
            LXC_BRIDGE="$DEFAULT_LXC_BRIDGE"
            break
        fi
        
        if [ -z "$LXC_BRIDGE" ]; then
            LXC_BRIDGE="$DEFAULT_LXC_BRIDGE"
            break
        fi
        
        if [ -n "$LXC_BRIDGE" ]; then
            break
        fi
    done
    
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
                # Static IP 입력
                while true; do
                    printf "IP Address (e.g., 192.168.1.100/24): "
                    if ! read -r LXC_IP; then
                        echo "IP Address is required for static configuration."
                        continue
                    fi
                    
                    if [ -z "$LXC_IP" ]; then
                        echo "IP Address is required for static configuration."
                        continue
                    fi
                    
                    if [[ "$LXC_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
                        break
                    else
                        echo "Invalid IP format. Please use format: 192.168.1.100/24"
                    fi
                done
                
                # Gateway 입력
                while true; do
                    printf "Gateway [default: 192.168.1.1]: "
                    if ! read -r LXC_GATEWAY; then
                        LXC_GATEWAY="192.168.1.1"
                        break
                    fi
                    
                    if [ -z "$LXC_GATEWAY" ]; then
                        LXC_GATEWAY="192.168.1.1"
                        break
                    fi
                    
                    if validate_ip "$LXC_GATEWAY"; then
                        break
                    else
                        echo "Invalid gateway IP address."
                    fi
                done
                break
                ;;
            *)
                echo "Please select 1 or 2."
                ;;
        esac
    done
    
    # DNS 입력
    while true; do
        printf "DNS Server [default: %s]: " "$DEFAULT_DNS"
        if ! read -r LXC_DNS; then
            LXC_DNS="$DEFAULT_DNS"
            break
        fi
        
        if [ -z "$LXC_DNS" ]; then
            LXC_DNS="$DEFAULT_DNS"
            break
        fi
        
        if validate_ip "$LXC_DNS"; then
            break
        else
            echo "Invalid DNS IP address."
        fi
    done
    
    log "INFO" "네트워크 설정 완료: 브리지=$LXC_BRIDGE, IP=$LXC_IP, 게이트웨이=$LXC_GATEWAY, DNS=$LXC_DNS"
}

# 서비스 포트 설정 입력 함수
collect_service_settings() {
    log "INFO" "=== 서비스 포트 설정 ==="
    
    # Dockge Port 입력
    while true; do
        printf "Dockge Port [default: %s]: " "$DEFAULT_DOCKGE_PORT"
        if ! read -r DOCKGE_PORT; then
            DOCKGE_PORT="$DEFAULT_DOCKGE_PORT"
            break
        fi
        
        if [ -z "$DOCKGE_PORT" ]; then
            DOCKGE_PORT="$DEFAULT_DOCKGE_PORT"
            break
        fi
        
        if validate_port "$DOCKGE_PORT"; then
            break
        else
            echo "Invalid port number. Please enter a number between 1 and 65535."
        fi
    done
    
    # CloudCmd Port 입력
    while true; do
        printf "CloudCmd Port [default: %s]: " "$DEFAULT_CLOUDCMD_PORT"
        if ! read -r CLOUDCMD_PORT; then
            CLOUDCMD_PORT="$DEFAULT_CLOUDCMD_PORT"
            break
        fi
        
        if [ -z "$CLOUDCMD_PORT" ]; then
            CLOUDCMD_PORT="$DEFAULT_CLOUDCMD_PORT"
            break
        fi
        
        if validate_port "$CLOUDCMD_PORT"; then
            break
        else
            echo "Invalid port number. Please enter a number between 1 and 65535."
        fi
    done
    
    # Supabase Studio Port 입력
    while true; do
        printf "Supabase Studio Port [default: %s]: " "$DEFAULT_SUPABASE_STUDIO_PORT"
        if ! read -r SUPABASE_STUDIO_PORT; then
            SUPABASE_STUDIO_PORT="$DEFAULT_SUPABASE_STUDIO_PORT"
            break
        fi
        
        if [ -z "$SUPABASE_STUDIO_PORT" ]; then
            SUPABASE_STUDIO_PORT="$DEFAULT_SUPABASE_STUDIO_PORT"
            break
        fi
        
        if validate_port "$SUPABASE_STUDIO_PORT"; then
            break
        else
            echo "Invalid port number. Please enter a number between 1 and 65535."
        fi
    done
    
    # 도메인 설정
    if [ "$LXC_IP" = "dhcp" ]; then
        while true; do
            printf "Domain/Hostname (will be set later for DHCP) [default: %s]: " "$DEFAULT_DOMAIN"
            if ! read -r DOMAIN; then
                DOMAIN="$DEFAULT_DOMAIN"
                break
            fi
            
            if [ -z "$DOMAIN" ]; then
                DOMAIN="$DEFAULT_DOMAIN"
                break
            fi
            
            if [ -n "$DOMAIN" ]; then
                break
            fi
        done
    else
        container_ip=$(echo "$LXC_IP" | cut -d'/' -f1)
        while true; do
            printf "Domain/Hostname [default: %s]: " "$container_ip"
            if ! read -r DOMAIN; then
                DOMAIN="$container_ip"
                break
            fi
            
            if [ -z "$DOMAIN" ]; then
                DOMAIN="$container_ip"
                break
            fi
            
            if [ -n "$DOMAIN" ]; then
                break
            fi
        done
    fi
    
    log "INFO" "서비스 설정 완료: Dockge=$DOCKGE_PORT, CloudCmd=$CLOUDCMD_PORT, Supabase Studio=$SUPABASE_STUDIO_PORT"
}

# Supabase 환경변수 설정 함수
collect_supabase_settings() {
    log "INFO" "=== Supabase 환경변수 설정 ==="
    
    # 데이터베이스 비밀번호
    echo -e "\n${YELLOW}Set PostgreSQL database password.${NC}"
    echo "Leave empty to auto-generate a strong password."
    
    printf "PostgreSQL Password: "
    if ! read -r POSTGRES_PASSWORD; then
        POSTGRES_PASSWORD=""
    fi
    
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
    
    printf "SMTP Host: "
    if ! read -r smtp_host; then
        smtp_host=""
    fi
    
    if [ -n "$smtp_host" ]; then
        SMTP_HOST=$smtp_host
        
        # SMTP Port 입력
        while true; do
            printf "SMTP Port [default: 587]: "
            if ! read -r SMTP_PORT; then
                SMTP_PORT="587"
                break
            fi
            
            if [ -z "$SMTP_PORT" ]; then
                SMTP_PORT="587"
                break
            fi
            
            if validate_port "$SMTP_PORT"; then
                break
            else
                echo "Invalid port number. Please enter a number between 1 and 65535."
            fi
        done
        
        printf "SMTP Username: "
        if ! read -r SMTP_USER; then
            SMTP_USER=""
        fi
        
        printf "SMTP Password: "
        if ! read -r SMTP_PASS; then
            SMTP_PASS=""
        fi
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