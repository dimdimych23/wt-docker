#!/bin/sh
set -eu

# --- общий graceful-выход ---
MAIN_PID=""
terminate() {
  echo "[entrypoint] caught signal, terminating main process…"
  if [ -n "${MAIN_PID}" ] && kill -0 "$MAIN_PID" 2>/dev/null; then
    kill -TERM "$MAIN_PID" 2>/dev/null || true
    wait "$MAIN_PID" 2>/dev/null || true
  fi
  exit 0
}
trap terminate TERM INT

# 1) Генерим VFS-конфиг + доверяем CA и ПЕРЕХОДИМ в xhttp через init-vfs.sh
# init-vfs.sh сам сделает exec /WebsoftServer/xhttp.out — PID останется тем же
echo "[entrypoint] running init-vfs.sh (will exec xhttp)…"
/WebsoftServer/init-vfs.sh &
MAIN_PID=$!

# 2) Ждём готовности HTTP (8011) с таймером, параллельно следим что процесс живой
ATTEMPTS=0
MAX_ATTEMPTS=30       # ~90 сек
SLEEP=3
echo "[entrypoint] waiting for http://localhost:8011/spxml_web/main.htm"
while true; do
  # если xhttp умер раньше времени — падаем с логами
  if ! kill -0 "$MAIN_PID" 2>/dev/null; then
    echo "[entrypoint] init/xhttp exited prematurely, printing last logs…"
    tail -n 200 /WebsoftServer/Logs/* 2>/dev/null || true
    exit 1
  fi
  if wget -q --spider http://localhost:8011/spxml_web/main.htm; then
    break
  fi
  ATTEMPTS=$((ATTEMPTS+1))
  if [ "$ATTEMPTS" -ge "$MAX_ATTEMPTS" ]; then
    echo "[entrypoint] timeout (> $((MAX_ATTEMPTS*SLEEP))s) waiting platform, printing last logs…"
    tail -n 200 /WebsoftServer/Logs/* 2>/dev/null || true
    exit 1
  fi
  sleep "$SLEEP"
done
echo "[entrypoint] platform is up"

# 3) Включаем медиасервис через XShell (если ещё не включён — операция идемпотентная)
echo "[entrypoint] enabling mediaservice (wftget)…"
/WebsoftServer/x-shell -c "wftget enable websoft.mediaservice" || {
  echo "[entrypoint] wftget failed — check Logs"; exit 1;
}
echo "[entrypoint] mediaservice enabled"

# 4) Привязываем жизнь контейнера к основному процессу (xhttp из init-vfs.sh)
wait "$MAIN_PID"