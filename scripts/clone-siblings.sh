#!/usr/bin/env bash
# Клонирует/обновляет sibling-репозитории строго с главной ветки (по умолчанию main).
# Политика платформы: сборка ./up.sh всегда опирается на финальную ветку сервисов, не на feature.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ORG="${GITHUB_ORG:-rinat1313}"
BRANCH="${SIBLING_BRANCH:-main}"

# required siblings
repos=(zakupki-core zakupki-gateway zakupki-parser zakupki-customer analizator_zakupok)
# optional
optional_repos=(zakupki-search)

sync_one() {
  local r="$1" required="$2"
  local path="$ROOT/$r"
  local url="https://github.com/$ORG/$r.git"

  if [[ ! -d "$path/.git" ]]; then
    echo "clone  $r  (origin/$BRANCH)"
    if git clone --branch "$BRANCH" --single-branch "$url" "$path"; then
      echo "OK    $r @ $(git -C "$path" rev-parse --short HEAD)"
      return 0
    fi
    if [[ "$required" == "1" ]]; then
      echo "ERROR: не удалось клонировать $r с ветки $BRANCH" >&2
      return 1
    fi
    echo "WARN: $r недоступен — пропуск" >&2
    return 0
  fi

  echo "sync   $r  → origin/$BRANCH"
  (
    cd "$path"
    if [[ -n "$(git status --porcelain)" ]]; then
      echo "WARN: $r: есть локальные изменения — sync пропущен (commit/stash/clean)" >&2
      echo "      сейчас: $(git rev-parse --abbrev-ref HEAD) @ $(git rev-parse --short HEAD)"
      exit 0
    fi
    git fetch origin "$BRANCH"
    if ! git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
      echo "ERROR: $r: нет origin/$BRANCH" >&2
      exit 1
    fi
    git checkout -B "$BRANCH" "origin/$BRANCH"
    git pull --ff-only origin "$BRANCH"
    echo "OK    $r @ $(git rev-parse --short HEAD) (origin/$BRANCH)"
  )
  local ec=$?
  if [[ $ec -ne 0 && "$required" == "1" ]]; then
    return "$ec"
  fi
  return 0
}

echo "Sibling branch: $BRANCH  (override: SIBLING_BRANCH=...)"
echo "Parent dir:     $ROOT"
echo

fail=0
for r in "${repos[@]}"; do
  sync_one "$r" 1 || fail=1
done
for r in "${optional_repos[@]}"; do
  sync_one "$r" 0 || true
done

if [[ $fail -ne 0 ]]; then
  echo >&2
  echo "ERROR: не все обязательные siblings на $BRANCH" >&2
  exit 1
fi

echo
echo "Done. Все доступные siblings синхронизированы с origin/$BRANCH."
