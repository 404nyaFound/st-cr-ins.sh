#!/bin/bash

SOFTWARE_NAME="clewdr"
GITHUB_REPO="Xerxes-2/clewdr"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
TARGET_DIR="${SCRIPT_DIR}/clewdr"
GH_PROXY="https://ghfast.top/"
GH_DOWNLOAD_URL_BASE="https://github.com/${GITHUB_REPO}/releases/latest/download"
GH_API_URL="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
GH_ACTION_URL="https://github.com/${GITHUB_REPO}/actions/workflows/release.yml"
VERSION_FILE="${TARGET_DIR}/version.txt"
PORT=8484

handle_error() {
    echo "�����F${2}"
    exit ${1}
}

detect_system() {
    echo "�����n������..."
    
    if [[ -n "$PREFIX" ]] && [[ "$PREFIX" == *"/com.termux"* ]]; then
        IS_TERMUX=true
        echo "������Termux����"
    else
        IS_TERMUX=false
        
        if command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -q -i 'musl'; then
            IS_MUSL=true
            echo "������MUSL Linux����"
        else
            IS_MUSL=false
            echo "���������yLinux����(glibc)"
        fi
    fi
    
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64) ARCH="x86_64" ;;
        aarch64|arm64) ARCH="aarch64" ;;
        armv7l|armv8l) handle_error 1 "���s�x��32��ARM���� ($ARCH)" ;;
        *) handle_error 1 "�s�x���I�n������: $ARCH" ;;
    esac
    echo "����������: $ARCH"
    
    if [ "$IS_TERMUX" = true ] && [ "$ARCH" != "aarch64" ]; then
        handle_error 1 "Termux�������x��aarch64����"
    fi
    
    if [ "$IS_TERMUX" = true ]; then
        PACKAGE_MANAGER="pkg"
        INSTALL_CMD="pkg install -y"
    elif command -v apt >/dev/null 2>&1; then
        PACKAGE_MANAGER="apt"
        INSTALL_CMD="apt install -y"
    elif command -v dnf >/dev/null 2>&1; then
        PACKAGE_MANAGER="dnf"
        INSTALL_CMD="dnf install -y"
    elif command -v yum >/dev/null 2>&1; then
        PACKAGE_MANAGER="yum"
        INSTALL_CMD="yum install -y"
    elif command -v pacman >/dev/null 2>&1; then
        PACKAGE_MANAGER="pacman"
        INSTALL_CMD="pacman -S --noconfirm"
    elif command -v zypper >/dev/null 2>&1; then
        PACKAGE_MANAGER="zypper"
        INSTALL_CMD="zypper install -y"
    elif command -v apk >/dev/null 2>&1; then
        PACKAGE_MANAGER="apk"
        INSTALL_CMD="apk add"
    else
        echo "�x��: ���������x���I��Ǘ���C��������������"
        PACKAGE_MANAGER="unknown"
        INSTALL_CMD=""
    fi
    
    [ -n "$PACKAGE_MANAGER" ] && echo "�g�p��Ǘ���: $PACKAGE_MANAGER"
}

install_dependencies() {
    echo "�������������..."
    local dependencies=("curl" "unzip")
    local missing_deps=()
    
    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -eq 0 ]; then
        echo "���L�����߈���"
        return 0
    fi
    
    if [ "$PACKAGE_MANAGER" = "unknown" ] || [ -z "$INSTALL_CMD" ]; then
        handle_error 1 "㞏��ȉ������C�A�ٖ@��������: ${missing_deps[*]}"
    fi
    
    echo "����㞎��I����: ${missing_deps[*]}"
    
    case "$PACKAGE_MANAGER" in
        apt|pkg) apt update || pkg update ;;
        pacman) pacman -Sy ;;
        zypper) zypper refresh ;;
        apk) apk update ;;
    esac
    
    if ! $INSTALL_CMD "${missing_deps[@]}"; then
        handle_error 1 "�������������C����������: ${missing_deps[*]}"
    fi
    
    for dep in "${missing_deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            handle_error 1 "���� $dep ���������C����������"
        fi
    done
    
    echo "������������"
}

