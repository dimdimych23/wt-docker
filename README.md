# WebSoft HCM (WebTutor) — кластерная установка через Docker

Этот README описывает порядок запуска и настройки WebSoft HCM (WebTutor) в кластерной конфигурации через Docker.

---

## ✨ Структура окружения

**Основные компоненты:**

- `PostgreSQL` — основная база данных
- `Redis` — кеширование и кластеры
- `WebSoft HCM`:
  - 2 ноды WebRole (`web1`, `web2`)
  - 1 нода WorkerRole (`worker`)
  - 1 нода MediaService (если используется визуальный контент)
  - Дополнительные роли WebRole возможны (например, `web3`)
- `Nginx` — внешний балансировщик (не подключён на этапе dev)
- `Grafana + Loki + Promtail` — логирование (опционально)

---

## ✅ Этап 1: Инициализация базы данных

Для избежания конфликтов при создании каталогов и схем — запускаем отдельную init-ноду.

### ⚡ Создание и запуск `docker-compose.init.yml`

```bash
docker compose -f docker-compose.init.yml up -d
```

> **Важно:** init-нода имеет `UpgradeLocked: false` и `StrictWebRole: false`. Она единственная инициализирует БД.

### ❌ Остановка

```bash
docker compose -f docker-compose.init.yml down
```

---

## ✅ Этап 2: Запуск основного кластера

После инициализации — запускаем боевые сервисы:

```bash
docker compose up -d
```

### 💼 Адреса доступа к ролям

- Web-интерфейс WebTutor: http://localhost:81
- Прямая ссылка на Worker (если требуется): http://localhost:82

Nginx маршрутизирует запросы между web1, web2 и worker в зависимости от порта.

### ℹ️ Что входит в `docker-compose.yml`

- `postgres` — с `init.sql` для создания пользователя и БД `wt`
- `redis` — с healthcheck и volume
- `pgadmin` — для просмотра БД
- `web1`, `web2`, `worker` — роли WebTutor:
  - `RoleType=0` — WebRole
  - `RoleType=1` — WorkerRole
  - `StrictWebRole` и `StrictWorkerRole` указываются в `spxml_unibridge_config.xml`
- `volumes:` и `networks:` — общие: `wt_net`, `pgdata`, `redis_data`, `grafana-storage` и т.д.

---

## 💡 Важные файлы конфигурации

### `xHttp.ini`

Общий для всех нод:

- `DEFAULT-DATABASE: wt_data`
- `WEB-DIR: wt/web`
- `DOTNETCORE-PATH`, `DOTNETLIBS-PATH` — важны для работы C# компонентов

### `spxml_unibridge_config.xml`

Разный для каждой роли:

Примеры ключевых параметров:

```xml
<add key="Cluster" value="true" />
<add key="StrictWebRole" value="true" />
<add key="StrictWorkerRole" value="false" />
<add key="DistributedCache" value="true" />
<add key="DistributedCacheType" value="spxml_redis_cache" />
<add key="DistributedCacheConfig" value="redis:6379, abortConnect=false, ..." />
```

> **Важно:** Только одна нода должна запускаться с `UpgradeLocked: false` (это была init-нода)

### `nginx.conf`

Находится в `./nginx/nginx.conf`. Содержит:

- Прокси для WebRole (порт 81) — upstream `wt_web1` и `wt_web2`
- Прокси для WorkerRole (порт 82) — прямое направление на `wt_worker`

Учитываются заголовки `Host`, `X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Proto`.

---

## 🔎 Логи и мониторинг

Логи каждой роли находятся по путям:

```
/WebsoftServer/Logs/web1
/WebsoftServer/Logs/web2
/WebsoftServer/Logs/worker
/WebsoftServer/Logs/mediaserver
```

### Если подключён Loki + Promtail + Grafana:
- В `promtail.yaml` указаны пути к этим логам
- Grafana открывается на `http://localhost:3000`

---

## 🔐 Права и лицензии

В `license.xfpx` проверяется имя хоста:

```yaml
hostname: wt_dev
```

Все контейнеры используют одинаковый `hostname`, чтобы лицензия применялась.

---

## ⚖️ Рекомендации

- Не запускай WebRole и Worker одновременно при первом старте
- Используй именованные volume для логов и БД
- Разделяй конфиги по ролям:
  - `configs/web1/`
  - `configs/web2/`
  - `configs/worker/`
  - `configs/common/`

---

## 🚀 Пример команд

```bash
# 1. Инициализация БД
docker compose -f docker-compose.init.yml up -d

# 2. Остановить
docker compose -f docker-compose.init.yml down

# 3. Запуск основного кластера
docker compose up -d

# 4. Проверка доступа
open http://localhost:81/spxml_web/main.htm
open http://localhost:82/spxml_web/main.htm

# 5. Проверка логов
docker logs -f wt_web1
```

---

Готово — теперь у тебя работающее кластерное окружение WebSoft HCM ✨

---

🧩 Прочие сервисы (`Redis`, `PostgreSQL`, `Loki`, `Promtail`) подключаются через внутреннюю сеть `wt_net`.
Открытие внешних портов для них не рекомендуется.