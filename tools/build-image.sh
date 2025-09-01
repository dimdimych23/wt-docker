#!/usr/bin/env bash
# Собирает кастомный образ WebSoft HCM с твоими компонентами,
# (опционально) пушит в Nexus и обновляет WT_IMAGE в .env проекта.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# 1) Подхват параметров из .env.build
ENV_BUILD="${ROOT}/.env.build"
if [ -f "$ENV_BUILD" ]; then
  export $(grep -E '^[A-Z0-9_]+=' "$ENV_BUILD" | xargs)
fi

# 2) Значения по умолчанию
WT_BASE_IMAGE="${WT_BASE_IMAGE:-websoft/hcm:2025.2.1225}"
IMAGE_REPO="${IMAGE_REPO:-hcm/platform}"
IMAGE_TAG="${IMAGE_TAG:-2025.2.1225-tmk.1}"

IMAGE_TITLE="${IMAGE_TITLE:-WebSoft HCM (custom)}"
IMAGE_DESCRIPTION="${IMAGE_DESCRIPTION:-HCM with curated components}"
LABEL_NOTES="${LABEL_NOTES:-}"

COMPONENTS_SRC="${COMPONENTS_SRC:-websoft/components.src}"

REGISTRY_HOST="${REGISTRY_HOST:-}"
REGISTRY_USER="${REGISTRY_USER:-}"
REGISTRY_PASS="${REGISTRY_PASS:-}"
PUSH="${PUSH:-false}"

# Полное имя образа
if [ -n "$REGISTRY_HOST" ]; then
  FULL_IMAGE="${REGISTRY_HOST}/${IMAGE_REPO}:${IMAGE_TAG}"
else
  FULL_IMAGE="${IMAGE_REPO}:${IMAGE_TAG}"
fi

echo "[build] base:   $WT_BASE_IMAGE"
echo "[build] image:  $FULL_IMAGE"
echo "[build] comps:  $COMPONENTS_SRC"

# 3) Проверим каталог компонентов (может быть пустым — ок)
if [ ! -d "${ROOT}/${COMPONENTS_SRC}" ]; then
  echo "[info] ${COMPONENTS_SRC} not found — создаю пустой каталог"
  mkdir -p "${ROOT}/${COMPONENTS_SRC}"
fi

# 4) Подтянем базовый образ и узнаем его digest (для меток)
docker pull "$WT_BASE_IMAGE" >/dev/null 2>&1 || true
BASE_DIGEST="$(docker inspect --format='{{index .RepoDigests 0}}' "$WT_BASE_IMAGE" 2>/dev/null || echo "")"
GIT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo "")"
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# 5) «Манифест компонентов» — список подпапок в components.src (через запятую)
if [ -d "${ROOT}/${COMPONENTS_SRC}" ]; then
  COMPONENTS_MANIFEST="$(ls -1 "${ROOT}/${COMPONENTS_SRC}" | paste -sd, - 2>/dev/null || true)"
else
  COMPONENTS_MANIFEST=""
fi

# 6) Сборка
docker build \
  --build-arg WT_BASE_IMAGE="$WT_BASE_IMAGE" \
  --build-arg COMPONENTS_SRC="$COMPONENTS_SRC" \
  --build-arg IMAGE_TITLE="$IMAGE_TITLE" \
  --build-arg IMAGE_DESCRIPTION="$IMAGE_DESCRIPTION" \
  --build-arg GIT_SHA="$GIT_SHA" \
  --build-arg BUILD_DATE="$BUILD_DATE" \
  --build-arg BASE_DIGEST="$BASE_DIGEST" \
  --build-arg COMPONENTS_MANIFEST="$COMPONENTS_MANIFEST" \
  --build-arg LABEL_NOTES="$LABEL_NOTES" \
  -f "${ROOT}/Dockerfile.hcm" \
  -t "$FULL_IMAGE" \
  "${ROOT}"

# 7) (опц.) пуш в Nexus
if [ "$PUSH" = "true" ] && [ -n "$REGISTRY_HOST" ]; then
  echo "[push] → ${REGISTRY_HOST}"
  if [ -n "$REGISTRY_USER" ] && [ -n "$REGISTRY_PASS" ]; then
    echo "$REGISTRY_PASS" | docker login -u "$REGISTRY_USER" --password-stdin "$REGISTRY_HOST"
  else
    echo "[warn] нет REGISTRY_USER/REGISTRY_PASS — предполагаю, что логин уже сделан (docker login)"
  fi
  docker push "$FULL_IMAGE"
else
  echo "[push] skip (PUSH=$PUSH, REGISTRY_HOST=$REGISTRY_HOST)"
fi

# 8) Обновим WT_IMAGE в .env проекта
PLATFORM_ENV="${ROOT}/.env"
if [ -f "$PLATFORM_ENV" ]; then
  if grep -q '^WT_IMAGE=' "$PLATFORM_ENV"; then
    sed -i.bak "s#^WT_IMAGE=.*#WT_IMAGE=${FULL_IMAGE}#g" "$PLATFORM_ENV"
  else
    echo "WT_IMAGE=${FULL_IMAGE}" >> "$PLATFORM_ENV"
  fi
  echo "[env] WT_IMAGE set to ${FULL_IMAGE} in .env"
else
  echo "[env] WARNING: .env не найден, пропускаю обновление WT_IMAGE"
fi

echo "[done] image ready: ${FULL_IMAGE}"