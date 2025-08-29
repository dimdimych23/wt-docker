#!/bin/sh
# /WebsoftServer/init-components.sh
# Установка компонентов из /WebsoftServer/components-init по флагу COMPONENTS_INIT_ENABLED
set -e

[ "${COMPONENTS_INIT_ENABLED}" = "true" ] || { echo "[init-components] disabled"; exit 0; }

INIT_DIR="/WebsoftServer/components-init"
[ -d "$INIT_DIR" ] || { echo "[init-components] no $INIT_DIR"; exit 0; }

# Нормализуем список архивов
set +e
ZIPS=$(ls -1 "$INIT_DIR"/*.zip 2>/dev/null)
RC=$?
set -e
[ $RC -eq 0 ] || { echo "[init-components] no archives"; exit 0; }

echo "[init-components] begin"
# Устанавливаем по алфавиту (можно пронумеровать 01-*, 02-* для порядка зависимостей)
for z in $ZIPS; do
  name="$(basename "$z")"
  echo "[init-components] installing: $name"
  # если wftget доступен — ставим им (рекомендуется)
  if command -v wftget >/dev/null 2>&1; then
    wftget install "$z" || { echo "[init-components] FAILED: $name"; exit 1; }
  else
    # fallback: распаковать напрямую (работает, но всё равно нужен рестарт)
    tmpdir="/tmp/components_unpack.$$"
    mkdir -p "$tmpdir"
    unzip -o -q "$z" -d "$tmpdir"
    cp -R "$tmpdir"/* /WebsoftServer/components/
    rm -rf "$tmpdir"
  fi
done

echo "[init-components] done (restart required)"
exit 0