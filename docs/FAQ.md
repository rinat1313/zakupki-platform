# FAQ / типичные ошибки

## Документы `unprocessed` / LibreOffice not found / pdftotext not found

В контейнере `parser` должны быть LibreOffice и Poppler.
Обновите `zakupki-parser` и пересоберите:

```bash
cd zakupki-platform
git pull origin main
(cd ../zakupki-parser && git pull origin main)
./up.sh --down
./up.sh
```

Затем в UI откройте закупку → **«Обновить карточку»** (старые документы уже сохранены как unprocessed и сами не переконвертируются).

## AI-анализ: `analizator disabled` / `connection refused`

AI поднимается **только** через `./up.sh --ai` (или `--full`). Обычный `./up.sh` анализатор не стартует — `health.sh` покажет `SKIP`, и это нормально.

Wiring:

| Кто | Куда |
|-----|------|
| core (Docker bridge) | `ANALIZATOR_URL=http://analizator:8088` |
| analizator → LM Studio | `http://host.docker.internal:1234/v1` (образ `analizator_zakupok@main` + compose) |

В `.env` **нельзя**:

- пустой `ANALIZATOR_URL=` — core видит `analizator=disabled`
- `ANALIZATOR_URL=http://127.0.0.1:8088` для core в **bridge** — из контейнера `127.0.0.1` это сам core, не analizator  
  (для host-network `./up.sh` сам ставит `127.0.0.1:8088`)

`zakupki-platform` **не** перезаписывает LM/dose-конфиг (промпты, dose). Sibling `analizator_zakupok` берите с `origin/main`.

### 1. LM Studio на Mac

- модель загружена, Server → Start
- порт **1234**, лучше **Serve on Local Network** / bind `0.0.0.0`

```bash
curl http://127.0.0.1:1234/v1/models
```

### 2. Где править настройки

```text
analizator_zakupok/configs/          # lm_studio.yaml, checklists, prompts
analizator_zakupok/Dockerfile*       # ENV по умолчанию в образе
```

Не задавайте `LM_STUDIO_*` / `PAGE_CHARS` / `DOSE_*` в `zakupki-platform/.env` «на всякий случай».

### 3. Перезапуск стека с AI

```bash
cd /path/to/zakupki-platform
./up.sh --down
./up.sh --ai
```

### 4. Проверка

```bash
curl -s http://127.0.0.1:1234/v1/models
curl -s http://127.0.0.1:8088/health
curl -s http://127.0.0.1:8080/api/v1/health
# ожидаем "analizator":"ok"
```

`./up.sh --ai` после общего health дополнительно проверяет analizator и что core видит `"analizator":"ok"`.

### 5. UI

http://localhost:3000 → закупка → **AI-анализ**.

## AI-анализ дозированный (самозанятый)

Анализатор не отправляет весь текст разом (иначе `Context size has been exceeded`).

Алгоритм:
1. режет документы на «страницы» и шлёт порциями;
2. на каждую порцию модель даёт **краткие заметки**;
3. если порция не влезает в контекст — уменьшает её и повторяет;
4. в конце собирает итоговую оценку (например, участие самозанятого).

Параметры dose (`PAGE_CHARS`, `DOSE_PAGES`, `CONTEXT_BUDGET_CHARS`, …) живут в **analizator_zakupok**, не в platform compose.

Если снова `Context size exceeded` — уменьшите бюджет в конфиге analizator или увеличьте n_ctx в LM Studio.

## AI вернул unknown / пустые заметки при наличии документов

Документы **подаются** (из PostgreSQL). Частая причина с **Qwen3**: модель тратит весь `max_tokens` на thinking (`reasoning_content`), а `content` пустой — анализатор видит «пустые» порции.

Исправлено в analizator (чтение `reasoning_content`, `/no_think`, больше `DOSE_MAX_TOKENS`).
Дополнительно в LM Studio: Developer → отключите thinking / «separate reasoning_content», либо увеличьте max tokens.

```bash
DOSE_MAX_TOKENS=1600
SYNTH_MAX_TOKENS=2000
```

## В логах LM Studio только `GET /v1/models`

Это **не анализ**, а health-check (Docker/core раньше дергали `/models` каждые ~10с).

Настоящий анализ = **`POST /v1/chat/completions`** (несколько раз: порции + итог).

Проверка, что чат доходит:

```bash
curl -X POST http://127.0.0.1:8088/api/v1/lm/smoke
```

