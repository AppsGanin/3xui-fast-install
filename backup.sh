#!/usr/bin/env bash
# =============================================================================
# backup.sh — создаёт бекап 3x-ui с удалённого сервера и сохраняет локально
#
# Использование:
#   bash backup.sh <IP>
#   bash backup.sh <IP> -i ~/.ssh/id_rsa
#   SSH_PORT=2222 bash backup.sh <IP>
#   BACKUP_DIR=~/backups bash backup.sh <IP>
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()     { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

SERVER_IP="${1:-}"
[[ -z "$SERVER_IP" ]] && die "Укажите IP: bash backup.sh <IP>"
shift

SSH_PORT="${SSH_PORT:-22}"
SSH_USER="${SSH_USER:-root}"
SSH_EXTRA=(${@+"${@}"})
_KNOWN_HOSTS="${HOME}/.ssh/known_hosts"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$_KNOWN_HOSTS" -o ConnectTimeout=10 -p "$SSH_PORT" ${SSH_EXTRA[@]+"${SSH_EXTRA[@]}"})
SCP_OPTS=(-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$_KNOWN_HOSTS" -o ConnectTimeout=10 -P "$SSH_PORT" ${SSH_EXTRA[@]+"${SSH_EXTRA[@]}"});

BACKUP_DIR="${BACKUP_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="backup_${SERVER_IP}_${TIMESTAMP}.tar.gz"
REMOTE_TMP="/tmp/3xui_backup_${TIMESTAMP}.tar.gz"

mkdir -p "$BACKUP_DIR"

XUI_DIR="${XUI_DIR:-/root}"

info "Создаю архив на сервере ${SERVER_IP}..."
ssh "${SSH_OPTS[@]}" "${SSH_USER}@${SERVER_IP}" \
    XUI_DIR="${XUI_DIR}" REMOTE_TMP="${REMOTE_TMP}" bash <<'REMOTE'
set -euo pipefail

COMPOSE_FILE="${XUI_DIR}/docker-compose.yml"

# Останавливаем контейнер чтобы БД не изменилась во время копирования
if [[ -f "$COMPOSE_FILE" ]]; then
    docker compose -f "$COMPOSE_FILE" stop 2>/dev/null || true
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# БД и сертификаты 3x-ui
[[ -d "${XUI_DIR}/db"   ]] && cp -a "${XUI_DIR}/db"   "$TMP_DIR/"
[[ -d "${XUI_DIR}/cert" ]] && cp -a "${XUI_DIR}/cert" "$TMP_DIR/"

# docker-compose.yml
[[ -f "$COMPOSE_FILE" ]] && cp "$COMPOSE_FILE" "$TMP_DIR/"

# Caddy selfsteal — Caddyfile, .env, docker-compose.yml, статический сайт
if [[ -d /opt/caddy ]]; then
    mkdir -p "$TMP_DIR/caddy"
    rsync -a --exclude='logs/' /opt/caddy/ "$TMP_DIR/caddy/"
fi

# Файл с доступами
[[ -f /root/3xui-credentials.txt ]] && cp /root/3xui-credentials.txt "$TMP_DIR/"

tar -czf "$REMOTE_TMP" -C "$TMP_DIR" .

# Стартуем обратно
if [[ -f "$COMPOSE_FILE" ]]; then
    docker compose -f "$COMPOSE_FILE" up -d 2>/dev/null || true
fi
REMOTE

info "Скачиваю архив..."
scp "${SCP_OPTS[@]}" "${SSH_USER}@${SERVER_IP}:${REMOTE_TMP}" "${BACKUP_DIR}/${BACKUP_NAME}"

info "Удаляю временный файл на сервере..."
ssh "${SSH_OPTS[@]}" "${SSH_USER}@${SERVER_IP}" "rm -f ${REMOTE_TMP}"

echo
success "Бекап сохранён: ${BACKUP_DIR}/${BACKUP_NAME}"
ls -lh "${BACKUP_DIR}/${BACKUP_NAME}"
