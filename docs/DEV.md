# Разработка

## Раскладка репозиториев

Клонируйте sibling-репы рядом с platform:

```bash
cd /path/to/parent
git clone https://github.com/rinat1313/zakupki-platform.git
cd zakupki-platform && make sync-siblings
```

Итого:

```
parent/
  zakupki-platform/
  zakupki-core/
  zakupki-gateway/
  zakupki-parser/
  zakupki-customer/
  zakupki-search/
  analizator_zakupok/
```

### Политика веток (обязательно для агентов и локального запуска)

- Сборка платформы (`./up.sh`, Docker context) всегда берёт sibling-сервисы с **`origin/main`** — финальная ветка.
- `make sync-siblings` / `./scripts/clone-siblings.sh` клонирует или `checkout`+`pull --ff-only` на `main`.
- `./up.sh` вызывает sync сам (отключить: `--no-sync` или `ZAKUPKI_SKIP_SIBLING_SYNC=1`).
- Фичи пишутся в `cursor/<name>-…` **внутри своего** репо сервиса; в platform для compose/up **не** подставлять feature-ветки siblings.
- Override только явно: `SIBLING_BRANCH=...` (не использовать в обычном launch).
- Cursor Cloud Environment: все sibling-репы в environment; ref для сборки/запуска платформы — **`main`**.

Legacy-исследование ЕИС может оставаться в `ZakupkiParser` / `zakupkiparser` — runtime-путь уже через `zakupki-parser`.

## Язык и инфраструктура

- **Go** во всех сервисах
- **PostgreSQL** — источник истины (миграции в `zakupki-platform/migrations`)
- **Redis / Kafka (Redpanda)** — опциональные профили compose
- Связь сервисов на MVP: **HTTP JSON**; события Kafka описаны в `kafka/topics.yml`

## Как вести разработку

1. Фича в одном сервисе → ветка `cursor/<name>-XXXX` только в его репо; в `main` мержить до запуска через platform.
2. Контракт (новый эндпоинт/событие) → обновить `zakupki-platform/contracts` (в т.ч. OpenAPI в `contracts/openapi/`) + README сервисов в том же PR-наборе. Просмотр: `make swagger`.
3. Миграции PG — только в `zakupki-platform/migrations` (не плодить init.sql в каждом сервисе).
4. Локально без Docker: поднять postgres, затем `go run` в parser → core → gateway.
5. Cursor Cloud Agent: environment =  
   `zakupki-platform`, `zakupki-core`, `zakupki-gateway`, `zakupki-parser`,  
   `zakupki-customer`, `zakupki-search`, `analizator_zakupok` — refs на **`main`**.  
   `./up.sh` поднимает search, если sibling рядом
   (`Dockerfile` + `cmd/search`, порт `:8093`, БД `zakupki_search`, `CORE_URL`→core).

## Минимальный smoke

```bash
cd zakupki-platform
make up
make health
# UI http://localhost:3000 — загрузить CSV с reg_number
```

С AI:

```bash
export LM_STUDIO_MODEL=<id>
make up-ai
```

## Запуск одной командой

```bash
cd zakupki-platform
./up.sh
```

Скрипт сам:
1. синхронизирует siblings с `origin/main`,
2. находит sibling-репозитории,
3. собирает Go-бинарники,
4. собирает Docker-образы,
5. поднимает все контейнеры,
6. проверяет health.

Остановить: `./up.sh --down`.

По умолчанию — обычный Docker bridge (порты на localhost). Так работает Docker Desktop на Mac/Windows.
Только на Linux при проблемах с сетью: `ZAKUPKI_HOST_NET=1 ./up.sh`.

