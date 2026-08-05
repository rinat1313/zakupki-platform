#!/usr/bin/env bash
# Поднимает LM Studio (модель qwen/qwen3-8b, context 8192, thinking off)
# по списку host:port из configs/lm_studio_pool.conf и синхронизирует
# analizator_zakupok/configs/lm_studio.yaml для Docker/analizator.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PARENT="$(cd "$ROOT/.." && pwd)"
CONF="${LM_STUDIO_POOL_CONF:-$ROOT/configs/lm_studio_pool.conf}"
ANALIZATOR_PATH="${ANALIZATOR_PATH:-$PARENT/analizator_zakupok}"
OUT_YAML="${LM_STUDIO_YAML_OUT:-$ANALIZATOR_PATH/configs/lm_studio.yaml}"
MODEL="${LM_STUDIO_MODEL:-qwen/qwen3-8b}"
CONTEXT_LEN="${LM_STUDIO_CONTEXT_LENGTH:-8192}"
API_KEY="${LM_STUDIO_API_KEY:-lm-studio}"
PARALLEL="${LM_STUDIO_PARALLEL:-}"

log() { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
err() { printf 'ERROR: %s\n' "$*" >&2; }

find_lms() {
  if [[ -n "${LMS_BIN:-}" && -x "$LMS_BIN" ]]; then
    echo "$LMS_BIN"
    return 0
  fi
  if command -v lms >/dev/null 2>&1; then
    command -v lms
    return 0
  fi
  local c
  for c in \
    "$HOME/.lmstudio/bin/lms" \
    "/Applications/LM Studio.app/Contents/Resources/app/.webpack/bin/lms" \
    "$HOME/Applications/LM Studio.app/Contents/Resources/app/.webpack/bin/lms"
  do
    if [[ -x "$c" ]]; then
      echo "$c"
      return 0
    fi
  done
  return 1
}

is_local_host() {
  case "$1" in
    127.0.0.1|localhost|0.0.0.0|::1) return 0 ;;
    *) return 1 ;;
  esac
}

docker_host_for() {
  local host="$1"
  if is_local_host "$host"; then
    echo "host.docker.internal"
  else
    echo "$host"
  fi
}

probe_models() {
  local host="$1" port="$2"
  curl -fsS --max-time 3 "http://${host}:${port}/v1/models" >/dev/null 2>&1
}

