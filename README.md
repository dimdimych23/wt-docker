WebSoft HCM (WebTutor) — кластерная установка через Docker с поддержкой виртуальных классов (VClass) и сервера записи

Этот README описывает полный порядок подготовки и запуска WebSoft HCM (WebTutor) в кластерной конфигурации через Docker с поддержкой медиасервера виртуальных классов и сервера записи.

⸻

📦 Структура окружения

Компоненты кластера:
	•	PostgreSQL — основная база данных
	•	Redis — кеширование и кластеры
	•	WebSoft HCM:
	•	2 ноды WebRole (web-backend-1, web-backend-2)
	•	1 нода WorkerRole (worker-backend)
	•	1 нода MediaService для виртуальных классов (vclass-media)
	•	1 нода сервера записи виртуальных классов (vclass-recorder)
	•	Nginx — внешний балансировщик и прокси с поддержкой HTTPS
	•	Grafana + Loki + Promtail — централизованное логирование (опционально)

⸻

1️⃣ Подготовка /etc/hosts

Для локальной разработки нужно прописать домены:
127.0.0.1 wt.local
127.0.0.1 wt-vclass.local
127.0.0.1 wt-recorder.local
::1 wt.local
::1 wt-vclass.local
::1 wt-recorder.local

2️⃣ Создание сертификатов

Установка mkcert
brew install mkcert
brew install nss # для Firefox
mkcert -install

Генерация сертификатов для всех доменов
mkdir -p ./certs/wt.local
cd ./certs/wt.local
mkcert wt.local wt-vclass.local wt-recorder.local

В результате будут созданы:
	•	wt.local+2.pem
	•	wt.local+2-key.pem

Создание PFX для сервера записи

openssl pkcs12 -export \
  -inkey wt.local+2-key.pem \
  -in wt.local+2.pem \
  -out ../../websoft/configs/vclass-recorder/certs/recorder.pfx \
  -passout pass:recpass

  3️⃣ Конфигурация Nginx

Файл nginx-proxy/nginx.conf содержит:
	•	Upstream для web-backend, worker-backend, vclass-media, vclass-recorder
	•	Редиректы HTTP → HTTPS
	•	SSL для всех сервисов
	•	Настройки WebSocket и заголовков

Важно:
	•	Для vclass-recorder в dev-режиме proxy_ssl_verify off, в продакшене включить проверку сертификата.
	•	Все server_name соответствуют прописанным в /etc/hosts доменам.

⸻

4️⃣ Конфигурация Mediasoup (vclass-media)

Файл websoft/configs/vclass-media/mediasoup_config.json:
	•	RtcMinPort и RtcMaxPort — диапазон портов для WebRTC (в dev можно оставить 20000-20009, в проде расширить)
	•	ListenIps → AnnouncedIp заменить на внешний IP в продакшене
	•	Аудио/видео кодеки перечислены в RtpCodecCapabilities
	•	ServeMode в MeetingServerSettings — Open (в dev), в проде можно закрыть доступ.

⸻

5️⃣ Конфигурация сервера записи (vclass-recorder)

Файл websoft/configs/vclass-recorder/config.json:
	•	"Certificate" → "Path": "/Websoft.Recording/certs/recorder.pfx" (путь внутри контейнера)
	•	"Password": "recpass" — пароль, указанный при создании PFX
	•	"Host" в "Clients" — URL портала (https://wt.local)
	•	"Slots" — кол-во одновременных сессий записи
	•	"RecordingDir" — путь внутри контейнера для сохранения записей

⸻

6️⃣ docker-compose.yml

Основные моменты:
	•	nginx-proxy монтирует nginx.conf и сертификаты
	•	vclass-media пробрасывает UDP/TCP порты для WebRTC
	•	vclass-recorder использует PFX и HTTPS на 8443
	•	Все контейнеры в одной сети wt-net
	•	Healthcheck’и на web, worker и vclass-media

⸻

7️⃣ Запуск кластера

Первый запуск (инициализация БД)

docker compose -f docker-compose.init.yml up -d
docker compose -f docker-compose.init.yml down

Запуск всего окружения
docker compose up -d

8️⃣ Доступ к сервисам
	•	Портал: https://wt.local
	•	Медиасервер VClass: https://wt-vclass.local
	•	Сервер записи: https://wt-recorder.local

⸻

9️⃣ Логи
	•	./websoft/Logs/web-backend-1
	•	./websoft/Logs/web-backend-2
	•	./websoft/Logs/worker-backend
	•	./websoft/Logs/vclass-media
	•	./websoft/Logs/vclass-recorder

⸻

🔟 Рекомендации для продакшена
	•	Расширить диапазон портов для WebRTC
	•	AnnouncedIp в mediasoup указать на внешний IP
	•	Включить проверку сертификатов (proxy_ssl_verify on)
	•	Ограничить доступ к vclass-recorder по IP
	•	Хранить пароли и ключи в защищённом vault’е