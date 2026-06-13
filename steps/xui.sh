# shellcheck source=steps/_lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)/_lib.sh"

info "Запуск 3x-ui (Docker)..."

ensure_dns "Запуск 3x-ui" "ghcr.io"
ensure_dns "Запуск 3x-ui" "pkg-containers.githubusercontent.com"
ensure_dns "Запуск 3x-ui" "github-cloud.githubusercontent.com"

mkdir -p "${XUI_DIR}/db" "${XUI_DIR}/cert"

XUI_SERVICE_LIMITS=""
if truthy "${LOW_POWER_MODE:-0}" && [[ -n "${XUI_CPUS_LIMIT:-}" ]]; then
    XUI_SERVICE_LIMITS+="    cpus: \"${XUI_CPUS_LIMIT}\"\n"
fi

XUI_XRAY_LOG_LEVEL="${XUI_LOG_LEVEL:-info}"
if truthy "${LOW_POWER_MODE:-0}"; then
    XUI_XRAY_LOG_LEVEL="${XUI_LOG_LEVEL:-warning}"
fi

# ── docker-compose.yml ───────────────────────────────────────────────────────
cat > "${XUI_DIR}/docker-compose.yml" <<EOF
services:
  3xui:
    image: ghcr.io/mhsanaei/3x-ui:${XUI_VERSION}
    container_name: 3xui_app
    hostname: ${DOMAIN}
$(printf '%b' "${XUI_SERVICE_LIMITS}")
    volumes:
      - ${XUI_DIR}/db/:/etc/x-ui/
      - ${XUI_DIR}/cert/:/root/cert/
    environment:
      XRAY_VMESS_AEAD_FORCED: "false"
      XUI_ENABLE_FAIL2BAN: "${XUI_ENABLE_FAIL2BAN}"
      TZ: "${TZ:-Europe/Moscow}"
    tty: true
    network_mode: host
    restart: unless-stopped
EOF

# ── Запуск контейнера ────────────────────────────────────────────────────────
_pull_retries=3
for _pull_attempt in $(seq 1 "$_pull_retries"); do
    docker compose -f "${XUI_DIR}/docker-compose.yml" pull && break
    if [[ "$_pull_attempt" -eq "$_pull_retries" ]]; then
        die "Не удалось скачать образ 3x-ui после ${_pull_retries} попыток."
    fi
    warn "Попытка ${_pull_attempt}/${_pull_retries} не удалась, повтор через 10с..."
    sleep 10
done
docker compose -f "${XUI_DIR}/docker-compose.yml" up -d \
    || die "Не удалось запустить контейнер 3x-ui."

# Ждём появления БД (до 30 сек)
XUI_DB="${XUI_DIR}/db/x-ui.db"
for i in $(seq 1 30); do
    [[ -f "$XUI_DB" ]] && break
    sleep 1
done
[[ -f "$XUI_DB" ]] || die "БД x-ui не появилась в ${XUI_DB} за 30 секунд."

# ── Reality-ключи (через exec в уже запущенный контейнер) ────────────────────
_xray_bin=/app/bin/xray-linux-amd64

REALITY_KEYS=""
for i in $(seq 1 10); do
    REALITY_KEYS=$(docker exec 3xui_app "$_xray_bin" x25519 2>/dev/null || true)
    [[ "$REALITY_KEYS" == *"PrivateKey"* ]] && break
    REALITY_KEYS=""
    sleep 2
done
if [[ -z "$REALITY_KEYS" ]]; then
    warn "Вывод xray x25519:"
    docker exec 3xui_app "$_xray_bin" x25519 2>&1 || true
    die "Не удалось сгенерировать Reality-ключи (xray x25519)."
fi
REALITY_PRIVATE=$(echo "$REALITY_KEYS" | awk '/PrivateKey:/ {print $2}' | tr -d '[:space:]')
REALITY_PUBLIC=$(echo "$REALITY_KEYS"  | awk '/Password \(PublicKey\):/ {print $NF}' | tr -d '[:space:]')
[[ -z "$REALITY_PRIVATE" ]] && die "Не удалось извлечь приватный ключ: $REALITY_KEYS"
[[ -z "$REALITY_PUBLIC"  ]] && die "Не удалось извлечь публичный ключ: $REALITY_KEYS"

