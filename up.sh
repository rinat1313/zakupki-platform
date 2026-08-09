#!/usr/bin/env bash
# Единая точка запуска всей платформы.
# Пользователю достаточно: ./up.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

export DOCKER_BUILDKIT="${DOCKER_BUILDKIT:-0}"

COMPOSE=(docker compose)
if ! docker info >/dev/null 2>&1; then
  if command -v sudo >/dev/null && sudo -n docker info >/dev/null 2>&1; then
    COMPOSE=(sudo -E docker compose)
  elif command -v sudo >/dev/null && sudo docker info >/dev/null 2>&1; then
    COMPOSE=(sudo -E docker compose)
  else
    echo "ERROR: Docker не запущен. Установите Docker Desktop / Engine и повторите." >&2
    exit 1
  fi
fi

MODE="default"
NO_BUILD=0
FROM_SOURCE=0

usage() {
  cat <<'USAGE'
Запуск платформы закупок (все сервисы через Docker).

Usage:
  ./up.sh              поднять весь стек (собрать Go → образы → контейнеры)
  ./up.sh --ai         + analizator (LM Studio на хосте :1234)
  ./up.sh --full       + redis + kafka + ai
  ./up.sh --down       остановить всё
  ./up.sh --logs       логи
  ./up.sh --health     проверка health
  ./up.sh --from-source  собирать образы полным Dockerfile (без предсборки Go)
  ./up.sh --no-build   не пересобирать

Одного скрипта достаточно — сервисы и их Dockerfile поднимаются сами.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ai) MODE=ai ;;
    --full) MODE=full ;;
    --down) MODE=down ;;
    --logs) MODE=logs ;;
    --health) MODE=health ;;
    --no-build) NO_BUILD=1 ;;
    --from-source) FROM_SOURCE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

PARENT="$(cd "$ROOT/.." && pwd)"
resolve_repo() {
  local name="$1"
  local envvar="$2"
  local def="$PARENT/$name"
  local val=""
  if [[ -n "${!envvar+x}" ]]; then
    val="${!envvar}"
  fi
  if [[ -n "$val" ]]; then
    echo "$val"
    return
  fi
  if [[ -d "$def" ]]; then
    echo "$def"
    return
  fi
  echo ""
}

export CORE_PATH="$(resolve_repo zakupki-core CORE_PATH)"
export PARSER_PATH="$(resolve_repo zakupki-parser PARSER_PATH)"
export GATEWAY_PATH="$(resolve_repo zakupki-gateway GATEWAY_PATH)"
export CUSTOMER_PATH="$(resolve_repo zakupki-customer CUSTOMER_PATH)"
export ANALIZATOR_PATH="$(resolve_repo analizator_zakupok ANALIZATOR_PATH)"
export SEARCH_PATH="$(resolve_repo zakupki-search SEARCH_PATH)"

need_repos=(CORE_PATH PARSER_PATH GATEWAY_PATH CUSTOMER_PATH)
if [[ "$MODE" == "ai" || "$MODE" == "full" ]]; then
  need_repos+=(ANALIZATOR_PATH)
fi

missing=0
for v in "${need_repos[@]}"; do
  path="${!v}"
  if [[ -z "$path" || ! -d "$path" ]]; then
    echo "ERROR: не найден репозиторий для $v" >&2
    missing=1
  else
    echo "OK  $v = $path"
  fi
done
if [[ $missing -ne 0 ]]; then
  echo >&2
  echo "Ожидается рядом с zakupki-platform:" >&2
  echo "  $PARENT/zakupki-{core,parser,gateway,customer,search}" >&2
  echo "  $PARENT/analizator_zakupok   # для --ai" >&2
  echo "Или: ./scripts/clone-siblings.sh" >&2
  exit 1
fi

# zakupki-search: подключаем, если sibling уже есть (сервис ещё может писаться).
ENABLE_SEARCH=0
if [[ -n "${SEARCH_PATH:-}" && -d "$SEARCH_PATH" ]]; then
  ENABLE_SEARCH=1
  echo "OK  SEARCH_PATH = $SEARCH_PATH"
else
  echo "SKIP SEARCH_PATH (нет ../zakupki-search — поиск не поднимется)"
fi

if [[ ! -f .env && -f .env.example ]]; then
  cp .env.example .env
  echo "created .env from .env.example"
fi

COMPOSE_FILES=(-f docker-compose.yml)
if [[ $FROM_SOURCE -eq 0 ]]; then
  COMPOSE_FILES+=(-f docker-compose.runtime.yml)
