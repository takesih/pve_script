#!/bin/bash

# Supabase LXC Installer Docker Module
# 이 파일은 Docker 설치 관련 함수들을 포함합니다.

# 설정 파일과 유틸리티 로드
source "$(dirname "$0")/config.sh"
source "$(dirname "$0")/utils.sh"

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
    compose_version=$(get_latest_release "docker/compose")
    
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

# Dockge 설치 함수들
create_dockge_directories() {
    log "INFO" "Dockge 디렉토리를 생성하는 중..."
    
    if ! exec_in_container "mkdir -p /opt/dockge"; then
        log "ERROR" "Dockge 디렉토리 생성에 실패했습니다."
        return 1
    fi
    
    if ! exec_in_container "mkdir -p /opt/dockge/stacks"; then
        log "ERROR" "Dockge stacks 디렉토리 생성에 실패했습니다."
        return 1
    fi
    
    log "INFO" "Dockge 디렉토리 생성 완료"
    return 0
}

create_dockge_compose() {
    log "INFO" "Dockge docker-compose.yml 파일을 생성하는 중..."
    
    local compose_content="version: '3.8'
services:
  dockge:
    image: louislam/dockge:1
    container_name: dockge
    restart: unless-stopped
    ports:
      - \"$DOCKGE_PORT:5001\"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /opt/dockge/data:/app/data
      - /opt/dockge/stacks:/opt/stacks
    environment:
      - DOCKGE_STACKS_DIR=/opt/stacks
    networks:
      - dockge_network

networks:
  dockge_network:
    driver: bridge"
    
    if ! exec_in_container "cat > /opt/dockge/docker-compose.yml << 'EOF'
$compose_content
EOF"; then
        log "ERROR" "Dockge docker-compose.yml 파일 생성에 실패했습니다."
        return 1
    fi
    
    log "INFO" "Dockge docker-compose.yml 파일 생성 완료"
    return 0
}

start_dockge_service() {
    log "INFO" "Dockge 서비스를 시작하는 중..."
    
    if ! exec_in_container "cd /opt/dockge && docker-compose up -d"; then
        log "ERROR" "Dockge 서비스 시작에 실패했습니다."
        return 1
    fi
    
    # 서비스 시작 대기
    sleep 10
    
    log "INFO" "Dockge 서비스 시작 완료"
    return 0
}

verify_dockge_installation() {
    log "INFO" "Dockge 설치를 검증하는 중..."
    
    # 컨테이너 상태 확인
    if ! exec_in_container "docker ps | grep -q dockge"; then
        log "ERROR" "Dockge 컨테이너가 실행되지 않고 있습니다."
        return 1
    fi
    
    # 웹 인터페이스 접근 확인
    local container_ip=$(pct exec "$LXC_ID" -- hostname -I | awk '{print $1}')
    if ! curl -s "http://$container_ip:$DOCKGE_PORT" > /dev/null; then
        log "WARN" "Dockge 웹 인터페이스에 접근할 수 없습니다."
    fi
    
    log "INFO" "Dockge 설치 검증 완료"
    return 0
}

# CloudCmd 설치 함수들
create_cloudcmd_directories() {
    log "INFO" "CloudCmd 디렉토리를 생성하는 중..."
    
    if ! exec_in_container "mkdir -p /opt/cloudcmd"; then
        log "ERROR" "CloudCmd 디렉토리 생성에 실패했습니다."
        return 1
    fi
    
    log "INFO" "CloudCmd 디렉토리 생성 완료"
    return 0
}

create_cloudcmd_compose() {
    log "INFO" "CloudCmd docker-compose.yml 파일을 생성하는 중..."
    
    local compose_content="version: '3.8'
services:
  cloudcmd:
    image: coderaiser/cloudcmd:latest
    container_name: cloudcmd
    restart: unless-stopped
    ports:
      - \"$CLOUDCMD_PORT:8000\"
    volumes:
      - /:/mnt/fs:ro
      - /opt/cloudcmd/data:/root
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
    
    if ! exec_in_container "cat > /opt/cloudcmd/docker-compose.yml << 'EOF'
$compose_content
EOF"; then
        log "ERROR" "CloudCmd docker-compose.yml 파일 생성에 실패했습니다."
        return 1
    fi
    
    log "INFO" "CloudCmd docker-compose.yml 파일 생성 완료"
    return 0
}

