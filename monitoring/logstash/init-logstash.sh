#!/usr/bin/env bash
set -euo pipefail

echo "[init] preparing logstash ..."

# 1) sincedb каталог(и) — чтобы file/s3 inputs имели где хранить чекпоинт
mkdir -p /usr/share/logstash/data/sincedb

# 2) Плагины — мягкая установка, если отсутствуют
NEED_PLUGINS=${LOGSTASH_PLUGINS:-}
if [ -n "$NEED_PLUGINS" ]; then
  for p in $NEED_PLUGINS; do
    # Тихая проверка: попросим list отфильтровать по имени и не пишем в STDOUT
    if bin/logstash-plugin list "$p" >/dev/null 2>&1; then
      echo "[init] plugin present: $p"
    else
      echo "[init] installing plugin: $p"
      # Пара попыток на случай сетевых глюков
      bin/logstash-plugin install --no-verify "$p" \
        || bin/logstash-plugin install --no-verify "$p"
    fi
  done
fi

# 3) Доверяем MinIO CA, если включено и файл смонтирован
if [ "${TRUST_MINIO_CA:-false}" = "true" ] && [ -f "${MINIO_CA_PATH:-/secrets/minio-rootCA.crt}" ]; then
  echo "[init] trusting MinIO root CA"
  # Системное хранилище (если утилита есть)
  if command -v update-ca-certificates >/dev/null 2>&1; then
    mkdir -p /usr/local/share/ca-certificates
    cp -f "${MINIO_CA_PATH}" /usr/local/share/ca-certificates/minio-rootCA.crt
    update-ca-certificates || true
  fi
  # Java keystore Logstash’а (JDK внутри образа есть)
  /usr/share/logstash/jdk/bin/keytool -importcert -noprompt -trustcacerts \
    -keystore /usr/share/logstash/jdk/lib/security/cacerts \
    -storepass changeit \
    -alias minio-local \
    -file "${MINIO_CA_PATH}" || true
else
  echo "[init] skipping MinIO CA trust (TRUST_MINIO_CA=$TRUST_MINIO_CA, file=${MINIO_CA_PATH})"
fi

echo "[init] starting logstash ..."
exec /usr/local/bin/docker-entrypoint