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

get_linux_id() {
    if [[ -r /etc/os-release ]]; then
        . /etc/os-release
        printf '%s' "${ID:-}"
    fi
}

default_dns_check_domain() {
    case "$(get_linux_id)" in
        ubuntu) printf '%s' "archive.ubuntu.com" ;;
        debian) printf '%s' "deb.debian.org" ;;
        *)      printf '%s' "deb.debian.org" ;;
    esac
}

dns_resolve_ipv4s() {
    local host="$1"
    getent ahosts "$host" 2>/dev/null \
        | awk '{print $1}' \
        | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' \
        | sort -u || true
}

doh_resolve_ipv4s() {
    local host="$1" json

    if command_exists curl; then
        json=$(curl -fsSL --retry 2 --connect-timeout 5 --max-time 15 \
            --resolve cloudflare-dns.com:443:1.1.1.1 \
            -H 'accept: application/dns-json' \
            "https://cloudflare-dns.com/dns-query?name=${host}&type=A" 2>/dev/null || true)
    elif command_exists python3; then
        json=$(python3 - "$host" <<'PY' 2>/dev/null || true
import json, sys, urllib.request
import ssl
import urllib.parse
host = sys.argv[1]
req = urllib.request.Request(
    f"https://1.1.1.1/dns-query?name={urllib.parse.quote(host)}&type=A",
    headers={
        "accept": "application/dns-json",
        "Host": "cloudflare-dns.com",
    },
)
try:
    ctx = ssl._create_unverified_context()
    with urllib.request.urlopen(req, context=ctx, timeout=15) as resp:
        sys.stdout.write(resp.read().decode())
except Exception:
    pass
PY
)
    else
        json=""
    fi

    printf '%s\n' "$json" \
        | grep -oE '"data":"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"' \
        | sed -E 's/^"data":"//; s/"$//' \
        | sort -u || true
}

dns_update_hosts_entry() {
    local host="$1" ip="$2"
    [[ -n "$host" && -n "$ip" ]] || return 1

    if grep -Eq "^[[:space:]]*${ip//./\\.}[[:space:]]+${host}([[:space:]]|$)" /etc/hosts 2>/dev/null; then
        return 0
    fi

    printf '%s %s\n' "$ip" "$host" >> /etc/hosts
}

port_is_listening() {
    local port="$1"
    ss -H -lntp 2>/dev/null | awk -v port=":${port}" '$4 ~ port { found=1 } END { exit(found ? 0 : 1) }'
}

port_listeners() {
    local port="$1"
    ss -H -lntp 2>/dev/null | awk -v port=":${port}" '$4 ~ port { print }' || true
}

dns_resolv_conf_dump() {
    if [[ -L /etc/resolv.conf ]]; then
        echo "symlink -> $(readlink /etc/resolv.conf 2>/dev/null || echo '(unreadable)')"
    fi
    if [[ -r /etc/resolv.conf ]]; then
        sed 's/^/  /' /etc/resolv.conf
    else
        echo "  (не удалось прочитать /etc/resolv.conf)"
    fi
}

dns_internet_check() {
    local host port
    for target in \
        "1.1.1.1:443" \
        "1.0.0.1:443" \
        "8.8.8.8:53" \
        "9.9.9.9:53"
    do
        host="${target%:*}"
        port="${target#*:}"
        if timeout 4 bash -c ":</dev/tcp/${host}/${port}" &>/dev/null; then
            printf '%s' "$target"
            return 0
        fi
    done
    return 1
}

dns_restore_resolv_conf() {
    local backup="/etc/resolv.conf.codex.bak"
    if [[ -e /etc/resolv.conf && ! -e "$backup" ]]; then
        cp -a /etc/resolv.conf "$backup" 2>/dev/null || true
    fi

    if command_exists systemctl && systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        systemctl stop systemd-resolved 2>/dev/null || true
    fi

    rm -f /etc/resolv.conf
    cat > /etc/resolv.conf <<'EOF'
# Restored by 3x-ui installer after DNS failure
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 9.9.9.9
options timeout:2 attempts:2 rotate
EOF
    chmod 644 /etc/resolv.conf 2>/dev/null || true
}

dns_diagnostics() {
    local context="$1" domain="$2" expected="${3:-}" found="${4:-}"

    warn "[DEBUG] ${context}: dig +short A ${domain}"
    if command_exists dig; then
        dig +short A "$domain" 2>/dev/null | sed 's/^/[DEBUG]   /' || true
    else
        warn "[DEBUG]   dig не установлен"
    fi
    warn "[DEBUG] ${context}: getent ahosts ${domain}"
    getent ahosts "$domain" 2>/dev/null | sed 's/^/[DEBUG]   /' || true
    warn "[DEBUG] ${context}: expected IP: ${expected:-'(не задан)'}"
    warn "[DEBUG] ${context}: detected IP: ${found:-'(не найден)'}"
    warn "[DEBUG] ${context}: /etc/resolv.conf"
    dns_resolv_conf_dump | sed 's/^/[DEBUG]   /'
}

