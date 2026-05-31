# shellcheck source=steps/_lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)/_lib.sh"

info "Настройка UFW..."

if command_exists ufw || install_packages ufw &>/dev/null; then
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    for port in 22 80 "$VLESS_PORT" "$PANEL_PORT" "$SUB_PORT"; do
        ufw allow "$port"
    done
    ufw allow "${HY2_PORT}/udp"
    ufw --force enable
    success "UFW включён. Открытые порты: 22 80 ${VLESS_PORT} ${PANEL_PORT} ${SUB_PORT} ${HY2_PORT}/udp."
else
    warn "UFW не найден и не удалось установить — пропущено."
fi