# Останавливаем для применения настроек
docker compose -f "${XUI_DIR}/docker-compose.yml" stop

# ── sqlite3 ──────────────────────────────────────────────────────────────────
if ! command_exists sqlite3; then
    die "sqlite3 не найден. Установите prereqs или добавьте sqlite3 вручную."
fi

# ShortIds
SIDS_JSON=""
for n in 7 2 5 8 6 3 1 4; do
    sid=$(openssl rand -hex "$n")
    SIDS_JSON+="\"${sid}\", "
done
SIDS_JSON="[${SIDS_JSON%, }]"

# ── Xray config ──────────────────────────────────────────────────────────────
XRAY_CONFIG=$(cat <<__JSON__
{
  "log": {"access": "", "dnsLog": false, "error": "", "loglevel": "${XUI_XRAY_LOG_LEVEL}"},
  "api": {"tag": "api", "services": ["HandlerService", "LoggerService", "StatsService"]},
  "inbounds": [{"tag": "api", "listen": "127.0.0.1", "port": $XRAY_API_PORT, "protocol": "dokodemo-door", "settings": {"address": "127.0.0.1"}}],
  "outbounds": [
    {"tag": "blocked", "protocol": "blackhole", "settings": {}},
    {"protocol": "socks", "settings": {"servers": [{"address": "127.0.0.1", "port": $WARP_PROXY_PORT, "users": []}]}, "tag": "warp"},
    {"protocol": "socks", "settings": {"servers": [{"address": "127.0.0.1", "port": $OPERA_PROXY_PORT, "users": []}]}, "tag": "opera"},
    {"protocol": "socks", "settings": {"servers": [{"address": "127.0.0.1", "port": $TOR_PORT, "users": []}]}, "tag": "tor"},
    {"tag": "direct", "protocol": "freedom", "settings": {"domainStrategy": "UseIPv4"}}
  ],
  "policy": {"levels": {"0": {"statsUserDownlink": true, "statsUserUplink": true}}, "system": {"statsInboundDownlink": true, "statsInboundUplink": true, "statsOutboundDownlink": true, "statsOutboundUplink": true}},
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {"type": "field", "inboundTag": ["api"], "outboundTag": "api"},
      {"type": "field", "outboundTag": "blocked", "domain": ["geosite:category-ads-all", "ext:geosite_IR.dat:malware", "ext:geosite_IR.dat:phishing", "ext:geosite_IR.dat:cryptominers"]},
      {"type": "field", "outboundTag": "warp", "domain": ["ext:geosite_RU.dat:ru-available-only-inside", "regexp:.*\\\\.ru\$", "regexp:.*\\\\.su\$", "regexp:.*\\\\.xn--p1ai\$", "domain:ntc.party"]},
      {"type": "field", "ip": ["ext:geoip_RU.dat:ru"], "outboundTag": "warp"},
      {"type": "field", "outboundTag": "tor", "domain": ["regexp:.*\\\\.onion\$", "domain:check.torproject.org"]},
      {"type": "field", "outboundTag": "opera", "domain": ["geosite:disney", "geosite:reddit", "domain:disneyplus.com", "domain:reddit.com", "domain:redd.it", "domain:redditmedia.com", "domain:redditstatic.com", "domain:reddituploads.com"]},
      {"type": "field", "outboundTag": "direct", "network": "tcp,udp"}
    ]
  },
  "stats": {},
  "metrics": {"tag": "metrics"},
  "dns": {"hosts": {"dns.google": ["8.8.8.8", "8.8.4.4"]}, "servers": [], "queryStrategy": "UseIP", "tag": "dns_inbound"},
  "fakedns": null
}
__JSON__
)

