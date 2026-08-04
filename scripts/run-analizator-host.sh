#!/usr/bin/env bash
# Запуск analizator на Mac-хосте (обходит Docker→LM Studio networking).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PARENT="$(cd "$ROOT/.." && pwd)"
AZ="${ANALIZATOR_PATH:-$PARENT/analizator_zakupok}"
if [[ ! -d "$AZ" ]]; then
  echo "не найден $AZ" >&2
  exit 1
fi
: "${LM_STUDIO_BASE_URL:?задайте LM_STUDIO_BASE_URL, напр. http://127.0.0.1:1234/v1}"
: "${LM_STUDIO_MODEL:?задайте LM_STUDIO_MODEL}"
export LM_STUDIO_API_KEY="${LM_STUDIO_API_KEY:-lm-studio}"
export HTTP_ADDR="${HTTP_ADDR:-:8088}"
export TENDERS_ROOT="${TENDERS_ROOT:-/tmp/zakupki-tenders}"
mkdir -p "$TENDERS_ROOT"
cd "$AZ"
echo "analizator → $LM_STUDIO_BASE_URL model=$LM_STUDIO_MODEL"
echo "listening $HTTP_ADDR"
exec go run ./cmd/analizator
