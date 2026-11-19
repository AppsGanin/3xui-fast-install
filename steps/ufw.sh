# shellcheck source=steps/_lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)/_lib.sh"

info "Настройка UFW..."

# Добавляет/убирает NAT-редирект диапазона port hopping → HY2_PORT в before.rules.
# В Xray-core hysteria port hopping не настраивается в конфиге: клиент прыгает по
# диапазону UDP-портов, а на сервере весь диапазон REDIRECT'ится на реальный порт.
# Правило живёт в /etc/ufw/before.rules (таблица nat), поэтому переживает ребут.
hy2_hop_nat() {
    local action="$1"   # on|off
    local rules="/etc/ufw/before.rules"
    local begin="# BEGIN 3XUI HY2 PORT HOPPING"
    local end="# END 3XUI HY2 PORT HOPPING"

    [[ -f "$rules" ]] || { warn "Файл ${rules} не найден — NAT-редирект для port hopping пропущен."; return 1; }

    # Снимаем прежний блок (идемпотентность при повторной установке).
    local tmp
    tmp=$(mktemp)
    awk -v b="$begin" -v e="$end" '
        $0==b {skip=1}
        !skip {print}
        $0==e {skip=0}
    ' "$rules" > "$tmp" && mv "$tmp" "$rules"

    [[ "$action" == "on" ]] || return 0

    # Вставляем nat-блок перед первой таблицей *filter.
    local ln
    ln=$(grep -n '^\*filter' "$rules" | head -n1 | cut -d: -f1)
    [[ -n "$ln" ]] || { warn "В ${rules} нет секции *filter — NAT-редирект пропущен."; return 1; }

    tmp=$(mktemp)
    {
        head -n "$((ln - 1))" "$rules"
        printf '%s\n' \
            "$begin" \
            "*nat" \
            ":PREROUTING ACCEPT [0:0]" \
            "-A PREROUTING -p udp --dport ${HY2_HOP_RANGE} -j REDIRECT --to-ports ${HY2_PORT}" \
            "COMMIT" \
            "$end"
        tail -n "+${ln}" "$rules"
    } > "$tmp" && mv "$tmp" "$rules"
}

if command_exists ufw || install_packages ufw &>/dev/null; then
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing

    if truthy "$HY2_HOP"; then
        hy2_hop_nat on
    else
        hy2_hop_nat off
    fi

    # Панель и подписка работают за Caddy на 443, наружу их порты не открываем.
    # Для port hopping в фильтре достаточно открыть сам HY2_PORT: пакеты с портов
    # диапазона редиректятся на него в nat PREROUTING ещё до фильтра INPUT.
    # Trojan-WS наружу не открываем: он слушает localhost, а трафик приходит через
    # 443 (VLESS Reality steal → Caddy → localhost-инбаунд по секретному пути).
    # SSH: открываем SSH_PORT (заданный или определённый автоматически) и все
    # порты, на которых реально слушает sshd, чтобы не потерять доступ после
    # `ufw reset`. Если порт SSH не 22, порт 22 не открываем.
    ssh_ports=("$SSH_PORT")
    while read -r p; do
        [[ "$p" =~ ^[0-9]+$ ]] && ssh_ports+=("$p")
    done < <(sshd -T 2>/dev/null | awk '$1=="port"{print $2}')
    mapfile -t ssh_ports < <(printf '%s\n' "${ssh_ports[@]}" | sort -un)

    for port in "${ssh_ports[@]}" 80 "$VLESS_PORT" "$HY2_PORT"; do
        ufw allow "$port"
    done
    ufw --force enable

    if truthy "$HY2_HOP"; then
        success "UFW включён. Открытые порты: ${ssh_ports[*]} 80 ${VLESS_PORT} ${HY2_PORT}; port hopping ${HY2_HOP_RANGE}/udp → ${HY2_PORT} (панель/подписка/Trojan-WS — за Caddy на 443)."
    else
        success "UFW включён. Открытые порты: ${ssh_ports[*]} 80 ${VLESS_PORT} ${HY2_PORT} (панель/подписка/Trojan-WS — за Caddy на 443)."
    fi
else
    warn "UFW не найден и не удалось установить — пропущено."
fi
