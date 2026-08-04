#!/usr/bin/env bash
set -euo pipefail
check() {
  local name="$1" url="$2"
  if curl -fsS "$url" >/dev/null 2>&1; then
    echo "OK   $name  $url"
  else
    echo "FAIL $name  $url"
    return 1
  fi
}
ec=0
check gateway   http://127.0.0.1:3000/health || ec=1
check core      http://127.0.0.1:8080/api/v1/health || ec=1
check parser    http://127.0.0.1:8091/health || ec=1
check customer  http://127.0.0.1:8092/health || ec=1
if curl -fsS http://127.0.0.1:8088/health >/dev/null 2>&1; then
  echo "OK   analizator http://127.0.0.1:8088/health"
else
  echo "SKIP analizator (profile ai not running)"
fi
exit $ec
