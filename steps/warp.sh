# shellcheck source=steps/_lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)/_lib.sh"

info "Установка WARP..."

get_debian_codename() {
    if command -v lsb_release &>/dev/null; then
        lsb_release -cs
    elif [[ -r /etc/os-release ]]; then
        . /etc/os-release
        printf '%s' "${VERSION_CODENAME:-}"
    fi
}

install_warp_deb() {
    apt-get update -qq
    apt-get install -y --no-install-recommends lsb-release ca-certificates apt-transport-https

    local codename
    codename=$(get_debian_codename)
    if [[ -z "$codename" ]]; then
        die "Не удалось определить кодовое имя Debian/Ubuntu для установки WARP."
    fi

    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg \
        | gpg --batch --yes --dearmor -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
    chmod 644 /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg

    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $codename main" \
        > /etc/apt/sources.list.d/cloudflare-client.list

    apt-get update -qq
    apt-get install -y cloudflare-warp
}

install_warp_rpm() {
    curl -fsSL https://pkg.cloudflareclient.com/cloudflare-warp-ascii.repo \
        -o /etc/yum.repos.d/cloudflare-warp.repo
    yum install -y cloudflare-warp
}

if command -v apt-get &>/dev/null; then
    install_warp_deb
elif command -v yum &>/dev/null; then
    install_warp_rpm
else
    die "Не удалось установить WARP: пакетный менеджер не найден (нужен apt или yum)."
fi

if ! command -v warp-cli &>/dev/null; then
    warn "warp-cli не найден: WARP не установлен. Пропускаем настройку WARP."
    exit 0
fi

systemctl enable --now warp-svc

if ! warp-cli --accept-tos registration show &>/dev/null; then
    warp-cli --accept-tos registration new
fi

warp-cli --accept-tos mode proxy
warp-cli --accept-tos proxy port "$WARP_PROXY_PORT"
warp-cli --accept-tos connect

for i in $(seq 1 30); do
    status=$(warp-cli --accept-tos status 2>/dev/null || true)
    echo "$status" | grep -q "Connected" && break
    sleep 1
done

if echo "$status" | grep -q "Connected"; then
    success "WARP подключён. SOCKS5 proxy: 127.0.0.1:${WARP_PROXY_PORT}"
else
    warn "WARP установлен, но статус подключения неизвестен. Проверьте вручную: warp-cli status"
fi
