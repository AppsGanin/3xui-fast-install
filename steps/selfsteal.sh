# shellcheck source=steps/_lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)/_lib.sh"

info "Установка Caddy selfsteal (SSL генерирует Caddy)..."

CADDY_CONTAINER="caddy-selfsteal"
mkdir -p "$CERT_DIR"

CERT_INSIDE="/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${DOMAIN}/${DOMAIN}.crt"
KEY_INSIDE="/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${DOMAIN}/${DOMAIN}.key"

info "Проверяю DNS: $DOMAIN → этот сервер..."
_server_ip=$(curl -fsSL -4 --connect-timeout 5 ifconfig.io 2>/dev/null \
           || curl -fsSL -4 --connect-timeout 5 icanhazip.com 2>/dev/null \
           || true)
_dns_a_records=$(dig +short A "$DOMAIN" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true)
_dns_ip=$(printf '%s\n' "$_dns_a_records" | head -1)
_dns_ahosts=$(getent ahosts "$DOMAIN" 2>/dev/null | awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {print $1}' | uniq || true)
if [[ -z "$_dns_ip" && -n "$_dns_ahosts" ]]; then
    _dns_ip=$(printf '%s\n' "$_dns_ahosts" | head -1)
fi
if [[ -z "$_dns_ip" ]]; then
    die "DNS для $DOMAIN не разрешается. Убедитесь, что A-запись настроена. A-записи: $(printf '%s,' "$_dns_a_records" | sed 's/,$//') ahosts: $(printf '%s,' "$_dns_ahosts" | sed 's/,$//')"
fi
if [[ -n "$_server_ip" && "$_dns_ip" != "$_server_ip" ]]; then
    die "DNS для $DOMAIN указывает на $_dns_ip, а не на этот сервер ($_server_ip). Проверьте A-запись. A-записи: $(printf '%s,' "$_dns_a_records" | sed 's/,$//') ahosts: $(printf '%s,' "$_dns_ahosts" | sed 's/,$//')"
fi
success "DNS: $DOMAIN → $_dns_ip"

info "Запускаю selfsteal Caddy для домена $DOMAIN..."
selfsteal_tmp_dir=$(mktemp -d)
trap 'rm -rf "$selfsteal_tmp_dir"' EXIT
selfsteal_installer="${selfsteal_tmp_dir}/selfsteal.sh"
selfsteal_log="${selfsteal_tmp_dir}/selfsteal.log"

curl -fsSL https://github.com/DigneZzZ/remnawave-scripts/raw/main/selfsteal.sh \
    -o "$selfsteal_installer" \
    || die "Не удалось скачать selfsteal installer."

# У upstream installer strict-mode иногда падает без полезной диагностики;
# --debug оставляет проверки, но не обрывает установку на безвредных командах.
if ! TERM=dumb bash "$selfsteal_installer" @ --debug --force --domain "$DOMAIN" install >"$selfsteal_log" 2>&1; then
    sed 's/^/[SELFSTEAL] /' "$selfsteal_log" | tail -n 80
    die "Ошибка установки selfsteal Caddy."
fi
sed 's/^/[SELFSTEAL] /' "$selfsteal_log" | tail -n 80

info "Жду сертификат Let's Encrypt от Caddy (до 60 с)..."
for i in $(seq 1 60); do
    docker exec "$CADDY_CONTAINER" test -f "$CERT_INSIDE" 2>/dev/null && break
    sleep 1
done
if ! docker exec "$CADDY_CONTAINER" test -f "$CERT_INSIDE" 2>/dev/null; then
    warn "Логи Caddy для диагностики:"
    docker logs --tail 40 "$CADDY_CONTAINER" 2>&1 || true
    die "Caddy не получил сертификат за 60 секунд. DNS: $DOMAIN → $_dns_ip. Порт 80 должен быть открыт."
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
