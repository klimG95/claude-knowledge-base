---
type: adr
adr_id: 3
status: accepted
tags: [auragrid, trading, strategy, impulse, architecture, preset-type]
created: 2026-05-25
updated: 2026-05-25
---

# ADR-003: Импульсная стратегия как отдельный preset-type

**Status:** accepted
**Date:** 2026-05-25
**Project:** AuraGrid

## Context

Продакт-владелец сформулировал новую торговую стратегию — `AuraImpulse`. Это **breakout-импульсная single-shot** модель, концептуально несовместимая с AuraGrid:

- Один pending на канал (не цепочка доборов), периодически перевыставляется.
- При срабатывании оппозитный pending снимается, открывается **ровно одна** позиция.
- Стартовый SL сразу при заполнении (нет фазы активации трейла по USD).
- Единая формула трейл-SL (та же, что в TZ TRAIL_REWORK v1.0 для profit-трейлинга).
- Защита equity не через `max_loss` (относительный USD), а через `min_account_balance` (абсолютный порог equity).
- Cooldown между сделками.
- Нет сетки, нет мартингейла, нет CG-фазы.

Подробности концепции — [[auragrid-impulse-strategy]]. Реализационное ТЗ — `auragrid/docs/tz/TZ_IMPULSE_STRATEGY_v1.0.md`.

Возникает архитектурный вопрос: **как добавить эту стратегию в кодовую базу AuraGrid**, где сейчас существует ровно один тип стратегии — scalp+grid+CG.

## Considered options

### Option 1 — Режим внутри существующей стратегии (`strategy_mode`)

Добавить в `general` поле `strategy_mode: "grid" | "impulse"`. Engine читает это поле и выбирает поведение. yaml содержит **все** поля от обеих стратегий; для каждого режима применима своя подсхема.

**Плюс:** один тип бота, не плодим preset-types, минимум изменений в Wizard / Strategy-list / IPC.

**Минус:**
- В yaml таскаются неприменимые поля (для impulse — вся `conservative_grid`, лишние scalping-поля). Пользователь видит в UI/файле поля, которые ничего не делают для его режима.
- Pydantic-валидация становится условной (если `mode=impulse` — некоторые поля должны быть `None`; если `mode=grid` — другие). Условные инварианты — типовой источник дыр.
- Step3Editor рендерит все поля; нужно скрывать половину под флагом — UI становится сложнее, риск показа неактуальных полей вырастает с каждой правкой.
- `extra="forbid"` (см. [[auragrid-trading-settings]]) перестаёт работать как защита: схема обязана принимать union полей.
- `last_lot_raw`, `grid_count`, `current_step` в `ChannelState` нерелевантны для impulse, но останутся в SQLite-state.

### Option 2 — Отдельный preset-type (`strategy_type`)

Добавить в yaml ключ верхнего уровня `strategy_type: "auragrid" | "auraimpulse"` (default `"auragrid"` для backward-compat существующих пресетов). Под каждый type — отдельная pydantic-модель (`AuraGridConfig`, `AuraImpulseConfig`) с **своим** набором секций. Engine dispatch'ит на под-движок по type.

**Плюс:**
- Каждый type имеет собственный изолированный набор полей. `extra="forbid"` работает строго.
- UI: Wizard на старте предлагает выбрать type, дальше — type-specific Step3Editor с только релевантными полями.
- pydantic-валидация — без условных инвариантов. Каждая модель сама за себя.
- Engine state — отдельная dataclass `ImpulseState`, без неиспользуемых полей.
- Расширение в будущем (третий type) — добавление по той же схеме.

**Минус:**
- Больше изменений в инфраструктуре: Wizard, IPC-схема создания стратегии, Rust `strategies.rs` (export/import preset), типы в TypeScript для UI.
- Strategy-list в UI должен показывать type каждой стратегии (иначе тестировщик не отличит AuraGrid от AuraImpulse в списке).
- `magic_number` инвариант (read-only после создания) распространяется и на type — нельзя сменить type существующей стратегии.

### Option 3 — Отдельный репо / отдельный бот

