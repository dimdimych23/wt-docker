#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# 1) env
ENV_BUILD="${ROOT}/.env.build"
if [ -f "$ENV_BUILD" ]; then
  export $(grep -E '^[A-Z0-9_]+=' "$ENV_BUILD" | xargs)
fi

WT_BASE_IMAGE="${WT_BASE_IMAGE:-websoft/hcm:2025.2.1225}"
IMAGE_REPO="${IMAGE_REPO:-hcm/platform}"
IMAGE_TAG="${IMAGE_TAG:-2025.2.1225-tmk.1}"

IMAGE_TITLE="${IMAGE_TITLE:-WebSoft HCM (custom)}"
IMAGE_DESCRIPTION="${IMAGE_DESCRIPTION:-HCM with curated components}"
LABEL_NOTES="${LABEL_NOTES:-}"

COMPONENTS_SRC="${COMPONENTS_SRC:-websoft/components.src}"
COMPONENTS_LIST="${COMPONENTS_LIST:-}"   # <--- НОВОЕ

REGISTRY_HOST="${REGISTRY_HOST:-}"
REGISTRY_USER="${REGISTRY_USER:-}"
REGISTRY_PASS="${REGISTRY_PASS:-}"
PUSH="${PUSH:-false}"

if [ -n "$REGISTRY_HOST" ]; then
  FULL_IMAGE="${REGISTRY_HOST}/${IMAGE_REPO}:${IMAGE_TAG}"
else
  FULL_IMAGE="${IMAGE_REPO}:${IMAGE_TAG}"
fi

echo "[build] base:   $WT_BASE_IMAGE"
echo "[build] image:  $FULL_IMAGE"
echo "[build] comps:  $COMPONENTS_SRC"
[ -z "$COMPONENTS_LIST" ] || echo "[build] list:   $COMPONENTS_LIST"

# Каталог источника компонентов
SRC_DIR="${ROOT}/${COMPONENTS_SRC}"
if [ ! -d "$SRC_DIR" ]; then
  echo "[info] ${COMPONENTS_SRC} not found — создаю пустой каталог"
  mkdir -p "$SRC_DIR"
fi

# 2) Подтянем базу и метаданные
docker pull "$WT_BASE_IMAGE" >/dev/null 2>&1 || true
BASE_DIGEST="$(docker inspect --format='{{index .RepoDigests 0}}' "$WT_BASE_IMAGE" 2>/dev/null || echo "")"
GIT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo "")"
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# 3) Подготовим «выбранные» компоненты (если задан COMPONENTS_LIST)
#    Чтобы COPY не тащил всё подряд, соберём временный каталог из выбранных папок
SELECTED_DIR="${ROOT}/build/components.selected"
rm -rf "$SELECTED_DIR"; mkdir -p "$SELECTED_DIR"

trim() { awk '{$1=$1;print}'; }

if [ -n "$COMPONENTS_LIST" ]; then
  IFS=',' read -r -a ITEMS <<< "$COMPONENTS_LIST"
  COMPONENTS_ARRAY=()
  for raw in "${ITEMS[@]}"; do
    comp="$(echo "$raw" | tr -d '\r' | trim)"
    [ -z "$comp" ] && continue
    if [ -d "${SRC_DIR}/${comp}" ]; then
      cp -R "${SRC_DIR}/${comp}" "${SELECTED_DIR}/"
      COMPONENTS_ARRAY+=("$comp")
    else
      echo "[error] компонента '${comp}' нет в ${COMPONENTS_SRC}" >&2
      exit 1
    fi
  done
  # Манифест из списка
  COMPONENTS_MANIFEST="$(printf "%s\n" "${COMPONENTS_ARRAY[@]}" | paste -sd, -)"
  # JSON для укладки в образ
  COMPONENTS_MANIFEST_JSON="$(printf '['; printf '"%s",' "${COMPONENTS_ARRAY[@]}" | sed 's/,$//'; printf ']')"
  # Источник для COPY переключаем на выбранные
  EFFECTIVE_SRC="build/components.selected"
