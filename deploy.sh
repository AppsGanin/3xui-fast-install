#!/usr/bin/env bash
# =============================================================================
# deploy.sh — заливает steps/ на сервер и запускает setup.sh
#
# Использование:
#   bash deploy.sh <IP>
#   bash deploy.sh <IP> -i ~/.ssh/id_rsa   # явно указать ключ
#   SSH_PORT=2222 bash deploy.sh <IP>       # нестандартный порт
#   DOMAIN=vpn.example.com bash deploy.sh <IP>
# =============================================================================
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/local_lib.sh
source "$SCRIPT_ROOT/scripts/local_lib.sh"

# ─── Аргументы ────────────────────────────────────────────────────────────────
SERVER_IP="${1:-}"
[[ -z "$SERVER_IP" ]] && die "Укажите IP сервера: bash deploy.sh <IP>"
shift

REMOTE_DIR="${REMOTE_DIR:-/root/3xui-setup}"
SSH_EXTRA=("$@")
SSH_CONNECT_TIMEOUT="${SSH_CONNECT_TIMEOUT:-5}"
init_ssh_options

STEPS_DIR="$SCRIPT_ROOT/steps"

# ─── Домен ────────────────────────────────────────────────────────────────────
if [[ -z "${DOMAIN:-}" ]]; then
    read -rp "Введите домен (например vpn.example.com): " DOMAIN
    [[ -z "$DOMAIN" ]] && die "Домен не может быть пустым."
fi

# Локальные переопределения должны попасть в удалённый setup.sh.
REMOTE_ENV_VARS=(
    DOMAIN
    PANEL_PORT PANEL_USER PANEL_PASS PANEL_PATH
    SUB_PORT SUB_PATH SUB_TITLE
    CLIENT_EMAIL CLIENT_UUID CLIENT_SUB_ID CLIENT_HY2_AUTH
    WARP_PROXY_PORT OPERA_PROXY_PORT OPERA_COUNTRY TOR_PORT XRAY_API_PORT HY2_PORT
    XUI_DIR CERT_DIR VLESS_PORT
)
remote_env_assignments=()
for var_name in "${REMOTE_ENV_VARS[@]}"; do
    var_value="${!var_name:-}"
    [[ -z "$var_value" ]] && continue
    remote_env_assignments+=("${var_name}=$(shell_quote "$var_value")")
done
remote_env_prefix="${remote_env_assignments[*]}"

# ─── Ожидание SSH ─────────────────────────────────────────────────────────────
info "Ожидаю SSH ${SSH_USER}@${SERVER_IP}:${SSH_PORT}..."
WAIT_MAX=30; WAIT_STEP=5; elapsed=0
while true; do
    ssh_error=$(ssh "${SSH_OPTS[@]}" "${SSH_USER}@${SERVER_IP}" 'exit 0' 2>&1) && break
    if grep -q "REMOTE HOST IDENTIFICATION HAS CHANGED" <<<"$ssh_error"; then
        die "SSH host key для ${SERVER_IP} изменился. Если сервер переустановлен и это ожидаемо, удалите старый ключ: ssh-keygen -R ${SERVER_IP}"
    fi
    (( elapsed >= WAIT_MAX )) && die "SSH недоступен после ${WAIT_MAX}с."
    warn "Нет соединения, повтор через ${WAIT_STEP}с... (${elapsed}/${WAIT_MAX}с)"
    sleep "$WAIT_STEP"
    (( elapsed += WAIT_STEP ))
done
success "SSH доступен."

# ─── Копирование ──────────────────────────────────────────────────────────────
echo
info "Копирую файлы → ${REMOTE_DIR}/..."
remote_dir_q=$(shell_quote "$REMOTE_DIR")
ssh "${SSH_OPTS[@]}" "${SSH_USER}@${SERVER_IP}" "mkdir -p ${remote_dir_q}"
scp "${SCP_OPTS[@]}" "$STEPS_DIR"/*.sh "${SSH_USER}@${SERVER_IP}:${remote_dir_q}/"
success "Файлы скопированы."

# ─── Запуск ───────────────────────────────────────────────────────────────────
echo
info "Запускаю setup.sh на сервере (домен: ${DOMAIN})..."
echo

info "Прогресс ниже, подробный лог: /root/3xui-install-full.log (Ctrl+C — остановить установку)..."
echo

if ssh -t "${SSH_OPTS[@]}" "${SSH_USER}@${SERVER_IP}" \
    "find ${remote_dir_q} -name '*.sh' -exec chmod +x {} +; \
     rm -f /root/3xui-install.log /root/3xui-install-full.log; \
     touch /root/3xui-install.log; \
     ${remote_env_prefix} bash ${remote_dir_q}/setup.sh"; then
    echo
    success "Деплой завершён."

    # ─── Итог ─────────────────────────────────────────────────────────────────────
    echo
    info "Доступы:"
    ssh "${SSH_OPTS[@]}" "${SSH_USER}@${SERVER_IP}" "cat /root/3xui-credentials.txt 2>/dev/null || echo '(файл доступов не найден)'"
else
    echo
    die "Деплой не завершён. Проверьте лог на сервере: /root/3xui-install-full.log"
fi