Сделать AuraImpulse параллельным проектом, переиспользовать только утилиты (`mt5/`, `licensing/`, IPC-инфраструктуру) через extracted-пакет.

**Плюс:** полная изоляция, никакого риска регрессии в AuraGrid.

**Минус:** дублирование Tauri-shell, license server'а, log-shipper'а, MSI-сборки. Тестировщику два MSI. Несоразмерно scope'у новой стратегии.

## Decision

**Выбран Option 2 — отдельный preset-type.**

Самые сильные аргументы:
1. **Чистая валидация.** `extra="forbid"` остаётся как защита. Каждая стратегия — своя pydantic-модель без условных инвариантов. Это эталон, к которому уже стремится AuraGrid (см. TZ_TRAIL_REWORK v1.0, где боролись именно с мутными инвариантами).
2. **Чистый UX.** Тестировщик не видит неприменимых полей. Step3Editor для impulse — 13 полей (vs 38 для AuraGrid). Понятнее, меньше места для ошибок настройки.
3. **Согласуется с [[adr-001-surgical-minimal-vault-updates]] на уровне архитектуры.** Минимизация структуры на уровне yaml/pydantic = аналог Simplicity First на уровне vault'а.
4. **Расширяемость.** Если в будущем появится третья стратегия (например, статистический арбитраж) — добавляется ровно тем же паттерном, без накопления `if mode == X` веток в каждом модуле.

Имена: `strategy_type: "auragrid"` (текущее поведение, default для обратной совместимости) и `"auraimpulse"` (новое). Не `"grid"` / `"impulse"` — полные имена улучшают читаемость пресетов и UI.

## Consequences

**Положительные:**

- Pydantic-валидация и `extra="forbid"` работают строго для обоих типов.
- UI/Wizard: пользователь явно выбирает стратегию при создании. После создания — type заморожен (как `magic_number`).
- SQLite-state: каждый type — свой формат, не пересекаются.
- Engine dispatch — один if-branch на старте, дальше под-движок работает с своей моделью.
- Backward-compat: существующие пресеты без `strategy_type` интерпретируются как `"auragrid"` (default в pydantic). `config_version` бамп не требуется для добавления нового type (только для **изменения** существующего; добавление optional поля с default — non-breaking).

**Отрицательные:**

- Бо́льший diff в инфраструктуре: Wizard (новый шаг выбора type), IPC (создание стратегии теперь параметризовано type), Rust `strategies::{create,export,import}_preset` (dispatch по type), Strategy-list UI (отображение type).
- `LicenseClient`/`bot_version`/telemetry — должны включать type в payload (для аналитики по типам стратегий).
- Тестировщикам нужно объяснить, что AuraGrid и AuraImpulse — это разные стратегии, не «два режима»; они конкурируют за один MT5-инструмент.

**Не-последствия (явно):**

- AuraGrid не меняется. Никаких правок в `scalping.py`, `conservative_grid.py`, `profit_trailing.py`, `protection.py`, кроме добавления type-dispatch в `engine.py` и Wizard/IPC-слоёв.
- `magic_number` — общее пространство имён для обоих type (число должно быть уникально по всем стратегиям пользователя независимо от type).
- MT5 `magic` фильтрует ордера/позиции независимо от type — никаких коллизий между AuraGrid и AuraImpulse на одном символе, если magic'и разные.

## Migration plan

**Backward-compat для существующих пресетов:**
- В `BotConfig` добавить `strategy_type: Literal["auragrid", "auraimpulse"] = "auragrid"` (default).
- Любой существующий yaml без `strategy_type` интерпретируется как AuraGrid — текущее поведение сохраняется.
- `config_version` остаётся `2` (TZ TRAIL_REWORK v1.0 — последний bump). Добавление optional поля с default — non-breaking change.

