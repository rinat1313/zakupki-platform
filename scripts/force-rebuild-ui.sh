#!/usr/bin/env bash
# Принудительно: git pull ветки UI → пересборка gateway (ui в образе) → recreate.
#
# На Mac:
#   cd /Users/rinat/Documents/work/platform/zakupki-platform
#   ./scripts/force-rebuild-ui.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
PARENT="$(cd "$ROOT/.." && pwd)"
BRANCH="${BRANCH:-cursor/ui-catalog-csv-7460}"

GATEWAY_PATH="${GATEWAY_PATH:-$PARENT/zakupki-gateway}"
CORE_PATH="${CORE_PATH:-$PARENT/zakupki-core}"
PLATFORM_PATH="$ROOT"

need() { command -v "$1" >/dev/null || { echo "ERROR: нужен $1" >&2; exit 1; }; }
need git
need docker
need curl

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Docker Desktop не запущен" >&2
  exit 1
fi

pull_repo() {
  local path="$1"
  local name
  name="$(basename "$path")"
  if [[ ! -d "$path/.git" ]]; then
    echo "WARN  нет репо $path — пропуск"
    return 0
  fi
  (
    cd "$path"
    git fetch origin --prune
    if ! git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
      echo "ERROR: $name — нет origin/$BRANCH. Сначала push с агента." >&2
      exit 2
    fi
    if ! git diff --quiet || ! git diff --cached --quiet || [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
      git stash push -u -m "force-rebuild-ui $(date +%Y%m%d-%H%M%S)" >/dev/null || true
      echo "  stash $name"
    fi
    git checkout -B "$BRANCH" "origin/$BRANCH"
    echo "  OK  $name @ $(git rev-parse --short HEAD) $(git log -1 --pretty=%s)"
  )
}

echo "=== force-rebuild-ui ==="
echo "branch: $BRANCH"
echo "gateway: $GATEWAY_PATH"

pull_repo "$PLATFORM_PATH"
pull_repo "$GATEWAY_PATH"
pull_repo "$CORE_PATH"

# Проверка, что UI-файлы на диске — новые
MARKER="ai-coverage-pct"
if ! grep -q "$MARKER" "$GATEWAY_PATH/ui/index.html"; then
  echo "ERROR: в $GATEWAY_PATH/ui/index.html нет '$MARKER' — ветка не подтянулась" >&2
  exit 3
fi
if ! grep -q "progress-line" "$GATEWAY_PATH/ui/app.js"; then
  echo "ERROR: в app.js нет progress-line — старый код" >&2
  exit 3
fi
echo "OK  локальный UI содержит $MARKER / progress-line"

echo "→ down"
./up.sh --down || true

echo "→ up --ai (полная пересборка бинарников + образов)"
./up.sh --ai

echo "→ force recreate gateway (на случай кэша слоя)"
export GATEWAY_PATH CORE_PATH
export ANALIZATOR_PATH="${ANALIZATOR_PATH:-$PARENT/analizator_zakupok}"
export PARSER_PATH="${PARSER_PATH:-$PARENT/zakupki-parser}"
export CUSTOMER_PATH="${CUSTOMER_PATH:-$PARENT/zakupki-customer}"
docker compose -f docker-compose.yml -f docker-compose.runtime.yml --profile ai \
  up -d --build --force-recreate --no-deps gateway

sleep 2
echo "→ проверка UI из контейнера / HTTP"
GW_JS="$(curl -fsS "http://127.0.0.1:3000/app.js?v=check" | head -c 200000 || true)"
if echo "$GW_JS" | grep -q "progressLine\|ai-coverage-pct\|renderAICoverage"; then
  echo "OK  http://localhost:3000 отдаёт новый app.js"
else
  echo "FAIL gateway отдаёт старый app.js — смотрите:" >&2
  echo "  docker compose -f docker-compose.yml -f docker-compose.runtime.yml exec gateway ls -la /app/ui" >&2
  echo "  docker compose ... exec gateway grep -n ai-coverage /app/ui/index.html" >&2
  exit 4
fi

echo ""
echo "Готово. Откройте http://localhost:3000 и сделайте Cmd+Shift+R"
echo "gateway commit: $(git -C "$GATEWAY_PATH" rev-parse --short HEAD)"
