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

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()     { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ─── Аргументы ────────────────────────────────────────────────────────────────
SERVER_IP="${1:-}"
[[ -z "$SERVER_IP" ]] && die "Укажите IP сервера: bash deploy.sh <IP>"
shift

SSH_PORT="${SSH_PORT:-22}"
SSH_USER="${SSH_USER:-root}"
REMOTE_DIR="${REMOTE_DIR:-/root/3xui-setup}"
SSH_EXTRA=(${@+"${@}"})

# Отпечаток сохраняется в ~/.ssh/known_hosts только для этого хоста.
# При первом подключении принимается автоматически; при повторных — проверяется.
_KNOWN_HOSTS="${HOME}/.ssh/known_hosts"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$_KNOWN_HOSTS" -o ConnectTimeout=5 -p "$SSH_PORT" ${SSH_EXTRA[@]+"${SSH_EXTRA[@]}"})
SCP_OPTS=(-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$_KNOWN_HOSTS" -o ConnectTimeout=5 -P "$SSH_PORT" ${SSH_EXTRA[@]+"${SSH_EXTRA[@]}"})

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/steps"

# ─── Домен ────────────────────────────────────────────────────────────────────
if [[ -z "${DOMAIN:-}" ]]; then
    read -rp "Введите домен (например vpn.example.com): " DOMAIN
    [[ -z "$DOMAIN" ]] && die "Домен не может быть пустым."
fi

# ─── Ожидание SSH ─────────────────────────────────────────────────────────────
info "Ожидаю SSH ${SSH_USER}@${SERVER_IP}:${SSH_PORT}..."
WAIT_MAX=300; WAIT_STEP=5; elapsed=0
while true; do
    ssh "${SSH_OPTS[@]}" "${SSH_USER}@${SERVER_IP}" 'exit 0' 2>/dev/null && break
    (( elapsed >= WAIT_MAX )) && die "SSH недоступен после ${WAIT_MAX}с."
    warn "Нет соединения, повтор через ${WAIT_STEP}с... (${elapsed}/${WAIT_MAX}с)"
    sleep "$WAIT_STEP"
    (( elapsed += WAIT_STEP ))
done
success "SSH доступен."

# ─── Копирование ──────────────────────────────────────────────────────────────
echo
info "Копирую файлы → ${REMOTE_DIR}/..."
ssh "${SSH_OPTS[@]}" "${SSH_USER}@${SERVER_IP}" "mkdir -p ${REMOTE_DIR}"
scp "${SCP_OPTS[@]}" "$SCRIPT_DIR"/*.sh "${SSH_USER}@${SERVER_IP}:${REMOTE_DIR}/"
success "Файлы скопированы."

# ─── Запуск ───────────────────────────────────────────────────────────────────
echo
info "Запускаю setup.sh в screen-сессии на сервере (домен: ${DOMAIN})..."
echo

# Устанавливаем screen если нет, запускаем setup в фоне
ssh "${SSH_OPTS[@]}" "${SSH_USER}@${SERVER_IP}" bash <<REMOTE
command -v screen &>/dev/null || apt-get install -y -qq screen
find ${REMOTE_DIR} -name '*.sh' -exec chmod +x {} +
# Завершить предыдущую сессию если есть
screen -S 3xui-setup -X quit 2>/dev/null || true
# Запустить setup в detached screen
screen -dmS 3xui-setup bash -c "DOMAIN='${DOMAIN}' bash ${REMOTE_DIR}/setup.sh; echo \"--- Exit: \$?\" >> /root/3xui-install.log"
REMOTE

info "Setup запущен. Слежу за логом /root/3xui-install.log (Ctrl+C — остановить установку)..."
echo

# При Ctrl+C убиваем screen-сессию на сервере
_cleanup() {
    echo
    warn "Прерывание — останавливаю setup на сервере..."
    ssh "${SSH_OPTS[@]}" "${SSH_USER}@${SERVER_IP}" \
        "screen -S 3xui-setup -X quit 2>/dev/null; pkill -f '${REMOTE_DIR}/setup.sh' 2>/dev/null || true"
    exit 1
}
trap _cleanup INT TERM

# Tail лога до маркера завершения или ошибки
# Показываем только строки прогресса — [INFO]/[OK]/[WARN]/[ERROR] и заголовки шагов
ssh -t "${SSH_OPTS[@]}" "${SSH_USER}@${SERVER_IP}" \
    "for i in \$(seq 1 60); do [ -f /root/3xui-install.log ] && break; sleep 1; done; \
     tail -n 0 -f /root/3xui-install.log | awk '/\[(INFO|OK|WARN|ERROR)\]|══|── |╔|╚/ { print; fflush() } /--- SETUP DONE ---|^\[ERROR\]/ { print; exit }'"

trap - INT TERM

echo
success "Деплой завершён."

# ─── Итог ─────────────────────────────────────────────────────────────────────
echo
info "Доступы:"
ssh "${SSH_OPTS[@]}" "${SSH_USER}@${SERVER_IP}" "cat /root/3xui-credentials.txt 2>/dev/null || echo '(файл доступов не найден)'"
