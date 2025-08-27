#!/bin/sh
set -e

TPL="/WebsoftServer/configs/spxml_unibridge_config.xml.template"
OUT="/WebsoftServer/spxml_unibridge_config.xml"

# envsubst предпочтителен, но если его нет — подменим через awk
if command -v envsubst >/dev/null 2>&1; then
  envsubst < "$TPL" > "$OUT"
else
  awk '{
    line=$0
    while (match(line, /\$\{[A-Za-z0-9_]+\}/)) {
      var=substr(line, RSTART+2, RLENGTH-3)
      gsub("\\$\\{"var"\\}", ENVIRON[var] ? ENVIRON[var] : "", line)
    }
    print line
  }' "$TPL" > "$OUT"
fi

echo "[init-spxml] rendered $OUT"