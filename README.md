# WebSoft HCM (WebTutor) — Minimal DevSuite (Docker)

Минимальная сборка WebSoft HCM (WebTutor) для локальной разработки:  
**Nginx → WebRole(2) → WorkerRole(1) + Redis** и опционально **Postgres** (включается профилем).  
Мониторинг (по желанию): **Promtail → Loki → Grafana**. Без MinIO/бакетов.

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

> **Внимание по `runtimes/`:** возможно потребуется монтировать на каждую ноду отдельные папки рантаймов, до конца не разобрался как они заполняются.

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
  ./websoft/wt_data      -> /WebsoftServer/wt_data
  ./websoft/Logs/...     -> /WebsoftServer/Logs
  ./websoft/web/webtutor -> /WebsoftServer/wt/web/webtutor
  ./websoft/ft-idx       -> /WebsoftServer/ft-idx
  ```
- В SPXML `SharedFTDirectory` указывает на `/WebsoftServer/ft-idx/`.  

## Частые проблемы и решения

### 400/404 на портале сразу после запуска

- Убедитесь, что `xhttp_config.json` содержит разрешённый AllowedHosts и корректный порт.

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
Если понадобятся бакеты S3/MinIO — это отдельная сборка; в текущей используются mounts/шары и Promtail.

### clear-logs.sh
Скрипт для очистки примонтированных логов (web-backend-1, web-backend-2, worker-backend).  
Запуск:
```bash
./websoft/configs/common/clear-logs.sh
```

# Кастомные образы WebSoft HCM и публикация

У нас есть Docker-реестр: nexus.company.com:5001.
Работаем нативно через docker login / tag / push / pull.

## Зачем

Мы собираем собственный Docker-образ на базе официального websoft/hcm:* и накладываем дополнительные/обновлённые компоненты из каталога websoft/components.src/. Это даёт повторяемость и одинаковый состав на всех нодах (web1, web2, worker).


## Где лежит логика сборки

-	`Dockerfile.hcm` — рецепт образа (COPY поверх базовых компонентов + OCI-лейблы).
-	`tools/build-image.sh` — единая команда сборки/пуша (читается .env.build).
-	`.env.build` — все параметры сборки/публикации и описания образа (без хардкода).
-	`websoft/components.src/` — **распакованные** папки доп. компонентов (overlay).


## Быстрый старт (локальная сборка)

1) Необходимо указать переменные сборки в `.env.build` :
```ini
# куда пушим
REGISTRY_HOST=nexus.company.com:5001
REGISTRY_USER=<логин_в_Nexus>
REGISTRY_PASS=<пароль_в_Nexus>
PUSH=true

# как называем образ (namespace/name:tag)
IMAGE_REPO=websoft/hcm
IMAGE_TAG=2025.2.1225-company.1
```
2) Запуск:
```bash
# 1) сборка и публикация
./tools/build-image.sh

