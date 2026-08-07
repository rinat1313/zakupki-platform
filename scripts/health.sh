#!/usr/bin/env bash
set -euo pipefail
check() {
  local name="$1" url="$2"
  if curl -fsS --connect-timeout 2 --max-time 5 "$url" >/dev/null 2>&1; then
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
# analizator (profile ai): на Mac при сломанном host-net часто «тишина» на :8088
if curl -fsS --connect-timeout 2 --max-time 5 http://127.0.0.1:8088/health >/dev/null 2>&1; then
  echo "OK   analizator http://127.0.0.1:8088/health"
else
  # считаем ошибкой только если контейнер ai должен быть поднят
  if docker compose ps --status running 2>/dev/null | grep -q analizator || \
     docker ps --format '{{.Names}}' 2>/dev/null | grep -q zakupki-analizator; then
    echo "FAIL analizator http://127.0.0.1:8088/health (контейнер есть, порт недоступен — часто host-net на Mac)"
    echo "     Починка: ZAKUPKI_ANALIZATOR_LAN=0 ./up.sh --ai"
    ec=1
  else
    echo "SKIP analizator (не запущен; нужен ./up.sh --ai)"
  fi
fi
exit $ec
