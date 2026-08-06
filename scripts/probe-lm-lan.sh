#!/usr/bin/env bash
# Проверка: хост и (если запущен) контейнер analizator видят LM Studio из yaml.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PARENT="$(cd "$ROOT/.." && pwd)"
AZ="${ANALIZATOR_PATH:-$PARENT/analizator_zakupok}"
YAML="${1:-$AZ/configs/lm_studio.yaml}"

if [[ ! -f "$YAML" ]]; then
  echo "нет $YAML" >&2
  exit 1
fi

echo "→ yaml: $YAML"
mapfile -t URLS < <(python3 - "$YAML" <<'PY'
import re, sys
from pathlib import Path
t = Path(sys.argv[1]).read_text(encoding="utf-8")
for m in re.finditer(r"base_url:\s*(\S+)", t):
    print(m.group(1).rstrip("/"))
PY
)

fail=0
for u in "${URLS[@]}"; do
  echo
  echo "=== HOST curl $u/models ==="
  if curl -fsS --connect-timeout 3 --max-time 10 "$u/models" | head -c 240; then
    echo
    echo "OK host → $u"
  else
    echo "FAIL host → $u"
    fail=1
  fi
done

echo
echo "=== analizator pool (если :8088 вверх) ==="
if curl -fsS --connect-timeout 2 --max-time 5 http://127.0.0.1:8088/api/v1/lm/pool 2>/dev/null | python3 -m json.tool 2>/dev/null; then
  :
else
  echo "(analizator ещё не отвечает на :8088)"
fi

echo
if [[ $fail -eq 0 ]]; then
  echo "OK: все endpoint'ы из yaml отвечают с хоста"
else
  echo "WARN: часть endpoint'ов с хоста недоступна — на удалённой LMS: Server Start, bind 0.0.0.0, firewall" >&2
  exit 1
fi
