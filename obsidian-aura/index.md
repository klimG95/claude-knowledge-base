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
- [[auragrid-analytics-module]] — второй python-процесс (indicators/regime/levels/calendar/preset-eval), состояние на 2026-05-22 — частично сломан

### Операционные знания AuraGrid

- [[auragrid-incidents-log]] — журнал инцидентов проекта
- [[auragrid-log-analysis]] — методология анализа логов desktop.log / bot.log

## Источники

_Заполняется по мере обработки raw/._