VLESS_REALITY_KEYS_SETTINGS="\"show\":false,\"xver\":0,\"target\":\"127.0.0.1:9443\",\"serverNames\":[\"$DOMAIN\"],\"privateKey\":\"$REALITY_PRIVATE\",\"minClientVer\":\"\",\"maxClientVer\":\"\",\"maxTimediff\":0,\"shortIds\":$SIDS_JSON,\"mldsa65Seed\":\"\",\"settings\":{\"publicKey\":\"$REALITY_PUBLIC\",\"fingerprint\":\"firefox\",\"serverName\":\"\",\"spiderX\":\"/\",\"mldsa65Verify\":\"\"}"

ROUTING='happ://routing/onadd/eyJOYW1lIjoiUm9zY29tVlBOIiwiR2xvYmFsUHJveHkiOiJ0cnVlIiwiVXNlQ2h1bmtGaWxlcyI6InRydWUiLCJSZW1vdGVEbnMiOiI4LjguOC44IiwiRG9tZXN0aWNEbnMiOiI3Ny44OC44LjgiLCJSZW1vdGVETlNUeXBlIjoiRG9IIiwiUmVtb3RlRE5TRG9tYWluIjoiaHR0cHM6Ly84LjguOC44L2Rucy1xdWVyeSIsIlJlbW90ZUROU0lQIjoiOC44LjguOCIsIkRvbWVzdGljRE5TVHlwZSI6IkRvSCIsIkRvbWVzdGljRE5TRG9tYWluIjoiaHR0cHM6Ly83Ny44OC44LjgvZG5zLXF1ZXJ5IiwiRG9tZXN0aWNETlNJUCI6Ijc3Ljg4LjguOCIsIkdlb2lwdXJsIjoiaHR0cHM6Ly9jZG4uanNkZWxpdnIubmV0L2doL2h5ZHJhcG9uaXF1ZS9yb3Njb212cG4tZ2VvaXBAMjAyNjA0MjQwNTQyL3JlbGVhc2UvZ2VvaXAuZGF0IiwiR2Vvc2l0ZXVybCI6Imh0dHBzOi8vY2RuLmpzZGVsaXZyLm5ldC9naC9oeWRyYXBvbmlxdWUvcm9zY29tdnBuLWdlb3NpdGVAMjAyNjA0MTUyMjM1L3JlbGVhc2UvZ2Vvc2l0ZS5kYXQiLCJMYXN0VXBkYXRlZCI6IjE3NzcwMDkzOTAiLCJEbnNIb3N0cyI6eyJsa2ZsMi5uYWxvZy5ydSI6IjIxMy4yNC42NC4xNzUiLCJsa25wZC5uYWxvZy5ydSI6IjIxMy4yNC42NC4xODEifSwiUm91dGVPcmRlciI6ImJsb2NrLXByb3h5LWRpcmVjdCIsIkRpcmVjdFNpdGVzIjpbImdlb3NpdGU6cHJpdmF0ZSIsImdlb3NpdGU6Y2F0ZWdvcnktcnUiLCJnZW9zaXRlOndoaXRlbGlzdCIsImdlb3NpdGU6bWljcm9zb2Z0IiwiZ2Vvc2l0ZTphcHBsZSIsImdlb3NpdGU6ZXBpY2dhbWVzIiwiZ2Vvc2l0ZTpyaW90IiwiZ2Vvc2l0ZTplc2NhcGVmcm9tdGFya292IiwiZ2Vvc2l0ZTpzdGVhbSIsImdlb3NpdGU6dHdpdGNoIiwiZ2Vvc2l0ZTpwaW50ZXJlc3QiLCJnZW9zaXRlOmZhY2VpdCJdLCJEaXJlY3RJcCI6WyJnZW9pcDpwcml2YXRlIiwiZ2VvaXA6ZGlyZWN0Il0sIlByb3h5U2l0ZXMiOlsiZ2Vvc2l0ZTpnb29nbGUtcGxheSIsImdlb3NpdGU6Z2l0aHViIiwiZ2Vvc2l0ZTp0d2l0Y2gtYWRzIiwiZ2Vvc2l0ZTp5b3V0dWJlIiwiZ2Vvc2l0ZTp0ZWxlZ3JhbSJdLCJQcm94eUlwIjpbXSwiQmxvY2tTaXRlcyI6WyJnZW9zaXRlOndpbi1zcHkiLCJnZW9zaXRlOnRvcnJlbnQiLCJnZW9zaXRlOmNhdGVnb3J5LWFkcyJdLCJCbG9ja0lwIjpbXSwiRG9tYWluU3RyYXRlZ3kiOiJJUElmTm9uTWF0Y2giLCJGYWtlRE5TIjoiZmFsc2UifQo='

