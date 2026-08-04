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

## AI-анализ: `analizator disabled` / `connection refused` / порт 55674

**Важно:** Docker берёт порт из файла `zakupki-platform/.env`, а не из «воздуха».
Если в ошибке фигурирует `:55674` — в `.env` **или в терминале** (`export LM_STUDIO_…`) застрял старый порт.
Docker Compose приоритетнее берёт переменные из **shell**, чем из `.env` — поэтому старый `export …:55674` ломал всё даже при правильном `.env`.

`./up.sh --ai` теперь:
- читает `.env` и **перезаписывает** shell;
- принудительно чинит порт `55674` → `1234`;
- делает `force-recreate` контейнера `analizator`.

LM Studio сейчас слушает **1234** — исправьте `.env` и пересоздайте контейнеры. Перед запуском можно сбросить старый export:

```bash
unset LM_STUDIO_BASE_URL LM_STUDIO_API_KEY LM_STUDIO_MODEL
```

### 1. LM Studio на Mac

- модель загружена, Server → Start
- порт **1234** (лог: `HTTP server listening on port 1234`)
- желательно **Serve on Local Network** / bind `0.0.0.0`

Проверка (каждая команда — отдельная строка, без комментариев справа):

```bash
curl http://127.0.0.1:1234/v1/models
```

Из ответа скопируйте `"id"` модели.

### 2. Файл настроек (главное место)

Откройте:

```text
zakupki-platform/.env
```

Должно быть **ровно** так (подставьте свой id модели):

```bash
LM_STUDIO_BASE_URL=http://host.docker.internal:1234/v1
LM_STUDIO_API_KEY=lm-studio
LM_STUDIO_MODEL=qwen/qwen3-8b
```

Не оставляйте `55674` и другие старые порты. После правки:

```bash
unset LM_STUDIO_BASE_URL LM_STUDIO_API_KEY LM_STUDIO_MODEL
```

### 3. Перезапуск стека с AI

```bash
cd /Users/rinat/Documents/work/platform/zakupki-platform
./up.sh --down
./up.sh --ai
```

### 4. Проверка (по одной команде)

```bash
curl http://127.0.0.1:1234/v1/models
curl http://127.0.0.1:8088/health
curl http://127.0.0.1:8080/api/v1/health
```

В `8088/health` в `lm_studio_error` **не** должно быть `:55674`.
В `8080/health` ожидайте `"analizator":"ok"`.

### 5. UI

http://localhost:3000 → закупка → **AI-анализ**.

## AI-анализ дозированный (самозанятый)

Анализатор больше не отправляет весь текст разом (из‑за этого был `Context size has been exceeded`).

Алгоритм:
1. режет документы на «страницы» (~1800 символов) и шлёт порциями по ~5 страниц;
2. на каждую порцию модель даёт **краткие заметки** (ей сообщают, что будут ещё части);
3. если порция не влезает в контекст — автоматически уменьшает её и повторяет;
4. в конце собирает итоговый ответ на вопрос: **«Оцени закупку по возможности участия самозанятого»**.

Настройки (в `zakupki-platform/.env` или compose):

```bash
PAGE_CHARS=1800
DOSE_PAGES=5
CONTEXT_BUDGET_CHARS=10000
DOSE_MAX_TOKENS=400
SYNTH_MAX_TOKENS=900
```

Если снова `Context size exceeded` — уменьшите `CONTEXT_BUDGET_CHARS` (например `6000`) или увеличьте n_ctx в LM Studio.

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

## Пауза / стоп сбора и AI

В UI (блок «Общий прогресс») есть кнопки:

| | Сбор (ingest) | AI-анализ |
|---|---|---|
| **Пауза** | не берёт новые позиции из очереди | новые AI-запросы отклоняются |
| **Продолжить** | снова обрабатывает очередь | снова принимает AI-запросы |
| **Стоп** | отменяет очередь (`cancelled`) | отменяет текущий AI-запрос и ставит паузу |

API:

```bash
curl http://127.0.0.1:8080/api/v1/workers
curl -X POST http://127.0.0.1:8080/api/v1/workers/ingest/pause
curl -X POST http://127.0.0.1:8080/api/v1/workers/ingest/resume
curl -X POST http://127.0.0.1:8080/api/v1/workers/ingest/stop
curl -X POST http://127.0.0.1:8080/api/v1/workers/analyze/pause
curl -X POST http://127.0.0.1:8080/api/v1/workers/analyze/resume
curl -X POST http://127.0.0.1:8080/api/v1/workers/analyze/stop
```

Новая загрузка CSV / refresh автоматически снимает stop/pause со сбора.

## LM Studio: Docker всё ещё не достучится (Mac)

Если после правки `.env` на `:1234` всё равно `connection refused`:

1. В LM Studio включите **Serve on Local Network** / `0.0.0.0`
2. Либо запускайте analizator на хосте (см. ниже)

### Надёжный вариант на Mac (analizator на хосте)

```bash
# терминал 1 — стек без AI-контейнера
cd /Users/rinat/Documents/work/platform/zakupki-platform
./up.sh

# терминал 2 — analizator на Mac, прямо к LM Studio
cd /Users/rinat/Documents/work/platform/analizator_zakupok
export LM_STUDIO_BASE_URL=http://127.0.0.1:1234/v1
export LM_STUDIO_API_KEY=lm-studio
export LM_STUDIO_MODEL=Qwen3-8B-Q8_0
export HTTP_ADDR=:8088
export TENDERS_ROOT=/tmp/tenders
go run ./cmd/analizator
```

И чтобы core в Docker звал этот analizator:

```bash
cd /Users/rinat/Documents/work/platform/zakupki-platform
export ANALIZATOR_URL=http://host.docker.internal:8088
docker compose -f docker-compose.yml -f docker-compose.runtime.yml up -d --force-recreate core
```

В UI снова нажмите **AI-анализ**.

