#!/usr/bin/env sh
set -eu

HOST="${HOST_NAME__PG:-postgres}"
PORT="${HOST_PORT__PG:-5432}"
DEADLINE="${PG_WAIT_DEADLINE:-60}"      # секунд всего
INTERVAL="${PG_WAIT_INTERVAL:-2}"       # пауза между попытками
ENABLED="${PG_WAIT_ENABLED:-true}"      # true|false
ON_TO="${PG_WAIT_ON_TIMEOUT:-fail}"     # fail|skip

if [ "$ENABLED" != "true" ]; then
  echo "[pg-wait] disabled"; exit 0
fi

echo "[pg-wait] wait ${HOST}:${PORT} (deadline=${DEADLINE}s, interval=${INTERVAL}s, on_timeout=${ON_TO})"
start_ts=$(date +%s)

while :; do
  if command -v pg_isready >/dev/null 2>&1; then
    if pg_isready -h "$HOST" -p "$PORT" -t 3 >/dev/null 2>&1; then
      echo "[pg-wait] pg_isready: OK"; exit 0
    fi
  elif command -v nc >/dev/null 2>&1; then
    if nc -z "$HOST" "$PORT" >/dev/null 2>&1; then
      echo "[pg-wait] nc: OK"; exit 0
    fi
  elif command -v bash >/dev/null 2>&1; then
    if bash -c ">/dev/tcp/${HOST}/${PORT}" >/dev/null 2>&1; then
      echo "[pg-wait] /dev/tcp: OK"; exit 0
    fi
  else
    echo "[pg-wait] no checker available; skip"
    exit 0
  fi

  now=$(date +%s); elapsed=$((now - start_ts))
  if [ "$elapsed" -ge "$DEADLINE" ]; then
    echo "[pg-wait] timeout after ${elapsed}s"
    [ "$ON_TO" = "skip" ] && exit 0 || exit 1
  fi
  sleep "$INTERVAL"
done