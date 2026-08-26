Без явного разрешения пользователя нельзя менять:

- `contracts/openapi/` включая `internal/`
- HTTP path, method, JSON, статусы, query
- `docs/API.md`
- порты сервисов как публичный контракт
- новые файлы в `migrations/` (схема = контракт данных)

Можно без нового разрешения:

- реализация за уже описанным path
- адаптер площадки в `zakupki-parser/internal/adapter`
- UI gateway на существующем `/api/v1`
- чек-листы/промпты `analizator_zakupok`
- `.cursor/` правила, skills, агенты
