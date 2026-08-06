#!/usr/bin/env bash
# Полный локальный пересборка + проверка LM Studio + запуск стека с AI.
#
# Запуск с Mac:
#   cd /Users/rinat/Documents/work/platform/zakupki-platform
#   ./scripts/local-ai-bootstrap.sh
#
# Опции:
#   BRANCH=cursor/fix-auto-ai-docs-7460   # checkout sibling-реп (если задан)
#   SKIP_GIT=1                            # не трогать git
#   RESET_FAILED_AI=1                     # other→none в Postgres после up (по умолчанию 1)
#   NO_BUILD=0                            # передать --no-build в up.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
PLATFORM_PARENT="$(cd "$ROOT/.." && pwd)"

BRANCH="${BRANCH:-cursor/fix-auto-ai-docs-7460}"
SKIP_GIT="${SKIP_GIT:-0}"
RESET_FAILED_AI="${RESET_FAILED_AI:-1}"
NO_BUILD="${NO_BUILD:-0}"

echo "=== local-ai-bootstrap ==="
echo "platform: $ROOT"
echo "parent:   $PLATFORM_PARENT"
echo "branch:   $BRANCH (SKIP_GIT=$SKIP_GIT)"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: нужен $1" >&2; exit 1; }
}
need_cmd docker
need_cmd curl
need_cmd git

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Docker не запущен (Docker Desktop)." >&2
  exit 1
fi

ANALIZATOR_PATH="${ANALIZATOR_PATH:-$PLATFORM_PARENT/analizator_zakupok}"
CORE_PATH="${CORE_PATH:-$PLATFORM_PARENT/zakupki-core}"
GATEWAY_PATH="${GATEWAY_PATH:-$PLATFORM_PARENT/zakupki-gateway}"
PARSER_PATH="${PARSER_PATH:-$PLATFORM_PARENT/zakupki-parser}"
CUSTOMER_PATH="${CUSTOMER_PATH:-$PLATFORM_PARENT/zakupki-customer}"

repos=(
  "$ROOT"
  "$ANALIZATOR_PATH"
  "$CORE_PATH"
  "$GATEWAY_PATH"
  "$PARSER_PATH"
  "$CUSTOMER_PATH"
)

for r in "${repos[@]}"; do
  if [[ ! -d "$r/.git" ]]; then
    echo "ERROR: нет git-репо: $r" >&2
    exit 1
  fi
done

