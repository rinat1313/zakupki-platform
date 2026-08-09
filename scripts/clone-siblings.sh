#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ORG="${GITHUB_ORG:-rinat1313}"
# required siblings
repos=(zakupki-core zakupki-gateway zakupki-parser zakupki-customer analizator_zakupok)
# optional — сервис может ещё разрабатываться
optional_repos=(zakupki-search)

clone_one() {
  local r="$1" required="$2"
  if [[ -d "$ROOT/$r/.git" ]]; then
    echo "exists $r"
    return 0
  fi
  echo "clone  $r"
  if git clone "https://github.com/$ORG/$r.git" "$ROOT/$r"; then
    return 0
  fi
  if [[ "$required" == "1" ]]; then
    echo "ERROR: не удалось клонировать $r" >&2
    return 1
  fi
  echo "WARN: $r ещё нет на GitHub — пропуск (./up.sh поднимет search, когда репо появится)" >&2
  return 0
}

for r in "${repos[@]}"; do
  clone_one "$r" 1
done
for r in "${optional_repos[@]}"; do
  clone_one "$r" 0
done
echo "Done. Parent dir: $ROOT"