disable_thinking_model_yaml() {
  local roots=()
  local r
  for r in \
    "$HOME/.lmstudio/hub/models" \
    "$HOME/.cache/lm-studio/models" \
    "$HOME/.lmstudio/models"
  do
    [[ -d "$r" ]] && roots+=("$r")
  done
  [[ ${#roots[@]} -eq 0 ]] && return 0

  local files=()
  while IFS= read -r f; do
    [[ -n "$f" ]] && files+=("$f")
  done < <(find "${roots[@]}" -type f -name 'model.yaml' 2>/dev/null | grep -iE 'qwen3-8b|qwen/qwen3' | head -20)

  local f
  for f in "${files[@]+"${files[@]}"}"; do
    [[ -f "$f" ]] || continue
    grep -q 'key:[[:space:]]*enableThinking' "$f" 2>/dev/null || continue
    python3 - "$f" <<'PY' 2>/dev/null || true
import re, sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
pat = re.compile(r"(key:\s*enableThinking.*?defaultValue:\s*)true", re.S)
new, n = pat.subn(r"\1false", text, count=1)
if n:
    open(path, "w", encoding="utf-8").write(new)
    print(f"patched thinking off: {path}")
PY
  done
}

write_yaml_all() {
  local out="$1"
  mkdir -p "$(dirname "$out")"
  local n="${#NAMES[@]}"
  {
    echo "# Автогенерация: scripts/lm-studio-start-pool.sh"
    echo "# Источник: $CONF"
    echo "# Модель $MODEL, context $CONTEXT_LEN, thinking off (клиент + model.yaml)."
    echo "# IP/порты: configs/lm_studio_pool.conf → ./up.sh --ai"
    echo
    echo "endpoints:"
    if [[ "$n" -eq 1 ]]; then
      local dh
      dh="$(docker_host_for "${HOSTS[0]}")"
      cat <<EOF
  - base_url: http://${dh}:${PORTS[0]}/v1
    api_key: ${API_KEY}
    model: ${MODEL}
    name: ${NAMES[0]}
    concurrent: ${PARALLEL:-4}
EOF
    else
      local i=0
      while [[ $i -lt ${#NAMES[@]} ]]; do
        local dh
        dh="$(docker_host_for "${HOSTS[$i]}")"
        cat <<EOF
  - base_url: http://${dh}:${PORTS[$i]}/v1
    api_key: ${API_KEY}
    model: ${MODEL}
    name: ${NAMES[$i]}
EOF
        i=$((i + 1))
      done
    fi
    echo
    echo "health_interval_sec: 15"
    echo "context_length: ${CONTEXT_LEN}"
    echo "thinking: false"
  } >"$out"
  log "OK  записан $out"
}

write_yaml_single_parallel() {
  local out="$1" primary_port="$2" parallel="$3"
  local dh
  dh="$(docker_host_for 127.0.0.1)"
  mkdir -p "$(dirname "$out")"
  {
    echo "# Автогенерация: scripts/lm-studio-start-pool.sh (single-server + parallel)"
    echo "# Источник: $CONF"
    echo "# Один LM Studio на :${primary_port}, concurrent=${parallel}, context=${CONTEXT_LEN}."
    echo
    echo "endpoints:"
    echo "  - base_url: http://${dh}:${primary_port}/v1"
    echo "    api_key: ${API_KEY}"
    echo "    model: ${MODEL}"
    echo "    name: lm-primary"
    echo "    concurrent: ${parallel}"
    local i=0
    while [[ $i -lt ${#NAMES[@]} ]]; do
      if is_local_host "${HOSTS[$i]}" && [[ "${PORTS[$i]}" == "$primary_port" ]]; then
        i=$((i + 1))
        continue
      fi
      local h
      h="$(docker_host_for "${HOSTS[$i]}")"
      echo "  - base_url: http://${h}:${PORTS[$i]}/v1"
      echo "    api_key: ${API_KEY}"
      echo "    model: ${MODEL}"
      echo "    name: ${NAMES[$i]}"
      i=$((i + 1))
    done
    echo
    echo "health_interval_sec: 15"
    echo "context_length: ${CONTEXT_LEN}"
    echo "thinking: false"
  } >"$out"
  log "OK  записан $out (concurrent=${parallel} на :${primary_port})"
}

# --- load pool config ---
if [[ ! -f "$CONF" ]]; then
  err "нет конфига пула: $CONF"
  exit 1
fi

NAMES=()
HOSTS=()
PORTS=()
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%%#*}"
  line="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [[ -z "$line" ]] && continue
  # shellcheck disable=SC2086
  set -- $line
  if [[ $# -lt 3 ]]; then
    warn "пропуск строки (нужно: name host port): $line"
    continue
  fi
  NAMES+=("$1")
  HOSTS+=("$2")
  PORTS+=("$3")
done <"$CONF"

if [[ ${#NAMES[@]} -eq 0 ]]; then
  err "в $CONF нет ни одного инстанса"
  exit 1
fi

log "→ LM Studio pool: ${#NAMES[@]} endpoint(ов), model=$MODEL context=$CONTEXT_LEN"

if [[ -z "$PARALLEL" ]]; then
  PARALLEL="${LM_STUDIO_PARALLEL_DEFAULT:-4}"
fi

write_yaml_all "$OUT_YAML"

LMS=""
if ! LMS="$(find_lms)"; then
  warn "lms CLI не найден — YAML обновлён; поднимите LM Studio вручную."
  i=0
  while [[ $i -lt ${#NAMES[@]} ]]; do
    if probe_models "${HOSTS[$i]}" "${PORTS[$i]}"; then
      log "OK  ${NAMES[$i]} http://${HOSTS[$i]}:${PORTS[$i]}/v1"
    else
      warn "нет ответа ${NAMES[$i]} http://${HOSTS[$i]}:${PORTS[$i]}/v1"
    fi
    i=$((i + 1))
  done
  exit 0
fi
log "OK  lms → $LMS"

disable_thinking_model_yaml || true

LOCAL_PORTS=()
REMOTE_IDX=()
i=0
while [[ $i -lt ${#NAMES[@]} ]]; do
  if is_local_host "${HOSTS[$i]}"; then
    LOCAL_PORTS+=("${PORTS[$i]}")
  else
    REMOTE_IDX+=("$i")
  fi
  i=$((i + 1))
done

PRIMARY_PORT=""
if [[ ${#LOCAL_PORTS[@]} -gt 0 ]]; then
  PRIMARY_PORT="${LOCAL_PORTS[0]}"
  log "→ lms server start --port $PRIMARY_PORT --bind 0.0.0.0"
  "$LMS" server start --port "$PRIMARY_PORT" --bind 0.0.0.0 --cors 2>/dev/null \
    || "$LMS" server start --port "$PRIMARY_PORT" --bind 0.0.0.0 2>/dev/null \
    || warn "server start вернул ошибку (возможно уже запущен)"

  j=1
  while [[ $j -lt ${#LOCAL_PORTS[@]} ]]; do
    pp="${LOCAL_PORTS[$j]}"
    if probe_models 127.0.0.1 "$pp"; then
      log "OK  уже слушает :$pp"
    else
      log "→ попытка lms server start --port $pp"
      if ! "$LMS" server start --port "$pp" --bind 0.0.0.0 2>/dev/null; then
        warn "порт $pp не стартовал — для 4 портов нужны разные хосты LMS"
      fi
    fi
    j=$((j + 1))
  done

  log "→ lms load $MODEL --context-length $CONTEXT_LEN --parallel $PARALLEL"
  if ! "$LMS" load "$MODEL" --context-length "$CONTEXT_LEN" --parallel "$PARALLEL" -y 2>/dev/null; then
    "$LMS" load "$MODEL" --context-length "$CONTEXT_LEN" --parallel "$PARALLEL" --yes 2>/dev/null \
      || "$LMS" load "$MODEL" --context-length "$CONTEXT_LEN" -y 2>/dev/null \
      || warn "load не удался — загрузите $MODEL вручную (context $CONTEXT_LEN)"
  fi
fi

for i in "${REMOTE_IDX[@]+"${REMOTE_IDX[@]}"}"; do
  [[ -n "${i:-}" ]] || continue
  rh="${HOSTS[$i]}"; rp="${PORTS[$i]}"; rn="${NAMES[$i]}"
  log "→ remote $rn ${rh}:${rp}"
  if probe_models "$rh" "$rp"; then
    "$LMS" load "$MODEL" --context-length "$CONTEXT_LEN" --parallel 1 --host "$rh" -y 2>/dev/null \
      || "$LMS" load "$MODEL" --context-length "$CONTEXT_LEN" --host "$rh" -y 2>/dev/null \
      || true
    log "OK  remote отвечает $rn"
  else
    warn "remote $rn http://${rh}:${rp} недоступен"
  fi
done

ok=0
alive_local=0
i=0
while [[ $i -lt ${#NAMES[@]} ]]; do
  h="${HOSTS[$i]}"; p="${PORTS[$i]}"
  if probe_models "$h" "$p"; then
    log "OK  ${NAMES[$i]} http://${h}:${p}/v1 models"
    ok=$((ok + 1))
    if is_local_host "$h"; then
      alive_local=$((alive_local + 1))
    fi
  else
    warn "нет /v1/models у ${NAMES[$i]} http://${h}:${p}"
  fi
  i=$((i + 1))
done

if [[ -n "$PRIMARY_PORT" ]] && [[ $alive_local -eq 1 ]] && [[ ${#LOCAL_PORTS[@]} -gt 1 ]]; then
  write_yaml_single_parallel "$OUT_YAML" "$PRIMARY_PORT" "$PARALLEL"
fi

if [[ $ok -eq 0 ]]; then
  warn "ни один endpoint не ответил. Откройте LM Studio (Server Start) и повторите."
  exit 0
fi

log "OK  LM Studio pool готов (ответили: $ok/${#NAMES[@]})"