if [[ "$SKIP_GIT" != "1" ]]; then
  echo "→ git fetch/checkout $BRANCH в sibling-репах…"
  for r in "${repos[@]}"; do
    (
      cd "$r"
      name="$(basename "$r")"
      git fetch origin --prune
      if ! git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
        echo "  WARN $name: нет origin/$BRANCH — оставляем $(git branch --show-current)"
        exit 0
      fi
      # Локальные правки (часто lm_studio.yaml) не должны ронять bootstrap.
      if ! git diff --quiet || ! git diff --cached --quiet || [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
        stash_msg="local-ai-bootstrap $(date +%Y%m%d-%H%M%S)"
        git stash push -u -m "$stash_msg" >/dev/null || true
        echo "  stash $name → $stash_msg"
      fi
      git checkout -B "$BRANCH" "origin/$BRANCH"
      echo "  OK  $name → $BRANCH"
    )
  done
fi

YAML="$ANALIZATOR_PATH/configs/lm_studio.yaml"
if [[ ! -f "$YAML" ]]; then
  echo "ERROR: нет $YAML" >&2
  exit 1
fi
echo "→ LM yaml: $YAML"
echo "----"
grep -E 'base_url:|model:|name:|concurrent:' "$YAML" || true
echo "----"

echo "→ проверка LM Studio endpoints из yaml…"
python3 - "$YAML" <<'PY'
import re, subprocess, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
urls = re.findall(r"base_url:\s*(\S+)", text)
ok = 0
for u in urls:
    u = u.rstrip("/")
    host = u.replace("http://", "").replace("https://", "").split("/")[0]
    # host.docker.internal с Mac-хоста часто не резолвится — пробуем 127.0.0.1
    candidates = [u]
    if "host.docker.internal" in u:
        candidates.append(u.replace("host.docker.internal", "127.0.0.1"))
    if "127.0.0.1" in u:
        candidates.append(u)  # already
    success = False
    for c in candidates:
        try:
            r = subprocess.run(
                ["curl", "-fsS", "--connect-timeout", "3", "--max-time", "8", f"{c}/models"],
                capture_output=True, text=True,
            )
            if r.returncode == 0 and "data" in r.stdout:
                print(f"  OK  {c}/models")
                success = True
                ok += 1
                break
        except Exception as e:
            print(f"  FAIL {c}: {e}")
    if not success:
        print(f"  FAIL {u}/models (и fallback)")
print(f"ответили {ok}/{len(urls)}")
if ok == 0:
    print("ERROR: ни один LM Studio не отвечает. Запустите LMS Server :1234, модель загружена.", file=sys.stderr)
    sys.exit(2)
PY

echo "→ останавливаю стек…"
./up.sh --down || true

echo "→ поднимаю стек с AI (полная пересборка Go + образы)…"
UP_ARGS=(--ai)
if [[ "$NO_BUILD" == "1" ]]; then
  UP_ARGS+=(--no-build)
fi
./up.sh "${UP_ARGS[@]}"

echo "→ health / pool / smoke…"
sleep 2
curl -fsS http://127.0.0.1:8088/health >/dev/null && echo "  OK  analizator /health"
curl -fsS http://127.0.0.1:8080/api/v1/health >/dev/null && echo "  OK  core /health"
curl -fsS http://127.0.0.1:3000/health >/dev/null && echo "  OK  gateway /health"

echo "  --- lm/pool ---"
curl -fsS http://127.0.0.1:8088/api/v1/lm/pool | python3 -m json.tool

echo "  --- lm/smoke (должен дать POST /v1/chat/completions в LMS) ---"
SMOKE="$(curl -fsS -X POST http://127.0.0.1:8088/api/v1/lm/smoke || true)"
echo "$SMOKE" | python3 -m json.tool 2>/dev/null || echo "$SMOKE"
if echo "$SMOKE" | python3 -c 'import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get("ok") else 1)' 2>/dev/null; then
  echo "  OK  smoke"
else
  echo "  WARN smoke не ok — смотрите логи LMS / pool"
fi

if [[ "$RESET_FAILED_AI" == "1" ]]; then
  echo "→ сброс analysis_status other/analyzing → none (карточки с текстом)…"
  docker compose exec -T postgres psql -U zakupki -d zakupki -v ON_ERROR_STOP=1 <<'SQL'
UPDATE tenders SET analysis_status='none', updated_at=now()
 WHERE analysis_status IN ('analyzing','other')
   AND EXISTS (
     SELECT 1 FROM documents d
     WHERE d.tender_id=tenders.id AND NOT d.removed
       AND d.text_content IS NOT NULL AND length(trim(d.text_content))>0
   );
SELECT analysis_status::text AS status, count(*) FROM tenders GROUP BY 1 ORDER BY 1;
SELECT count(*) AS ready_candidates FROM tenders t
 WHERE t.analysis_status='none'
   AND EXISTS (
     SELECT 1 FROM documents d WHERE d.tender_id=t.id AND NOT d.removed
       AND d.text_content IS NOT NULL AND length(trim(d.text_content))>0
   );
SELECT filename, length(text_content) AS chars
  FROM documents WHERE NOT removed AND text_content IS NOT NULL
 ORDER BY chars DESC NULLS LAST LIMIT 8;
SQL
fi

echo ""
echo "Готово."
echo "  UI:     http://localhost:3000"
echo "  Включите переключатель «Авто» — core вернёт упавшие other в очередь и начнёт анализ."
echo "  Логи:   docker compose logs -f core analizator"
echo "  Ждите в LMS: POST /v1/chat/completions с большим body (порции документов)."
echo "  Диагноз: curl -s http://127.0.0.1:8080/api/v1/workers | python3 -m json.tool"
