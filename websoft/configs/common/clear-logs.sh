#!/bin/sh
# Очистка логов внутри примонтированных папок web-backend-1, web-backend-2 и worker-backend
# Удаляет все файлы кроме .gitkeep/.gitkip

# Путь к логам на хосте (относительно корня проекта)
LOGS_BASE="$PWD/websoft/Logs"

DIRS="$LOGS_BASE/web-backend-1
$LOGS_BASE/web-backend-2
$LOGS_BASE/worker-backend"

echo "[clear-logs] Начинаю очистку логов..."
for dir in $DIRS; do
  if [ -d "$dir" ]; then
    echo "  -> Очищаю $dir"
    find "$dir" -type f ! \( -name ".gitkeep" -o -name ".gitkip" \) -delete
  else
    echo "  -> Пропускаю $dir (нет такой папки)"
  fi
done
echo "[clear-logs] Очистка завершена."cd ..