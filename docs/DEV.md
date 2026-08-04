# Разработка

## Раскладка репозиториев

Клонируйте sibling-репы рядом с platform:

```bash
cd /path/to/parent
git clone https://github.com/rinat1313/zakupki-platform.git
cd zakupki-platform && make clone-siblings
```

Итого:

```
parent/
  zakupki-platform/
  zakupki-core/
  zakupki-gateway/
  zakupki-parser/
  zakupki-customer/
  analizator_zakupok/
```

Legacy-исследование ЕИС может оставаться в `ZakupkiParser` / `zakupkiparser` — runtime-путь уже через `zakupki-parser`.

## Язык и инфраструктура

- **Go** во всех сервисах
- **PostgreSQL** — источник истины (миграции в `zakupki-platform/migrations`)
- **Redis / Kafka (Redpanda)** — опциональные профили compose
- Связь сервисов на MVP: **HTTP JSON**; события Kafka описаны в `kafka/topics.yml`

## Как вести разработку

1. Фича в одном сервисе → ветка `cursor/<name>-XXXX` только в его репо.
2. Контракт (новый эндпоинт/событие) → обновить `zakupki-platform/contracts` + README сервисов в том же PR-наборе.
3. Миграции PG — только в `zakupki-platform/migrations` (не плодить init.sql в каждом сервисе).
4. Локально без Docker: поднять postgres, затем `go run` в parser → core → gateway.
5. Cursor Cloud Agent: добавить в environment репозитории  
   `zakupki-platform`, `zakupki-core`, `zakupki-gateway`, `zakupki-parser`,  
   `zakupki-customer` (stub), `analizator_zakupok`.  
   Legacy `zakupkiparser` — по желанию для фикстур HTML.

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
1. находит sibling-репозитории,
2. собирает Go-бинарники,
3. собирает Docker-образы,
4. поднимает все контейнеры,
5. проверяет health.

Остановить: `./up.sh --down`.

По умолчанию используется `network_mode: host` (сервисы на localhost) — так стек надёжно стартует в cloud/nested Docker.
Отключить: `ZAKUPKI_HOST_NET=0 ./up.sh`.

