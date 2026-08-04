# zakupki-platform

Точка запуска **всей платформы** закупок: docker-compose, миграции PostgreSQL, контракты API/событий, health.

Не содержит бизнес-логики парсинга/анализа — только оркестрация.

## Быстрый старт

```bash
# 1) sibling-репозитории рядом
make clone-siblings

# 2) поднять стек
make up

# 3) проверить
make health
```

- UI: http://localhost:3000  
- Core API: http://localhost:8080/api/v1/health  
- Parser: http://localhost:8091/health  
- Customer: http://localhost:8092/health  

AI (LM Studio на хосте):

```bash
export LM_STUDIO_MODEL=<id>
make up-ai
```

## Документы

- [ARCHITECTURE.md](docs/ARCHITECTURE.md) — схема сервисов
- [DEV.md](docs/DEV.md) — как вести разработку и что добавить агенту
- [API.md](docs/API.md) — HTTP API (через gateway → core)
- [kafka/topics.yml](kafka/topics.yml) — целевые события

## Сервисы

| Репозиторий | Порт | Назначение |
|-------------|------|------------|
| [zakupki-gateway](https://github.com/rinat1313/zakupki-gateway) | 3000 | UI + внешние каналы |
| [zakupki-core](https://github.com/rinat1313/zakupki-core) | 8080 | домен + PostgreSQL |
| [zakupki-parser](https://github.com/rinat1313/zakupki-parser) | 8091 | парсинг ЕИС и ЭТП |
| [zakupki-customer](https://github.com/rinat1313/zakupki-customer) | 8092 | обогащение заказчика |
| [analizator_zakupok](https://github.com/rinat1313/analizator_zakupok) | 8088 | AI-анализ (profile `ai`) |