fi
if [[ "${ENABLE_SEARCH:-0}" == "1" ]]; then
  COMPOSE_FILES+=(-f docker-compose.search.yml)
fi

# Docker Desktop (macOS/Windows): обычный bridge + published ports.
# Host networking включайте только на Linux при проблемах с bridge: ZAKUPKI_HOST_NET=1
if [[ -z "${ZAKUPKI_HOST_NET:-}" ]]; then
  case "$(uname -s)" in
    Darwin|MINGW*|MSYS*|CYGWIN*) ZAKUPKI_HOST_NET=0 ;;
    *) ZAKUPKI_HOST_NET=0 ;;
  esac
fi
if [[ "${ZAKUPKI_HOST_NET}" == "1" ]]; then
  COMPOSE_FILES+=(-f docker-compose.host.yml)
  echo "OK  network_mode=host (Linux fallback)"
else
  echo "OK  network_mode=bridge (порты на localhost)"
fi

compose() {
  "${COMPOSE[@]}" "${COMPOSE_FILES[@]}" "$@"
}

# Архитектура Linux-контейнеров Docker (не хоста macOS!).
docker_go_arch() {
  local arch
  arch="$(docker info --format '{{.Architecture}}' 2>/dev/null || true)"
  case "$arch" in
    aarch64|arm64|arm64/v8) echo arm64 ;;
    x86_64|amd64) echo amd64 ;;
    *)
      case "$(uname -m)" in
        arm64|aarch64) echo arm64 ;;
        x86_64|amd64) echo amd64 ;;
        *) echo amd64 ;;
      esac
      ;;
  esac
}

prep_bins() {
  echo "→ собираю Go-бинарники для Linux-контейнеров…"
  export GOTOOLCHAIN="${GOTOOLCHAIN:-auto}"
  local goarch
  goarch="$(docker_go_arch)"
  echo "OK  GOOS=linux GOARCH=$goarch"
  mkdir -p "$CORE_PATH/bin" "$PARSER_PATH/bin" "$GATEWAY_PATH/bin" "$CUSTOMER_PATH/bin"
  # Важно: на Mac без GOOS=linux получается darwin-бинарник → exec format error в Docker.
  (cd "$CORE_PATH" && CGO_ENABLED=0 GOOS=linux GOARCH="$goarch" go build -o bin/core ./cmd/core)
  (cd "$PARSER_PATH" && CGO_ENABLED=0 GOOS=linux GOARCH="$goarch" go build -o bin/parser-service ./cmd/service)
  (cd "$GATEWAY_PATH" && CGO_ENABLED=0 GOOS=linux GOARCH="$goarch" go build -o bin/gateway ./cmd/gateway)
  (cd "$CUSTOMER_PATH" && CGO_ENABLED=0 GOOS=linux GOARCH="$goarch" go build -o bin/customer ./cmd/customer)
  if [[ -n "${ANALIZATOR_PATH:-}" && -d "$ANALIZATOR_PATH" ]]; then
    mkdir -p "$ANALIZATOR_PATH/bin"
    (cd "$ANALIZATOR_PATH" && CGO_ENABLED=0 GOOS=linux GOARCH="$goarch" go build -o bin/analizator ./cmd/analizator)
    if [[ ! -f "$ANALIZATOR_PATH/Dockerfile.runtime" ]]; then
      echo "ERROR: нет Dockerfile.runtime в $ANALIZATOR_PATH" >&2
      exit 1
    fi
  fi
  if [[ "${ENABLE_SEARCH:-0}" == "1" ]]; then
    # search собирается полным Dockerfile в образе (миграции + binary).
    if [[ ! -f "$SEARCH_PATH/Dockerfile" ]]; then
      echo "ERROR: нет Dockerfile в $SEARCH_PATH" >&2
      exit 1
    fi
    if [[ ! -d "$SEARCH_PATH/cmd/search" ]]; then
      echo "ERROR: ожидается $SEARCH_PATH/cmd/search" >&2
      exit 1
    fi
    echo "OK  search → Docker multi-stage (Dockerfile), HTTP :8093, DB zakupki_search"
  fi
  # ensure runtime dockerfiles exist
  for pair in \
    "$CORE_PATH:core" \
    "$PARSER_PATH:parser-service" \
    "$GATEWAY_PATH:gateway" \
    "$CUSTOMER_PATH:customer"
  do
    repo="${pair%%:*}"
    if [[ ! -f "$repo/Dockerfile.runtime" ]]; then
      echo "ERROR: нет Dockerfile.runtime в $repo" >&2
      exit 1
    fi
  done
  # gateway needs ui/
  if [[ ! -d "$GATEWAY_PATH/ui" ]]; then
    echo "ERROR: нет ui/ в gateway" >&2
    exit 1
  fi
}

