# shellcheck source=steps/_lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)/_lib.sh"

info "Установка Tor..."

# Idempotency: если Tor уже слушает нужный порт — пропускаем
if systemctl is-active --quiet tor 2>/dev/null && port_listening "$TOR_PORT"; then
    info "Tor уже запущен на порту ${TOR_PORT}, пропускаем."
    exit 0
fi

install_packages tor || die "Не удалось установить Tor."

# Минимальный torrc — только SOCKS5 на localhost
cat > /etc/tor/torrc <<EOF
SocksPort 127.0.0.1:${TOR_PORT}
SocksPolicy accept 127.0.0.1
Log notice syslog
DataDirectory /var/lib/tor
EOF

systemctl enable tor
systemctl restart tor

if wait_for_tcp_port "$TOR_PORT" 30; then
    success "Tor запущен. SOCKS5: 127.0.0.1:${TOR_PORT}"
else
    warn "Tor не слушает порт ${TOR_PORT}. Проверьте: systemctl status tor"
fi
