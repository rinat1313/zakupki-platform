# Zakupki Platform API

Base URL (local): `http://localhost:8080/api/v1`  
UI proxy: `http://localhost:3000/api/v1`

**OpenAPI / Swagger:** [`contracts/openapi/openapi.yaml`](../contracts/openapi/openapi.yaml) — `make swagger` → http://localhost:8081

Auth: none (local / private network).

Env:
- `DATABASE_URL` — Postgres DSN
- `HTTP_ADDR` — default `:8080`
- `ANALIZATOR_URL` — base URL `analizator_zakupok` (например `http://analizator:8088`). Пусто = мост выключен.

## Models

### Category
`{ id, slug, title, created_at }`

### Tender
`{ id, reg_number, source_site, law, customer_id, object_name, status, nmck, currency, published_at, updated_on_site, application_end, analysis_status, payload, created_at, updated_at, category_slugs? }`

`analysis_status`: `none` | `analyzed` | `delete` | `irrelevant` | `past` | `other`

### Customer
`{ id, inn, kpp, ogrn, full_name, short_name, address, email, phone, contact_person, organization_code, agency_id, payload, ... }`

### Document
`{ id, tender_id, uid, filename, source_url, group_title, edition, process_status, text_content?, process_error, content_hash, removed }`

`process_status`: `processed` | `unprocessed`  
On failure: `unprocessed` + `source_url` + `process_error`. Files are not kept on disk.

### Ingest job
`{ id, category_id, category_slug?, source_name, status, total_items, done_items, error_items, ... }`

Item statuses: `queued` | `running` | `ok` | `error` | `skipped` | `unsupported_source` | `failed_analyze`

### Assessment
`{ tender_id, summary, score, details, updated_at }`  
При AI-анализе `details.source = "analizator_zakupok"` (+ recommendation, items, risks, …).

## Upsert rules

- Unique tender: `(reg_number, source_site)` — no duplicates.
- On re-ingest: update nmck / dates / payload when changed; append history events.
- Documents: unique `(tender_id, source_url)`; mark missing as `removed`.
- New category on existing tender: only link in `tender_categories`.
- Non-ЕИС sites in CSV (e.g. `https://tektorg.ru`) are stored on the ingest item / payload.
The worker still tries to load the notice from `zakupki.gov.ru` by registration number (aggregator exports often reuse EIS numbers).
If ЕИС is unreachable or the number is not an EIS notice, the item ends as `unsupported_source` (stub tender may still appear in the catalog).

## Endpoints

Полная схема (параметры, тела, ответы) — в OpenAPI. Краткий список:

| Method | Path | Notes |
|--------|------|-------|
| GET | `/health` | `{ status, analizator }` |
| GET/POST | `/categories` | create: `{ title, slug? }` |
| GET | `/categories/{slug}` | |
| DELETE | `/categories/{slug}/tenders` | очистить закупки категории |
| DELETE | `/categories/{slug}/jobs` | очистить ingest-jobs |
| POST | `/categories/{slug}/refresh` | `{ statuses: ["none",…] }` → новый job |
| GET/POST | `/categories/{slug}/ai-configs` | промпты AI по категории |
| PUT/DELETE | `/categories/{slug}/ai-configs/{id}` | |
| PUT | `/categories/{slug}/active-ai-config` | активный конфиг (`409` при Авто AI) |
| POST | `/ingest` | multipart: `file` (CSV), `category_slug` **or** `category_title` |
| GET | `/ingest/jobs` | |
| GET | `/ingest/jobs/{id}` | `{ job, items }` |
| GET | `/ingest/jobs/{id}/logs` | |
| DELETE | `/ingest/jobs/{id}` | |
| GET | `/stats/ingest` | counters per category |
| GET | `/tenders` | query: `category`, `q`, `status` (`analysis_status`) |
| GET/PATCH/DELETE | `/tenders/{id}` | PATCH: `analysis_status`, `object_name`, … |
| POST | `/tenders/{id}/refresh` | перезагрузка карточки |
| GET | `/tenders/{id}/documents` | `?text=1` includes `text_content` |
| GET | `/tenders/{id}/events` | change history |
| GET/PUT | `/tenders/{id}/assessment` | `{ summary, score, details }` |
| POST | `/tenders/{id}/analyze` | AI через analizator; body `{ checklist_id? }` |
| GET | `/workers` | ingest / auto_ai / capacity |
| PUT | `/workers/auto-ai` | `{ enabled: true }` |
| POST | `/workers/ingest/pause`, `/resume`, `/stop` | управление сбором |
| POST | `/workers/analyze/stop` | остановить AI |
| GET/POST/PATCH/DELETE | `/customers`, `/customers/{id}` | |
| GET | `/customers/{id}/courts` | stub `[]` |
| GET | `/customers/{id}/rnp` | stub `[]` |

## CSV format

```
reg_number;source_url
0373100075325000001;https://zakupki.gov.ru
```

Delimiter `;` or `,`; header row optional. Multiple files → multiple jobs; worker shares one queue.

## Examples

```bash
# Create category
curl -s -X POST http://localhost:8080/api/v1/categories \
  -H 'Content-Type: application/json' \
  -d '{"title":"Поставка резервуаров"}'

# Ingest CSV
curl -s -X POST http://localhost:8080/api/v1/ingest \
  -F category_slug=postavka-rezervuarov \
  -F file=@list.csv

# AI analysis (needs ANALIZATOR_URL + LM Studio)
curl -s -X POST http://localhost:8080/api/v1/tenders/<uuid>/analyze \
  -H 'Content-Type: application/json' \
  -d '{"checklist_id":"default"}'

# External service: new tenders for a category
curl -s 'http://localhost:8080/api/v1/tenders?category=postavka-rezervuarov&status=none'

# Mark analyzed
curl -s -X PATCH http://localhost:8080/api/v1/tenders/<uuid> \
  -H 'Content-Type: application/json' \
  -d '{"analysis_status":"analyzed"}'
```

## Errors

JSON `{ "error": "..." }` with HTTP 4xx/5xx. Unknown id → 404. Courts/RNP stubs return empty list `[]` (ready for future data).  
AI: `503` если `ANALIZATOR_URL` не задан; `502` если analizator/LM Studio недоступны.

См. также [HANDOFF.md](HANDOFF.md).
