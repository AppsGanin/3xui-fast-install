# shellcheck source=steps/_lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)/_lib.sh"

info "Шаг 5/7: Установка Caddy selfsteal (SSL генерирует Caddy)..."

CADDY_CONTAINER="caddy-selfsteal"
mkdir -p "$CERT_DIR"

CERT_INSIDE="/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${DOMAIN}/${DOMAIN}.crt"
KEY_INSIDE="/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${DOMAIN}/${DOMAIN}.key"

info "Проверяю DNS: $DOMAIN → этот сервер..."
_server_ip=$(curl -fsSL -4 --connect-timeout 5 ifconfig.io 2>/dev/null \
           || curl -fsSL -4 --connect-timeout 5 icanhazip.com 2>/dev/null \
           || true)
_dns_ip=$(getent hosts "$DOMAIN" 2>/dev/null | awk '{print $1; exit}' \
        || dig +short A "$DOMAIN" 2>/dev/null | grep -E '^[0-9.]+$' | head -1 \
        || true)
if [[ -z "$_dns_ip" ]]; then
    die "DNS для $DOMAIN не разрешается. Убедитесь, что A-запись настроена."
fi
if [[ -n "$_server_ip" && "$_dns_ip" != "$_server_ip" ]]; then
    die "DNS для $DOMAIN указывает на $_dns_ip, а не на этот сервер ($_server_ip). Обновите A-запись."
fi
success "DNS: $DOMAIN → $_dns_ip"

info "Запускаю selfsteal Caddy для домена $DOMAIN..."
TERM=xterm bash <(curl -fsSL https://github.com/DigneZzZ/remnawave-scripts/raw/main/selfsteal.sh) \
    @ --force --domain "$DOMAIN" install \
    || die "Ошибка установки selfsteal Caddy."

info "Жду сертификат Let's Encrypt от Caddy (до 180 с)..."
for i in $(seq 1 180); do
    docker exec "$CADDY_CONTAINER" test -f "$CERT_INSIDE" 2>/dev/null && break
    sleep 1
done
if ! docker exec "$CADDY_CONTAINER" test -f "$CERT_INSIDE" 2>/dev/null; then
    warn "Логи Caddy для диагностики:"
    docker logs --tail 40 "$CADDY_CONTAINER" 2>&1 || true
    die "Caddy не получил сертификат за 180 секунд. DNS: $DOMAIN → $_dns_ip. Порт 80 должен быть открыт."
fi

info "Копирую сертификат из Caddy на хост..."
docker cp "${CADDY_CONTAINER}:${CERT_INSIDE}" "$CERT_DIR/fullchain.pem" \
    || die "Не удалось скопировать сертификат из контейнера."
docker cp "${CADDY_CONTAINER}:${KEY_INSIDE}" "$CERT_DIR/privkey.pem" \
    || die "Не удалось скопировать приватный ключ из контейнера."
chmod 600 "$CERT_DIR/privkey.pem"
chmod 644 "$CERT_DIR/fullchain.pem"

RENEW_SCRIPT="/root/caddy-cert-sync.sh"
cat > "$RENEW_SCRIPT" <<SCRIPT
#!/usr/bin/env bash
CADDY_CONTAINER="${CADDY_CONTAINER}"
CERT_DIR="${CERT_DIR}"
DOMAIN="${DOMAIN}"
CERT_INSIDE="/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/\${DOMAIN}/\${DOMAIN}.crt"
KEY_INSIDE="/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/\${DOMAIN}/\${DOMAIN}.key"

docker cp "\${CADDY_CONTAINER}:\${CERT_INSIDE}" "\${CERT_DIR}/fullchain.pem" 2>/dev/null || exit 1
docker cp "\${CADDY_CONTAINER}:\${KEY_INSIDE}"  "\${CERT_DIR}/privkey.pem"  2>/dev/null || exit 1
chmod 600 "\${CERT_DIR}/privkey.pem"
chmod 644 "\${CERT_DIR}/fullchain.pem"
docker restart 3xui_app 2>/dev/null || true
SCRIPT
chmod 700 "$RENEW_SCRIPT"

(crontab -l 2>/dev/null | grep -v "caddy-cert-sync" || true; echo "30 4 * * * $RENEW_SCRIPT") | crontab -

success "Selfsteal Caddy установлен. Сертификат: ${CERT_DIR}/fullchain.pem"