XRAY_CONFIG_1L=$(printf '%s' "$XRAY_CONFIG" | tr -d '\n')

# ── Запись настроек в БД ─────────────────────────────────────────────────────
xui_db_set() {
    local key="$1"
    local val
    val=$(sql_escape "$2")
    sqlite3 "$XUI_DB" \
        "DELETE FROM settings WHERE key='${key}'; INSERT INTO settings(key,value) VALUES('${key}','${val}');" \
        || die "Ошибка записи '$key' в БД"
}

sqlite3 "$XUI_DB" "DELETE FROM settings WHERE rowid NOT IN (SELECT MAX(rowid) FROM settings GROUP BY key);"

xui_db_set webPort            "$PANEL_PORT"
xui_db_set webDomain          "$DOMAIN"
xui_db_set webBasePath        "$PANEL_PATH"
xui_db_set subPort            "$SUB_PORT"
xui_db_set subDomain          "$DOMAIN"
xui_db_set subEnable          "true"
xui_db_set subJsonEnable      "false"
xui_db_set subTitle           "$SUB_TITLE"
xui_db_set subPath            "$SUB_PATH"
xui_db_set subUpdates         "1"
xui_db_set subRoutingRules    "$ROUTING"
xui_db_set xrayTemplateConfig "$XRAY_CONFIG_1L"
xui_db_set webCertFile        "${CERT_DIR}/fullchain.pem"
xui_db_set webKeyFile         "${CERT_DIR}/privkey.pem"
xui_db_set subCertFile        "${CERT_DIR}/fullchain.pem"
xui_db_set subKeyFile         "${CERT_DIR}/privkey.pem"

# ── VLESS Reality ────────────────────────────────────────────────────────────
# В новой версии 3x-ui клиенты хранятся в отдельных таблицах clients/client_inbounds/client_traffics
VLESS_REALITY_SETTINGS="{\"clients\":[],\"decryption\":\"none\",\"encryption\":\"none\",\"fallbacks\":[{\"dest\":9443,\"xver\":1}]}"
VLESS_REALITY_STREAM="{\"network\":\"tcp\",\"security\":\"reality\",\"externalProxy\":[],\"realitySettings\":{${VLESS_REALITY_KEYS_SETTINGS}},\"tcpSettings\":{\"acceptProxyProtocol\":false,\"header\":{\"type\":\"none\"}}}"
VLESS_REALITY_SNIFFING='{"enabled":true,"destOverride":["http","tls","quic","fakedns"],"metadataOnly":false,"routeOnly":false}'

VLESS_REALITY_SE_SQL="${VLESS_REALITY_SETTINGS//\'/\'\'}"
VLESS_REALITY_SS_SQL="${VLESS_REALITY_STREAM//\'/\'\'}"
VLESS_REALITY_SN_SQL="${VLESS_REALITY_SNIFFING//\'/\'\'}"

# Чистим всех клиентов и связанные данные перед пересозданием инбаундов
sqlite3 "$XUI_DB" \
    "DELETE FROM client_traffics;
     DELETE FROM client_inbounds;
     DELETE FROM clients;
     DELETE FROM inbounds;" \
    || die "Ошибка очистки клиентов и инбаундов в БД"

