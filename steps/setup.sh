#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Лог ─────────────────────────────────────────────────────────────────────
# Весь stdout/stderr команд уходит в full log-файл.
# info/success/warn/die пишут только в filtered log-файл.
LOGFILE=/root/3xui-install.log
FULL_LOGFILE=/root/3xui-install-full.log
export LOGFILE FULL_LOGFILE
mkdir -p "$(dirname "$LOGFILE")"
mkdir -p "$(dirname "$FULL_LOGFILE")"
exec 3>&1 >>"$FULL_LOGFILE" 2>&1
printf "%s\n" "[$(date '+%Y-%m-%d %H:%M:%S')] ══════ Начало установки ══════" >>"$FULL_LOGFILE"
printf "%s\n" "[INFO]  Setup стартовал. Полный лог: $FULL_LOGFILE" >>"$LOGFILE"
printf "%s\n" "[INFO]  Setup стартовал. Полный лог: $FULL_LOGFILE" >&3

# shellcheck source=steps/_lib.sh
source "$SCRIPT_DIR/_lib.sh"

info "Полный лог установки: $FULL_LOGFILE"
trap 'printf "[$(date +%T)] ABORT\n" >> "$FULL_LOGFILE"; printf "[ERROR] Установка прервана. Подробности: %s\n" "$FULL_LOGFILE" >> "$LOGFILE"; printf "[ERROR] Установка прервана. Подробности: %s\n" "$FULL_LOGFILE" >&3; exit 1' ERR

# ─── Запуск шагов как подпроцессов ───────────────────────────────────────────
_run_step() {
    local label="$1" script="$2"
    local line
    line="[$(date '+%H:%M:%S')] ── $label"
    printf "\n%s\n" "$line"
    printf "\n%s\n" "$line" >>"$LOGFILE"
    printf "\n%s\n" "$line" >&3
    bash "$script"
}

_run_step "Prereqs"     "$SCRIPT_DIR/prereqs.sh"
_run_step "BBR"         "$SCRIPT_DIR/bbr.sh"
_run_step "UFW"         "$SCRIPT_DIR/ufw.sh"
_run_step "WARP"        "$SCRIPT_DIR/warp.sh"
_run_step "Opera Proxy" "$SCRIPT_DIR/opera-proxy.sh"
_run_step "Tor"         "$SCRIPT_DIR/tor.sh"
_run_step "Docker"      "$SCRIPT_DIR/docker.sh"
_run_step "fail2ban"    "$SCRIPT_DIR/fail2ban.sh"
_run_step "Selfsteal"   "$SCRIPT_DIR/selfsteal.sh"
_run_step "3x-ui"       "$SCRIPT_DIR/xui.sh"

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
printf "%s\n" "--- SETUP DONE ---" >>"$LOGFILE"
printf "%s\n" "--- SETUP DONE ---" >&3