case "$MODE" in
  down)
    down_files=(-f docker-compose.yml -f docker-compose.search.yml)
    "${COMPOSE[@]}" "${down_files[@]}" --profile ai --profile redis --profile kafka down
    echo "stopped"
    exit 0
    ;;
  logs)
    exec compose logs -f --tail=200
    ;;
  health)
    exec ./scripts/health.sh
    ;;
esac

# Wiring: core → analizator в docker-сети. LM/промпты/dose — дефолты самого контейнера.
if [[ "$MODE" == "ai" || "$MODE" == "full" ]]; then
  export ANALIZATOR_URL="${ANALIZATOR_URL:-http://analizator:8088}"
fi
# Wiring: gateway/core могут ходить в search (если сервис поднят).
if [[ "${ENABLE_SEARCH:-0}" == "1" ]]; then
  if [[ "${ZAKUPKI_HOST_NET:-0}" == "1" ]]; then
    export SEARCH_URL="${SEARCH_URL:-http://127.0.0.1:8093}"
  else
    export SEARCH_URL="${SEARCH_URL:-http://search:8093}"
  fi
  echo "OK  SEARCH_URL = $SEARCH_URL"
fi

profiles=()
[[ "$MODE" == "ai" ]] && profiles+=(--profile ai)
[[ "$MODE" == "full" ]] && profiles+=(--profile ai --profile redis --profile kafka)

if [[ $NO_BUILD -eq 0 && $FROM_SOURCE -eq 0 ]]; then
  prep_bins
fi

up_args=(up -d --remove-orphans)
[[ $NO_BUILD -eq 0 ]] && up_args+=(--build)

echo
echo "→ поднимаю контейнеры ($MODE)…"
# Без Progress=tty на Mac иногда кажется, что зависло на "up 2/3" (особенно build analizator).
export BUILDKIT_PROGRESS="${BUILDKIT_PROGRESS:-plain}"
if [[ ${#profiles[@]} -gt 0 ]]; then
  compose "${profiles[@]}" "${up_args[@]}"
else
  compose "${up_args[@]}"
fi

# БД search на уже существующем volume init-скрипт не пересоздаст — гарантируем здесь.
ensure_search_db() {
  [[ "${ENABLE_SEARCH:-0}" == "1" ]] || return 0
  echo "→ ensure database zakupki_search…"
  local i
  for i in $(seq 1 30); do
    if compose exec -T postgres pg_isready -U zakupki >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  if compose exec -T postgres psql -U zakupki -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='zakupki_search'" 2>/dev/null | grep -q 1; then
    echo "OK  database zakupki_search exists"
    return 0
  fi
  if compose exec -T postgres psql -U zakupki -d postgres -c "CREATE DATABASE zakupki_search OWNER zakupki;" >/dev/null 2>&1; then
    echo "OK  created database zakupki_search"
    return 0
  fi
  echo "WARN: не удалось создать zakupki_search — search может не стартовать" >&2
}

ensure_search_db
if [[ "${ENABLE_SEARCH:-0}" == "1" ]]; then
  echo "→ дожидаюсь search…"
  compose up -d --no-deps search >/dev/null 2>&1 || true
fi

echo
echo "→ жду health (до ~2 мин)…"
ok=0
for i in $(seq 1 60); do
  if ./scripts/health.sh >/tmp/zakupki-health.out 2>&1; then
    ok=1
    break
  fi
  # показываем прогресс, чтобы не казалось что зависло
  echo "  … попытка $i/60"
  sed 's/^/     /' /tmp/zakupki-health.out 2>/dev/null || true
  sleep 2
done
echo
cat /tmp/zakupki-health.out || true
if [[ $ok -ne 1 ]]; then
  echo >&2
  echo "WARN: health не зелёный. Статус/логи:" >&2
  compose ps || true
  compose logs --tail=100 || true
  exit 1
fi

echo
echo "Готово."
echo "  UI:       http://localhost:3000"
echo "  Core API: http://localhost:8080/api/v1/health"
echo "  Parser:   http://localhost:8091/health"
echo "  Customer: http://localhost:8092/health"
if [[ "${ENABLE_SEARCH:-0}" == "1" ]]; then
  echo "  Search:   http://localhost:8093/health"
fi
if [[ "$MODE" == "ai" || "$MODE" == "full" ]]; then
  echo "  Analizator: http://localhost:8088/health"
fi
echo
echo "Остановить: ./up.sh --down"
echo "Логи:       ./up.sh --logs"
