# shellcheck source=steps/_lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)/_lib.sh"

info "Установка opera-proxy (Opera VPN / SurfEasy)..."

OPERA_BIN="/usr/local/bin/opera-proxy"
OPERA_SERVICE="/etc/systemd/system/opera-proxy.service"

_arch=$(uname -m)
case "$_arch" in
    x86_64)  _arch_str="linux-amd64" ;;
    aarch64) _arch_str="linux-arm64" ;;
    armv7*)  _arch_str="linux-arm"   ;;
    *)       warn "Неподдерживаемая архитектура: $_arch — пропускаю opera-proxy."; exit 0 ;;
esac

ensure_dns "Установка opera-proxy" "github.com"
ensure_dns "Установка opera-proxy" "release-assets.githubusercontent.com"
ensure_dns "Установка opera-proxy" "api.github.com"

_latest_url="https://github.com/Alexey71/opera-proxy/releases/latest/download/opera-proxy.${_arch_str}"
_latest_tag="latest"
info "Скачиваю последнюю версию напрямую: ${_latest_url}"

# Пропустить скачивание, если уже установлена актуальная версия
_ver_file="/usr/local/share/opera-proxy.version"
if [[ -x "$OPERA_BIN" && -n "$_latest_tag" && -f "$_ver_file" && "$(cat "$_ver_file")" == "$_latest_tag" ]]; then
    info "opera-proxy уже актуальной версии ($_latest_tag), пропускаю перекачку."
else
    # Остановить сервис перед перезаписью бинаря (иначе ETXTBSY)
    systemctl stop opera-proxy 2>/dev/null || true

    mkdir -p "$(dirname "$OPERA_BIN")"
    info "Скачиваю $_latest_url..."
    curl -fsSL --retry 3 --retry-all-errors --connect-timeout 10 --max-time 120 \
        -o "${OPERA_BIN}.tmp" "$_latest_url" \
        || {
            warn "Direct download не удался, пробую GitHub API..."
            _api_resp=$(curl -fsSL --retry 3 --retry-all-errors --connect-timeout 10 --max-time 30 \
                -H "Accept: application/vnd.github+json" \
                "https://api.github.com/repos/Alexey71/opera-proxy/releases/latest" 2>/dev/null) || true
            _latest_url=$(echo "$_api_resp" \
                | grep -o '"browser_download_url": *"[^"]*opera-proxy\.'"${_arch_str}"'"' \
                | grep -o 'https://[^"]*' || true)
            _latest_tag=$(echo "$_api_resp" \
                | grep -o '"tag_name": *"[^"]*"' \
                | grep -o '"[^"]*"$' \
                | tr -d '"' || true)
            [[ -n "$_latest_url" ]] || die "Не удалось скачать opera-proxy: нет доступа ни к direct download, ни к GitHub API."
            curl -fsSL --retry 3 --retry-all-errors --connect-timeout 10 --max-time 120 \
                -o "${OPERA_BIN}.tmp" "$_latest_url" \
                || die "Ошибка скачивания opera-proxy."
        }
    mv -f "${OPERA_BIN}.tmp" "$OPERA_BIN"
    chmod 755 "$OPERA_BIN"
    [[ -n "$_latest_tag" ]] && echo "$_latest_tag" > "$_ver_file"
fi

# ── Systemd-сервис (создаётся/обновляется всегда) ────────────────────────────
info "Создаю systemd-сервис opera-proxy (порт ${OPERA_PROXY_PORT}, регион: ${OPERA_REGION})..."
cat > "$OPERA_SERVICE" <<EOF
[Unit]
Description=Opera Proxy (SurfEasy VPN)
After=network.target

[Service]
Type=simple
ExecStart=${OPERA_BIN} \\
    -socks-mode \\
    -bind-address 127.0.0.1:${OPERA_PROXY_PORT} \\
    -country ${OPERA_REGION} \\
    -server-selection fastest
Restart=on-failure
RestartSec=10
NoNewPrivileges=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now opera-proxy

# ── Проверка ─────────────────────────────────────────────────────────────────
# opera-proxy требует подключения к SurfEasy/Opera API — некоторые IP-адреса
# (в т.ч. ряд VPS-провайдеров) блокируются на стороне API (код 801).
# В этом случае прокси не запустится независимо от настроек.
info "Жду запуска opera-proxy (до 10 с)..."
for i in $(seq 1 10); do
    port_listening "$OPERA_PROXY_PORT" && break
    sleep 1
done

if port_listening "$OPERA_PROXY_PORT"; then
    success "opera-proxy запущен. SOCKS5: 127.0.0.1:${OPERA_PROXY_PORT} (регион: ${OPERA_REGION})"
else
    warn "opera-proxy не слушает порт ${OPERA_PROXY_PORT} — возможно, IP сервера заблокирован Opera API. После установки измените правила маршрутизации, чтобы не использовать opera-proxy"
fi
