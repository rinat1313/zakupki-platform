---
name: tz-pipeline
description: >
  ALWAYS use when the user sends a ТЗ, техническое задание, spec, feature request,
  bugfix, or asks to implement, add, fix, or change the zakupki platform or sibling
  services. Mandatory pipeline: analyst+architect then lead then developer then tester
  then specialist review then lead report and merge to main. Use for Russian and English
  task briefs. Do not skip this skill when the message is a development assignment.
---

# Пайплайн ТЗ

Родительский агент исполняет этот skill сам и делегирует роли через Task (`subagent_type` = имя агента). Не реализуй фичу до гейта lead. Lead не спавнит детей (лимит вложенности).

Субагенты: `analyst`, `architect`, `lead`, `developer`, `tester` в `.cursor/agents/`.

Шаблон отчёта: `references/report-template.md`.
Граница контракта: `references/contract-boundary.md`.

## Короткий путь

Если запрос — вопрос без изменения репозитория: ответь сам или через профильного readonly-агента. Без developer, без merge.

## Полный путь (ТЗ / фича / баг с правками)

### 1. Предварительный анализ (параллельно)

В одном сообщении два Task:

- `analyst` — ТЗ, риски, приёмка, список работ
- `architect` — границы сервисов, контракт, миграции, куда класть код

### 2. Lead — список задач

Task `lead` с полным текстом ТЗ и выводами шага 1.

Выход: нумерованные задачи для developer, запреты, нужен ли стоп на endpoint.

Если architect/analyst требуют новый HTTP path без разрешения пользователя — остановись и спроси пользователя. Developer не запускай.

### 3. Developer

Task `developer` со списком задач lead. Один writer. После кода — commit/push на feature-ветку.

### 4. Tester

Task `tester` (readonly). Код не правит.

Если «на доработку» — снова шаг 3 с замечаниями, затем снова tester. Цикл, пока tester не примет или lead не зафиксирует блокер.

### 5. Специалисты

Снова `analyst` и `architect` (readonly) по diff и отчёту tester.

Замечания → шаг 3. Нет замечаний → шаг 6.

### 6. Lead — merge и отчёт

Task `lead` на финал.

Условие merge в `main`: tester принял, специалисты без замечаний.

Сделать: влить в `origin/main`. Не force-push. Чужие PR не трогать. Если нельзя — `main: не влита` и причина.

Пользователю показать отчёт по шаблону. Не писать комментарии в GitHub без просьбы.