# 2) проверка, что образ в реестре, пример:
docker pull nexus.company.com:5001/websoft/hcm:2025.2.1225-company.1
```

Скрипт `tools/build-image.sh` прочитает `.env.build`, сделает docker login, соберёт образ и запушит его как
`nexus.company.com:5001/${IMAGE_REPO}:${IMAGE_TAG}`.

3) Можно раскатать по очереди:

```bash
docker compose up -d --no-deps web-backend-1
docker compose up -d --no-deps web-backend-2
docker compose up -d --no-deps worker-backend
```

**Важно**
-	Для Mac/ARM собираем под linux/amd64 (так настроено в .env.build: BUILD_PLATFORM=linux/amd64).
-	Тегируйте релизы кодом и образом синхронно (например, 2025.2.1225-company.N).
-	Состав оверлея компонентов фиксируется в `label` и в `/WebsoftServer/components.manifest.json` внутри образа.

## Использование в docker-compose

В `.env` (проекты, стенды):
```ini
IMAGE_WT=nexus.company.com:5001/websoft/hcm:2025.2.1225-company.1
```
# 
---


## Мониторинг: Promtail → Loki → Grafana

Эта сборка читает логи WebSoft HCM из **примонтированных каталогов/файловых шар** на хосте с помощью **Promtail**, отправляет их в **Loki**, а **Grafana** используется как UI для поиска и дашбордов. Никакого Logstash и S3/MinIO в этом варианте не требуется.

### Что уже сделано в compose
- Сервисы: `loki`, `promtail`, `grafana` (Grafana включается профилем `local-grafana`).
- Логи WebSoft примонтированы read-only в Promtail:
  - `./websoft/Logs/web-backend-1` → `/var/log/wt/web-backend-1`
  - `./websoft/Logs/web-backend-2` → `/var/log/wt/web-backend-2`
  - `./websoft/Logs/worker-backend` → `/var/log/wt/worker-backend`
- Автопровиженинг Grafana для источников/дашбордов подключён через каталоги:
  - `monitoring/grafana/provisioning/{datasources,dashboards}`
  - `monitoring/grafana/dashboards` (куда кладём JSON/NDJSON с дашбордами)

### Переменные окружения (из `.env`)
**MONITORING / promtail**
- `IMAGE_PROMTAIL` — образ Promtail.
- `LOKI_JOB_LABEL` — значение лейбла `job` для всех потоков (по умолчанию `websoft-hcm`).
- `PROMTAIL_MULTILINE_FIRSTLINE` — regex начала новой записи (по умолчанию `^\d{2}:\d{2}:\d{2}`).
- `PROMTAIL_MULTILINE_MAX_WAIT_TIME` — максимальная задержка ожидания следующей строки мультилайна (например, `3s`).
- `ENV_FALLBACK` — дефолтное окружение (например, `dev`). Используется, если его нельзя вывести из имени файла.

**MONITORING / loki**
- `IMAGE_LOKI`, `HOST_NAME__LOKI`, `HOST_PORT__LOKI` — образ и адрес Loki.
- Retention/тайминги:
  - `LOKI_RETENTION_PERIOD` — срок хранения данных в Loki (буфер поиска).
  - `LOKI_REJECT_OLD_SAMPLES_MAX_AGE` — максимальная давность принимаемых сообщений.
  - `LOKI_MAX_LOOK_BACK_PERIOD` — максимальная глубина поиска.
  - `LOKI_CHUNK_IDLE_PERIOD`, `LOKI_MAX_CHUNK_AGE`, `LOKI_CHUNK_RETAIN_PERIOD` — размер чанков vs задержка индексации.

**MONITORING / grafana**
- `IMAGE_GRAFANA`, `HOST_PORT__GRAFANA`, `GF_SECURITY_*`, `GF_USERS_ALLOW_SIGN_UP` — базовые настройки и доступ.

### Как запустить локально
```bash
# Loki + Promtail (обязательно) и локальная Grafana (по профилю)
docker compose --profile local-grafana up -d loki promtail grafana
```

Зайди в Grafana: **http://localhost:${HOST_PORT__GRAFANA}** (логин/пароль из `.env`).  
Datasource Loki создаётся через провижининг. Если менял провижининг — перезапусти Grafana:
```bash
docker compose restart grafana
```

### Как Promtail размечает логи
- **role** — имя верхнего каталога: `web-backend-1`, `web-backend-2`, `worker-backend`.
- **log_type** — из имени файла до суффикса даты:  
  `microsoft.aspnetcore.dataprotection.keymanagement.xmlkeymanager_2025-09-02.log` →  
  `log_type="microsoft.aspnetcore.dataprotection.keymanagement.xmlkeymanager"`
  ```
  auth-events_2025-09-02.log         -> log_type="auth-events"
  spxml_unibridge_2025-09-02.log     -> log_type="spxml_unibridge"
  xhttp_2025-09-02.log               -> log_type="xhttp"
  components_2025-09-03.log          -> log_type="components"
  ```
- **env** — берётся из `ENV_FALLBACK` (если захочешь — можно расширить извлечение из имени файла `wt_dev.*`, но сейчас это не требуется).
- **job** — равно `LOKI_JOB_LABEL` (например, `websoft-hcm`).
- **timestamp** — из времени в начале строки (мультилайн-регекс) + текущая дата файла, или задаётся самим Loki по времени приёма, если формат строки иной.

### Примеры запросов в Grafana (LogQL)
```logql
{job="${LOKI_JOB_LABEL}"}
{job="${LOKI_JOB_LABEL}", role="web-backend-1"} |= "Error"
{job="${LOKI_JOB_LABEL}", log_type="xhttp"}
{job="${LOKI_JOB_LABEL}"} |~ "^\d{2}:\d{2}:\d{2}\s+\[\d+\]"
```

### Типовая отладка
- Проверить готовность Loki:
  ```bash
  docker run --rm --network wt-net curlimages/curl:8.8.0 -sS http://loki:3100/ready
  # -> ready
  ```
- Посмотреть позиции чтения Promtail:
  ```
  docker exec -it wt-docker-promtail-1 cat /positions/positions.yaml
  ```
- Убедиться, что файлы видны внутри Promtail:
  ```
  docker exec -it wt-docker-promtail-1 ls -la /var/log/wt/web-backend-1
  ```

### Дашборды Grafana
- Клади JSON-дашборды в `monitoring/grafana/dashboards/`.
- Провижининг дашбордов/датасорсов — в `monitoring/grafana/provisioning/{dashboards,datasources}`.
- Перечитать провижининг без рестарта:
  ```bash
  curl -u "${GF_SECURITY_ADMIN_USER}:${GF_SECURITY_ADMIN_PASSWORD}" \
    -X POST http://localhost:${HOST_PORT__GRAFANA}/api/admin/provisioning/dashboards/reload
  curl -u "${GF_SECURITY_ADMIN_USER}:${GF_SECURITY_ADMIN_PASSWORD}" \
    -X POST http://localhost:${HOST_PORT__GRAFANA}/api/admin/provisioning/datasources/reload
  ```
