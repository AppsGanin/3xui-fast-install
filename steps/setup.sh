#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Лог ─────────────────────────────────────────────────────────────────────
# Весь stdout/stderr команд уходит в лог-файл.
# info/success/warn/die пишут на терминал через fd 3.
LOGFILE=/root/3xui-install.log
export LOGFILE
mkdir -p "$(dirname "$LOGFILE")"
exec 3>&1 >>"$LOGFILE" 2>&1
echo "[$(date '+%Y-%m-%d %H:%M:%S')] ══════ Начало установки ══════"

trap 'echo "[$(date +%T)] ABORT" >> "$LOGFILE"; echo -e "\033[0;31m[ERROR]\033[0m Установка прервана. Подробности: $LOGFILE" >&3; exit 1' ERR

# shellcheck source=steps/_lib.sh
source "$SCRIPT_DIR/_lib.sh"

# ─── Проверки ─────────────────────────────────────────────────────────────────
command -v curl &>/dev/null || die "curl не найден."

# ─── Запуск шагов как подпроцессов ───────────────────────────────────────────
_run_step() {
    local label="$1" script="$2"
    echo
    echo "[$(date '+%H:%M:%S')] ── $label"
    bash "$script"
}

_run_step "BBR"         "$SCRIPT_DIR/01_bbr.sh"
_run_step "UFW"         "$SCRIPT_DIR/02_ufw.sh"
_run_step "WARP"        "$SCRIPT_DIR/03a_warp.sh"
_run_step "Opera Proxy" "$SCRIPT_DIR/03b_opera_proxy.sh"
_run_step "Tor"         "$SCRIPT_DIR/03c_tor.sh"
_run_step "Docker"      "$SCRIPT_DIR/04_docker.sh"
_run_step "Selfsteal"   "$SCRIPT_DIR/05_selfsteal.sh"
_run_step "3x-ui"       "$SCRIPT_DIR/06_xui.sh"

# ─── Сохраняем доступы ────────────────────────────────────────────────────────
cat > /root/3xui-credentials.txt <<CREDS
Дата установки : $(date '+%Y-%m-%d %H:%M:%S')
Домен          : ${DOMAIN}
Панель URL     : https://${DOMAIN}:${PANEL_PORT}/${PANEL_PATH}/
Логин          : ${PANEL_USER}
Пароль         : ${PANEL_PASS}
Подписки       : https://${DOMAIN}:${SUB_PORT}${SUB_PATH}
Selfsteal      : https://${DOMAIN}
Сертификат     : ${XUI_DIR}/cert/ssl/fullchain.pem
WARP SOCKS5    : 127.0.0.1:${WARP_PROXY_PORT}
Opera SOCKS5   : 127.0.0.1:${OPERA_PROXY_PORT} (регион: ${OPERA_COUNTRY})
Tor SOCKS5     : 127.0.0.1:${TOR_PORT}
CREDS
chmod 600 /root/3xui-credentials.txt

echo "--- SETUP DONE ---"