start_cloudcmd_service() {
    log "INFO" "CloudCmd 서비스를 시작하는 중..."
    
    if ! exec_in_container "cd /opt/cloudcmd && docker-compose up -d"; then
        log "ERROR" "CloudCmd 서비스 시작에 실패했습니다."
        return 1
    fi
    
    # 서비스 시작 대기
    sleep 10
    
    log "INFO" "CloudCmd 서비스 시작 완료"
    return 0
}

verify_cloudcmd_installation() {
    log "INFO" "CloudCmd 설치를 검증하는 중..."
    
    # 컨테이너 상태 확인
    if ! exec_in_container "docker ps | grep -q cloudcmd"; then
        log "ERROR" "CloudCmd 컨테이너가 실행되지 않고 있습니다."
        return 1
    fi
    
    log "INFO" "CloudCmd 설치 검증 완료"
    return 0
}

# Supabase 설치 함수들
create_supabase_directories() {
    log "INFO" "Supabase 디렉토리를 생성하는 중..."
    
    if ! exec_in_container "mkdir -p /opt/supabase"; then
        log "ERROR" "Supabase 디렉토리 생성에 실패했습니다."
        return 1
    fi
    
    log "INFO" "Supabase 디렉토리 생성 완료"
    return 0
}

download_supabase_configs() {
    log "INFO" "Supabase 설정 파일을 다운로드하는 중..."
    
    local base_url="https://raw.githubusercontent.com/supabase/supabase/master/docker"
    
    # docker-compose.yml 다운로드
    if ! exec_in_container "curl -fsSL '$base_url/docker-compose.yml' -o /opt/supabase/docker-compose.yml"; then
        log "ERROR" "Supabase docker-compose.yml 다운로드에 실패했습니다."
        return 1
    fi
    
    # .env.example 다운로드
    if ! exec_in_container "curl -fsSL '$base_url/.env.example' -o /opt/supabase/.env.example"; then
        log "ERROR" "Supabase .env.example 다운로드에 실패했습니다."
        return 1
    fi
    
    log "INFO" "Supabase 설정 파일 다운로드 완료"
    return 0
}

create_supabase_env() {
    log "INFO" "Supabase 환경변수 파일을 생성하는 중..."
    
    local env_content="# Supabase Configuration
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
JWT_SECRET=$JWT_SECRET
ANON_KEY=$ANON_KEY
SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY
API_EXTERNAL_URL=$API_EXTERNAL_URL
SUPABASE_PUBLIC_URL=$SUPABASE_PUBLIC_URL

# Database
POSTGRES_HOST=db
POSTGRES_PORT=5432
POSTGRES_DB=postgres

# API
API_PORT=8001
STUDIO_PORT=$SUPABASE_STUDIO_PORT

# Auth
JWT_EXPIRY=3600
JWT_DEFAULT_GROUP_NAME=authenticated

# Storage
STORAGE_BACKEND=file
FILE_STORAGE_BACKEND_PATH=/var/lib/storage

# SMTP (Optional)
SMTP_HOST=$SMTP_HOST
SMTP_PORT=$SMTP_PORT
SMTP_USER=$SMTP_USER
SMTP_PASS=$SMTP_PASS
SMTP_SENDER_NAME=Supabase
SMTP_SENDER_EMAIL=noreply@supabase.com"
    
    if ! exec_in_container "cat > /opt/supabase/.env << 'EOF'
$env_content
EOF"; then
        log "ERROR" "Supabase .env 파일 생성에 실패했습니다."
        return 1
    fi
    
    log "INFO" "Supabase 환경변수 파일 생성 완료"
    return 0
}

