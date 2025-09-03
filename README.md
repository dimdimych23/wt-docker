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
- Если понадобятся MinIO/мониторинг — используйте другой compose-

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

## Мониторинг: Logstash → Loki → Grafana

Эта сборка позволяет читать логи WebSoft HCM из **примонтированных каталогов/файловых шар** (и опционально из **S3/MinIO**), нормализовать их в **Logstash** и отправлять в **Loki**. Grafana (локально — для отладки; в ТМК — корпоративная) используется только как UI к Loki.

### Как включить локально

```bash
# 1) проверь переменные в секции "MONITORING / loki" в .env (см. ниже)
# 2) подними Loki, Logstash и локальную Grafana одним профилем:
docker compose --profile monitoring up -d loki logstash grafana
# 3) Зайди в Grafana: http://localhost:3000 (admin / change_me)
#   datasource "Loki (Local)" уже будет доступен (см. monitoring/grafana/provisioning)
```

### Переменные окружения (секции `.env`)

#### MONITORING / logstash → loki

- `LOKI_JOB_LABEL` — имя лейбла *job* в Loki (удобный ключ для запросов/панелей).
  Пример запроса в Grafana (LogQL):
  ```
  {job="${LOKI_JOB_LABEL}", service="web1"} |= "Error"
  ```
- `ROLE_FALLBACK`, `ENV_FALLBACK`, `LOG_TYPE_FALLBACK` — значения по умолчанию, если лог не удаётся отнести к роли/окружению/типу по имени файла.

#### MONITORING / loki

- `IMAGE_LOKI` — образ Loki (по умолчанию `grafana/loki:2.9.3`).
- `HOST_NAME__LOKI` — имя сервиса Loki в docker-сети (обычно `loki`).
- `HOST_PORT__LOKI` — порт HTTP API Loki (по умолчанию `3100`).
- `LOKI_RETENTION_PERIOD` — срок хранения данных в Loki (буфер для поиска). **Истина — в файлах/шаре/S3**, поэтому здесь обычно 48–168 часов.
- `LOKI_REJECT_OLD_SAMPLES_MAX_AGE` — максимальная давность записей, которые Loki примет. Держите ≥ `LOKI_RETENTION_PERIOD`.
- `LOKI_MAX_LOOK_BACK_PERIOD` — максимальная глубина поиска в запросах Grafana (обычно равно или больше retention).
- `LOKI_CHUNK_IDLE_PERIOD` — сколько ждать тишины по стриму до закрытия чанка. Меньше — быстрее индексируется, но больше мелких чанков.
- `LOKI_MAX_CHUNK_AGE` — принудительное закрытие чанка при непрерывном потоке (балансирует размер/задержку).
- `LOKI_CHUNK_RETAIN_PERIOD` — сколько держать закрытый чанк в памяти для «поздних» строк.

### Когда и что крутить (симптом → параметр)

| Симптом | Что изменить | Рекомендация |
|---|---|---|
| Логи долго появляются в поиске | `LOKI_CHUNK_IDLE_PERIOD` ↓, `LOKI_MAX_CHUNK_AGE` ↓ | Dev: 2–5m / 30–60m; Prod: 5–10m / 60–120m |
| Слишком много маленьких чанков | `LOKI_CHUNK_IDLE_PERIOD` ↑, `LOKI_MAX_CHUNK_AGE` ↑ | Умеренно повышать, следить за диском |
| Не удаётся искать глубже по времени | `LOKI_MAX_LOOK_BACK_PERIOD` ↑ | Держите ≥ `LOKI_RETENTION_PERIOD` |
| Диск Loki разрастается | `LOKI_RETENTION_PERIOD` ↓ | Помните: первичное хранилище — файлы/шара/S3 |
| Падает при приёме старых логов | `LOKI_REJECT_OLD_SAMPLES_MAX_AGE` ↑ | Держите ≥ retention |

### Конфиг Loki (используется env)

См. `monitoring/loki/loki-config.yaml` — весь retention/лимиты/тайминги берутся из `.env`.

