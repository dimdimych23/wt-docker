#!/bin/sh
# ./deploy-components.sh
# Rolling-установка компонентов из ./websoft/components-init в контейнеры WT
# Использует /WebsoftServer/init-components.sh внутри контейнера

set -e

# Сервисы по умолчанию (2 web + 1 worker)
SERVICES="${*:-web-backend-1 web-backend-2 worker-backend}"
INIT_FLAG="${COMPONENTS_INIT_ENABLED:-true}"
HEALTH_PATH="${HEALTH_PATH:-/spxml_web/main.htm}"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-180}" # секунд ожидания готовности ноды

need_components() {
  # проверим, есть ли вообще что ставить
  ls -1 ./websoft/components-init/*.zip >/dev/null 2>&1
}

wait_healthy() {
  svc="$1"
  echo "    [wait] $svc → $HEALTH_PATH (timeout ${HEALTH_TIMEOUT}s)"
  # ждём внутри контейнера локальный порт 8011
  deadline=$(( $(date +%s) + HEALTH_TIMEOUT ))
  while :; do
    if docker exec "$COMPOSE_PROJECT_NAME-$svc-1" sh -lc "wget -q --spider http://localhost:8011${HEALTH_PATH}"; then
      echo "    [ok] $svc is healthy"
      return 0
    fi
    [ "$(date +%s)" -lt "$deadline" ] || { echo "    [fail] $svc not healthy in time"; return 1; }
    sleep 3
  done
}

echo "[deploy] Rolling install to: $SERVICES"

if ! need_components; then
  echo "[deploy] no archives in ./websoft/components-init — нечего устанавливать"; exit 0
fi

for svc in $SERVICES; do
  echo "[deploy] === $svc ==="
  cid="$(docker ps --format '{{.Names}}' | grep -E "^${COMPOSE_PROJECT_NAME:-wt-docker}-${svc}-[0-9]+$" || true)"
  [ -n "$cid" ] || { echo "  [skip] $svc не запущен"; continue; }

  echo "  [exec] install components via init-components.sh"
  docker exec "$cid" sh -lc "COMPONENTS_INIT_ENABLED=${INIT_FLAG} /WebsoftServer/init-components.sh"

  echo "  [restart] docker compose restart $svc"
  docker compose restart "$svc"

  wait_healthy "$svc"
done

echo "[deploy] done."