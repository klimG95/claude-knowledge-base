# Index — оглавление базы знаний

Это живое оглавление wiki. Обновляется агентом после каждой обработки `raw/` и любого значимого изменения в `wiki/`. Правила ведения — в [[AGENTS]].

**Текущий рабочий проект:** AuraGrid (торговый бот MT5). Точка входа — [[auragrid]].

> **🚩 Handoff 2026-06-04:** подготовка к первой продаже. Продаваемая сборка = ветка `fix/shelve-perf-restore-stability` (PR #37). Состояние релиза + открытые шаги — в баннере [[auragrid]] MOC и [[auragrid-incidents-log]] (2 инцидента 2026-06-04). Открыто: demo-валидация MSI, Ф1 подпись + Ф3 PyArmor (procurement).

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
- [[stacybot-impuls-strategy]] — восстановленная сторонняя стратегия StacyBot-Impuls (трендовый trailing-scalper XAUUSD M30, EMA9); реверс завершён + оценка качества (3/5, хрупкая negative-skew); проект-источник 🗄️ архив, кандидат на внедрение в Aura
- [[auragrid-analytics-module]] — второй python-процесс (indicators/regime/levels/calendar/preset-eval); unblock 2026-05-22 + TZ_ANALYTICS_INTEGRITY 2026-05-26 закрыты, данные корректны

### Операционные знания AuraGrid

- [[auragrid-incidents-log]] — журнал инцидентов проекта
- [[auragrid-log-analysis]] — методология анализа логов desktop.log / bot.log
- [[auragrid-checkpoint-2026-05-22-analytics-unblocked]] — **большой чекпоинт** для отката, первый стабильный вариант за долгое время
- [[auragrid-checkpoint-2026-05-30-pre-restructure]] — **чекпоинт перед перестройкой** (база отката под performance-рефакторинг), все слои зелёные, HEAD `461904b`
- [[auragrid-msi-uninstall-cleanup]] — деинсталляция с опциональной очисткой `%APPDATA%\GridScalp\` (WiX fragment + Tauri command + UI checkbox)

### Производительность AuraGrid

- [[auragrid-performance-strategy]] — стратегия ускорения (зависания/лаги на ультраволатильном рынке): диагноз 2 фронтов + 5 ярусов, status proposed

## Защита и релиз AuraGrid

- [[auragrid-protection-strategy]] — защита ПО перед первой продажей (анти-копирование/анти-взлом/tamper): threat-модель + 6 фаз, status proposed, ворота продажи = Ф1–3

## ADR

- [[adr-001-surgical-minimal-vault-updates]] — Surgical & minimal updates в vault'е (2026-05-24, accepted)
- [[adr-002-trail-rework-mq5-parity-departure]] — Намеренный отход от MQL5-эталона в логике трейлинга, удаление `pending_order_offset`, config_version 1→2 (2026-05-25, accepted)
- [[adr-003-impulse-strategy-new-preset-type]] — Импульсная стратегия как отдельный preset-type (`strategy_type: "auraimpulse"`), backward-compat default `"auragrid"` (2026-05-25, accepted)
- [[adr-004-impulse-adaptive-distance]] — AuraImpulse адаптивная дистанция pending'а: `first_step` → `candle_count` + `distance_coefficient` (M1 high-low), cooldown floor, config_version 2→3 (2026-05-28, accepted)
- [[adr-005-largest-lot-first-ordering]] — обслуживание корзины (SL/закрытие) по убыванию лота — нивелирует риск от медленного последовательного `order_send`; границы ускорения order-execution (2026-06-04, accepted)

## Источники

_Заполняется по мере обработки raw/._