ensure_dns() {
    local context="${1:-network operation}"
    local domain="${2:-${DNS_CHECK_DOMAIN:-deb.debian.org}}"
    local internet_target resolved

    if ! internet_target=$(dns_internet_check); then
        dns_diagnostics "$context" "$domain" "" ""
        die "${context}: нет доступности интернета по IP. Сначала проверьте маршрутизацию/файрвол/NAT."
    fi

    resolved=$(dns_resolve_ipv4s "$domain")
    if [[ -n "$resolved" ]]; then
        return 0
    fi

    info "${context}: интернет по IP доступен (${internet_target}), но DNS не резолвит ${domain}. Пытаюсь восстановить /etc/resolv.conf..."
    dns_restore_resolv_conf

    resolved=$(dns_resolve_ipv4s "$domain")
    if [[ -n "$resolved" ]]; then
        success "${context}: DNS восстановлен для ${domain} (${resolved})."
        return 0
    fi

    info "${context}: пробую DoH fallback для ${domain}..."
    resolved=$(doh_resolve_ipv4s "$domain")
    if [[ -n "$resolved" ]]; then
        dns_update_hosts_entry "$domain" "$(printf '%s\n' "$resolved" | head -1)" || true
        resolved=$(dns_resolve_ipv4s "$domain")
        if [[ -n "$resolved" ]]; then
            success "${context}: DNS восстановлен через DoH для ${domain} (${resolved})."
            return 0
        fi
    fi

    dns_diagnostics "$context" "$domain" "" "$resolved"
    die "${context}: DNS остаётся нерабочим после восстановления /etc/resolv.conf."
}

truthy() {
    case "${1:-}" in
        1|true|TRUE|yes|YES|on|ON|y|Y|low|LOW|light|LIGHT|lite|LITE)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

spinner_run() {
    local label="$1"
    shift

    # Если fd 3 не подключён к терминалу, просто запускаем команду без анимации.
    if ! { true >&3; } 2>/dev/null; then
        "$@"
        return $?
    fi

    local frames=('.  ' '.. ' '...') frame_index=0 ticker_pid status

    (
        while :; do
            frame_index=$(((frame_index + 1) % ${#frames[@]}))
            printf '\r\033[K%s %s' "$label" "${frames[$frame_index]}" >&3
            sleep 1
        done
    ) &
    ticker_pid=$!

    printf '\r\033[K%s %s' "$label" "${frames[0]}" >&3
    "$@"
    status=$?

    kill "$ticker_pid" 2>/dev/null || true
    wait "$ticker_pid" 2>/dev/null || true

    if [[ $status -eq 0 ]]; then
        printf '\r\033[K%s %s\n' "$label" "done" >&3
    else
        printf '\r\033[K%s %s\n' "$label" "failed" >&3
    fi

    return "$status"
}

install_packages() {
    ensure_dns "Установка пакетов" "${DNS_CHECK_DOMAIN:-$(default_dns_check_domain)}"
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

export WARP_PROXY_PORT="40000"
export OPERA_PROXY_PORT="40001"
export TOR_PORT="40002"
export XRAY_API_PORT="62789"
export HY2_PORT="${HY2_PORT:-63000}"
export OPERA_REGION="${OPERA_REGION:-EU}"
export XUI_DIR="/root"
export CERT_DIR="${XUI_DIR}/cert/ssl"
export VLESS_PORT="${VLESS_PORT:-443}"
export TRAFFIC_RESET="${TRAFFIC_RESET:-monthly}"
export LOGFILE="${XUI_DIR}/3xui-install.log"
export XUI_VERSION="3.2.6"
export LOW_POWER_MODE="${LOW_POWER_MODE:-0}"

if truthy "$LOW_POWER_MODE"; then
    export XUI_ENABLE_FAIL2BAN="${XUI_ENABLE_FAIL2BAN:-false}"
    export XUI_LOG_LEVEL="${XUI_LOG_LEVEL:-warning}"
    export XUI_CPUS_LIMIT="${XUI_CPUS_LIMIT:-0.5}"
else
    export XUI_ENABLE_FAIL2BAN="${XUI_ENABLE_FAIL2BAN:-true}"
    export XUI_LOG_LEVEL="${XUI_LOG_LEVEL:-info}"
    export XUI_CPUS_LIMIT="${XUI_CPUS_LIMIT:-}"
fi

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
    PANEL_PASS=$(random_alnum 18)
    export PANEL_PASS
fi

if [[ -z "${PANEL_PATH:-}" ]]; then
    PANEL_PATH=$(random_alnum 8 | tr '[:upper:]' '[:lower:]')
fi
# Нормализуем: путь должен начинаться и заканчиваться на /
[[ "$PANEL_PATH" != /* ]]  && PANEL_PATH="/${PANEL_PATH}"
[[ "$PANEL_PATH" != */ ]]  && PANEL_PATH="${PANEL_PATH}/"
export PANEL_PATH

# Нормализуем SUB_PATH аналогично
[[ "$SUB_PATH" != /* ]]    && SUB_PATH="/${SUB_PATH}"
[[ "$SUB_PATH" != */ ]]    && SUB_PATH="${SUB_PATH}/"
export SUB_PATH

if [[ -z "$CLIENT_EMAIL" ]]; then
    CLIENT_EMAIL="$(random_alnum 10)"
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
    HY2_PORT VLESS_PORT PANEL_PORT SUB_PORT
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
