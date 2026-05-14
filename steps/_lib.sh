#!/usr/bin/env bash
# Общие функции и переменные для шагов steps/
# Подключается автоматически при запуске шага напрямую.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Пишет в терминал (fd 3, если setup.sh перенаправил stdout в лог) И в лог.
# При прямом запуске шага fd 3 не открыт — пишет в stdout.
_print() {
    if { >&3; } 2>/dev/null; then
        echo -e "$*" >&3   # → терминал
        echo -e "$*"       # → лог (stdout уже перенаправлен)
    else
        echo -e "$*"
    fi
}

info()    { _print "${CYAN}[INFO]${NC}  $*"; }
success() { _print "${GREEN}[OK]${NC}    $*"; }
warn()    { _print "${YELLOW}[WARN]${NC}  $*"; }
die()     {
    if { >&3; } 2>/dev/null; then
        echo -e "${RED}[ERROR]${NC} $*" >&3
        echo -e "[ERROR] $*"
    else
        echo -e "${RED}[ERROR]${NC} $*" >&2
    fi
    exit 1
}

[[ $EUID -ne 0 ]] && die "Запустите скрипт от root: sudo bash $0"

export CERT_DIR="${CERT_DIR:-${XUI_DIR}/cert/ssl}"
export WARP_PROXY_PORT="${WARP_PROXY_PORT:-40000}"
export OPERA_PROXY_PORT="${OPERA_PROXY_PORT:-40001}"
export TOR_PORT="${TOR_PORT:-40002}"
export XRAY_API_PORT="${XRAY_API_PORT:-62789}"
export HY2_PORT="${HY2_PORT:-63000}"
export OPERA_COUNTRY="${OPERA_COUNTRY:-EU}"
export XUI_DIR="${XUI_DIR:-/root}"
export LOGFILE="${LOGFILE:-/root/3xui-install.log}"

export PANEL_PORT="${PANEL_PORT:-60000}"
export PANEL_USER="${PANEL_USER:-admin}"
export SUB_PORT="${SUB_PORT:-60001}"
export SUB_TITLE="${SUB_TITLE:-🏡 Home}"
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
