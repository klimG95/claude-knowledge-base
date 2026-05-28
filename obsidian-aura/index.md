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
- [[auragrid-impulse-strategy]] — концепция новой стратегии `AuraImpulse` (отдельный preset-type, single-shot breakout, 13 полей)
- [[auragrid-analytics-module]] — второй python-процесс (indicators/regime/levels/calendar/preset-eval); unblock 2026-05-22 + TZ_ANALYTICS_INTEGRITY 2026-05-26 закрыты, данные корректны

### Операционные знания AuraGrid

- [[auragrid-incidents-log]] — журнал инцидентов проекта
- [[auragrid-log-analysis]] — методология анализа логов desktop.log / bot.log
- [[auragrid-checkpoint-2026-05-22-analytics-unblocked]] — **большой чекпоинт** для отката, первый стабильный вариант за долгое время
- [[auragrid-msi-uninstall-cleanup]] — деинсталляция с опциональной очисткой `%APPDATA%\GridScalp\` (WiX fragment + Tauri command + UI checkbox)

## ADR

- [[adr-001-surgical-minimal-vault-updates]] — Surgical & minimal updates в vault'е (2026-05-24, accepted)
- [[adr-002-trail-rework-mq5-parity-departure]] — Намеренный отход от MQL5-эталона в логике трейлинга, удаление `pending_order_offset`, config_version 1→2 (2026-05-25, accepted)
- [[adr-003-impulse-strategy-new-preset-type]] — Импульсная стратегия как отдельный preset-type (`strategy_type: "auraimpulse"`), backward-compat default `"auragrid"` (2026-05-25, accepted)
- [[adr-004-impulse-adaptive-distance]] — AuraImpulse адаптивная дистанция pending'а: `first_step` → `candle_count` + `distance_coefficient` (M1 high-low), cooldown floor, config_version 2→3 (2026-05-28, accepted)

## Источники

_Заполняется по мере обработки raw/._
