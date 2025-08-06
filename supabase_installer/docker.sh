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