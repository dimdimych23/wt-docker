# WebSoft HCM (WebTutor) — Minimal DevSuite (Docker)

Минимальная сборка WebSoft HCM (WebTutor) для локальной разработки:  
**Nginx → WebRole(2) → WorkerRole(1) + Redis** и опционально **Postgres** (включается профилем).  
Без MinIO/бакетов, без мониторинга — только то, что нужно, чтобы система поднялась и работала.

---

## Состав

- **nginx-proxy** — внешний HTTPS-прокси/балансировщик
- **web-backend-1, web-backend-2** — WebRole (порт 8011 внутри контейнера)
- **worker-backend** — WorkerRole
- **redis** — кеш/кластерация (с паролем)
- **postgres** — опционально (локальная БД; включается профилем `local-postgres`)

---

## Требования

- Linux (любая современная x86_64, ядро ≥ 5.x)
- Docker ≥ 24, Docker Compose v2
- Открытые порты на хосте: 80, 443 (и, при желании, 81 для прямого доступа к воркеру через Nginx)
- Права записи в рабочий каталог проекта

---

## Структура каталогов

```
wt-docker/
├─ docker-compose.yml
├─ .env
├─ nginx-proxy/
│  ├─ nginx.conf.template
│  └─ init-nginx.sh
├─ websoft/
│  ├─ configs/
│  │  ├─ common/
│  │  │  ├─ spxml_unibridge_config.xml.template
│  │  │  ├─ init-spxml.sh
│  │  │  ├─ wait-pg.sh
│  │  │  ├─ xHttp.ini
│  │  │  ├─ license.xfpx
│  │  │  └─ resource_sec.json
│  │  ├─ web-backend/xhttp_config.json
│  │  └─ worker-backend/xhttp_config.json
│  ├─ runtimes/
│  │  ├─ web-backend/{platform,components}
│  │  └─ worker-backend/{platform,components}
│  ├─ wt_data/
│  ├─ applications/
│  ├─ web/
│  │  └─ webtutor/{web-backend-1,web-backend-2,worker-backend}
│  └─ Logs/
└─ certs/
│  └─ wt/ # PEM/KEY для Nginx
└─ postgres/
│  └─ init.sql
└─ redis/
```

> **Внимание по `runtimes/`:** если эти папки пустые на хосте, они перекрывают содержимое образа, и платформа не найдёт стандартные модули (`wtv_view_main.xml`). Либо заполните их из образа, либо временно уберите bind-mount’ы.

---

## Быстрый старт

### 1. Сертификаты для nginx-proxy

Для dev можно использовать самоподписанные сертификаты.

#### Вариант A — mkcert

```sh
sudo apt-get install -y libnss3-tools
curl -sSL https://dl.filippo.io/mkcert/latest?for=linux/amd64 | sudo tar -C /usr/local/bin -xz mkcert
mkcert -install

mkdir -p ./certs/wt
cd ./certs/wt
mkcert wt.local
# создаст: wt.local.pem и wt.local-key.pem
```

Затем укажите имена в `.env`:

```
WT_CERTS_DIR=./certs/wt
NGINX_CERT_WT_CRT=wt.local.pem
NGINX_CERT_WT_KEY=wt.local-key.pem
PUBLIC_FQDN__WEB=wt.local
```

#### Вариант B — openssl

```sh
mkdir -p ./certs/wt
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout ./certs/wt/wt.local-key.pem \
  -out    ./certs/wt/wt.local.pem \
  -subj "/CN=wt.local"
```

Добавьте `wt.local` в `/etc/hosts`:

```
127.0.0.1 wt.local
::1       wt.local
```

---

### 2. Настройте `.env`

Минимум, что нужно проверить/поменять:

```env
# Домены/серты
PUBLIC_FQDN__WEB=wt.local
WT_CERTS_DIR=./certs/wt
NGINX_CERT_WT_CRT=wt.local.pem
NGINX_CERT_WT_KEY=wt.local-key.pem

# Redis (включена авторизация)
HOST_NAME__REDIS=redis
HOST_PORT__REDIS=6379
PASSWORD__REDIS=super_secret_password
OPTS__REDIS=abortConnect=false, allowAdmin=true, connectTimeout=5000, keepAlive=10, syncTimeout=1000

# База (внешний Postgres ИЛИ локальный профилем)
HOST_NAME__PG=postgres
HOST_PORT__PG=5432
DB_NAME__PG=wt
DB_USER__PG=wt
DB_PASSWORD__PG=wt_password
```

> Пароль Redis уже включён в шаблон SPXML (`password=${PASSWORD__REDIS}`), а сервер Redis стартует с `--requirepass` — этого достаточно.

---

### 3. Запустите

- **С внешним Postgres (без профиля):**
  ```sh
  docker compose up -d
  ```

- **С локальным Postgres (включаем профиль):**
  ```sh
  docker compose --profile local-postgres up -d
  ```

#### Проверка

```sh
docker ps
curl -I https://wt.local/default
docker logs wt-docker-web-backend-1 | tail -n +1
```

#### Остановка

```sh
docker compose down
# или только локальную БД:
docker compose --profile local-postgres down
```

---

## Как это работает (важные нюансы)

### 1. Профиль `local-postgres`

- Сервис postgres помечен профилем и не обязателен.
- Не добавляйте `depends_on: postgres` к web/worker — без профиля это ломает запуск.
- Web/Worker сами ждут БД через `wait-pg.sh` (настройки в `.env`).

### 2. Redis с паролем

