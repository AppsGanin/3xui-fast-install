#!/usr/bin/env bash
# =============================================================================
# restore.sh — восстанавливает 3x-ui из локального бекапа на сервер
#
# Использование:
#   bash restore.sh <IP> <файл_бекапа.tar.gz>
#   bash restore.sh <IP> <файл_бекапа.tar.gz> -i ~/.ssh/id_rsa
#   SSH_PORT=2222 bash restore.sh <IP> <файл_бекапа.tar.gz>
# =============================================================================
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/local_lib.sh
source "$SCRIPT_ROOT/scripts/local_lib.sh"

SERVER_IP="${1:-}"
BACKUP_FILE="${2:-}"
[[ -z "$SERVER_IP"   ]] && die "Укажите IP: bash restore.sh <IP> <backup.tar.gz>"
[[ -z "$BACKUP_FILE" ]] && die "Укажите файл бекапа: bash restore.sh <IP> <backup.tar.gz>"
[[ -f "$BACKUP_FILE" ]] || die "Файл не найден: $BACKUP_FILE"
shift 2

SSH_EXTRA=("$@")
init_ssh_options

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REMOTE_TMP="/tmp/3xui_restore_${TIMESTAMP}.tar.gz"

echo
warn "ВНИМАНИЕ: текущие данные на ${SERVER_IP} будут заменены содержимым бекапа."
warn "Файл: ${BACKUP_FILE}"
read -rp "Продолжить? [y/N] " CONFIRM
[[ "$CONFIRM" =~ ^[yY]$ ]] || { info "Отменено."; exit 0; }

info "Загружаю архив на сервер..."
scp "${SCP_OPTS[@]}" "$BACKUP_FILE" "${SSH_USER}@${SERVER_IP}:${REMOTE_TMP}"

XUI_DIR="${XUI_DIR:-/root}"

info "Восстанавливаю данные на сервере..."
ssh "${SSH_OPTS[@]}" "${SSH_USER}@${SERVER_IP}" \
    XUI_DIR="${XUI_DIR}" REMOTE_TMP="${REMOTE_TMP}" bash <<'REMOTE'
set -euo pipefail

COMPOSE_FILE="${XUI_DIR}/docker-compose.yml"

# Останавливаем контейнеры
echo "[INFO] Останавливаю контейнеры..."
if [[ -f "$COMPOSE_FILE" ]]; then
    docker compose -f "$COMPOSE_FILE" down 2>/dev/null || true
fi
docker stop caddy-selfsteal 2>/dev/null || true

# Распаковываем во временную директорию
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
tar -xzf "$REMOTE_TMP" -C "$TMP_DIR"

# Восстанавливаем БД
if [[ -d "$TMP_DIR/db" ]]; then
    echo "[INFO] Восстанавливаю ${XUI_DIR}/db/..."
    mkdir -p "${XUI_DIR}/db"
    cp -a "$TMP_DIR/db/." "${XUI_DIR}/db/"
fi

# Восстанавливаем сертификаты
if [[ -d "$TMP_DIR/cert" ]]; then
    echo "[INFO] Восстанавливаю ${XUI_DIR}/cert/..."
    mkdir -p "${XUI_DIR}/cert"
    cp -a "$TMP_DIR/cert/." "${XUI_DIR}/cert/"
    find "${XUI_DIR}/cert" \( -name "*.key" -o -name "privkey.pem" \) -print | xargs -r chmod 600
    find "${XUI_DIR}/cert" \( \( -name "*.pem" ! -name "privkey.pem" \) -o -name "*.crt" \) -print | xargs -r chmod 644
fi

# Восстанавливаем docker-compose.yml
if [[ -f "$TMP_DIR/docker-compose.yml" ]]; then
    echo "[INFO] Восстанавливаю docker-compose.yml..."
    cp "$TMP_DIR/docker-compose.yml" "$COMPOSE_FILE"
fi

# Восстанавливаем /opt/caddy (Caddyfile, .env, docker-compose.yml, html/)
if [[ -d "$TMP_DIR/caddy" ]]; then
    echo "[INFO] Восстанавливаю /opt/caddy/..."
    mkdir -p /opt/caddy
    rsync -a "$TMP_DIR/caddy/" /opt/caddy/
fi

# Восстанавливаем файл доступов
if [[ -f "$TMP_DIR/3xui-credentials.txt" ]]; then
    cp "$TMP_DIR/3xui-credentials.txt" /root/3xui-credentials.txt
    chmod 600 /root/3xui-credentials.txt
fi

# Стартуем контейнеры
echo "[INFO] Запускаю контейнеры..."
if [[ -f "$COMPOSE_FILE" ]]; then
    docker compose -f "$COMPOSE_FILE" up -d && echo "[OK] 3x-ui запущен."
fi
# Caddy selfsteal управляется своим compose-файлом
CADDY_COMPOSE="/opt/caddy/docker-compose.yml"
if [[ -f "$CADDY_COMPOSE" ]]; then
    docker compose -f "$CADDY_COMPOSE" up -d && echo "[OK] caddy-selfsteal запущен."
elif docker inspect caddy-selfsteal &>/dev/null 2>&1; then
    docker start caddy-selfsteal && echo "[OK] caddy-selfsteal запущен."
fi

rm -f "$REMOTE_TMP"
echo "[OK] Восстановление завершено."
REMOTE

echo
success "Восстановление завершено."
