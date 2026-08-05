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
  ./up.sh --ai         + analizator + LM Studio pool (1×:1234×4 слота или N хостов)
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
  echo "  $PARENT/zakupki-{core,parser,gateway,customer}" >&2
  echo "  $PARENT/analizator_zakupok   # для --ai" >&2
  echo "Или: ./scripts/clone-siblings.sh" >&2
  exit 1
fi

if [[ ! -f .env && -f .env.example ]]; then
  cp .env.example .env
  echo "created .env from .env.example"
fi

COMPOSE_FILES=(-f docker-compose.yml)
if [[ $FROM_SOURCE -eq 0 ]]; then
  COMPOSE_FILES+=(-f docker-compose.runtime.yml)
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

# Docker Compose: значения из текущего shell перекрывают файл .env.
# Старый `export LM_STUDIO_BASE_URL=...:55674` как раз давал connection refused
# при работающем LM Studio на :1234.
ensure_lm_studio_env() {
  local env_url="" env_key="" env_model=""
  if [[ -f .env ]]; then
    # читаем только нужные ключи (без source всего файла — безопаснее)
    env_url="$(grep -E '^[[:space:]]*LM_STUDIO_BASE_URL=' .env | tail -1 | cut -d= -f2- | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")"
    env_key="$(grep -E '^[[:space:]]*LM_STUDIO_API_KEY=' .env | tail -1 | cut -d= -f2- | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")"
    env_model="$(grep -E '^[[:space:]]*LM_STUDIO_MODEL=' .env | tail -1 | cut -d= -f2- | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")"
  fi

  # Предпочитаем .env, затем уже export из shell, затем дефолт :1234
  if [[ -n "$env_url" ]]; then
    export LM_STUDIO_BASE_URL="$env_url"
  fi
  export LM_STUDIO_BASE_URL="${LM_STUDIO_BASE_URL:-http://192.168.1.124:1234/v1}"

  if [[ -n "$env_key" ]]; then
    export LM_STUDIO_API_KEY="$env_key"
  fi
  export LM_STUDIO_API_KEY="${LM_STUDIO_API_KEY:-lm-studio}"

  if [[ -n "$env_model" ]]; then
    export LM_STUDIO_MODEL="$env_model"
  fi
  export LM_STUDIO_MODEL="${LM_STUDIO_MODEL:-qwen/qwen3-8b}"

  # Чиним только застрявший порт 55674. Не форсим host.docker.internal —
  # основной сервер может быть LAN (192.168.1.124:1234).
  if [[ "$LM_STUDIO_BASE_URL" == *":55674"* ]]; then
    echo "WARN: LM_STUDIO_BASE_URL содержит старый порт 55674 → 192.168.1.124:1234" >&2
    export LM_STUDIO_BASE_URL="http://192.168.1.124:1234/v1"
  fi
  # Опционально: ZAKUPKI_LM_FORCE_1234=1 только чинит НЕ-:1234 URL на LAN primary
  if [[ "${ZAKUPKI_LM_FORCE_1234:-0}" == "1" ]] && [[ "$LM_STUDIO_BASE_URL" != *":1234"* ]]; then
    echo "WARN: LM_STUDIO_BASE_URL=$LM_STUDIO_BASE_URL не на :1234 → 192.168.1.124:1234" >&2
    export LM_STUDIO_BASE_URL="http://192.168.1.124:1234/v1"
  fi

  # Синхронизируем .env, чтобы следующий запуск и UI-доки совпадали
  if [[ -f .env ]]; then
    tmp="$(mktemp)"
    grep -v -E '^[[:space:]]*LM_STUDIO_(BASE_URL|API_KEY|MODEL)=' .env >"$tmp" || true
    {
      echo "LM_STUDIO_BASE_URL=$LM_STUDIO_BASE_URL"
      echo "LM_STUDIO_API_KEY=$LM_STUDIO_API_KEY"
      echo "LM_STUDIO_MODEL=$LM_STUDIO_MODEL"
    } >>"$tmp"
    mv "$tmp" .env
  fi

  echo "OK  LM Studio → $LM_STUDIO_BASE_URL  model=$LM_STUDIO_MODEL"
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
    "${COMPOSE[@]}" -f docker-compose.yml --profile ai --profile redis --profile kafka down
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

if [[ "$MODE" == "ai" || "$MODE" == "full" ]]; then
  export ANALIZATOR_URL="${ANALIZATOR_URL:-http://analizator:8088}"
  # Compose: переменные из shell ПЕРЕБИВАЮТ .env — из‑за старого
  # `export LM_STUDIO_BASE_URL=...:55674` контейнер продолжал ходить не туда.
  ensure_lm_studio_env

  # Выравниваем LM_STUDIO_BASE_URL с первым endpoint из yaml (источник правды).
  YAML_LM="$ANALIZATOR_PATH/configs/lm_studio.yaml"
  if [[ -f "$YAML_LM" ]]; then
    first_url="$(python3 - "$YAML_LM" <<'PY'
import re, sys
from pathlib import Path
t = Path(sys.argv[1]).read_text(encoding="utf-8")
m = re.search(r"base_url:\s*(\S+)", t)
print(m.group(1).strip().rstrip("/") if m else "")
PY
)"
    if [[ -n "$first_url" ]]; then
      export LM_STUDIO_BASE_URL="$first_url"
      if [[ -f .env ]]; then
        tmp="$(mktemp)"
        grep -v -E '^[[:space:]]*LM_STUDIO_BASE_URL=' .env >"$tmp" || true
        echo "LM_STUDIO_BASE_URL=$LM_STUDIO_BASE_URL" >>"$tmp"
        mv "$tmp" .env
      fi
      echo "OK  LM_STUDIO_BASE_URL ← yaml primary: $LM_STUDIO_BASE_URL"
    fi
  fi

  # Пул LM: список серверов только в analizator configs/lm_studio.yaml (не затираем).
  if [[ "${ZAKUPKI_SKIP_LM_POOL:-0}" != "1" ]]; then
    echo "→ LM Studio pool из yaml (analizator_zakupok/configs/lm_studio.yaml)…"
    ANALIZATOR_PATH="$ANALIZATOR_PATH" \
      LM_STUDIO_MODEL="${LM_STUDIO_MODEL:-qwen/qwen3-8b}" \
      LM_STUDIO_API_KEY="${LM_STUDIO_API_KEY:-lm-studio}" \
      bash "$ROOT/scripts/lm-studio-start-pool.sh" || {
        echo "WARN: lm-studio-start-pool.sh завершился с ошибкой — контейнеры всё равно подниму" >&2
      }
  else
    echo "OK  skip LM pool (ZAKUPKI_SKIP_LM_POOL=1)"
  fi
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

# Отдельно пересоздаём analizator с актуальным LM_STUDIO_* (shell больше не перекрывает .env)
if [[ "$MODE" == "ai" || "$MODE" == "full" ]]; then
  echo "→ force-recreate analizator (LM_STUDIO_BASE_URL=$LM_STUDIO_BASE_URL)…"
  compose --profile ai up -d --force-recreate --no-deps analizator
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
if [[ "$MODE" == "ai" || "$MODE" == "full" ]]; then
  echo "  Analizator: http://localhost:8088/health"
fi
echo
echo "Остановить: ./up.sh --down"
echo "Логи:       ./up.sh --logs"
