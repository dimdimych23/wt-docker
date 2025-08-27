#!/bin/sh
set -Eeuox pipefail

# -------- Обязательные переменные окружения --------
: "${S3_SERVICE_URL:?S3_SERVICE_URL is required (e.g. https://minio:9000)}"
: "${ROOT_USER__MINIO:?ROOT_USER__MINIO is required}"
: "${ROOT_PASSWORD__MINIO:?ROOT_PASSWORD__MINIO is required}"

# RW учётка для WebTutor
: "${S3_ACCESS_KEY_ID:?S3_ACCESS_KEY_ID is required}"
: "${S3_SECRET_ACCESS_KEY:?S3_SECRET_ACCESS_KEY is required}"

# RO учётка для чтения логов (Logstash/Vector и т.п.)
: "${S3_LOGS_RO_ACCESS_KEY_ID:?S3_LOGS_RO_ACCESS_KEY_ID is required}"
: "${S3_LOGS_RO_SECRET_ACCESS_KEY:?S3_LOGS_RO_SECRET_ACCESS_KEY is required}"

# Имена бакетов
: "${BUCKET_WEBTUTOR:?BUCKET_WEBTUTOR is required}"
: "${BUCKET_SPXML_BLOBS:?BUCKET_SPXML_BLOBS is required}"
: "${BUCKET_APPLICATIONS:?BUCKET_APPLICATIONS is required}"
: "${BUCKET_FTIDX:?BUCKET_FTIDX is required}"
: "${BUCKET_RECORDS:?BUCKET_RECORDS is required}"
: "${BUCKET_LOGS:?BUCKET_LOGS is required}"
: "${BUCKET_WEBTUTOR_PUBLIC:?BUCKET_WEBTUTOR_PUBLIC is required (true/false)}"

# Пути к JSON‑политикам (примонтированы RO)
WT_RW_POLICY_FILE="/policies/wt-rw.json"
LOGS_RO_POLICY_FILE="/policies/logs-ro.json"

MC="mc --insecure"
log() { printf '%s\n' "[minio-mc-init] $*"; }

# -------- 1) alias к MinIO (ждём готовности HTTPS) --------
log "Configuring mc alias 'local' → ${S3_SERVICE_URL}"
ATTEMPTS=0; MAX_ATTEMPTS=30
until $MC alias set local "${S3_SERVICE_URL}" "${ROOT_USER__MINIO}" "${ROOT_PASSWORD__MINIO}" >/dev/null 2>&1; do
  ATTEMPTS=$((ATTEMPTS+1))
  [ "$ATTEMPTS" -ge "$MAX_ATTEMPTS" ] && { log "ERROR: alias set failed after ${ATTEMPTS} attempts"; exit 1; }
  log "MinIO not ready yet, retry ${ATTEMPTS}/${MAX_ATTEMPTS} ..."
  sleep 2
done

for i in $(seq 1 10); do
  if $MC ls local >/dev/null 2>&1; then log "MinIO is ready"; break; fi
  sleep 1
done
$MC ls local >/dev/null 2>&1 || { log "ERROR: MinIO not ready, aborting"; exit 1; }

# -------- 2) Бакеты (идемпотентно) --------
log "Creating buckets (idempotent)..."
$MC mb -p "local/${BUCKET_WEBTUTOR}"     || true
$MC mb -p "local/${BUCKET_SPXML_BLOBS}"  || true
$MC mb -p "local/${BUCKET_APPLICATIONS}" || true
$MC mb -p "local/${BUCKET_FTIDX}"        || true
$MC mb -p "local/${BUCKET_RECORDS}"      || true
$MC mb -p "local/${BUCKET_LOGS}"         || true

upsert_policy() {
  # usage: upsert_policy <policy_name> <json_file>
  _name="$1"
  _file="$2"

  # если политика существует → сначала пытаемся update,
  # если команда в этой версии mc отсутствует/падает → пробуем create, затем add
  if $MC admin policy info local "$_name" >/dev/null 2>&1; then
    $MC admin policy update local "$_name" "$_file" || \
    $MC admin policy create local "$_name" "$_file" || \
    $MC admin policy add    local "$_name" "$_file" || true
  else
    # не существует → create/add с запасом
    $MC admin policy add    local "$_name" "$_file" || \
    $MC admin policy create local "$_name" "$_file" || true
  fi
}

# -------- 3) Политика RW + пользователь RW --------
[ -f "$WT_RW_POLICY_FILE" ] || { log "ERROR: policy file not found: $WT_RW_POLICY_FILE"; exit 1; }
log "Upserting policy 'wt-rw-selected' from $WT_RW_POLICY_FILE"

# Если политика уже есть — обновляем, если нет — создаём
upsert_policy wt-rw-selected "$WT_RW_POLICY_FILE"

log "Ensuring RW user '${S3_ACCESS_KEY_ID}' exists"
$MC admin user add local "${S3_ACCESS_KEY_ID}" "${S3_SECRET_ACCESS_KEY}" 2>/dev/null || true

log "Attaching policy 'wt-rw-selected' to user '${S3_ACCESS_KEY_ID}'"
$MC admin policy attach local --user "${S3_ACCESS_KEY_ID}" wt-rw-selected || true

# -------- 4) Политика RO для логов + пользователь RO --------
[ -f "$LOGS_RO_POLICY_FILE" ] || { log "ERROR: policy file not found: $LOGS_RO_POLICY_FILE"; exit 1; }
log "Upserting policy 'logs-ro' from $LOGS_RO_POLICY_FILE"

upsert_policy logs-ro "$LOGS_RO_POLICY_FILE"

log "Ensuring RO user '${S3_LOGS_RO_ACCESS_KEY_ID}' exists"
$MC admin user add local "${S3_LOGS_RO_ACCESS_KEY_ID}" "${S3_LOGS_RO_SECRET_ACCESS_KEY}" 2>/dev/null || true

log "Attaching policy 'logs-ro' to user '${S3_LOGS_RO_ACCESS_KEY_ID}'"
$MC admin policy attach local --user "${S3_LOGS_RO_ACCESS_KEY_ID}" logs-ro || true

# -------- 5) Публичность контента (опционально для DEV) --------
if [ "${BUCKET_WEBTUTOR_PUBLIC}" = "true" ]; then
  log "Enabling anonymous download on ${BUCKET_WEBTUTOR}"
  $MC anonymous set download "local/${BUCKET_WEBTUTOR}" || true
else
  log "Keeping ${BUCKET_WEBTUTOR} private"
  $MC anonymous set none "local/${BUCKET_WEBTUTOR}" || true
fi

# -------- 6) Диагностика --------
log "Summary:"
$MC admin user info   local "${S3_ACCESS_KEY_ID}"         || true
$MC admin user info   local "${S3_LOGS_RO_ACCESS_KEY_ID}" || true
$MC admin policy info local wt-rw-selected                 || true
$MC admin policy info local logs-ro                        || true
$MC ls local                                              || true
log "Done."