sqlite3 "$XUI_DB" \
    "INSERT INTO inbounds (user_id,up,down,total,remark,enable,expiry_time,traffic_reset,listen,port,protocol,settings,stream_settings,tag,sniffing)
     VALUES (1,0,0,0,'VLESS Reality',1,0,'${TRAFFIC_RESET}','',${VLESS_PORT},'vless','${VLESS_REALITY_SE_SQL}','${VLESS_REALITY_SS_SQL}','in-${VLESS_PORT}-tcp','${VLESS_REALITY_SN_SQL}');" \
    || die "Ошибка INSERT VLESS Reality inbound в БД"

# ── Hysteria2 ─────────────────────────────────────────────────────────────────
HY2_OBFS_PASS=$(random_alnum 32)

HYSTERIA2_SETTINGS="{\"clients\":[],\"version\":2}"
HYSTERIA2_STREAM="{\"network\":\"hysteria\",\"security\":\"tls\",\"externalProxy\":[],\"tlsSettings\":{\"serverName\":\"$DOMAIN\",\"minVersion\":\"1.2\",\"maxVersion\":\"1.3\",\"cipherSuites\":\"\",\"rejectUnknownSni\":true,\"disableSystemRoot\":false,\"enableSessionResumption\":true,\"certificates\":[{\"certificateFile\":\"${CERT_DIR}/fullchain.pem\",\"keyFile\":\"${CERT_DIR}/privkey.pem\",\"oneTimeLoading\":false,\"usage\":\"encipherment\",\"buildChain\":false}],\"alpn\":[\"h3\"],\"echServerKeys\":\"\",\"settings\":{\"fingerprint\":\"firefox\",\"echConfigList\":\"\"}},\"hysteriaSettings\":{\"version\":2,\"auth\":\"$CLIENT_HY2_AUTH\",\"udpIdleTimeout\":60,\"masquerade\":{\"type\":\"proxy\",\"dir\":\"\",\"url\":\"twitch.tv\",\"rewriteHost\":true,\"insecure\":false,\"content\":\"\",\"headers\":{},\"statusCode\":0}},\"finalmask\":{\"udp\":[{\"type\":\"salamander\",\"settings\":{\"password\":\"${HY2_OBFS_PASS}\"}}],\"quicParams\":{\"congestion\":\"bbr\"}}}"
HYSTERIA2_SNIFFING='{"enabled":true,"destOverride":["http","tls","quic","fakedns"],"metadataOnly":false,"routeOnly":false}'

HYSTERIA2_SE_SQL="${HYSTERIA2_SETTINGS//\'/\'\'}"
HYSTERIA2_SS_SQL="${HYSTERIA2_STREAM//\'/\'\'}"
HYSTERIA2_SN_SQL="${HYSTERIA2_SNIFFING//\'/\'\'}"

sqlite3 "$XUI_DB" \
    "INSERT INTO inbounds (user_id,up,down,total,remark,enable,expiry_time,traffic_reset,listen,port,protocol,settings,stream_settings,tag,sniffing)
     VALUES (1,0,0,0,'Hy2',1,0,'${TRAFFIC_RESET}','',${HY2_PORT},'hysteria','${HYSTERIA2_SE_SQL}','${HYSTERIA2_SS_SQL}','in-${HY2_PORT}-udp','${HYSTERIA2_SN_SQL}');" \
    || die "Ошибка INSERT Hysteria2 inbound в БД"

# ── Клиент (новая структура: clients + client_inbounds + client_traffics) ─────
CLIENT_EMAIL_SQL=$(sql_escape "$CLIENT_EMAIL")
CLIENT_UUID_SQL=$(sql_escape "$CLIENT_UUID")
CLIENT_SUB_ID_SQL=$(sql_escape "$CLIENT_SUB_ID")
CLIENT_HY2_AUTH_SQL=$(sql_escape "$CLIENT_HY2_AUTH")
NOW_MS=$(date +%s)000