else
  # Если список не задан — берём все подпапки из источника
  EFFECTIVE_SRC="$COMPONENTS_SRC"
  # Сформируем манифест из всех подпапок (может быть пусто — ок)
  if [ -d "$SRC_DIR" ]; then
    ALL=$(ls -1 "$SRC_DIR" 2>/dev/null || true)
    COMPONENTS_MANIFEST="$(printf "%s\n" $ALL | paste -sd, - 2>/dev/null || true)"
    # JSON
    if [ -n "$ALL" ]; then
      COMPONENTS_MANIFEST_JSON="$(printf '%s\n' $ALL | awk 'BEGIN{printf("[]")} {gsub(/"/,"\\\""); if(NR==1){printf("[\"%s\"", $0)} else {printf(",\"%s\"",$0)}} END{if(NR>0)printf("]");}' )"
    else
      COMPONENTS_MANIFEST_JSON="[]"
    fi
  else
    COMPONENTS_MANIFEST=""
    COMPONENTS_MANIFEST_JSON="[]"
  fi
fi

echo "[build] using src: $EFFECTIVE_SRC"
[ -n "$COMPONENTS_MANIFEST" ] && echo "[build] manifest: $COMPONENTS_MANIFEST"

# 4) Сборка
docker build \
  --build-arg WT_BASE_IMAGE="$WT_BASE_IMAGE" \
  --build-arg COMPONENTS_SRC="$EFFECTIVE_SRC" \
  --build-arg IMAGE_TITLE="$IMAGE_TITLE" \
  --build-arg IMAGE_DESCRIPTION="$IMAGE_DESCRIPTION" \
  --build-arg GIT_SHA="$GIT_SHA" \
  --build-arg BUILD_DATE="$BUILD_DATE" \
  --build-arg BASE_DIGEST="$BASE_DIGEST" \
  --build-arg COMPONENTS_MANIFEST="$COMPONENTS_MANIFEST" \
  --build-arg LABEL_NOTES="$LABEL_NOTES" \
  --build-arg COMPONENTS_MANIFEST_JSON="$COMPONENTS_MANIFEST_JSON" \
  -f "${ROOT}/Dockerfile.hcm" \
  -t "$FULL_IMAGE" \
  "${ROOT}"

# 5) Пуш (опц.)
if [ "$PUSH" = "true" ] && [ -n "$REGISTRY_HOST" ]; then
  echo "[push] → ${REGISTRY_HOST}"
  if [ -n "$REGISTRY_USER" ] && [ -n "$REGISTRY_PASS" ]; then
    echo "$REGISTRY_PASS" | docker login -u "$REGISTRY_USER" --password-stdin "$REGISTRY_HOST"
  else
    echo "[warn] нет REGISTRY_USER/REGISTRY_PASS — предполагаю, что login уже сделан"
  fi
  docker push "$FULL_IMAGE"
else
  echo "[push] skip (PUSH=$PUSH, REGISTRY_HOST=$REGISTRY_HOST)"
fi

# 6) Обновим WT_IMAGE в .env
PLATFORM_ENV="${ROOT}/.env"
if [ -f "$PLATFORM_ENV" ]; then
  if grep -q '^WT_IMAGE=' "$PLATFORM_ENV"; then
    sed -i.bak "s#^WT_IMAGE=.*#WT_IMAGE=${FULL_IMAGE}#g" "$PLATFORM_ENV"
  else
    echo "WT_IMAGE=${FULL_IMAGE}" >> "$PLATFORM_ENV"
  fi
  echo "[env] WT_IMAGE set to ${FULL_IMAGE} in .env"
else
  echo "[env] WARNING: .env не найден — пропустил обновление"
fi

echo "[done] image ready: ${FULL_IMAGE}"