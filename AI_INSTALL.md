# Инструкция для ИИ-агента: установка 3x-ui fast install на VPS

Эта инструкция предназначена для ИИ-агента, который помогает пользователю установить проект на VPS. Агент должен действовать аккуратно: сначала проверить входные данные и окружение, затем запустить установку через `deploy.sh`, после ошибки читать логи и исправлять конкретную причину.

## Входные данные

Попроси у пользователя или найди в контексте:

- IP сервера: например `1.2.3.4`
- Домен: например `vpn.example.com`
- SSH-пользователь: обычно `root`
- SSH-порт: обычно `22`
- SSH-ключ, если нужен: например `-i ~/.ssh/id_rsa`

Требования к серверу:

- Debian 12+ или Ubuntu 22.04+
- root-доступ по SSH
- A-запись домена указывает на IP сервера
- открыты порты `22/tcp`, `80/tcp`, `443/tcp`, `63000/udp`

## Правила безопасности

- Не отключай SSH host key checking глобально.
- Если SSH сообщает `REMOTE HOST IDENTIFICATION HAS CHANGED`, не игнорируй это. Спроси пользователя, переустанавливался ли сервер. Если да, удали старый ключ командой:

```bash
ssh-keygen -R <IP>
```

- Не печатай пароль панели в публичный чат или лог, если пользователь не просит.
- Не запускай `git reset --hard`, `rm -rf`, очистку сервера или переустановку ОС без явного подтверждения.
- Если установка уже частично прошла, сначала прочитай логи и состояние контейнеров, а не запускай всё заново вслепую.

## Проверки перед запуском

Проверь локально:

```bash
bash -n deploy.sh backup.sh restore.sh scripts/local_lib.sh
bash -n steps/*.sh
```

Проверь SSH:

```bash
ssh root@<IP> 'echo ok'
```

Проверь DNS:

```bash
dig +short A <DOMAIN>
```

Если `dig` недоступен локально, можно проверить на сервере после подключения:

```bash
getent ahosts <DOMAIN>
```

## Основной запуск

Рекомендуемый неинтерактивный запуск:

```bash
DOMAIN=<DOMAIN> bash deploy.sh <IP>
```

Со своим ключом:

```bash
DOMAIN=<DOMAIN> bash deploy.sh <IP> -i ~/.ssh/id_rsa
```

С нестандартным SSH-портом:

```bash
SSH_PORT=2222 DOMAIN=<DOMAIN> bash deploy.sh <IP>
```

После успешной установки `deploy.sh` должен вывести содержимое:

```bash
/root/3xui-credentials.txt
```

## Что считается успехом

На сервере должны быть:

```bash
docker ps
```

Ожидаемые контейнеры:

- `caddy-selfsteal`
- `3xui_app`

Файлы:

- `/root/3xui-credentials.txt`
- `/root/3xui-install.log`
- `/root/3xui-install-full.log`
- `/root/docker-compose.yml`
- `/root/cert/ssl/fullchain.pem`
- `/root/cert/ssl/privkey.pem`

Панель:

```text
https://<DOMAIN>:60000/<PANEL_PATH>/
```

## Диагностика ошибок

Если `deploy.sh` упал, прочитай полный лог:

```bash
ssh root@<IP> 'tail -n 200 /root/3xui-install-full.log'
```

И краткий лог:

```bash
ssh root@<IP> 'cat /root/3xui-install.log'
```

Проверь контейнеры:

```bash
ssh root@<IP> 'docker ps -a'
```

Проверь сервисы:

```bash
ssh root@<IP> 'systemctl --no-pager status docker warp-svc opera-proxy tor fail2ban'
```

Проверь firewall:

```bash
ssh root@<IP> 'ufw status verbose'
```

## Частые проблемы

### SSH host key changed

Симптом:

```text
REMOTE HOST IDENTIFICATION HAS CHANGED
Host key verification failed.
```

Если пользователь подтверждает, что сервер был переустановлен:

```bash
ssh-keygen -R <IP>
DOMAIN=<DOMAIN> bash deploy.sh <IP>
```

### DNS не указывает на сервер

Симптом в логе:

```text
DNS для <DOMAIN> указывает на <OLD_IP>, а не на этот сервер
```

Действия:

1. Попроси пользователя исправить A-запись домена.
2. Дождись обновления DNS.
3. Повтори:

```bash
DOMAIN=<DOMAIN> bash deploy.sh <IP>
```

### Selfsteal падает без подробной ошибки

Симптом:

```text
[SELFSTEAL] ❌ Script terminated with error code: 1
```

Действия:

1. Убедись, что в `steps/selfsteal.sh` внешний installer запускается с `--debug`.
2. Скопируй актуальный шаг на сервер:

```bash
scp steps/_lib.sh steps/selfsteal.sh root@<IP>:/root/3xui-setup/
```

3. Повтори только selfsteal:

```bash
ssh root@<IP> 'DOMAIN=<DOMAIN> bash /root/3xui-setup/selfsteal.sh'
```

4. Если selfsteal прошёл, продолжи установку с шага `xui.sh` или перезапусти `deploy.sh`.

### Сертификат не выдан

Симптом:

```text
Caddy не получил сертификат за 180 секунд
```

Проверь:

```bash
ssh root@<IP> 'docker logs --tail 80 caddy-selfsteal'
ssh root@<IP> 'ufw status verbose'
dig +short A <DOMAIN>
```

Частые причины:

- порт `80/tcp` закрыт у провайдера или firewall
- DNS ещё не обновился
- домен указывает не на этот IP
- превышен rate limit Let's Encrypt

### 3x-ui не стартует

Проверь:

```bash
ssh root@<IP> 'docker compose -f /root/docker-compose.yml ps'
ssh root@<IP> 'docker compose -f /root/docker-compose.yml logs --tail 120'
```

Если нет БД:

```bash
ssh root@<IP> 'ls -la /root/db /root/db/x-ui.db'
```

## Продолжение после частичного успеха

Если предыдущие шаги уже прошли и упал только финальный шаг `3x-ui`, можно синхронизировать актуальные файлы и запустить только `xui.sh`:

```bash
scp steps/_lib.sh steps/xui.sh root@<IP>:/root/3xui-setup/
ssh root@<IP> 'DOMAIN=<DOMAIN> bash /root/3xui-setup/xui.sh'
```

После ручного запуска `xui.sh` проверь, что существует файл доступов:

```bash
ssh root@<IP> 'cat /root/3xui-credentials.txt'
```

Если файла нет, лучше перезапустить полный `deploy.sh`, потому что именно `setup.sh` создаёт `/root/3xui-credentials.txt` после всех шагов.

## Финальный отчёт пользователю

В конце сообщи коротко:

- установка завершена или где остановилась
- URL панели
- где лежит файл доступов
- какие проверки выполнены

Не вставляй пароль панели в ответ, если пользователь не просил явно.