- Сервер поднимается с `--requirepass ${PASSWORD__REDIS}`.
- Клиенты (Web/Worker) берут пароль из шаблона SPXML:
  ```xml
  <add key="DistributedCacheConfig" value="${HOST_NAME__REDIS}:${HOST_PORT__REDIS}, password=${PASSWORD__REDIS}, ${OPTS__REDIS}" />
  ```
- Healthcheck Redis выполняется как `redis-cli -a "$PASSWORD__REDIS" PING`.

**Проверка вручную:**
```sh
docker exec -it wt-docker-redis-1 redis-cli -a "$PASSWORD__REDIS" PING
# PONG
```

### 3. Шаги запуска внутри web/worker

Команда контейнера:
```sh
/bin/sh -lc "sh /WebsoftServer/wait-pg.sh && sh /WebsoftServer/init-spxml.sh && exec /WebsoftServer/xhttp.out"
```
1. ждём доступности PG,
2. рендерим `spxml_unibridge_config.xml` из шаблона,
3. запускаем основной бинарь `xhttp.out`.

### 4. VFS и Lucene

- FT-индексы и данные хранятся в бинд-каталогах:
  ```
  ./websoft/wt_data  -> /WebsoftServer/wt_data
  ./websoft/Logs/... -> /WebsoftServer/Logs
  ```
- В SPXML `SharedFTDirectory` указывает на `/WebsoftServer/ft-idx/`.  
  Если требуется отдельный каталог индексов, добавьте bind-mount в compose и обновите шаблон.

### 5. Runtimes (platform.runtime / components.runtime)

- Если хотите хранить рантаймы на хосте, предварительно заполните каталоги содержимым из образа:
  ```sh
  mkdir -p ./websoft/runtimes/web-backend/{platform,components}
  CID=$(docker create websoft/hcm:2025.2.1212)
  docker cp $CID:/WebsoftServer/platform.runtime/.   ./websoft/runtimes/web-backend/platform/
  docker cp $CID:/WebsoftServer/components.runtime/. ./websoft/runtimes/web-backend/components/
  docker rm $CID
  ```
- Иначе просто уберите соответствующие bind-mount’ы — образ содержит нужные файлы.

---

## Частые проблемы и решения

### 400/404 на портале сразу после запуска

- Проверьте, что рантаймы не пустые (см. раздел про runtimes/).
- Убедитесь, что `xhttp_config.json` содержит разрешённый AllowedHosts и корректный порт.

### Error loading document x-local://wtv/wtv_view_main.xml

- Один в один симптом пустых `platform.runtime/components.runtime`.  
  Уберите bind-mount’ы или заполните директории.

### Поднялся Redis, но клиенты не коннектятся (NOAUTH/WRONGPASS)

- Проверьте, что в SPXML в `DistributedCacheConfig` есть `password=...`.
- Убедитесь, что пароль совпадает с `--requirepass` в redis.

### Permission denied при запуске скриптов

- Мы вызываем их через `sh /path/script.sh`, поэтому execute-бит не обязателен.
- Но убедитесь, что в файлах Unix-переводы строк (LF), иначе `/bin/sh` может падать:
  ```sh
  sed -i 's/\r$//' websoft/configs/common/*.sh
  ```

### Профиль Postgres выключен, а web/worker всё равно ждут БД

- Это нормально: `wait-pg.sh` ждёт адрес `HOST_NAME__PG:HOST_PORT__PG`.  
  Если БД внешняя — выставьте реальные значения, иначе поставьте `PG_WAIT_ON_TIMEOUT=skip`.

---

## Обновление/пересоздание

**Перечитать конфиги после правок `.env` или шаблонов:**
```sh
docker compose up -d --force-recreate redis web-backend-1 web-backend-2 worker-backend
```

**Полная очистка локальной БД (если включали профиль):**
```sh
docker compose --profile local-postgres down -v
# удалит том postgres-data
```

---

## Лицензии и безопасность

- Тестовые пароли и сертификаты годятся только для локального контура.
- Для продакшена используйте менеджер секретов (Docker Secrets / Vault), валидные сертификаты и закрытые сети/ACL.
- Redis без TLS аутентифицируется паролем — не публикуйте порт за пределы docker-сети.

---

## Поддержка

- Вопросы по конфигурации SPXML/xHttp — в каталоге `websoft/configs/*`.
- Логи: `./websoft/Logs/<service>` и `docker logs <container>`.
- Если понадобятся MinIO/мониторинг — используйте другой compose-

### clear-logs.sh
Скрипт для очистки примонтированных логов (web-backend-1, web-backend-2, worker-backend).  
Запуск:
```bash
./websoft/configs/common/clear-logs.sh
```

# Кастомные образы WebSoft HCM и публикация


## Зачем

Мы собираем собственный Docker-образ на базе официального websoft/hcm:* и накладываем дополнительные/обновлённые компоненты из каталога websoft/components.src/. Это даёт повторяемость и одинаковый состав на всех нодах (web1, web2, worker).


## Где лежит логика сборки

•	`Dockerfile.hcm` — рецепт образа (COPY поверх базовых компонентов + OCI-лейблы).
•	`tools/build-image.sh` — единая команда сборки/пуша (читается .env.build).
•	`.env.build` — все параметры сборки/публикации и описания образа (без хардкода).
•	`websoft/components.src/` — **распакованные** папки доп. компонентов (overlay).


## Быстрый старт (локальная сборка)


```bash
./tools/build-image.sh
# итоговый образ: <IMAGE_REPO>:<IMAGE_TAG>
# WT_IMAGE в .env можно обновить вручную при необходимости
```
