# shellcheck source=steps/_lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)/_lib.sh"

info "Установка необходимых пакетов..."
if command_exists apt-get; then
    install_packages \
        curl gnupg lsb-release ca-certificates apt-transport-https \
        python3 sqlite3 apache2-utils \
        || die "Не удалось установить необходимые пакеты для Debian/Ubuntu."
elif command_exists yum; then
    install_packages \
        curl python3 sqlite gnupg2 redhat-lsb-core ca-certificates \
        || die "Не удалось установить необходимые пакеты для RHEL/CentOS."
else
    die "Пакетный менеджер не найден. Нужен apt-get или yum."
fi

success "Необходимые пакеты установлены."