В LM Studio должен появиться `Received request: POST to /v1/chat/completions`.
Глубокий health: `curl 'http://127.0.0.1:8088/health?lm=1'`

## Откуда берётся текст для AI

Платформа **не** читает `valid_info/` с диска analizator.

Цепочка:

1. UI → `POST /api/v1/tenders/{id}/analyze` (**zakupki-core**)
2. core из **PostgreSQL**: карточка тендера + `documents.text_content`
3. `BuildCorpus(...)` → поле `text` в запросе к analizator
4. analizator режет `text` на порции и шлёт в LM Studio

Файлы `valid_info/valid_doc` — только legacy для CLI; при наличии `text` их отсутствие **не ошибка**.

## Неполный текст DOCX в карточке

В UI раньше превью обрезалось на **6000 символов** — это выглядело как «6 страниц из 40». Теперь показывается весь `text_content`.

Для извлечения DOCX парсер использует **native ZIP/XML** (все `w:t` из document/header/footer) + LibreOffice, выбирает более полный вариант. DOC/RTF: конвертация в DOCX → native extract. После обновления парсера нажмите **«Обновить карточку»**.

## Несколько LM Studio

Файл `analizator_zakupok/configs/lm_studio.yaml` — список `base_url` моделей. Анализатор проверяет доступность и параллелит запросы. Core ставит `analyze_capacity = min(healthy, CPU−10%)`.

```bash
curl http://127.0.0.1:8088/api/v1/lm/pool
```

## Сбор, авто-AI и статусы

В UI (блок «Общий прогресс»):

| | Сбор (ingest) | AI-анализ |
|---|---|---|
| **Пауза / Продолжить / Стоп** | управляют очередью сбора | — |
| **Переключатель «Авто»** | — | вкл/выкл автоматический AI (по умолчанию выкл, если AI не настроен — недоступен) |
| **Чек-лист** | — | системный / пользовательский промпт и правила **по категории** |
| **Выпадающий список** | — | активная конфигурация; при включённом Авто список заблокирован |

Авто-AI стартует, когда **парсер закончил карточку** (`ingest ok`) и есть хотя бы один документ с текстом — **не ждёт** обработки всех файлов.

Параллельный сбор: число активных воркеров = `max(1, очередь/10)` (до 32), `FOR UPDATE SKIP LOCKED`.

Шкалы на карточке: зелёная — сбор (растёт по документам), синяя — AI (по порциям LM Studio). Недогруженные карточки — светло-оранжевые.

API:

```bash
curl http://127.0.0.1:8080/api/v1/workers
# {"ingest":"running","auto_ai":false,"analyze_active":false,"analizator_configured":true}

curl -X PUT http://127.0.0.1:8080/api/v1/workers/auto-ai \
  -H 'Content-Type: application/json' \
  -d '{"enabled":true}'

# конфиги AI категории
curl http://127.0.0.1:8080/api/v1/categories/MYKEY/ai-configs
curl -X POST http://127.0.0.1:8080/api/v1/categories/MYKEY/ai-configs \
  -H 'Content-Type: application/json' \
  -d '{"name":"самозанятый","system_prompt":"...","user_prompt":"...","rules":"...","activate":true}'
```

Новая загрузка CSV / refresh автоматически снимает stop/pause со сбора.

## LM Studio: Docker всё ещё не достучится (Mac)

1. В LM Studio включите **Serve on Local Network** / `0.0.0.0`
2. Проверьте URL/модель в конфиге **analizator_zakupok** (не в platform)
3. Либо запускайте analizator на хосте (см. ниже)

### Надёжный вариант на Mac (analizator на хосте)

```bash
# терминал 1 — стек без AI-контейнера
cd /path/to/zakupki-platform
./up.sh

# терминал 2 — analizator на Mac со своими ENV/config
cd /path/to/analizator_zakupok
export LM_STUDIO_BASE_URL=http://127.0.0.1:1234/v1
export LM_STUDIO_API_KEY=lm-studio
export LM_STUDIO_MODEL=<id из /v1/models>
export HTTP_ADDR=:8088
export TENDERS_ROOT=/tmp/tenders
go run ./cmd/analizator
```

Чтобы core в Docker звал этот analizator:

```bash
cd /path/to/zakupki-platform
ANALIZATOR_URL=http://host.docker.internal:8088 \
  docker compose -f docker-compose.yml -f docker-compose.runtime.yml up -d --force-recreate core
```

В UI снова нажмите **AI-анализ**.