### Пример запросов в Grafana (LogQL)
```logql
{job="websoft-hcm"}
{job="websoft-hcm", service="web1"} |= "Error"
{job="websoft-hcm", level="Error"}
```

### Нота о хранении

Loki — это **временный буфер для поиска и панелей**. Источником истины являются **логи WebSoft** в примонтированном каталоге/на файловой шаре или в S3/MinIO. При сбоях Loki/Logstash данные не теряются — можно дочитать из первичного источника.

### Logstash → Loki: как включить и что за что отвечает

#### 0) Идея
- Источник истины — файлы логов WebSoft (локально / файловая шара / S3).
- Logstash читает источники, нормализует сообщения и пушит в Loki.
- Loki используется как «буфер для поиска и панелей» (Grafana).

#### 1) Настрой `.env` (секция “MONITORING / logstash → loki”)
- `LOGSTASH_INPUT_FILES_ENABLED` — включить чтение из **файлов/шар**.
- `LOGSTASH_INPUT_S3_ENABLED` — включить чтение из **S3/MinIO**.
- `LOGSTASH_FILES_GLOB_*` — где лежат логи **внутри контейнера logstash** (мы пробрасываем их через volumes).
- `LOGSTASH_ML_*` — мультилайн (для xhttp строк вида `HH:MM:SS [dddd]`).
- `LOKI_JOB_LABEL` и `*_FALLBACK` — метки, попадающие в Loki.
- `S3_*` — параметры доступа к MinIO/S3 (если включаешь S3).
- `HOST_NAME__LOKI`/`HOST_PORT__LOKI` — адрес Loki в docker-сети.

#### 2) Подключи каталоги логов к контейнеру logstash
В `docker-compose.yml` у `logstash` добавь volumes:
```yaml
- ./websoft/Logs/web-backend-1:/var/log/wt/web1:ro
- ./websoft/Logs/web-backend-2:/var/log/wt/web2:ro
- ./websoft/Logs/worker-backend:/var/log/wt/worker:ro
```
Для файловой шары: смонтируй её на хост (например, /mnt/wt-logs/...) и пробрось те же пути вместо ./websoft/Logs/....

3) Включи нужные input’ы
  - Только файлы/шары: `LOGSTASH_INPUT_FILES_ENABLED=true`, `LOGSTASH_INPUT_S3_ENABLED=false`.
	-	Только S3: `LOGSTASH_INPUT_FILES_ENABLED=false`, `LOGSTASH_INPUT_S3_ENABLED=true`.
	-	Оба: обе переменные true (для миграций).

4) Конфиги pipeline (что за что отвечает)
	-	`00-input-files.conf` — file input (читает GLOB-паттерны; мультилайн; проставляет метку роли).
	-	`01-input-s3.conf` — s3 input (опрашивает бакет; кладёт ключ объекта в метаданные).
	-	`10-filter-common.conf` — нормализация:
	-	вычисляет role (web1/web2/worker) по пути/ключу,
	-	извлекает env и log_type из имени файла,
	-	собирает JSON для Loki (streams/labels/values).
	-	`90-output-loki.conf` — HTTP push в Loki (/loki/api/v1/push).

5) Запуск и тест
```bash
docker compose --profile monitoring up -d loki logstash grafana
docker logs -f wt-docker-logstash-1
# в Grafana: {job="websoft-hcm"} или {job="websoft-hcm", role="web1"} |= "Error"
```

6) Типовые проблемы
	-	«Логи не собираются из файлов» — проверь volumes у logstash и что `LOGSTASH_INPUT_FILES_ENABLED=true`.
	-	«Мультилайн не работает» — удостоверься, что `LOGSTASH_ML_PATTERN` ровно `^\\d{2}:\\d{2}:\\d{2}\\s\\\\\d{4}\\\\s+`.
	-	«S3 не читается» — включи `LOGSTASH_INPUT_S3_ENABLED=true`, проверь S3_*, доверенные сертификаты (Dockerfile уже импортирует CA MinIO).
	-	«Grafana не видит логи» — проверь, что Loki поднят, и что `HOST_PORT__LOKI` проброшен (`3100:3100`).
