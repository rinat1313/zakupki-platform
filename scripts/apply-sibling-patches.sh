#!/usr/bin/env bash
# Локальные launch-патчи для siblings (не коммитятся в их репозитории).
# Нужны, пока фикс ещё не в origin/main сервиса, а у platform-агента нет push туда.
#
# Политика: перед сборкой sibling = origin/main + известные launch-патчи.
#
# Каталог siblings: ZAKUPKI_PARENT (задаёт up.sh) или родитель каталога platform.
set -euo pipefail

PLATFORM="$(cd "$(dirname "$0")/.." && pwd)"
PARENT="${ZAKUPKI_PARENT:-$(cd "$PLATFORM/.." && pwd)}"
BRANCH="${SIBLING_BRANCH:-main}"
FORCE_RESET="${ZAKUPKI_PATCH_FORCE_RESET:-1}"

# Маркер именно в server.go (регистрация маршрута), не в untracked leftovers.
fixed_in_tree() {
  local path="$1"
  grep -q 'HandleFunc("/api/v1/categories/", s.serveCategories)' \
    "$path/internal/httpapi/server.go" 2>/dev/null
}

apply_core_servemux_patch() {
  local repo_name="zakupki-core"
  local patch_file="$PLATFORM/patches/zakupki-core-servemux-categories.patch"
  local path="${CORE_PATH:-$PARENT/$repo_name}"

  if [[ ! -d "$path/.git" ]]; then
    echo "SKIP $repo_name: нет репозитория ($path)"
    return 0
  fi
  if [[ ! -f "$patch_file" ]]; then
    echo "ERROR: нет патча $patch_file" >&2
    return 1
  fi

  (
    cd "$path"

    if [[ "$FORCE_RESET" == "1" ]]; then
      git fetch origin "$BRANCH"
      git checkout -B "$BRANCH" "origin/$BRANCH"
      git reset --hard "origin/$BRANCH"
      # git apply создаёт новые файлы как untracked — их reset --hard не снимает.
      git clean -fd -- internal/httpapi/
    fi

    if fixed_in_tree "$path"; then
      echo "OK    $repo_name: фикс уже в origin/$BRANCH"
      exit 0
    fi

    if ! git apply --check "$patch_file" >/dev/null 2>&1; then
      echo "ERROR: $repo_name: патч $(basename "$patch_file") не применяется к текущему дереву" >&2
      echo "       обновите patches/ в zakupki-platform или смержите фикс в $repo_name@$BRANCH" >&2
      exit 1
    fi
    git apply "$patch_file"
    echo "OK    $repo_name: применён launch-патч $(basename "$patch_file")"
  )
}

echo "→ launch-патчи siblings (поверх origin/$BRANCH, parent=$PARENT)…"
apply_core_servemux_patch
echo "Done."
