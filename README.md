# 3x-ui Personal VPN Setup

Автоматизированная установка личного VPN-сервера. Разворачивает [3x-ui](https://github.com/MHSanaei/3x-ui) с VLESS Reality, Hysteria2, Cloudflare WARP, Opera Proxy, Tor, selfsteal Caddy и автоматической настройкой всей маршрутизации.

## Что устанавливается

| Компонент           | Описание                                                                                         |
| ------------------- | ------------------------------------------------------------------------------------------------ |
| **3x-ui**           | Панель управления Xray (Docker), VLESS Reality на 443 + Hysteria2 на 63000                       |
| **VLESS + Reality** | Транспорт поверх TLS, маскируется под легитимный домен                                           |
| **Hysteria2**       | UDP-протокол поверх TLS, маскировка под Twitch, быстрее на потерях — особенно на мобильных сетях |
| **Caddy selfsteal** | TLS-терминатор на 443 → 9443, выдаёт Let's Encrypt сертификат                                    |
| **Cloudflare WARP** | SOCKS5-прокси для RU-сайтов (геоблоки, реестр Роскомнадзора)                                     |
| **Opera Proxy**     | SOCKS5-прокси для зарубежных сервисов (Disney+, Reddit и др.)                                    |
| **Tor**             | SOCKS5-прокси для .onion и анонимного трафика                                                    |
| **BBR**             | Алгоритм контроля перегрузки TCP — ускоряет соединение                                           |
| **UFW**             | Фаервол: открыты 22/80/443/UDP:63000 + порты панели и подписок                                   |
| **fail2ban**        | Защита от перебора паролей                                                                       |

## Маршрутизация трафика (Xray)

| Трафик                                    | Outbound                                                       |
| ----------------------------------------- | -------------------------------------------------------------- |
| Реклама, вредоносные домены               | `blocked`                                                      |
| RU-домены (.ru, .su, .рф), IP из RU GeoIP | `warp` (WARP) — чтобы не светить IP сервера перед RU-ресурсами |
| .onion, check.torproject.org              | `tor` — добавлены для примера, настройте под себя              |
| Disney+, Reddit                           | `opera` — добавлены для примера, настройте под себя            |
| Всё остальное                             | `direct`                                                       |

GeoIP/GeoSite для клиентов Happ подписки берутся из [roscomvpn-routing](https://github.com/hydraponique/roscomvpn-routing).

## Требования

- VPS с Debian/Ubuntu, root-доступ по SSH (пользователь root)
- Версии: Debian 12+ / Ubuntu 22.04+
- Домен с A-записью, направленной на IP сервера
- Открытые порты: **80** (Let's Encrypt), **443** (Reality), **63000/UDP** (Hysteria2)

Рекомендуемый провайдер: [https://www.vdsina.com](https://www.vdsina.com/?partner=nmzki7z7tu)

## Быстрый старт

### С локальной машины (через deploy.sh)

```bash
git clone https://github.com/AppsGanin/3xui-fast-install/3xui-personal
cd 3xui-personal

bash deploy.sh 1.2.3.4
```

По окончании скрипт выведет URL панели, логин и пароль.

Для установки через ИИ-агента см. [AI_INSTALL.md](AI_INSTALL.md).

---

## Скрипты

### `deploy.sh` — установка с локальной машины

Копирует скрипты на сервер, запускает `setup.sh` и показывает отфильтрованный лог прогресса. При Ctrl+C — останавливает установку на сервере.

```bash
# Минимальный (спросит домен интерактивно)
bash deploy.sh <IP>

# С доменом
DOMAIN=vpn.example.com bash deploy.sh <IP>

# Со своим SSH-ключом
DOMAIN=vpn.example.com bash deploy.sh <IP> -i ~/.ssh/id_rsa

# Нестандартный SSH-порт
SSH_PORT=2222 DOMAIN=vpn.example.com bash deploy.sh <IP>
```

После завершения выводит содержимое `/root/3xui-credentials.txt`.

---

### `backup.sh` — резервное копирование

Останавливает контейнер, создаёт архив на сервере, скачивает локально в `backups/`.

```bash
bash backup.sh <IP>

# С ключом / нестандартным портом
bash backup.sh <IP> -i ~/.ssh/id_rsa
SSH_PORT=2222 bash backup.sh <IP>

# Своя папка для бекапов
BACKUP_DIR=~/my-backups bash backup.sh <IP>
```

Архив содержит:

- `db/x-ui.db` — база 3x-ui (inbounds, клиенты, настройки панели)
- `cert/ssl/` — TLS-сертификаты
- `docker-compose.yml` — конфиг контейнера 3x-ui
- `caddy/Caddyfile` — конфиг selfsteal
- `caddy/.env` — переменные окружения Caddy
- `caddy/docker-compose.yml` — конфиг контейнера Caddy
- `caddy/html/` — статические файлы сайта-маскировки
- `3xui-credentials.txt` — URL, логин, пароль

---

### `restore.sh` — восстановление из бекапа

Загружает архив на сервер, останавливает контейнеры, восстанавливает данные, поднимает всё обратно.

```bash
bash restore.sh <IP> backups/backup_1.2.3.4_20260508_120000.tar.gz

# С ключом
bash restore.sh <IP> backups/backup_*.tar.gz -i ~/.ssh/id_rsa
```

Перед восстановлением запросит подтверждение.

---

## Переменные окружения

Все параметры имеют значения по умолчанию и могут быть переопределены:

| Переменная         | По умолчанию   | Описание                            |
| ------------------ | -------------- | ----------------------------------- |
| `DOMAIN`           | — (обязателен) | Домен для Reality SNI и сертификата |
| `PANEL_PORT`       | `60000`        | Порт панели 3x-ui                   |
| `PANEL_USER`       | `admin`        | Логин панели                        |
| `PANEL_PASS`       | случайный      | Пароль панели                       |
| `PANEL_PATH`       | случайный      | URL-путь панели                     |
| `SUB_PORT`         | `60001`        | Порт подписок                       |
| `SUB_PATH`         | `/subs/`       | URL-путь подписок                   |
| `SUB_TITLE`        | домен          | Название подписки                   |
| `WARP_PROXY_PORT`  | `40000`        | SOCKS5-порт WARP (localhost)        |
| `OPERA_PROXY_PORT` | `40001`        | SOCKS5-порт Opera Proxy (localhost) |
| `OPERA_COUNTRY`    | `EU`           | Регион Opera Proxy                  |
| `TOR_PORT`         | `40002`        | SOCKS5-порт Tor (localhost)         |
| `XRAY_API_PORT`    | `62789`        | Порт Xray API (localhost)           |
| `HY2_PORT`         | `63000`        | Порт Hysteria2 (UDP)                |
| `XUI_DIR`          | `/root`        | Директория данных 3x-ui на сервере  |
| `SSH_PORT`         | `22`           | SSH-порт сервера                    |
| `SSH_USER`         | `root`         | SSH-пользователь                    |
| `BACKUP_DIR`       | `./backups`    | Локальная папка для бекапов         |

Пример с кастомными параметрами:

```bash
DOMAIN=vpn.example.com \
PANEL_PORT=8443 \
PANEL_PASS=MySecretPass \
OPERA_COUNTRY=US \
bash deploy.sh 1.2.3.4
```

---

## Структура проекта

```
├── deploy.sh           # Деплой с локальной машины
├── backup.sh           # Резервное копирование
├── restore.sh          # Восстановление из бекапа
├── backups/            # Локальные бекапы (в .gitignore)
├── scripts/
│   └── local_lib.sh    # Общие функции локальных deploy/backup/restore
└── steps/
    ├── prereqs.sh      # Установка зависимостей (curl, python3, ca-certificates и др.)
    ├── setup.sh        # Оркестратор — запускает шаги по порядку
    ├── _lib.sh         # Общие функции, переменные с дефолтами
    ├── bbr.sh          # Включение BBR congestion control
    ├── ufw.sh          # Настройка UFW фаервола
    ├── warp.sh         # Установка Cloudflare WARP
    ├── opera-proxy.sh  # Установка Opera Proxy
    ├── tor.sh          # Установка Tor
    ├── fail2ban.sh     # Установка fail2ban
    ├── docker.sh       # Установка Docker
    ├── selfsteal.sh    # Caddy selfsteal + Let's Encrypt
    └── xui.sh          # 3x-ui, Reality-ключи, Xray config, БД
```

---

## После установки

- Войти в панель: `https://<DOMAIN>:<PANEL_PORT>/<PANEL_PATH>/`
- В панели уже настроены два inbound'а:
  - **VLESS Reality** — порт 443/TCP
  - **Hysteria2** — порт 63000/UDP, маскировка под Twitch, TLS на сертификате домена
- Подписки: `https://<DOMAIN>:<SUB_PORT>/subs/<UUID>`
- Управление контейнером: `docker compose -f /root/docker-compose.yml [start|stop|restart|logs]`
- Лог установки: `/root/3xui-install.log`
- Доступы: `/root/3xui-credentials.txt`
