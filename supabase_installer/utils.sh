#!/bin/bash

# Supabase LXC Installer Utilities
# 이 파일은 공통 유틸리티 함수들을 포함합니다.

# 설정 파일 로드
source "$(dirname "$0")/config.sh"

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

# 사용자 입력 함수 (개선된 버전)
prompt_input() {
    local prompt_text="$1"
    local default_value="$2"
    local validation_func="$3"
    local input_value=""
    
    while true; do
        if [ -n "$default_value" ]; then
            printf "%s [default: %s]: " "$prompt_text" "$default_value"
        else
            printf "%s: " "$prompt_text"
        fi
        
        # read 명령어에 타임아웃 추가 (30초)
        if ! read -r -t 30 input_value; then
            if [ -n "$default_value" ]; then
                log "DEBUG" "Read timeout, using default value: $default_value"
                printf "%s\n" "$default_value"
                return 0
            else
                log "ERROR" "Read timeout and no default value provided"
                return 1
            fi
        fi
        
        # 빈 입력시 기본값 사용
        if [ -z "$input_value" ] && [ -n "$default_value" ]; then
            input_value="$default_value"
        fi
        
        # 검증 함수가 있으면 검증 수행
        if [ -n "$validation_func" ] && [ "$validation_func" != "" ]; then
            if $validation_func "$input_value"; then
                printf "%s\n" "$input_value"
                return 0
            else
                echo "Invalid input. Please try again." >&2
                continue
            fi
        else
            printf "%s\n" "$input_value"
            return 0
        fi
    done
}

# 임시 파일 정리 함수
cleanup_temp_files() {
    log "INFO" "임시 파일들을 정리하는 중..."
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        log "INFO" "임시 디렉토리 삭제 완료: $TEMP_DIR"
    fi
}

# 오류 발생시 정리 함수
cleanup_on_error() {
    log "ERROR" "오류가 발생했습니다. 임시 파일을 정리합니다..."
    cleanup_temp_files
    
    # 생성된 컨테이너가 있다면 정리 옵션 제공
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

# 최신 버전 가져오기 함수
get_latest_release() {
    local repo="$1"
    curl -fsSL "https://api.github.com/repos/$repo/releases/latest" | grep '"tag_name":' | cut -d'"' -f4
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

# 시스템 리소스 확인 함수
check_system_resources() {
    log "INFO" "시스템 리소스를 확인하는 중..."
    
    # 메모리 확인 (최소 8GB 권장)
    local total_memory=$(free -m | awk 'NR==2{printf "%.0f", $2}')
    if [ "$total_memory" -lt 8192 ]; then
        log "WARN" "시스템 메모리가 부족할 수 있습니다. (현재: ${total_memory}MB, 권장: 8192MB 이상)"
    fi
    
    # 디스크 공간 확인 (최소 20GB 권장)
    local available_space=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
    if [ "$available_space" -lt 20 ]; then
        log "WARN" "디스크 공간이 부족할 수 있습니다. (현재: ${available_space}GB, 권장: 20GB 이상)"
        log "WARN" "계속 진행하시겠습니까? 공간 부족으로 설치가 실패할 수 있습니다."
    elif [ "$available_space" -lt 50 ]; then
        log "WARN" "디스크 공간이 권장 사양보다 적습니다. (현재: ${available_space}GB, 권장: 50GB 이상)"
    fi
    
    log "INFO" "시스템 리소스 확인 완료"
}

# 네트워크 연결 확인 함수
check_network_connectivity() {
    log "INFO" "네트워크 연결을 확인하는 중..."
    
    # 인터넷 연결 확인
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        log "ERROR" "인터넷 연결을 확인할 수 없습니다."
        return 1
    fi
    
    # GitHub 접근 확인
    if ! curl -s --connect-timeout 5 https://github.com &> /dev/null; then
        log "ERROR" "GitHub에 접근할 수 없습니다. 방화벽 설정을 확인하세요."
        return 1
    fi
    
    # Docker Hub 접근 확인
    if ! curl -s --connect-timeout 5 https://hub.docker.com &> /dev/null; then
        log "ERROR" "Docker Hub에 접근할 수 없습니다. 방화벽 설정을 확인하세요."
        return 1
    fi
    
    log "INFO" "네트워크 연결 확인 완료"
    return 0
} 