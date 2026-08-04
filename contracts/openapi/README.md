# OpenAPI

- Публичный API пользователя: через **zakupki-gateway** (`/api/v1/*` → core).
- Внутренний fetch: **zakupki-parser** `POST /api/v1/fetch`.
- Анализ: **analizator_zakupok** `POST /api/v1/analyze`.
- Обогащение: **zakupki-customer** `GET /api/v1/customers/{id}/…`.

Подробные маршруты core: см. исторический `docs/API.md` / HANDOFF в ZakupkiParser PR.
