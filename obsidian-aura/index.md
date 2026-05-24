# Index — оглавление базы знаний

Это живое оглавление wiki. Обновляется агентом после каждой обработки `raw/` и любого значимого изменения в `wiki/`. Правила ведения — в [[AGENTS]].

**Текущий рабочий проект:** AuraGrid (торговый бот MT5). Точка входа — [[auragrid]].

**Обязательный workflow:** [[runbook-vault-integration]] — vault как первая и последняя фаза каждой задачи.

---

## Темы

### Методология vault и работы агента

- [[methodology-overview]] — общая методология «второго мозга»
- [[runbook-session-start]] — чек-лист начала сессии
- [[runbook-session-handoff]] — чек-лист завершения сессии
- [[runbook-vault-integration]] — vault как обязательный workflow проекта

## Сущности

### Проекты

- [[auragrid]] — MOC проекта AuraGrid (торговый бот MT5, XAUUSD, Tauri+Python)

### Компоненты AuraGrid

- [[auragrid-trading-core]] — торговое ядро (engine/protection/profit_trailing/risk)
- [[auragrid-trading-settings]] — каталог торговых настроек пресета (36 параметров + валидации + UI)
- [[auragrid-analytics-module]] — второй python-процесс (indicators/regime/levels/calendar/preset-eval), состояние на 2026-05-22 — частично сломан

### Операционные знания AuraGrid

- [[auragrid-incidents-log]] — журнал инцидентов проекта
- [[auragrid-log-analysis]] — методология анализа логов desktop.log / bot.log
- [[auragrid-checkpoint-2026-05-22-analytics-unblocked]] — **большой чекпоинт** для отката, первый стабильный вариант за долгое время

## ADR

- [[adr-001-surgical-minimal-vault-updates]] — Surgical & minimal updates в vault'е (2026-05-24, accepted)
- [[adr-002-trail-rework-mq5-parity-departure]] — Намеренный отход от MQL5-эталона в логике трейлинга, удаление `pending_order_offset`, config_version 1→2 (2026-05-25, accepted)

## Источники

_Заполняется по мере обработки raw/._
