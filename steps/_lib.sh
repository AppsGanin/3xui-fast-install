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

validate_port() {
    local name="$1" port="$2"
    [[ "$port" =~ ^[0-9]+$ ]] || die "${name} должен быть числом от 1 до 65535, сейчас: ${port}"
    (( port >= 1 && port <= 65535 )) || die "${name} должен быть числом от 1 до 65535, сейчас: ${port}"
}

sql_escape() {
    printf '%s' "${1//\'/\'\'}"
}

random_alnum() {
    local length="$1" value=""
    value=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c "$length" || true)
    [[ -n "$value" ]] || die "Не удалось сгенерировать случайную строку."
    printf '%s' "$value"
}

random_uuid_v4() {
    local hex
    hex=$(openssl rand -hex 16 || true)
    [[ ${#hex} -eq 32 ]] || die "Не удалось сгенерировать UUID клиента."
    printf '%s-%s-4%s-%s%s-%s' \
        "${hex:0:8}" "${hex:8:4}" "${hex:13:3}" \
        "$(printf '%x' "$(( (0x${hex:16:1} & 0x3) | 0x8 ))")" \
        "${hex:17:3}" "${hex:20:12}"
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

export CLIENT_EMAIL="${CLIENT_EMAIL:-}"
export CLIENT_UUID="${CLIENT_UUID:-}"
export CLIENT_SUB_ID="${CLIENT_SUB_ID:-}"
export CLIENT_HY2_AUTH="${CLIENT_HY2_AUTH:-}"

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

if [[ -z "$CLIENT_EMAIL" ]]; then
    CLIENT_EMAIL="client-$(random_alnum 6)"
    export CLIENT_EMAIL
fi

if [[ -z "$CLIENT_UUID" ]]; then
    CLIENT_UUID=$(random_uuid_v4)
    export CLIENT_UUID
fi

if [[ -z "$CLIENT_SUB_ID" ]]; then
    CLIENT_SUB_ID=$(random_alnum 16 | tr '[:upper:]' '[:lower:]')
    export CLIENT_SUB_ID
fi

if [[ -z "$CLIENT_HY2_AUTH" ]]; then
    CLIENT_HY2_AUTH=$(random_alnum 24)
    export CLIENT_HY2_AUTH
fi

[[ "$CLIENT_EMAIL" =~ ^[A-Za-z0-9._@-]+$ ]] || die "CLIENT_EMAIL может содержать только латиницу, цифры, точку, подчёркивание, @ и дефис."
[[ "$CLIENT_UUID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || die "CLIENT_UUID должен быть UUID."
[[ "$CLIENT_SUB_ID" =~ ^[A-Za-z0-9]+$ ]] || die "CLIENT_SUB_ID может содержать только латиницу и цифры."
[[ "$CLIENT_HY2_AUTH" =~ ^[A-Za-z0-9._@=-]+$ ]] || die "CLIENT_HY2_AUTH может содержать только латиницу, цифры, точку, подчёркивание, @, = и дефис."

for _port_var in \
    WARP_PROXY_PORT OPERA_PROXY_PORT TOR_PORT XRAY_API_PORT HY2_PORT \
    VLESS_PORT PANEL_PORT SUB_PORT
do
    validate_port "$_port_var" "${!_port_var}"
done
unset _port_var

if [[ -z "${DOMAIN:-}" ]]; then
    read -rp "Введите домен для selfsteal (например vpn.example.com): " DOMAIN
    [[ -z "$DOMAIN" ]] && die "Домен не может быть пустым."
fi
export DOMAIN

# По умолчанию название подписки делаем доменом, если оно не задано явно.
export SUB_TITLE="${SUB_TITLE:-${DOMAIN}}"