get_installed_version() {
    if [ -f "$TARGET_DIR/$SOFTWARE_NAME" ] && [ -x "$TARGET_DIR/$SOFTWARE_NAME" ]; then
        local version_output
        version_output=$("$TARGET_DIR/$SOFTWARE_NAME" -V 2>/dev/null)
        local exit_code=$?
        
        if [ $exit_code -eq 0 ] && [ -n "$version_output" ]; then
            INSTALLED_VERSION=$(echo "$version_output" | grep -o "v[0-9]\+\.[0-9]\+\.[0-9]\+" || echo "$version_output")
            echo "���������Q���������Ŗ{: $INSTALLED_VERSION"
            return 0
        fi
    fi
    
    if [ -f "$VERSION_FILE" ]; then
        INSTALLED_VERSION=$(cat "$VERSION_FILE")
        echo "���Ŗ{�����������Ŗ{: $INSTALLED_VERSION"
        return 0
    fi
    
    INSTALLED_VERSION=""
    echo "���������߈����Ŗ{"
    return 1
}

check_version() {
    echo "���������Ŗ{..."
    
    if [ ! -d "$TARGET_DIR" ]; then
        echo "���������߈��������C�����s�񎟈���"
        return 0
    fi
    
    get_installed_version
    
    if [ "$USE_BETA" = true ]; then
        echo "���������������ŁC�������Ŗ{����"
        LATEST_VERSION="beta-$(date +%Y%m%d)"
        return 0
    fi
    
    echo "���������ŐV����Ŗ{..."
    
    local country_code=$(curl -s --connect-timeout 5 ipinfo.io/country)
    local api_url="$GH_API_URL"
    local use_proxy=false
    
    if [ -n "$country_code" ] && [ "$country_code" = "CN" ]; then
        echo "��������������IP�C���g�p�㗝����Ŗ{�M��"
        api_url="${GH_PROXY}${GH_API_URL}"
        use_proxy=true
    fi
    
    local latest_info=$(curl -s --connect-timeout 10 "$api_url")
    if [ -z "$latest_info" ]; then
        echo "�ٖ@����ŐV�Ŗ{�M���C���ێ����O�Ŗ{"
        return 1
    fi
    
    LATEST_VERSION=$(echo "$latest_info" | grep -o '"tag_name": *"[^"]*"' | head -n 1 | cut -d'"' -f4)
    if [ -z "$LATEST_VERSION" ]; then
        LATEST_VERSION=$(echo "$latest_info" | grep -o '"tag_name":"[^"]*"' | head -n 1 | cut -d'"' -f4)
    fi
    
    if [ -z "$LATEST_VERSION" ]; then
        echo "��͔Ŗ{�M�������C���ێ����O�Ŗ{"
        return 1
    fi
    
    echo "�ŐV����Ŗ{: $LATEST_VERSION"
    
    if [ -z "$INSTALLED_VERSION" ]; then
        echo "���������߈����Ŗ{�C�������ŐV�Ŗ{"
        return 0
    fi
    
    if [ "$INSTALLED_VERSION" = "$LATEST_VERSION" ]; then
        echo "�ߐ��ŐV����Ŗ{�C�َ��X�V"
        read -p "���������d�V�����H(y/N): " force_update
        if [[ "$force_update" =~ ^[Yy]$ ]]; then
            echo "�������d�V����..."
            return 0
        else
            return 1
        fi
    else
        echo "�����V����Ŗ{�C���� $INSTALLED_VERSION �X�V�� $LATEST_VERSION"
        return 0
    fi
}

select_version() {
    echo "�����������Ŗ{���^:"
    echo "1) ����� (����GitHub Releases)"
    echo "2) ������ (����GitHub Actions)"
    
    read -p "������ [1/2] (����:1): " version_choice
    
    case "$version_choice" in
        2)
            USE_BETA=true
            echo "������������"
            ;;
        *)
            USE_BETA=false
            echo "�����������"
            ;;
    esac
}

