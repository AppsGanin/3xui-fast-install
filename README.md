# 3x-ui Fast install Setup

Личный VPN-сервер под ключ за один запуск. Скрипты разворачивают 3x-ui, VLESS Reality, Hysteria2, selfsteal Caddy, Cloudflare WARP, Opera Proxy, Tor, BBR, UFW и fail2ban, а затем сразу выдают готовые доступы к панели.

## Что вы получаете

- Готовый 3x-ui в Docker с автозапуском после перезагрузки сервера.
- Два протокола из коробки: VLESS Reality и Hysteria2.
- Первый клиент создаётся автоматически сразу в обоих inbound'ах.
- Персональная ссылка подписки сохраняется в файле доступов.
- Сертификаты Let's Encrypt через Caddy selfsteal.
- Раздельную маршрутизацию: RU-трафик через WARP, выбранные зарубежные сервисы через Opera Proxy, `.onion` через Tor, остальное напрямую.
- Настроенный фаервол, BBR и базовую защиту fail2ban.
- Backup/restore-скрипты для переноса и восстановления сервера.

## Для кого

Для тех, кто хочет быстро поднять личную VPN-инфраструктуру на VPS без ручной настройки 3x-ui, inbound'ов, сертификатов, firewall-правил и Xray routing. Подходит для личного сервера, тестового стенда или аккуратной самостоятельной установки с понятными логами.

## Быстрый старт

Нужны VPS с Debian/Ubuntu, root-доступ по SSH и домен с A-записью на IP сервера.

```bash
git clone https://github.com/AppsGanin/3xui-fast-install/3xui-personal
cd 3xui-personal

bash deploy.sh 1.2.3.4
```

После установки скрипт покажет URL панели, логин, пароль и персональную ссылку подписки первого клиента. Эти же данные сохраняются на сервере в `/root/3xui-credentials.txt`.

Для установки через ИИ-агента см. [AI_INSTALL.md](AI_INSTALL.md).

## Компоненты

| Компонент           | Что делает                                                                                  |
| ------------------- | ------------------------------------------------------------------------------------------- |
| **3x-ui**           | Панель управления Xray в Docker, inbound'ы VLESS Reality и Hysteria2                        |
| **VLESS + Reality** | Основной TCP-вход, по умолчанию на `443`, с fallback-маскировкой через Caddy                |
| **Hysteria2**       | UDP-вход поверх TLS, по умолчанию на `63000/udp`, хорошо переживает мобильные сети и потери |
| **Caddy selfsteal** | Получает Let's Encrypt сертификат и держит fallback-маскировку                              |
| **Cloudflare WARP** | Локальный SOCKS5 outbound для RU-ресурсов                                                   |
| **Opera Proxy**     | Локальный SOCKS5 outbound для выбранных зарубежных сервисов                                 |
| **Tor**             | Локальный SOCKS5 outbound для `.onion` и отдельных Tor-сценариев                            |
| **BBR**             | TCP congestion control для более стабильной скорости                                        |
| **UFW**             | Открывает только нужные порты: SSH, 80, Reality, Hysteria2, панель и подписки               |
| **fail2ban**        | Базовая защита от перебора                                                                  |

## Маршрутизация

| Трафик                                   | Куда отправляется                                      |
| ---------------------------------------- | ------------------------------------------------------ |
| Реклама и вредоносные домены             | `blocked`                                              |
| RU-домены `.ru`, `.su`, `.рф` и RU GeoIP | `warp`, чтобы не светить IP сервера перед RU-ресурсами |
| `.onion`, `check.torproject.org`         | `tor`                                                  |
| Disney+, Reddit                          | `opera`                                                |
| Всё остальное                            | `direct`                                               |