sqlite3 "$XUI_DB" \
    "INSERT INTO clients (email,sub_id,uuid,auth,flow,security,limit_ip,total_gb,expiry_time,enable,tg_id,group_name,comment,reset,created_at,updated_at)
     VALUES ('${CLIENT_EMAIL_SQL}','${CLIENT_SUB_ID_SQL}','${CLIENT_UUID_SQL}','${CLIENT_HY2_AUTH_SQL}','xtls-rprx-vision','auto',0,0,0,1,0,'','',0,${NOW_MS},${NOW_MS});
     INSERT INTO client_inbounds (client_id,inbound_id,flow_override,created_at)
     VALUES ((SELECT id FROM clients WHERE email='${CLIENT_EMAIL_SQL}'),(SELECT id FROM inbounds WHERE tag='in-${VLESS_PORT}-tcp'),'xtls-rprx-vision',${NOW_MS});
     INSERT INTO client_inbounds (client_id,inbound_id,flow_override,created_at)
     VALUES ((SELECT id FROM clients WHERE email='${CLIENT_EMAIL_SQL}'),(SELECT id FROM inbounds WHERE tag='in-${HY2_PORT}-udp'),'',${NOW_MS});
     INSERT INTO client_traffics (inbound_id,enable,email,up,down,expiry_time,total,reset)
     VALUES ((SELECT id FROM inbounds WHERE tag='in-${VLESS_PORT}-tcp'),1,'${CLIENT_EMAIL_SQL}',0,0,0,0,0);" \
    || die "Ошибка INSERT клиента в БД"

# ── Добавление клиента в settings инбаундов (3x-ui ищет клиентов в JSON) ─────
CLIENT_JSON="{\"id\":\"${CLIENT_UUID}\",\"auth\":\"${CLIENT_HY2_AUTH}\",\"flow\":\"xtls-rprx-vision\",\"security\":\"auto\",\"email\":\"${CLIENT_EMAIL}\",\"limitIp\":0,\"totalGB\":0,\"expiryTime\":0,\"enable\":true,\"tgId\":0,\"subId\":\"${CLIENT_SUB_ID}\",\"comment\":\"\",\"reset\":0,\"created_at\":${NOW_MS},\"updated_at\":${NOW_MS},\"password\":\"\"}"
CLIENT_JSON_SQL=$(sql_escape "$CLIENT_JSON")
sqlite3 "$XUI_DB" \
    "UPDATE inbounds SET settings=json_set(settings,'$.clients',json_array(json('${CLIENT_JSON_SQL}'))) WHERE tag='in-${VLESS_PORT}-tcp';
     UPDATE inbounds SET settings=json_set(settings,'$.clients',json_array(json('${CLIENT_JSON_SQL}'))) WHERE tag='in-${HY2_PORT}-udp';" \
    || die "Ошибка обновления settings инбаундов с клиентом"

# ── Хэш пароля (до старта контейнера) ───────────────────────────────────────
if ! command_exists htpasswd; then
    die "htpasswd не найден. Установите prereqs или добавьте apache2-utils вручную."
fi
PANEL_PASS_HASH=$(htpasswd -bnBC 10 "" "$PANEL_PASS" | tr -d ':\n') \
    || die "Не удалось сгенерировать bcrypt-хэш пароля."
[[ -n "$PANEL_PASS_HASH" ]] || die "bcrypt-хэш пустой."

# Ждём появления таблицы users в БД (контейнер ещё остановлен)
# Таблица уже должна быть — она создаётся при первом старте выше
PANEL_USER_SQL=$(sql_escape "$PANEL_USER")
PANEL_PASS_HASH_SQL=$(sql_escape "$PANEL_PASS_HASH")
sqlite3 "$XUI_DB" \
    "UPDATE users SET username='${PANEL_USER_SQL}', password='${PANEL_PASS_HASH_SQL}' WHERE id=1;" \
    || die "Не удалось задать логин/пароль в БД."

# ── Финальный старт (один раз, без рестарта) ─────────────────────────────────
docker compose -f "${XUI_DIR}/docker-compose.yml" up -d \
    || die "Не удалось запустить контейнер 3x-ui."
sleep 3
success "3x-ui запущен. Управление: docker compose -f ${XUI_DIR}/docker-compose.yml"
