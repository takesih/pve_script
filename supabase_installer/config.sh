#!/bin/bash

# Supabase LXC Installer Configuration
# 이 파일은 모든 설정 변수들을 포함합니다.

# 스크립트 버전
SCRIPT_VERSION="250807064448"

# 기본 디렉토리
# 원격 실행 시 임시 디렉토리 사용, 로컬 실행 시 현재 디렉토리 사용
if [[ "${BASH_SOURCE[0]}" == *"curl"* ]] || [[ "${BASH_SOURCE[0]}" == *"wget"* ]] || [[ ! -f "$(dirname "${BASH_SOURCE[0]:-$0}")/config.sh" ]]; then
    SCRIPT_DIR="/tmp/supabase_installer_scripts"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
fi

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

# SMTP 설정 변수
SMTP_HOST=""
SMTP_PORT=""
SMTP_USER=""
SMTP_PASS=""

# 기본값 설정
DEFAULT_LXC_MEMORY="4096"
DEFAULT_LXC_CORES="2"
DEFAULT_LXC_DISK="20"
DEFAULT_LXC_STORAGE="local-lvm"
DEFAULT_LXC_BRIDGE="vmbr0"
DEFAULT_DNS="8.8.8.8"
DEFAULT_DOCKGE_PORT="5001"
DEFAULT_CLOUDCMD_PORT="8000"
DEFAULT_SUPABASE_STUDIO_PORT="3001"
DEFAULT_DOMAIN="localhost"

# 검증 함수들
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