#!/usr/bin/env bash
# Общие функции и переменные для шагов steps/
# Подключается автоматически при запуске шага напрямую.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Пишет прогресс в filtered log без ANSI-кодов.
# При прямом запуске шага также печатает в терминал.
_print() {
    local line plain_line
    line="$*"
    plain_line=$(printf '%s' "$line" | sed -r 's/\x1b\[[0-9;]*m//g')
    if [[ -n "${LOGFILE:-}" ]]; then
        printf '%s\n' "$plain_line" >>"$LOGFILE"
    fi
    if { true >&3; } 2>/dev/null; then
        echo -e "$line" >&3
    elif [[ -z "${FULL_LOGFILE:-}" ]]; then
        echo -e "$line"
    fi
}

info()    { _print "${CYAN}[INFO]${NC}  $*"; }
success() { _print "${GREEN}[OK]${NC}    $*"; }
warn()    { _print "${YELLOW}[WARN]${NC}  $*"; }
die()     {
    local line plain_line
    line="${RED}[ERROR]${NC} $*"
    plain_line=$(printf '%s' "$line" | sed -r 's/\x1b\[[0-9;]*m//g')
    if [[ -n "${LOGFILE:-}" ]]; then
        printf '%s\n' "$plain_line" >>"$LOGFILE"
    fi
    if { true >&3; } 2>/dev/null; then
        echo -e "$line" >&3
    elif [[ -z "${FULL_LOGFILE:-}" ]]; then
        echo -e "$line" >&2
    fi
    exit 1
}

command_exists() {
    command -v "$1" &>/dev/null
}

install_packages() {
    if command_exists apt-get; then
        apt-get update -qq || true
        apt-get install -y --no-install-recommends "$@"
    elif command_exists yum; then
        yum install -y "$@"
    else
        die "Пакетный менеджер не найден. Нужен apt-get или yum."
    fi
}

port_listening() {
    local port="$1"
    ss -tlnp 2>/dev/null | grep -q ":${port}"
}

wait_for_tcp_port() {
    local port="$1"
    local timeout="${2:-30}"
    local i

    for i in $(seq 1 "$timeout"); do
        port_listening "$port" && return 0
        sleep 1
    done
    return 1
}

sql_escape() {
    printf '%s' "${1//\'/\'\'}"
}

[[ $EUID -ne 0 ]] && die "Запустите скрипт от root: sudo bash $0"

export WARP_PROXY_PORT="${WARP_PROXY_PORT:-40000}"
export OPERA_PROXY_PORT="${OPERA_PROXY_PORT:-40001}"
export TOR_PORT="${TOR_PORT:-40002}"
export XRAY_API_PORT="${XRAY_API_PORT:-62789}"
export HY2_PORT="${HY2_PORT:-63000}"
export OPERA_COUNTRY="${OPERA_COUNTRY:-EU}"
export XUI_DIR="${XUI_DIR:-/root}"
export CERT_DIR="${CERT_DIR:-${XUI_DIR}/cert/ssl}"
export VLESS_PORT="${VLESS_PORT:-443}"
export LOGFILE="${LOGFILE:-/root/3xui-install.log}"

export PANEL_PORT="${PANEL_PORT:-60000}"
export PANEL_USER="${PANEL_USER:-admin}"
export SUB_PORT="${SUB_PORT:-60001}"
export SUB_TITLE="${SUB_TITLE:-}"
export SUB_PATH="${SUB_PATH:-/subs/}"

if [[ -z "${PANEL_PASS:-}" ]]; then
    PANEL_PASS=$(openssl rand -base64 36 | tr -dc 'a-zA-Z0-9' | head -c 18 || true)
    [[ -n "$PANEL_PASS" ]] || die "Не удалось сгенерировать пароль панели."
    export PANEL_PASS
fi

if [[ -z "${PANEL_PATH:-}" ]]; then
    PANEL_PATH=$(tr -dc 'a-z0-9' </dev/urandom | head -c 8 || true)
    [[ -n "$PANEL_PATH" ]] || die "Не удалось сгенерировать путь панели."
    export PANEL_PATH
fi

if [[ -z "${DOMAIN:-}" ]]; then
    read -rp "Введите домен для selfsteal (например vpn.example.com): " DOMAIN
    [[ -z "$DOMAIN" ]] && die "Домен не может быть пустым."
fi
export DOMAIN

# По умолчанию название подписки делаем доменом, если оно не задано явно.
export SUB_TITLE="${SUB_TITLE:-${DOMAIN}}"