GeoIP/GeoSite для клиентов Happ подписки берутся из [roscomvpn-routing](https://github.com/hydraponique/roscomvpn-routing).

## Требования

- Debian 12+ или Ubuntu 22.04+.
- Root-доступ по SSH.
- Домен, A-запись которого указывает на IP сервера.
- Доступные порты: `80/tcp`, порт VLESS Reality (`443/tcp` по умолчанию), порт Hysteria2 (`63000/udp` по умолчанию), порт панели и порт подписок.

## Где взять VPS

Для установки подойдёт любой чистый VPS на Debian или Ubuntu. Если нужен быстрый старт без долгого выбора провайдера, можно взять сервер в VDSina:

**VDSina** — удобный вариант для личного VPN: быстрое создание VPS, root-доступ по SSH, понятная панель управления и тарифы, которых достаточно для домашнего использования 3x-ui. К тому же, при регистрации по [этой ссылке](https://www.vdsina.com/?partner=2c17h7h887kr) вы получите скидку 10% на оплату.

[Создать VPS в VDSina](https://www.vdsina.com/?partner=2c17h7h887kr)

## Где взять домен

Домен нужен для Let's Encrypt сертификата и SNI маскировки Reality. Можно взять бесплатно:

### DuckDNS

**DuckDNS** — бесплатный динамический DNS, идеален для личной инфраструктуры. Регистрация за минуту, настройка A-записи элементарна, работает со статическим IP и с динамическим (если меняется):

1. Перейти на [duckdns.org](https://www.duckdns.org/)
2. Авторизоваться (через Google, GitHub или другие)
3. Создать домен, например `myvpn.duckdns.org`
4. Указать IP сервера в управлении доменом
5. A-запись будет активна за несколько секунд

[Создать домен в DuckDNS](https://www.duckdns.org/)

### isroot.in

**isroot.in** — ещё один вариант бесплатного динамического DNS с простой настройкой. Поддерживает статические IP:

1. Перейти на [isroot.in](https://isroot.in/)
2. Создать аккаунт
3. Добавить домен и указать ваш IP
4. DNS активируется за несколько секунд

[Создать домен в isroot.in](https://isroot.in/)

## Способы установки

### Прямо на сервере

Этот вариант удобен, если вы уже зашли на VPS по SSH и хотите установить всё без локального деплоя.

```bash
ssh root@<IP>
apt-get update && apt-get install -y git
git clone https://github.com/AppsGanin/3xui-fast-install/3xui-personal
cd 3xui-personal
```

Минимальный запуск, домен будет запрошен интерактивно:

```bash
bash install.sh
```

Запуск без интерактива:

```bash
DOMAIN=vpn.example.com bash install.sh
```

С кастомными портами VPN:

```bash
DOMAIN=vpn.example.com \
VLESS_PORT=8443 \
HY2_PORT=63001 \
bash install.sh
```

`install.sh` запускает `steps/setup.sh` на текущем сервере, создаёт первого клиента, показывает прогресс и после завершения выводит содержимое `/root/3xui-credentials.txt`.

### С локальной машины через SSH (Linux/Mac/WSL)

Минимальный запуск, домен будет запрошен интерактивно:

```bash
bash deploy.sh <IP>
```

Запуск без интерактива:

```bash
DOMAIN=vpn.example.com bash deploy.sh <IP>
```

С SSH-ключом:

```bash
DOMAIN=vpn.example.com bash deploy.sh <IP> -i ~/.ssh/id_rsa
```

С нестандартным SSH-портом:

```bash
SSH_PORT=2222 DOMAIN=vpn.example.com bash deploy.sh <IP>
```

С кастомными портами VPN:

```bash
DOMAIN=vpn.example.com \
VLESS_PORT=8443 \
HY2_PORT=63001 \
bash deploy.sh <IP>
```

`deploy.sh` копирует `steps/` на сервер, запускает `setup.sh`, создаёт первого клиента, показывает прогресс и после завершения выводит содержимое `/root/3xui-credentials.txt`.

## После установки

- Панель: `https://<DOMAIN>:<PANEL_PORT>/<PANEL_PATH>/`
- Подписка первого клиента: `https://<DOMAIN>:<SUB_PORT><SUB_PATH>/<CLIENT_SUB_ID>`
- VLESS Reality: `<VLESS_PORT>/tcp`, по умолчанию `443/tcp`
- Hysteria2: `<HY2_PORT>/udp`, по умолчанию `63000/udp`
- Лог установки: `/root/3xui-install.log`
- Полный лог установки: `/root/3xui-install-full.log`
- Доступы: `/root/3xui-credentials.txt`
- Контейнер 3x-ui: `docker compose -f /root/docker-compose.yml [start|stop|restart|logs]`

## Backup и restore

Создать бекап:

```bash
bash backup.sh <IP>
```

С ключом, нестандартным SSH-портом или своей локальной папкой:

```bash
bash backup.sh <IP> -i ~/.ssh/id_rsa
SSH_PORT=2222 bash backup.sh <IP>
BACKUP_DIR=~/my-backups bash backup.sh <IP>
```

Восстановить сервер из архива:

```bash
bash restore.sh <IP> backups/backup_1.2.3.4_20260508_120000.tar.gz
bash restore.sh <IP> backups/backup_*.tar.gz -i ~/.ssh/id_rsa
```

Архив содержит базу 3x-ui, сертификаты, docker-compose файлы, Caddy-конфиг, статические файлы маскировки и файл доступов.

## Переменные окружения

Все ключевые параметры можно переопределить перед запуском `install.sh` или `deploy.sh`. Если переменная не задана, `steps/_lib.sh` подставит дефолт.

| Переменная         | По умолчанию | Описание                             |
| ------------------ | ------------ | ------------------------------------ |
| `DOMAIN`           | —            | Домен для Reality SNI и сертификата  |
| `PANEL_PORT`       | `60000`      | Порт панели 3x-ui                    |
| `PANEL_USER`       | `admin`      | Логин панели                         |
| `PANEL_PASS`       | случайный    | Пароль панели                        |
| `PANEL_PATH`       | случайный    | URL-путь панели                      |
| `SUB_PORT`         | `60001`      | Порт подписок                        |
| `SUB_PATH`         | `/subs/`     | URL-путь подписок                    |
| `SUB_TITLE`        | домен        | Название подписки                    |
| `CLIENT_EMAIL`     | случайный    | Имя автоматически созданного клиента |
| `CLIENT_UUID`      | случайный    | UUID VLESS-клиента                   |
| `CLIENT_SUB_ID`    | случайный    | ID персональной подписки             |
| `CLIENT_HY2_AUTH`  | случайный    | Auth-пароль Hysteria2-клиента        |
| `VLESS_PORT`       | `443`        | Порт VLESS Reality                   |
| `HY2_PORT`         | `63000`      | Порт Hysteria2 UDP                   |
| `WARP_PROXY_PORT`  | `40000`      | SOCKS5-порт WARP на localhost        |
| `OPERA_PROXY_PORT` | `40001`      | SOCKS5-порт Opera Proxy на localhost |
| `OPERA_COUNTRY`    | `EU`         | Регион Opera Proxy                   |
| `TOR_PORT`         | `40002`      | SOCKS5-порт Tor на localhost         |
| `XRAY_API_PORT`    | `62789`      | Порт Xray API на localhost           |
| `XUI_DIR`          | `/root`      | Директория данных 3x-ui на сервере   |
| `SSH_PORT`         | `22`         | SSH-порт сервера                     |
| `SSH_USER`         | `root`       | SSH-пользователь                     |
| `BACKUP_DIR`       | `./backups`  | Локальная папка для бекапов          |

Пример с кастомными параметрами:

```bash
DOMAIN=vpn.example.com \
PANEL_PORT=60010 \
PANEL_PASS=MySecretPass \
VLESS_PORT=8443 \
HY2_PORT=63001 \
OPERA_COUNTRY=US \
bash install.sh
```

Пример с фиксированным именем клиента и ID подписки:

```bash
DOMAIN=vpn.example.com \
CLIENT_EMAIL=phone \
CLIENT_SUB_ID=phone2026 \
bash install.sh
```

## Структура проекта

```text
├── install.sh          # Установка прямо на сервере
├── deploy.sh           # Деплой с локальной машины
├── backup.sh           # Резервное копирование
├── restore.sh          # Восстановление из бекапа
├── backups/            # Локальные бекапы, в .gitignore
├── scripts/
│   └── local_lib.sh    # Общие функции deploy/backup/restore
└── steps/
    ├── setup.sh        # Оркестратор установки
    ├── _lib.sh         # Общие функции и дефолты env
    ├── prereqs.sh      # Системные зависимости
    ├── bbr.sh          # BBR
    ├── ufw.sh          # UFW firewall
    ├── warp.sh         # Cloudflare WARP
    ├── opera-proxy.sh  # Opera Proxy
    ├── tor.sh          # Tor
    ├── docker.sh       # Docker
    ├── fail2ban.sh     # fail2ban
    ├── selfsteal.sh    # Caddy selfsteal и Let's Encrypt
    └── xui.sh          # 3x-ui, Reality-ключи, Xray config, БД
```
