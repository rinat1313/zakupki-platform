# zakupki-platform

Точка запуска **всей платформы** закупок.

## Запуск (один скрипт)

Sibling-репозитории лежат рядом. `./up.sh` **сам** подтягивает их с ветки **`main`** (финальная), затем собирает и поднимает стек:

```bash
./up.sh
```

Нужны: **Docker Desktop** (или Engine), **Git**, **Go**. На Mac/Windows host-network не используется — UI будет на http://localhost:3000.

Только синхронизировать репы с `main`:

```bash
make sync-siblings
```

```bash
./up.sh --ai        # + AI-анализ (LM Studio на хосте :1234)
./up.sh --down      # остановить
./up.sh --logs      # логи
./up.sh --health    # проверка
./up.sh --no-sync   # не трогать siblings (если сознательно на другой ветке)
```

- UI: http://localhost:3000
- Core: http://localhost:8080/api/v1/health


## Документы

- [ARCHITECTURE.md](docs/ARCHITECTURE.md) — схема сервисов
- [DEV.md](docs/DEV.md) — как вести разработку и что добавить агенту
- [API.md](docs/API.md) — HTTP API (через gateway → core)
- [OpenAPI / Swagger](contracts/openapi/) — машиночитаемые контракты (`make swagger` → http://localhost:8081)
- [kafka/topics.yml](kafka/topics.yml) — целевые события

## Сервисы

| Репозиторий | Порт | Назначение |
|-------------|------|------------|
| [zakupki-gateway](https://github.com/rinat1313/zakupki-gateway) | 3000 | UI + внешние каналы |
| [zakupki-core](https://github.com/rinat1313/zakupki-core) | 8080 | домен + PostgreSQL |
| [zakupki-parser](https://github.com/rinat1313/zakupki-parser) | 8091 | парсинг ЕИС и ЭТП |
| [zakupki-customer](https://github.com/rinat1313/zakupki-customer) | 8092 | обогащение заказчика |
| [zakupki-search](https://github.com/rinat1313/zakupki-search) | 8093 | поисковые профили ЕИС (своя БД `zakupki_search`; в репо дефолт :8091) |
| [analizator_zakupok](https://github.com/rinat1313/analizator_zakupok) | 8088 | AI-анализ (profile `ai`) |