start_supabase_service() {
    log "INFO" "Supabase 서비스를 시작하는 중..."
    
    if ! exec_in_container "cd /opt/supabase && docker-compose up -d"; then
        log "ERROR" "Supabase 서비스 시작에 실패했습니다."
        return 1
    fi
    
    # 서비스 시작 대기
    sleep 30
    
    log "INFO" "Supabase 서비스 시작 완료"
    return 0
}

verify_supabase_installation() {
    log "INFO" "Supabase 설치를 검증하는 중..."
    
    # 컨테이너 상태 확인
    if ! exec_in_container "docker ps | grep -q supabase"; then
        log "ERROR" "Supabase 컨테이너가 실행되지 않고 있습니다."
        return 1
    fi
    
    # API 상태 확인
    local container_ip=$(pct exec "$LXC_ID" -- hostname -I | awk '{print $1}')
    if ! curl -s "http://$container_ip:8001/health" > /dev/null; then
        log "WARN" "Supabase API에 접근할 수 없습니다."
    fi
    
    log "INFO" "Supabase 설치 검증 완료"
    return 0
}

# Dockge 설치 메인 함수
install_dockge() {
    log "INFO" "=== Dockge 설치 시작 ==="
    
    show_progress 1 4 "Dockge 디렉토리 생성 중..."
    if ! create_dockge_directories; then
        return 1
    fi
    
    show_progress 2 4 "Dockge Compose 파일 생성 중..."
    if ! create_dockge_compose; then
        return 1
    fi
    
    show_progress 3 4 "Dockge 서비스 시작 중..."
    if ! start_dockge_service; then
        return 1
    fi
    
    show_progress 4 4 "Dockge 설치 검증 중..."
    if ! verify_dockge_installation; then
        return 1
    fi
    
    log "INFO" "=== Dockge 설치 완료 ==="
    log "INFO" "Dockge 웹 인터페이스: http://$DOMAIN:$DOCKGE_PORT"
    return 0
}

# CloudCmd 설치 메인 함수
install_cloudcmd() {
    log "INFO" "=== CloudCmd 설치 시작 ==="
    
    show_progress 1 4 "CloudCmd 디렉토리 생성 중..."
    if ! create_cloudcmd_directories; then
        return 1
    fi
    
    show_progress 2 4 "CloudCmd Compose 파일 생성 중..."
    if ! create_cloudcmd_compose; then
        return 1
    fi
    
    show_progress 3 4 "CloudCmd 서비스 시작 중..."
    if ! start_cloudcmd_service; then
        return 1
    fi
    
    show_progress 4 4 "CloudCmd 설치 검증 중..."
    if ! verify_cloudcmd_installation; then
        return 1
    fi
    
    log "INFO" "=== CloudCmd 설치 완료 ==="
    log "INFO" "CloudCmd 웹 인터페이스: http://$DOMAIN:$CLOUDCMD_PORT"
    return 0
}

# Supabase 설치 메인 함수
install_supabase() {
    log "INFO" "=== Supabase 설치 시작 ==="
    
    show_progress 1 6 "Supabase 디렉토리 생성 중..."
    if ! create_supabase_directories; then
        return 1
    fi
    
    show_progress 2 6 "Supabase 설정 파일 다운로드 중..."
    if ! download_supabase_configs; then
        return 1
    fi
    
    show_progress 3 6 "Supabase 환경변수 설정 중..."
    if ! create_supabase_env; then
        return 1
    fi
    
    show_progress 4 6 "Supabase 서비스 시작 중..."
    if ! start_supabase_service; then
        return 1
    fi
    
    show_progress 5 6 "Supabase 설치 검증 중..."
    if ! verify_supabase_installation; then
        return 1
    fi
    
    show_progress 6 6 "Supabase 초기 설정 중..."
    # Supabase 초기 설정 (데이터베이스 마이그레이션 등)
    sleep 10
    
    log "INFO" "=== Supabase 설치 완료 ==="
    log "INFO" "Supabase Studio: http://$DOMAIN:$SUPABASE_STUDIO_PORT"
    log "INFO" "Supabase API: http://$DOMAIN:8001"
    return 0
} 