**Структура нового yaml для AuraImpulse:**
```yaml
config_version: 2
strategy_type: "auraimpulse"
license_key: "..."
bot_version: "0.1.x"
preset_name: "impulse-default"
log_level: INFO

general:
  allow_buy: true
  allow_sell: true
  magic_number: 20260002
  min_account_balance: 9500.0

impulse:
  lot_size: 0.01
  lot_type: "fixed"
  spread_buffer: 5
  first_step: 500
  pending_refresh_sec: 5
  sl_distance_pts: 200
  cooldown_sec: 60
  trail_size_profit: 50
  trail_update_distance_profit: 30

mt5:
  symbol: "XAUUSD"
  login: ...
  password: ...
  server: ...

ipc: { port: 8765, enabled: true }
licensing: { server_url: "..." }
log_shipping: { enabled: false, ... }
```

Секции `scalping`, `conservative_grid`, `notifications` в AuraImpulse-yaml **отсутствуют** (`extra="forbid"` на корневой модели должен это допускать — реализуется через discriminated union pydantic v2).

**Wizard:**
- Шаг 1: выбор `strategy_type` (radio с двумя опциями + описаниями).
- Шаг 2-3: type-specific форма (для AuraGrid — текущий Step3Editor; для AuraImpulse — новый ImpulseEditor с 13 полями).
- При сохранении: создаётся файл `%APPDATA%\GridScalp\strategies\<magic>.yaml` с правильным `strategy_type`.

**Strategy-list:**
- Отображает каждую стратегию с бейджем `[AuraGrid]` / `[AuraImpulse]`.
- При запуске бота — диспатч в `lib.rs::start_bot` идентичен, бот сам читает type из yaml и инициализирует нужный engine.

**SQLite-state:**
- Для AuraImpulse — отдельная таблица `impulse_state` со своей схемой. AuraGrid таблицы остаются (`channel_state`, etc.).
- Миграция БД: ALTER не нужен, новая таблица создаётся при первом запуске AuraImpulse-стратегии.

**Внимание:** `magic_number` AuraImpulse-стратегии должен быть **уникален** относительно ВСЕХ AuraGrid-стратегий пользователя. Сценарий «два бота на одном MT5-инструменте с одинаковым magic» — катастрофа: каждый увидит чужие позиции как «свои» и попытается ими управлять. UI должен проверять uniqueness при создании.

## Verify

ADR будет считаться полностью реализованным когда:

1. `BotConfig.strategy_type` присутствует, default `"auragrid"`, существующие тесты `test_config.py` зелёные без изменений.
2. `AuraImpulseConfig` (новая модель) с 13 полями + валидаторами реализована и покрыта unit-тестами.
3. Engine dispatch: новый файл `python/bot/core/impulse.py` (под-движок), `engine.py` выбирает между ним и `scalping.py` по `cfg.strategy_type`.
4. Wizard и Strategy-list поддерживают оба type. UI smoke-тест на оба пути создания стратегии.
5. Rust `strategies::{create,export,import}` корректно работают с обоими type.
6. Полный pytest + npm build + cargo check зелёные.
7. Acceptance-тест AuraImpulse: numeric example из ТЗ §X (закрепляется в TZ_IMPULSE_STRATEGY_v1.0).

Эти критерии — высокоуровневые. Детальный verify-чек-лист реализации — в TZ.

## Связано с

- [[auragrid-impulse-strategy]] — концептуальная страница стратегии (state machine, формула трейла, каталог настроек)
- [[auragrid-trading-core]] — паттерн engine/sub-engines/protection, используемый как референс
- [[auragrid-trading-settings]] — каталог настроек AuraGrid (для сравнения и обоснования отдельного type)
- [[adr-002-trail-rework-mq5-parity-departure]] — формула трейлинга, переиспользуется в AuraImpulse без изменений
- [[adr-001-surgical-minimal-vault-updates]] — методология «минимализм структуры», применённая на архитектурном уровне
- `auragrid/docs/tz/TZ_IMPULSE_STRATEGY_v1.0.md` — реализационное ТЗ (создаётся в этой же сессии)

## Источник

- Концептуальная сессия с продакт-владельцем 2026-05-25 (третья за день) — 4 раунда уточнений до замёрзшей концепции (13 полей)
- AuraGrid `python/bot/models/config.py` — текущая pydantic-схема (как контр-пример мутных инвариантов)
- [[auragrid-trading-settings]] §«Сводка валидаций» — 13 правил, которые в AuraImpulse становятся 10 более простых
