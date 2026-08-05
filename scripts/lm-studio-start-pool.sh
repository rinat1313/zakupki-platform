#!/usr/bin/env bash
# Работает от analizator_zakupok/configs/lm_studio.yaml (источник правды).
# Не перезаписывает yaml (кроме явного LM_STUDIO_SYNC_YAML=1 + conf).
# Стартует локальный LM Studio при необходимости; удалённые только проверяет.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PARENT="$(cd "$ROOT/.." && pwd)"
ANALIZATOR_PATH="${ANALIZATOR_PATH:-$PARENT/analizator_zakupok}"
YAML="${LM_STUDIO_YAML_OUT:-$ANALIZATOR_PATH/configs/lm_studio.yaml}"
MODEL="${LM_STUDIO_MODEL:-qwen/qwen3-8b}"
CONTEXT_LEN="${LM_STUDIO_CONTEXT_LENGTH:-8192}"
PARALLEL="${LM_STUDIO_PARALLEL:-4}"

log() { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
err() { printf 'ERROR: %s\n' "$*" >&2; }

find_lms() {
  if [[ -n "${LMS_BIN:-}" && -x "$LMS_BIN" ]]; then
    echo "$LMS_BIN"; return 0
  fi
  if command -v lms >/dev/null 2>&1; then
    command -v lms; return 0
  fi
  local c
  for c in \
    "$HOME/.lmstudio/bin/lms" \
    "/Applications/LM Studio.app/Contents/Resources/app/.webpack/bin/lms" \
    "$HOME/Applications/LM Studio.app/Contents/Resources/app/.webpack/bin/lms"
  do
    [[ -x "$c" ]] && { echo "$c"; return 0; }
  done
  return 1
}

is_local_host() {
  case "$1" in
    127.0.0.1|localhost|0.0.0.0|::1|host.docker.internal) return 0 ;;
    *) return 1 ;;
  esac
}

probe_models() {
  local host="$1" port="$2"
  curl -fsS --connect-timeout 2 --max-time 5 "http://${host}:${port}/v1/models" >/dev/null 2>&1
}

probe_tcp() {
  local host="$1" port="$2"
  # /dev/tcp may work where curl hangs
  timeout 3 bash -c "echo >/dev/tcp/${host}/${port}" 2>/dev/null
}

if [[ ! -f "$YAML" ]]; then
  err "нет yaml: $YAML"
  exit 1
fi

log "→ LM pool из yaml (только он): $YAML"

# Parse endpoints: name|host|port|model|concurrent
mapfile -t EPS < <(python3 - "$YAML" <<'PY'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
# very small yaml subset parser via regex blocks
blocks = re.split(r"\n\s*-\s+base_url:", text)
for b in blocks[1:]:
    m = re.search(r"https?://([^:/]+):(\d+)", b)
    if not m:
        continue
    host, port = m.group(1), m.group(2)
    name_m = re.search(r"name:\s*(\S+)", b)
    model_m = re.search(r"model:\s*(\S+)", b)
    conc_m = re.search(r"concurrent:\s*(\d+)", b)
    name = name_m.group(1) if name_m else host
    model = model_m.group(1) if model_m else ""
    conc = conc_m.group(1) if conc_m else "1"
    print(f"{name}|{host}|{port}|{model}|{conc}")
PY
)

if [[ ${#EPS[@]} -eq 0 ]]; then
  err "в $YAML нет endpoints"
  exit 1
fi

for line in "${EPS[@]}"; do
  IFS='|' read -r name host port model conc <<<"$line"
  log "  • $name → http://${host}:${port}/v1 (concurrent=${conc})"
done

LMS=""
if LMS="$(find_lms)"; then
  log "OK  lms → $LMS"
else
  warn "lms CLI не найден — только проверка endpoint'ов"
fi

# Start local servers / load model once
LOCAL_STARTED=0
for line in "${EPS[@]}"; do
  IFS='|' read -r name host port model conc <<<"$line"
  probe_host="$host"
  [[ "$host" == "host.docker.internal" ]] && probe_host="127.0.0.1"
  if ! is_local_host "$host" && ! is_local_host "$probe_host"; then
    continue
  fi
  if [[ -n "$LMS" && "$LOCAL_STARTED" -eq 0 ]]; then
    log "→ lms server start --port $port --bind 0.0.0.0"
    "$LMS" server start --port "$port" --bind 0.0.0.0 --cors 2>/dev/null \
      || "$LMS" server start --port "$port" --bind 0.0.0.0 2>/dev/null \
      || warn "local server start: возможно уже запущен"
    load_model="${model:-$MODEL}"
    log "→ lms load $load_model --context-length $CONTEXT_LEN --parallel $PARALLEL"
    "$LMS" load "$load_model" --context-length "$CONTEXT_LEN" --parallel "$PARALLEL" -y 2>/dev/null \
      || "$LMS" load "$load_model" --context-length "$CONTEXT_LEN" --parallel "$PARALLEL" --yes 2>/dev/null \
      || warn "load $load_model не удался"
    LOCAL_STARTED=1
  fi
done

ok=0
total=${#EPS[@]}
for line in "${EPS[@]}"; do
  IFS='|' read -r name host port model conc <<<"$line"
  probe_host="$host"
  [[ "$host" == "host.docker.internal" ]] && probe_host="127.0.0.1"
  if probe_models "$probe_host" "$port"; then
    log "OK  $name http://${probe_host}:${port}/v1/models"
    ok=$((ok + 1))
  else
    if probe_tcp "$probe_host" "$port"; then
      warn "$name: TCP :${port} открыт, но /v1/models не отвечает (Server Start? модель? firewall?)"
    else
      warn "$name: нет ответа http://${probe_host}:${port}/v1/models"
    fi
  fi
done

log "OK  yaml pool: ответили $ok/$total (список только из yaml, env-default не добавляется)"
exit 0