setup_download_url() {
    echo "�y����������..."
    
    echo "����IP�n���ʒu..."
    local country_code=$(curl -s --connect-timeout 5 ipinfo.io/country)
    local use_proxy=false
    
    if [ -n "$country_code" ] && [[ "$country_code" =~ ^[A-Z]{2}$ ]]; then
        echo "���������Ƒ���: $country_code"
        
        if [ "$country_code" = "CN" ]; then
            echo "��������������IP�C�������pGitHub�㗝: $GH_PROXY"
            read -p "���ۋ֗pGitHub�㗝�H(y/N): " disable_proxy
            
            if [[ "$disable_proxy" =~ ^[Yy]$ ]]; then
                use_proxy=false
                echo "�ߋ֗pGitHub�㗝�C������GitHub"
            else
                use_proxy=true
                echo "�g�pGitHub�㗝: $GH_PROXY"
            fi
        else
            echo "�񒆍�����IP�C�s�g�pGitHub�㗝"
        fi
    else
        echo "�ٖ@����IP�n���ʒu�C�s�g�pGitHub�㗝"
    fi
    
    if [ "$IS_TERMUX" = true ]; then
        FILE_SUFFIX="android-aarch64"
    elif [ "$IS_MUSL" = true ]; then
        FILE_SUFFIX="musllinux-$ARCH"
    else
        FILE_SUFFIX="linux-$ARCH"
    fi
    
    DOWNLOAD_FILENAME="$SOFTWARE_NAME-$FILE_SUFFIX.zip"
    echo "�������i��: $DOWNLOAD_FILENAME"
    
    if [ "$USE_BETA" = true ]; then
        echo "��������ŐV����������..."
        GH_DOWNLOAD_URL="https://nightly.link/${GITHUB_REPO}/workflows/dev-build/master/${GITHUB_REPO##*/}-${FILE_SUFFIX}.zip"
        echo "�g�p�����ŉ�������: $GH_DOWNLOAD_URL"
    else
        if [ "$use_proxy" = true ]; then
            GH_DOWNLOAD_URL="${GH_PROXY}${GH_DOWNLOAD_URL_BASE}"
        else
            GH_DOWNLOAD_URL="$GH_DOWNLOAD_URL_BASE"
        fi
    
        echo "�g�p����ŉ�������: $GH_DOWNLOAD_URL/$DOWNLOAD_FILENAME"
    fi
}

