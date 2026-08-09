# Архитектура

```
                 ┌──────────────────┐
  User / CSV ───►│ zakupki-gateway  │  UI + HTTP (+ Telegram/Slack later)
                 │  :3000           │
                 └────────┬─────────┘
                          │ HTTP
           ┌──────────────┼─────────────────┐
           ▼              ▼                 ▼
   ┌──────────────┐ ┌────────────┐  ┌────────────────┐
   │ zakupki-core │ │  customer  │  │ (future slack) │
   │ :8080 + PG   │ │  :8092     │  └────────────────┘
   └──────┬───────┘ └────────────┘
          │ PARSER_URL / ANALIZATOR_URL
     ┌────┴─────┐         ┌──────────────┐
     ▼          ▼         ▼              │
┌─────────┐ ┌────────────────────┐       │
│ parser  │ │ analizator_zakupok │◄──────┘
│ :8091   │ │ :8088 + LM Studio  │
└─────────┘ └────────────────────┘
```

## Ответственность

| Сервис | Репозиторий | Роль |
|--------|-------------|------|
| Оркестратор | `zakupki-platform` | compose, миграции, контракты, make up |
| Gateway / UI | `zakupki-gateway` | пользовательский UX, загрузка CSV, прокси |
| Core / СУБД | `zakupki-core` | домен, очередь ingest, статусы, assessments |
| Parser | `zakupki-parser` | ЕИС + адаптеры площадок **в одном сервисе** |
| Search | `zakupki-search` | профили поиска ЕИС + auth (`:8093` в platform; БД `zakupki_search`) |
| Analizator | `analizator_zakupok` | правила/чек-листы + LM Studio |
| Customer | `zakupki-customer` | ФНС/суды/ФАС/РНП (stub → рост) |

## Расширение вширь

- Новая торговая площадка → адаптер в **`zakupki-parser/internal/adapter`**, без нового репо.
- Новый канал UI (Telegram) → handlers в **`zakupki-gateway`**.
- Новый источник по заказчику → адаптер в **`zakupki-customer`**.
- Новый вид анализа → чек-лист/промпт в **`analizator_zakupok`**.

Kafka/Redis — профили compose (`make up-full`), подключаются когда HTTP-очередь станет узким местом.
