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

## AI-анализ: `analizator disabled: set ANALIZATOR_URL`

AI-сервис по умолчанию **не** поднимается. Нужно:

1. Установить [LM Studio](https://lmstudio.ai), загрузить модель, Start Server на порту **1234**
   (в логе: `HTTP server listening on port 1234`, OpenAI-compatible `/v1/chat/completions`).
2. Запустить стек с AI:

```bash
export LM_STUDIO_BASE_URL=http://host.docker.internal:1234/v1
export LM_STUDIO_API_KEY=lm-studio
export LM_STUDIO_MODEL=<id-модели-из-LM-Studio>
./up.sh --down
./up.sh --ai
```

Проверка:

```bash
curl http://127.0.0.1:1234/v1/models
curl http://127.0.0.1:8088/health
curl http://127.0.0.1:8080/api/v1/health   # analizator: ok
```

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
## LM Studio: `connection refused` / `dial tcp ...:55674`

На Mac LM Studio часто слушает только `127.0.0.1`, а контейнер `analizator` ходит через `host.docker.internal` — соединение отклоняется.

### Что сделать

1. В LM Studio (Developer / Server):
   - включите **Serve on Local Network** / bind `0.0.0.0` (не только localhost)
   - запомните порт из лога (`listening on http://...:PORT`)
2. Проверка **на Mac** (не в Docker):

```bash
curl http://127.0.0.1:PORT/v1/models
```

3. Перезапуск стека с этим портом:

```bash
export LM_STUDIO_BASE_URL=http://host.docker.internal:PORT/v1
export LM_STUDIO_API_KEY='<ключ или lm-studio>'
export LM_STUDIO_MODEL='<id из /v1/models>'
./up.sh --down
./up.sh --ai
```

### Надёжный вариант на Mac (analizator на хосте)

Если Docker так и не достучится до LM Studio:

```bash
# терминал 1 — только инфраструктура без AI-контейнера
./up.sh

# терминал 2 — analizator на Mac, прямо к LM Studio
cd ../analizator_zakupok
export LM_STUDIO_BASE_URL=http://127.0.0.1:PORT/v1
export LM_STUDIO_API_KEY='...'
export LM_STUDIO_MODEL='...'
export HTTP_ADDR=:8088
export TENDERS_ROOT=/tmp/tenders
go run ./cmd/analizator
```

И чтобы core в Docker звал этот analizator:

```bash
export ANALIZATOR_URL=http://host.docker.internal:8088
docker compose -f docker-compose.yml -f docker-compose.runtime.yml up -d --force-recreate core
```

В UI снова нажмите **AI-анализ**.