download_and_install() {
    echo "�y����������..."
    if [ ! -d "$TARGET_DIR" ]; then
        mkdir -p "$TARGET_DIR"
        echo "������������: $TARGET_DIR"
    else
        echo "���������ߑ��݁C����᳏d������"
    fi
    
    local download_url
    local download_path="$TARGET_DIR/$DOWNLOAD_FILENAME"
    
    if [ "$USE_BETA" = true ]; then
        download_url="$GH_DOWNLOAD_URL"
    else
        download_url="$GH_DOWNLOAD_URL/$DOWNLOAD_FILENAME"
    fi
    
    echo "����: $download_url"
    
    local max_retries=3
    local retry_count=0
    local wait_time=5
    
    while [ $retry_count -lt $max_retries ]; do
        if curl -fL --connect-timeout 15 --retry 3 --retry-delay 5 -S "$download_url" -o "$download_path" -#; then
            echo ""
            if [ -f "$download_path" ] && [ -s "$download_path" ]; then
                break
            fi
        fi
        
        echo "���������C�����d��..."
        rm -f "$download_path"
        retry_count=$((retry_count + 1))
        
        if [ $retry_count -lt $max_retries ]; then
            echo "���� $wait_time �b�@�d�� ($retry_count/$max_retries)..."
            sleep $wait_time
            wait_time=$((wait_time + 5))
        else
            handle_error 1 "��������: $download_url"
        fi
    done
    
    echo "��������..."
    
    local temp_dir="$TARGET_DIR/temp_extract"
    mkdir -p "$temp_dir"
    
    if ! unzip -o "$download_path" -d "$temp_dir"; then
        rm -f "$download_path"
        rm -rf "$temp_dir"
        handle_error 1 "��������: $download_path"
    fi
    
    if [ "$USE_BETA" = true ]; then
        echo "���������ŕ�������..."
        
        local beta_build_path="target/${SOFTWARE_NAME}-${FILE_SUFFIX}/release"
        
        if [ -d "$temp_dir/$beta_build_path" ]; then
            echo "�Q����������������: $beta_build_path"
            
            if [ -f "$temp_dir/$beta_build_path/$SOFTWARE_NAME" ]; then
                echo "���������s��������������"
                mv -f "$temp_dir/$beta_build_path/$SOFTWARE_NAME" "$TARGET_DIR/"
                chmod +x "$TARGET_DIR/$SOFTWARE_NAME"
            else
                echo "�x��: �������H�a�����Q�������s����"
            fi
            
            echo "�������������ŕ�������������"
            find "$temp_dir/$beta_build_path" -mindepth 1 -maxdepth 1 -type f -not -name "$SOFTWARE_NAME" -exec mv -f {} "$TARGET_DIR/" \;
            
            rm -rf "$temp_dir/$beta_build_path"
        else
            echo "�x��: ���Q�������I�����Ŗ�������: $beta_build_path"
            find_result=$(find "$temp_dir" -name "$SOFTWARE_NAME" -type f | head -n 1)
            if [ -n "$find_result" ]; then
                echo "�Q���֑�����s����: $find_result"
                mv -f "$find_result" "$TARGET_DIR/"
                chmod +x "$TARGET_DIR/$SOFTWARE_NAME"
            else
                rm -f "$download_path"
                rm -rf "$temp_dir"
                handle_error 1 "���Q�������s�����C�����ň�������"
            fi
        fi
    else
        echo "��������ŕ�������..."
        cp -rf "$temp_dir"/* "$TARGET_DIR/"
        if [ -f "$TARGET_DIR/$SOFTWARE_NAME" ]; then
            chmod +x "$TARGET_DIR/$SOFTWARE_NAME"
        fi
    fi
    
    rm -f "$download_path"
    rm -rf "$temp_dir"
    
    if [ ! -f "$TARGET_DIR/$SOFTWARE_NAME" ]; then
        handle_error 1 "��������: ���Q�������s���� $TARGET_DIR/$SOFTWARE_NAME"
    fi
    
    if [ "$USE_BETA" = true ]; then
        LATEST_VERSION="beta-$(date +%Y%m%d)"
        echo "$LATEST_VERSION" > "$VERSION_FILE"
        echo "�����ŐM���ߕۑ�: $LATEST_VERSION"
    elif [ -n "$LATEST_VERSION" ]; then
        echo "$LATEST_VERSION" > "$VERSION_FILE"
        echo "����ŐM���ߕۑ�: $LATEST_VERSION"
    fi
    
    echo "���������I"
    echo "===================="
    echo "$SOFTWARE_NAME �߈�����: $TARGET_DIR"
    if [ "$USE_BETA" = true ]; then
        echo "�߈��������� (����: $(date +%Y-%m-%d))"
    else
        echo "�߈��������: $LATEST_VERSION"
    fi
    echo "�������s: $TARGET_DIR/$SOFTWARE_NAME �����s����"
    echo "===================="
}

open_port() {
    echo "�������������[�� $PORT..."
    
    if [ "$EUID" -ne 0 ] && [ "$IS_TERMUX" = false ]; then
        echo "����: ���v�g�proot�����������[���C���O��root�p��"
        read -p "���������g�psudo�����[���H(y/N): " use_sudo
        if [[ ! "$use_sudo" =~ ^[Yy]$ ]]; then
            echo "�����[�������C�����������[�� $PORT"
            return
        fi
        HAS_SUDO=true
    else
        HAS_SUDO=false
    fi
    
    if [ "$IS_TERMUX" = true ]; then
        echo "Termux�����َ����������[���C���p�������g�p $PORT �[��"
        return
    fi
    
    if command -v ufw >/dev/null 2>&1; then
        echo "������ufw����"
        if [ "$HAS_SUDO" = true ]; then
            sudo ufw allow $PORT/tcp && \
            sudo ufw reload && \
            echo "�ߐ��������[�� $PORT (ufw)"
        else
            ufw allow $PORT/tcp && \
            ufw reload && \
            echo "�ߐ��������[�� $PORT (ufw)"
        fi
    elif command -v firewall-cmd >/dev/null 2>&1; then
        echo "������firewalld����"
        if [ "$HAS_SUDO" = true ]; then
            sudo firewall-cmd --zone=public --add-port=$PORT/tcp --permanent && \
            sudo firewall-cmd --reload && \
            echo "�ߐ��������[�� $PORT (firewalld)"
        else
            firewall-cmd --zone=public --add-port=$PORT/tcp --permanent && \
            firewall-cmd --reload && \
            echo "�ߐ��������[�� $PORT (firewalld)"
        fi
    elif command -v iptables >/dev/null 2>&1; then
        echo "�g�piptables�����[��"
        if [ "$HAS_SUDO" = true ]; then
            sudo iptables -A INPUT -p tcp --dport $PORT -j ACCEPT && \
            echo "�ߎg�piptables�����[�� $PORT"
            echo "���ӁF�����u�\�s��݌n���d���@�ۗ��C���l�������Y�����n�������r�{��"
        else
            iptables -A INPUT -p tcp --dport $PORT -j ACCEPT && \
            echo "�ߎg�piptables�����[�� $PORT"
            echo "���ӁF�����u�\�s��݌n���d���@�ۗ��C���l�������Y�����n�������r�{��"
        fi
    else
        echo "���������x���I�h���������C�����������[�� $PORT"
    fi
    
    if command -v getenforce >/dev/null 2>&1; then
        selinux_status=$(getenforce)
        if [ "$selinux_status" = "Enforcing" ] || [ "$selinux_status" = "Permissive" ]; then
            echo "������SELinux�������������C�����z�uSELinux����..."
            if command -v semanage >/dev/null 2>&1; then
                if [ "$HAS_SUDO" = true ]; then
                    sudo semanage port -a -t http_port_t -p tcp $PORT || \
                    echo "SELinux�[���z�u�������C�\���v�����z�u"
                else
                    semanage port -a -t http_port_t -p tcp $PORT || \
                    echo "SELinux�[���z�u�������C�\���v�����z�u"
                fi
            else
                echo "���Q��semanage���߁C�ٖ@�����z�uSELinux����"
                echo "�@�������������C�������z�uSELinux���������g�p�[�� $PORT"
            fi
        fi
    fi
    
    echo "�[�� $PORT ������"
}

run_program() {
    if [ -f "$TARGET_DIR/$SOFTWARE_NAME" ]; then
        read -p "���ۗ������s $SOFTWARE_NAME�H(y/N): " run_now
        if [[ "$run_now" =~ ^[Yy]$ ]]; then
            echo "�������� $SOFTWARE_NAME..."
            cd "$TARGET_DIR" && ./"$SOFTWARE_NAME"
        else
            echo "�����c�@�������s: $TARGET_DIR/$SOFTWARE_NAME �����s����"
        fi
    else
        echo "�x��: ���Q�������s���� $TARGET_DIR/$SOFTWARE_NAME"
    fi
}

main() {
    echo "���n���� $SOFTWARE_NAME..."
    detect_system
    install_dependencies
    select_version
    if ! check_version; then
        echo "�ߎ������/�X�V����"
        exit 0
    fi
    setup_download_url
    download_and_install
    open_port
    run_program
}

main