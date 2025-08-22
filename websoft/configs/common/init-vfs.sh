#!/bin/sh
set -eu

# -------- обязательные --------
: "${S3_SERVICE_URL:?S3_SERVICE_URL is required}"
: "${S3_ACCESS_KEY_ID:?S3_ACCESS_KEY_ID is required}"
: "${S3_SECRET_ACCESS_KEY:?S3_SECRET_ACCESS_KEY is required}"

# -------- опциональные с дефолтами --------
S3_FORCE_PATH_STYLE="${S3_FORCE_PATH_STYLE:-true}"
S3_TIMEOUT="${S3_TIMEOUT:-60}"

BUCKET_WEBTUTOR="${BUCKET_WEBTUTOR:-webtutor}"
BUCKET_SPXML_BLOBS="${BUCKET_SPXML_BLOBS:-spxml-blobs}"
BUCKET_APPLICATIONS="${BUCKET_APPLICATIONS:-applications}"
BUCKET_FTIDX="${BUCKET_FTIDX:-ft-idx}"
BUCKET_LOGS="${BUCKET_LOGS:-logs}"

LOG_LOCATION="${LOG_LOCATION:-generic/}"
LOG_MIN_CHECK_INTERVAL="${LOG_MIN_CHECK_INTERVAL:-5}"
LOG_CONSOLIDATION="${LOG_CONSOLIDATION:-true}"
LOG_CONSOLIDATE_CHECK_INTERVAL="${LOG_CONSOLIDATE_CHECK_INTERVAL:-60}"
LOG_FULL_CONSOLIDATION="${LOG_FULL_CONSOLIDATION:-true}"

VFS_LOOK_ON_LOCAL="${VFS_LOOK_ON_LOCAL:-true}"
VFS_FETCH_BACK="${VFS_FETCH_BACK:-true}"
VFS_DELETE_LOCAL_AFTER_FETCH="${VFS_DELETE_LOCAL_AFTER_FETCH:-false}"

S3_TRUSTED_CA_PATH="${S3_TRUSTED_CA_PATH:-/WebsoftServer/certs/minio/minio-rootCA.pem}"

TPL="/WebsoftServer/configs/vfs_conf.json.template"
OUT="/WebsoftServer/vfs_conf.json"

# -------- доверие CA (если файл есть) --------
if [ -f "$S3_TRUSTED_CA_PATH" ] && command -v update-ca-certificates >/dev/null 2>&1; then
  cp -f "$S3_TRUSTED_CA_PATH" /usr/local/share/ca-certificates/minio-local.crt || true
  update-ca-certificates >/dev/null 2>&1 || true
fi

[ -f "$TPL" ] || { echo "[init-vfs] template not found: $TPL" >&2; exit 1; }

escape_sed () { printf '%s' "$1" | sed 's/[\/&]/\\&/g'; }

tmp="$(mktemp)"
cp "$TPL" "$tmp"

# строки
sed -i "s|__S3_SERVICE_URL__|$(escape_sed "$S3_SERVICE_URL")|g" "$tmp"
sed -i "s|__S3_ACCESS_KEY_ID__|$(escape_sed "$S3_ACCESS_KEY_ID")|g" "$tmp"
sed -i "s|__S3_SECRET_ACCESS_KEY__|$(escape_sed "$S3_SECRET_ACCESS_KEY")|g" "$tmp"

sed -i "s|__BUCKET_WEBTUTOR__|$(escape_sed "$BUCKET_WEBTUTOR")|g" "$tmp"
sed -i "s|__BUCKET_SPXML_BLOBS__|$(escape_sed "$BUCKET_SPXML_BLOBS")|g" "$tmp"
sed -i "s|__BUCKET_APPLICATIONS__|$(escape_sed "$BUCKET_APPLICATIONS")|g" "$tmp"
sed -i "s|__BUCKET_FTIDX__|$(escape_sed "$BUCKET_FTIDX")|g" "$tmp"
sed -i "s|__BUCKET_LOGS__|$(escape_sed "$BUCKET_LOGS")|g" "$tmp"

sed -i "s|__LOG_LOCATION__|$(escape_sed "$LOG_LOCATION")|g" "$tmp"

# bool/number подстановка в шаблон без кавычек
to_bool () { printf '%s' "$1" | tr 'A-Z' 'a-z'; }
ensure_bool () { case "$(to_bool "$1")" in true|false) ;; *) echo "ERR bool: $2=\"$1\"" >&2; exit 2;; esac; }
ensure_int () { case "$1" in ''|*[!0-9]* ) echo "ERR int: $2=\"$1\"" >&2; exit 2;; esac; }

ensure_bool "$S3_FORCE_PATH_STYLE" S3_FORCE_PATH_STYLE
ensure_int  "$S3_TIMEOUT"          S3_TIMEOUT
ensure_bool "$LOG_CONSOLIDATION"   LOG_CONSOLIDATION
ensure_bool "$LOG_FULL_CONSOLIDATION" LOG_FULL_CONSOLIDATION
ensure_int  "$LOG_MIN_CHECK_INTERVAL" LOG_MIN_CHECK_INTERVAL
ensure_int  "$LOG_CONSOLIDATE_CHECK_INTERVAL" LOG_CONSOLIDATE_CHECK_INTERVAL
ensure_bool "$VFS_LOOK_ON_LOCAL"   VFS_LOOK_ON_LOCAL
ensure_bool "$VFS_FETCH_BACK"      VFS_FETCH_BACK
ensure_bool "$VFS_DELETE_LOCAL_AFTER_FETCH" VFS_DELETE_LOCAL_AFTER_FETCH

sed -i "s|__S3_FORCE_PATH_STYLE__|$(to_bool "$S3_FORCE_PATH_STYLE")|g" "$tmp"
sed -i "s|__S3_TIMEOUT__|$S3_TIMEOUT|g" "$tmp"

sed -i "s|__LOG_MIN_CHECK_INTERVAL__|$LOG_MIN_CHECK_INTERVAL|g" "$tmp"
sed -i "s|__LOG_CONSOLIDATION__|$(to_bool "$LOG_CONSOLIDATION")|g" "$tmp"
sed -i "s|__LOG_CONSOLIDATE_CHECK_INTERVAL__|$LOG_CONSOLIDATE_CHECK_INTERVAL|g" "$tmp"
sed -i "s|__LOG_FULL_CONSOLIDATION__|$(to_bool "$LOG_FULL_CONSOLIDATION")|g" "$tmp"

sed -i "s|__VFS_LOOK_ON_LOCAL__|$(to_bool "$VFS_LOOK_ON_LOCAL")|g" "$tmp"
sed -i "s|__VFS_FETCH_BACK__|$(to_bool "$VFS_FETCH_BACK")|g" "$tmp"
sed -i "s|__VFS_DELETE_LOCAL_AFTER_FETCH__|$(to_bool "$VFS_DELETE_LOCAL_AFTER_FETCH")|g" "$tmp"

mv "$tmp" "$OUT"

# мини-проверка JSON (при наличии jq - раскомментируй)
# jq empty "$OUT"

echo "[init-vfs] generated $OUT"
grep -E '"ServiceURL"|"Bucket"|"Location"|"ForcePathStyle"|"Timeout"|"LogMinCheckInterval"|"LogConsolidation"|"LogConsolidateCheckInterval"|"LogFullConsolidation"' -n "$OUT" \
  | sed -E 's/(SecretAccessKey": ")[^"]+/\1***MASKED***/'

exec /WebsoftServer/xhttp.out