#!/usr/bin/env sh
set -e

TPL="/WebsoftServer/configs/spxml_unibridge_config.xml.template"
OUT="/WebsoftServer/spxml_unibridge_config.xml"
LOCK="/WebsoftServer/.spxml.render.lock"

[ -f "$TPL" ] || { echo "[init-spxml] template not found: $TPL"; exit 1; }

# lock, чтобы не было гонок
exec 9>"$LOCK"
if ! flock -n 9 2>/dev/null; then
  echo "[init-spxml] already running; skip"
  exit 0
fi

TMP="$(mktemp)"
envsubst < "$TPL" > "$TMP"

if [ -f "$OUT" ] && cmp -s "$TMP" "$OUT"; then
  echo "[init-spxml] up-to-date"
  rm -f "$TMP"
else
  mv "$TMP" "$OUT"
  echo "[init-spxml] rendered $OUT"
fi