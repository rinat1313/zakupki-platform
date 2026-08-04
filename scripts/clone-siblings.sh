#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ORG="${GITHUB_ORG:-rinat1313}"
repos=(zakupki-core zakupki-gateway zakupki-parser zakupki-customer analizator_zakupok)
for r in "${repos[@]}"; do
  if [[ -d "$ROOT/$r/.git" ]]; then
    echo "exists $r"
  else
    echo "clone  $r"
    git clone "https://github.com/$ORG/$r.git" "$ROOT/$r"
  fi
done
echo "Done. Parent dir: $ROOT"
