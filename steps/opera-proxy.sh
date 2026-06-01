# shellcheck source=steps/_lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)/_lib.sh"

info "Установка opera-proxy (Opera VPN / SurfEasy)..."

OPERA_BIN="/usr/local/bin/opera-proxy"
OPERA_SERVICE="/etc/systemd/system/opera-proxy.service"

if ! command_exists python3; then
    die "Python3 не найден. Установите prereqs или добавьте python3 вручную."
fi

# ── Скачать последнюю версию ─────────────────────────────────────────────────
info "Определяю последнюю версию opera-proxy..."
_arch=$(uname -m)
case "$_arch" in
    x86_64)  _arch_str="linux-amd64" ;;
    aarch64) _arch_str="linux-arm64" ;;
    armv7*)  _arch_str="linux-arm"   ;;
    *)       warn "Неподдерживаемая архитектура: $_arch — пропускаю opera-proxy."; exit 0 ;;
esac

_latest_url=""
_latest_tag=""
for _attempt in 1 2 3; do
    info "Попытка $_attempt: запрашиваю GitHub API..."
    _api_resp=$(curl -fsSL --max-time 30 \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/Alexey71/opera-proxy/releases/latest" 2>/dev/null) || true
    _latest_url=$(echo "$_api_resp" | python3 -c "
import sys, json
try:
    data = json.loads(sys.stdin.read())
    needle = 'opera-proxy.${_arch_str}'
    for a in data.get('assets', []):
        if a['name'] == needle:
            print(a['browser_download_url'])
            break
except Exception:
    pass
" 2>/dev/null || true)
    _latest_tag=$(echo "$_api_resp" | python3 -c "
import sys, json
try:
    data = json.loads(sys.stdin.read())
    print(data.get('tag_name', ''))
except Exception:
    pass
" 2>/dev/null || true)
    [[ -n "$_latest_url" ]] && break
    [[ $_attempt -lt 3 ]] && sleep 5
done

if [[ -z "$_latest_url" ]]; then
    warn "Не удалось получить URL релиза opera-proxy (GitHub API недоступен). Пропускаю шаг."
    warn "Можно установить вручную позже: https://github.com/Alexey71/opera-proxy/releases"
    exit 0
fi

# Пропустить скачивание, если уже установлена актуальная версия
_ver_file="/usr/local/share/opera-proxy.version"
if [[ -x "$OPERA_BIN" && -n "$_latest_tag" && -f "$_ver_file" && "$(cat "$_ver_file")" == "$_latest_tag" ]]; then
    info "opera-proxy уже актуальной версии ($_latest_tag), пропускаю перекачку."
else

# Остановить сервис перед перезаписью бинаря (иначе ETXTBSY)
systemctl stop opera-proxy 2>/dev/null || true

mkdir -p "$(dirname "$OPERA_BIN")"
info "Скачиваю $_latest_url..."
curl -fsSL --max-time 120 -o "${OPERA_BIN}.tmp" "$_latest_url" || die "Ошибка скачивания opera-proxy."
mv -f "${OPERA_BIN}.tmp" "$OPERA_BIN"
chmod 755 "$OPERA_BIN"
[[ -n "$_latest_tag" ]] && echo "$_latest_tag" > "$_ver_file"

# ── Systemd-сервис ────────────────────────────────────────────────────────────
info "Создаю systemd-сервис opera-proxy (порт ${OPERA_PROXY_PORT}, регион: ${OPERA_COUNTRY})..."
cat > "$OPERA_SERVICE" <<EOF
[Unit]
Description=Opera Proxy (SurfEasy VPN)
After=network.target

[Service]
Type=simple
ExecStart=${OPERA_BIN} \\
    -socks-mode \\
    -bind-address 127.0.0.1:${OPERA_PROXY_PORT} \\
    -country ${OPERA_COUNTRY} \\
    -server-selection fastest
Restart=on-failure
RestartSec=10
NoNewPrivileges=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now opera-proxy
fi  # end version check

# ── Проверка ─────────────────────────────────────────────────────────────────
info "Жду запуска opera-proxy (до 30 с)..."
for i in $(seq 1 30); do
    port_listening "$OPERA_PROXY_PORT" && break
    sleep 1
done

if port_listening "$OPERA_PROXY_PORT"; then
    success "opera-proxy запущен. SOCKS5: 127.0.0.1:${OPERA_PROXY_PORT} (регион: ${OPERA_COUNTRY})"
else
    warn "opera-proxy не слушает порт ${OPERA_PROXY_PORT}. Проверьте: systemctl status opera-proxy"
fi
