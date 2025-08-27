#!/usr/bin/env sh
set -eu

TPL="/WebsoftServer/configs/spxml_unibridge_config.xml.template"
OUT="/WebsoftServer/spxml_unibridge_config.xml"
LOCK_DIR="/WebsoftServer/.spxml.render.lockdir"

[ -f "$TPL" ] || { echo "[init-spxml] template not found: $TPL"; exit 1; }

# простой lock: только один рендер за раз
if mkdir "$LOCK_DIR" 2>/dev/null; then
  trap 'rmdir "$LOCK_DIR" >/dev/null 2>&1 || true' EXIT HUP INT TERM
else
  echo "[init-spxml] another render in progress; skip"
  exit 0
fi

TMP="$(mktemp)"

# Подстановка ${VARNAME} значениями из окружения
awk '
{
  line=$0
  while (match(line, /\$\{[A-Za-z_][A-Za-z0-9_]*\}/)) {
    var = substr(line, RSTART+2, RLENGTH-3)
    val = (var in ENVIRON) ? ENVIRON[var] : ""
    gsub("\\$\\{" var "\\}", val, line)
  }
  print line
}
' "$TPL" > "$TMP"

# Перезаписываем только при изменении
if [ -f "$OUT" ] && cmp -s "$TMP" "$OUT"; then
  echo "[init-spxml] up-to-date"
  rm -f "$TMP"
else
  mv "$TMP" "$OUT"
  echo "[init-spxml] rendered $OUT"
fi