# OpenAPI / Swagger

Машиночитаемые контракты HTTP API платформы (OpenAPI 3.0).

| Файл | Сервис | Порт | Назначение |
|------|--------|------|------------|
| [`openapi.yaml`](openapi.yaml) | **zakupki-core** (публичный) | 8080 / через gateway 3000 | Категории, ingest CSV, тендеры, AI-конфиги, workers, customers |
| [`internal/parser.yaml`](internal/parser.yaml) | zakupki-parser | 8091 | `POST /api/v1/fetch` |
| [`internal/analizator.yaml`](internal/analizator.yaml) | analizator_zakupok | 8088 | AI-анализ, LM pool |
| [`internal/customer.yaml`](internal/customer.yaml) | zakupki-customer | 8092 | Обогащение заказчика (stubs) |

Человекочитаемое описание: [`docs/API.md`](../../docs/API.md).

## Просмотр Swagger UI

```bash
# из корня zakupki-platform
make swagger
# → http://localhost:8081
```

Или разово:

```bash
docker run --rm -p 8081:8080 \
  -e SWAGGER_JSON=/specs/openapi.yaml \
  -v "$PWD/contracts/openapi:/specs:ro" \
  swaggerapi/swagger-ui
```

Для внутренних спек подставьте другой файл, например `-e SWAGGER_JSON=/specs/internal/analizator.yaml`.

## Правила изменения

1. Новый/изменённый эндпоинт в сервисе → обновить соответствующий YAML здесь в том же PR-наборе.
2. Публичные маршруты пользователя идут через gateway → `openapi.yaml` (core).
3. Не дублировать бизнес-логику: спека описывает контракт, детали — в `docs/API.md` / FAQ.
