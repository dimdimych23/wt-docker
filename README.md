# WebSoft HCM (WebTutor) — кластер в Docker с VClass и сервером записи

Это пошаговая инструкция по развёртыванию WebSoft HCM (WebTutor) в docker‑кластере с поддержкой виртуальных классов (**VClass / mediasoup**) и сервера записи.

> **Состояние репозитория:** локальный dev‑контур. Конфиги и тестовые пароли хранятся в Git намеренно (для быстрого запуска). В проде храните секреты в vault/secrets.

---

## 1) Состав кластера

- **PostgreSQL** — основная база
- **Redis** — кеш/кластер
- **WebRole**: `web-backend-1`, `web-backend-2`
- **WorkerRole**: `worker-backend`
- **Mediasoup**: `vclass-media`
- **Recorder**: `vclass-recorder`
- **Nginx** — внешний прокси/балансер (HTTPS)
- (опц.) **Grafana + Loki + Promtail** — сбор и просмотр логов

---

## 2) /etc/hosts (локальный доступ)

Добавьте в `/etc/hosts`:

```txt
127.0.0.1 wt.local
127.0.0.1 wt-vclass.local
127.0.0.1 wt-recorder.local
::1        wt.local
::1        wt-vclass.local
::1        wt-recorder.local
```

---

## 3) Сертификаты

### 3.1 Установка и выпуск SAN‑сертификата (mkcert)

```bash
brew install mkcert
brew install nss   # для Firefox
mkcert -install

mkdir -p ./certs/wt.local
cd ./certs/wt.local
mkcert wt.local wt-vclass.local wt-recorder.local
```
Будут созданы файлы `wt.local+2.pem` и `wt.local+2-key.pem`. Они монтируются в контейнер **nginx-proxy**.

### 3.2 PFX для сервера записи

```bash
# оставаясь в ./certs/wt.local
openssl pkcs12 -export \
  -inkey wt.local+2-key.pem \
  -in    wt.local+2.pem \
  -out   ../../websoft/configs/vclass-recorder/certs/recorder.pfx \
  -passout pass:recpass
```
> В проде добавляйте в PFX полную цепочку. Пароль PFX должен совпадать с тем, что указан в `websoft/configs/vclass-recorder/config.json`.

---

## 4) Nginx (кратко)

Файл: `nginx-proxy/nginx.conf`

- HTTPS‑виртуалы:
  - `wt.local` → web‑backend (порт 8011 в контейнерах WebRole)
  - `wt-vclass.local` → `vclass-media`
  - `wt-recorder.local` → `vclass-recorder` (проксируем **HTTPS → HTTPS**)
- HTTP всегда редиректится на HTTPS.
- Для WebSocket выставлены `Upgrade/Connection`.
- В dev допустимо `proxy_ssl_verify off` для `vclass-recorder` (в проде включить verify и доверенный CA).

> **Важно про порты записи:** upstream `vclass-recorder` в `nginx.conf` настроен на **8443**. Убедитесь, что в `websoft/configs/vclass-recorder/config.json` параметр `Url` в Kestrel **совпадает** (или поменяйте upstream/compose под выбранный порт).

---

## 5) Mediasoup (vclass-media)

Файл: `websoft/configs/vclass-media/mediasoup_config.json`

Ключевые параметры:
- `WorkerSettings.RtcMinPort` / `RtcMaxPort` — диапазон RTP/RTCP/DTLS портов.
  - **Dev (macOS/Windows Docker Desktop):** начните с узкого окна `20000–20009` и **UDP‑только** в compose — так стабильнее. 
  - **Prod:** расширьте, например `20000–20999` (и при необходимости добавьте небольшой TCP‑фоллбек).
- Транспорт:
  - `WebRtcTransportSettings.ListenIps[0].AnnouncedIp`
  - `PlainTransportSettings.ListenIp.AnnouncedIp`
  - **Dev:** `127.0.0.1`
  - **Prod:** внешний IP/домен медианоды.
- Кодеки в `RouterSettings.RtpCodecCapabilities`.

Пример (фрагмент):

