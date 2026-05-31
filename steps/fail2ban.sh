# shellcheck source=steps/_lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)/_lib.sh"

info "Установка fail2ban..."

if command_exists fail2ban-server; then
    info "fail2ban уже установлен, пропускаем."
else
    info "Устанавливаю fail2ban..."
    install_packages fail2ban || warn "Не удалось установить fail2ban — пропускаю."
fi

if command_exists fail2ban-server; then
    systemctl enable --now fail2ban
    success "fail2ban установлен и запущен."
else
    warn "fail2ban не установлен, пропускаю активацию."
fi
