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

1. Установить [LM Studio](https://lmstudio.ai), загрузить модель, Start Server на порту **1234**.
2. Запустить стек с AI:

```bash
export LM_STUDIO_MODEL=<id-модели-из-LM-Studio>
./up.sh --down
./up.sh --ai
```

Проверка:

```bash
curl http://127.0.0.1:8088/health
curl http://127.0.0.1:8080/api/v1/health   # analizator: ok
```
