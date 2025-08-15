#!/bin/sh
set -eu

# 0) выход по Ctrl+C / docker stop
terminate() {
  echo "[entrypoint] caught signal, terminating xhttp…"
  kill -TERM "$XHTTP_PID" 2>/dev/null || true
  wait "$XHTTP_PID" 2>/dev/null || true
  exit 0
}
trap terminate TERM INT

# 1) Запускаем платформу
echo "[entrypoint] starting xhttp.out…"
/WebsoftServer/xhttp.out &
XHTTP_PID=$!

# 2) Ждём готовности HTTP (8011) с таймаутом ~90с
ATTEMPTS=0
MAX_ATTEMPTS=30
SLEEP=3
echo "[entrypoint] waiting for http://localhost:8011/spxml_web/main.htm"
until wget -q --spider http://localhost:8011/spxml_web/main.htm; do
  ATTEMPTS=$((ATTEMPTS+1))
  if [ "$ATTEMPTS" -ge "$MAX_ATTEMPTS" ]; then
    echo "[entrypoint] timeout waiting platform (>$((MAX_ATTEMPTS*SLEEP))s), printing last lines from Logs and exiting…"
    tail -n 200 /WebsoftServer/Logs/* 2>/dev/null || true
    exit 1
  fi
  sleep "$SLEEP"
done
echo "[entrypoint] platform is up"

# 3) Включаем медиасервис через XShell
echo "[entrypoint] enabling mediaservice (wftget)…"
/WebsoftServer/x-shell -c "wftget enable websoft.mediaservice" || {
  echo "[entrypoint] wftget failed — check Logs"; exit 1;
}
echo "[entrypoint] mediaservice enabled"

# 4) Ждём основной процесс (правильная привязка жизненного цикла контейнера)
wait "$XHTTP_PID"