```json
{
  "MediasoupSettings": {
    "WorkerSettings": { "RtcMinPort": 20000, "RtcMaxPort": 20009 },
    "WebRtcTransportSettings": { "ListenIps": [ { "Ip": "0.0.0.0", "AnnouncedIp": "127.0.0.1" } ] },
    "PlainTransportSettings":  { "ListenIp":   { "Ip": "0.0.0.0", "AnnouncedIp": "127.0.0.1" } }
  }
}
```

---

## 6) Recorder (vclass-recorder)

Файл: `websoft/configs/vclass-recorder/config.json`

Главное:
- HTTPS‑endpoint Kestrel, путь до **PFX** и **пароль**:

```json
{
  "Service": {
    "Kestrel": {
      "EndPoints": {
        "Https": {
          "Url": "https://*:8443",
          "Certificate": {
            "Path": "../certs/recorder.pfx",
            "Password": "recpass",
            "AllowInvalid": "true"
          }
        }
      }
    }
  }
}
```

- `Recording.RecordingDir` — куда писать файлы (смонтировано как `./websoft/records`).
- `Clients[*].Host` — URL портала (`https://wt.local`).

> Если меняете порт `Url`, синхронизируйте его и в `nginx.conf` (upstream `vclass-recorder`), и в `docker-compose.yml` (expose/ports).

---

## 7) Docker Compose

Файл: `docker-compose.yml`

- `nginx-proxy` публикует 80/443 (+ 81 для служебного backend; можно ограничить `127.0.0.1:81:81`).
- `vclass-media` публикует UDP‑диапазон для WebRTC. В dev на macOS/Windows не используйте большие окна с TCP — это часто «вешает» Docker Desktop.
- `vclass-recorder` экспонирует свой HTTPS‑порт (см. раздел 6).
- Healthchecks включены для web/worker и vclass-media.

### Инициализация БД (разово)

```bash
docker compose -f docker-compose.init.yml up -d
# дождитесь и затем
docker compose -f docker-compose.init.yml down --remove-orphans
```

### Запуск всего кластера

```bash
docker compose up -d
```

---

## 8) Проверка доступности

Точки входа:

- Портал: **https://wt.local**
- Вирт. классы (сигналинг): **https://wt-vclass.local**
- Сервер записи: **https://wt-recorder.local**

Быстрые проверки:

```bash
curl -I https://wt.local/default
curl -I https://wt-vclass.local/
curl -I https://wt-recorder.local/
```

---

## 9) Логи и полезные пути

- Логи WebSoft: `./websoft/Logs/<service>`
- Записи: `./websoft/records` и `./websoft/records/archive` (в Git храним только `.gitkeep`)
- Grafana (если включена): `http://localhost:3000`
- PgAdmin: `http://localhost:5050`

---

## 10) Частые проблемы

- **400 на портале** — в `xhttp_config.json` добавьте `"AllowedHosts": ["*", "wt.local"]`.
- **`vclass-media` зависает в `Starting`** — уберите healthcheck на несуществующий URL; начните с узкого UDP‑диапазона; убедитесь, что `RtcMinPort/RtcMaxPort` совпадают с проброшенными портами.
- **Recorder падает: `BIO routines: no such file`** — неверный путь/пароль к PFX. Проверьте `websoft/configs/vclass-recorder/config.json` и наличие файла `websoft/configs/vclass-recorder/certs/recorder.pfx`.
- **502 для `wt-recorder.local`** — порт в `nginx.conf` не совпадает с `Url` в конфиге сервера записи.

---

## 11) Продакшн‑заметки

- Расширить UDP‑диапазон WebRTC (например, `20000–20999`).
- `AnnouncedIp` в mediasoup — внешний IP/домен.
- Включить `proxy_ssl_verify on` и доверенный CA для recorder.
- Разнести `vclass-media` и `vclass-recorder` по разным нодам при высокой нагрузке.
- Пароли/ключи хранить в Vault/Secrets.

---

## 12) Быстрый чек‑лист запуска

```bash
# 1) hosts
# 2) mkcert + PFX
# 3) docker compose -f docker-compose.init.yml up -d && down --remove-orphans
# 4) docker compose up -d
# 5) curl -I https://wt.local/default
# 6) Проверить логи vclass-media и vclass-recorder
```

