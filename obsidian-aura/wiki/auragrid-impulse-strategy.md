---
type: concept
tags: [auragrid, trading, strategy, impulse, breakout, design]
component: bot.core (новая стратегия impulse)
layer: domain
shape: concept
created: 2026-05-25
updated: 2026-05-29
implementation_status: "v1.0 implemented (1253 pytest passed); 2026-05-28 cooldown UX + auto-cancel pendings on stop (1287 passed); 2026-05-28 adaptive distance v1.0 — first_step заменён на candle_count+distance_coefficient (1302 passed), config_version 2→3"
---

# AuraGrid — Impulse Strategy (концептуальная)

**TL;DR.** Новая отличная от AuraGrid торговая стратегия — `AuraImpulse`. Реализуется как **отдельный preset-type** в той же кодовой базе. Чистая breakout-импульсная модель: один pending stop на каждом разрешённом канале, на дистанции `first_step` от цены; периодическое перевыставление под актуальную цену; при срабатывании оппозитный pending снимается, открывается одна позиция со стартовым SL; дальше работает единая формула трейлинга (без отдельной фазы активации). После закрытия — настраиваемая пауза, затем цикл повторяется. Без сетки, без мартингейла, без CG-фазы, без индикаторов.

> Эта страница — **дизайн-документ**. Концепция замёрзла 2026-05-25; реализация v1.0 завершена в той же дате (4-я сессия) — полное соответствие state machine, формулам, 13 полям, gap-обработке. Внутрипроектное ТЗ: `auragrid/docs/tz/TZ_IMPULSE_STRATEGY_v1.0.md`. Архитектурное решение: [[adr-003-impulse-strategy-new-preset-type]].
>
> **Состояние реализации (2026-05-25):** Python ядро `python/bot/core/impulse.py` (~660 строк), state `python/bot/models/impulse_state.py`, persistence `python/bot/state/persistence.py` + schema. Engine dispatch в `main.py::build_engine` через `isinstance(config, AuraImpulseBotConfig)`. IPC: `handle_pause_channel/pause_strategy/close_channel/close_all/get_status/get_snapshot/reset_stopped` диспатчат на ImpulseEngine. Rust strategies.rs: `create_impulse` + serde-совместимое поле `strategy_type` в `StrategyEntry`. UI: Step2 Radio для выбора type + Step3EditorImpulse (9 pre-flight инвариантов) + бейдж `[AuraImpulse]`. Тесты: **84 impulse-теста** (полный pytest 1253 passed + collect-only 1272 в аудите). Manual QA: `docs/qa/scenarios/impulse_lifecycle.md`. **Fast-path решение** для приоритета пользователя «скорость»: двойная отправка SL (pre-fill SL в pending'е + точный modify после fill — окно беззащитности на gap'е = 0; TZ §2.6 «принять в реализации» — выбрана двойная отправка). **Аудит 5-й сессии 2026-05-25** ([[auragrid-incidents-log]] «След решения 2026-05-25», auto-memory `reference_impulse_audit_2026_05_25`) — дефектов нет, 13 рекомендаций (R1-R3 критичны перед раздачей MSI).

## Когда читать эту страницу

- Перед чтением `TZ_IMPULSE_STRATEGY_v1.0.md` (страница — концептуальный контекст ТЗ)
- При вопросах «почему impulse сделан отдельной стратегией, а не режимом» → [[adr-003-impulse-strategy-new-preset-type]]
- Перед расширением impulse-стратегии новыми параметрами или фильтрами (велосити, расписание, etc.)

## Концепция

### State machine (одна на стратегию, не два независимых канала)

```
            ┌──────────────────────────────────────────┐
            │  State A — Watching (нет позиции)        │
            │                                          │
            │  Для каждого разрешённого канала:        │
            │    • держим один pending stop            │
            │      на дистанции first_step от цены     │
            │    • раз в pending_refresh_sec           │
            │      modify под актуальную цену          │
            └──────────────┬───────────────────────────┘
                           │ цена дотянулась до pending
                           │ (BUY_STOP или SELL_STOP)
                           ▼
            ┌──────────────────────────────────────────┐
            │  Переход (один тик):                     │
            │    1. зафиксировать позицию              │
            │    2. снять оппозитный pending           │
            │    3. SL = entry ± sl_distance_pts·point │
            └──────────────┬───────────────────────────┘
                           │
                           ▼
            ┌──────────────────────────────────────────┐
            │  State B — Trading (одна позиция)        │
            │                                          │
            │    • никаких pending                     │
            │    • единая формула трейл-SL             │
            │      (см. §«Формула трейлинга»)          │
            │    • защита: min_account_balance         │
            │      по equity на каждом тике            │
            └──────────────┬───────────────────────────┘
                           │ закрытие (SL/ручной/min_balance)
                           ▼
            ┌──────────────────────────────────────────┐
            │  Cooldown (cooldown_sec)                 │
            │    • не выставляем pending               │
            │    • не открываем позиции                │
            │    cooldown_sec = 0 → пропускаем          │
            └──────────────┬───────────────────────────┘
                           │ таймер истёк
                           └─→ возврат в State A
```

### Ключевые отличия от AuraGrid

| | AuraGrid (scalp + CG) | AuraImpulse |
|---|---|---|
| Концепция | Грид + мартингейл + переход в CG | Single-shot breakout с трейлингом |
| Каналы | Два независимых state | Один общий state (один pending активен → второй снимается) |
| Позиций одновременно | До `max_scalp_orders + cg.max_orders` | Ровно **одна** |
| Pending | Цепочка доборов (scalp + CG trail) | Один pending на канал, периодический modify |
| Лот | Мартингейл от позиции к позиции | Один `lot_size` без масштабирования |
| Стоп-лосс | Только трейл-SL после активации по USD | Стартовый SL **с момента входа** + единая формула трейла |
| Активация трейла | Отдельная фаза по `profit_fixing_direction` (USD) | Активации как фазы **нет** — единая формула с момента входа |
| Защита equity | `max_loss` (относительный убыток USD) | `min_account_balance` (абсолютный порог equity USD) |
| Cooldown между сделками | Нет | `cooldown_sec` после любого закрытия |
| Зависимость от MQL5-эталона | Порт MQL5 (с отходами) | Полностью новая логика, нет MQL5-предка |

## Каталог настроек

Полный набор — **13 полей** (vs 38 у AuraGrid). Имена, типы, валидации — финальные после концептуальной сессии 2026-05-25.

### `general` (4 поля)

| # | Поле | Тип | Назначение |
|---|------|-----|------------|
| 1 | `allow_buy` | bool | Разрешить BUY_STOP pending. Если `False` — этот канал не участвует в State A |
| 2 | `allow_sell` | bool | Аналогично для SELL_STOP |
| 3 | `magic_number` | int (>0) | Уникальный ID стратегии, read-only после создания (как в AuraGrid) |
| 4 | `min_account_balance` | float (>0) | Порог equity счёта в USD. При `equity ≤ min_account_balance` стратегия останавливается: закрыть открытую позицию по рынку, снять все pending, выставить флаг `stopped` до ручного перезапуска. UI label: «Минимальный баланс счёта (USD)» (под капотом — `account_info().equity`, как и `max_loss` в AuraGrid) |

### `impulse` (9 полей, новая секция)

| # | Поле | Тип | Назначение |
|---|------|-----|------------|
| 5 | `lot_size` | float (>0) | Размер позиции (семантика зависит от `lot_type`) |
| 6 | `lot_type` | "fixed"\|"dynamic" | Заимствовано из AuraGrid. `fixed`: ровно `lot_size`. `dynamic`: % свободной маржи |
| 7 | `spread_buffer` | int (≥0) | Защита от расширения спреда. При широком спреде pending не модифицируется и не выставляется (как `check_spread_normal` в AuraGrid) |
| 8 | `first_step` | int (>0) | Дистанция pending stop от текущей цены (pts). Это и есть «фильтр импульсности»: большой `first_step` ловит только резкие движения, малый — почти любое касание |
| 9 | `pending_refresh_sec` | int (≥1) | Интервал перевыставления pending в State A (sec). Защита `≥1` от спама `TRADE_ACTION_MODIFY` |
| 10 | `sl_distance_pts` | int (>0) | Расстояние стартового SL от **цены входа** (pts). SL выставляется сразу при заполнении ордера |
| 11 | `cooldown_sec` | int (≥0) | Пауза после **любого** закрытия позиции перед возвратом в State A (sec). `0` = выкл (сразу новый цикл) |
| 12 | `trail_size_profit` | int (>0) | Удалённость SL от цены при трейлинге (pts). Заимствовано из AuraGrid с той же семантикой (TZ TRAIL_REWORK v1.0) |
| 13 | `trail_update_distance_profit` | int (>0) | Частота подтяжки SL (pts). Заимствовано из AuraGrid с той же семантикой |

### Что НЕ заимствуется из AuraGrid (с обоснованием)

- Вся секция `conservative_grid` — нет фазы после-скальпа.
- `price_distance`, `step_multiplier`, `min_grid_step` — нет сетки.
- `max_scalp_orders`, `max_scalp_loss` — нет режимных переходов.
- `martingale_coeff`, `increase_lot_size`, `max_lot_size` — один трейд за раз.
- `trail_size`, `trail_update_distance` (pending-трейл) — pending не трейлится в смысле AuraGrid; он **периодически перевыставляется** по новой цене (механизм проще).
- `profit_fixing_direction`, `auto_calculated_profit` — активации как фазы нет; стартовый SL + единая формула.
- `max_loss` (relative USD) — заменён на `min_account_balance` (absolute equity USD).

## Формула трейлинга (единая, без фазы активации)

Стартовый SL выставляется в момент заполнения pending. После этого на каждом тике применяется одна формула — та же, что у AuraGrid profit-трейлинга после активации (TZ TRAIL_REWORK v1.0):

**BUY:**
```
Стартовый SL = entry_price − sl_distance_pts · point   (в момент заполнения)

На каждом тике:
    dist = (bid − SL) / point
    если dist > trail_size_profit + trail_update_distance_profit:
        новый_SL = bid − trail_size_profit · point
        (если новый_SL > старый_SL — modify; иначе игнор, SL никогда не вниз)
```

**SELL:** зеркально (`ask + sl_distance_pts·point`, движение в минус по цене = плюс по PL).

**Инварианты:**
- SL никогда не двигается в сторону убытка (BUY — никогда вниз, SELL — никогда вверх).
- `effective_distance = max(trail_size_profit, broker_stops_level)` — поправка под минимальный стоп брокера (как `adjusted_stops` в AuraGrid).
- Поправка `spread_buffer` применяется как в AuraGrid: фактическая дистанция SL = `max(trail_size_profit + spread_buffer, stops_level)`.

### Тонкость: когда трейл стартует на первом тике

Если `sl_distance_pts > trail_size_profit + trail_update_distance_profit` → условие формулы выполнено уже в момент входа → SL подтянется ближе к цене **на следующем тике без плюсового движения**.

**Числовой пример** (BUY XAUUSD, point=0.01):
- entry = 2000.00, sl_distance_pts = 200 → стартовый SL = 1998.00
- trail_size_profit = 50, trail_update_distance_profit = 30 → порог = 80
- На входе: dist = (2000.00 − 1998.00)/0.01 = 200 > 80 → условие выполнено сразу
- Следующий тик (даже без движения цены): новый SL = 2000.00 − 50·0.01 = 1999.50

Это **не баг формулы — это её следствие**, зафиксированное продакт-владельцем как корректное поведение. Если хочется отложить подтяжку SL до плюсового движения — настраивать `sl_distance_pts ≤ trail_size_profit + trail_update_distance_profit`.

## Защита equity (`min_account_balance`)

На каждом тике (в начале `on_tick`, аналог `protection.check_max_loss` AuraGrid):
```
if account_info().equity ≤ min_account_balance:
    закрыть открытую позицию (если есть) по рынку
    снять все pending (если есть)
    state.stopped = True   # флаг до ручного перезапуска
    log.warning("impulse_min_balance_hit", equity=..., threshold=...)
    return  # дальнейший on_tick пропущен
```

После триггера стратегия не возобновляется автоматически (как `max_loss_hit` в AuraGrid). Пользователь снимает флаг через UI «Перезапустить стратегию».

## Cooldown после закрытия

Закрытие может произойти по трём причинам:
1. Брокер триггернул SL (стартовый или подтянутый).
2. Ручной close из UI (`Protection.arm_channel_trail` НЕ применяется — здесь логика проще, ручной close = немедленный physical close).
3. Триггер `min_account_balance` — этот случай в cooldown **не идёт**, переход сразу в `stopped`.

При (1) или (2):
```
state.cooldown_until = now() + cooldown_sec
```
В State A на каждом тике: `if now() < cooldown_until: return` (не выставляем pending, не модифицируем).
При `cooldown_sec == 0` — `cooldown_until` не сетится, переход в State A немедленный.

## Архитектурно: отдельный preset-type

Решение зафиксировано в [[adr-003-impulse-strategy-new-preset-type]]. Краткое обоснование:

- AuraGrid и AuraImpulse — концептуально разные стратегии (grid+martingale vs single-shot breakout), а не «два режима одной стратегии».
- Один тип = один набор полей в pydantic и Step3Editor; не приходится таскать неприменимые поля и плодить дыры в валидации.
- В UI: при создании стратегии (Wizard) пользователь выбирает type → дальше идёт type-specific Step3Editor.
- На уровне engine: новый под-движок `Impulse` (~аналог Scalping/CG, но проще — нет фазовых переходов).
- На уровне yaml: новый ключ верхнего уровня `strategy_type: "auragrid" | "auraimpulse"` (default — `auragrid` для совместимости). Для impulse-стратегий yaml содержит секцию `impulse` вместо `scalping` + `conservative_grid`.

Детали реализации (структура engine, pydantic-схема, UI-flow) — в `auragrid/docs/tz/TZ_IMPULSE_STRATEGY_v1.0.md`.

## Анти-паттерны (на этапе дизайна)

1. **Не пытаться переиспользовать `ChannelState` AuraGrid целиком.** Поля `grid_count`, `last_lot_raw`, `current_step`, `pending_ticket` (одно поле под цепочку доборов) — это про сетку, не нужны impulse. Чистая `ImpulseState` с полями: `mode: WATCHING|TRADING|STOPPED`, `buy_pending_ticket`, `sell_pending_ticket`, `position_ticket`, `entry_price`, `trail_sl`, `cooldown_until`, `stopped`.
2. **Не оставлять оппозитный pending живым после срабатывания.** Концептуальное решение — снять. Реализационно: в том же тике, что обработал позицию, удалить оппозитный pending через `TRADE_ACTION_REMOVE`. Если pending параллельно сработал на том же тике (теоретически возможно при двойном касании на гэпе) — закрыть его позицию немедленно (или вообще не открывать вторую: если первая уже зафиксирована, вторую отвергаем pre-flight). Edge-кейс детализируется в ТЗ §3.
3. **Не путать «закрытие позиции» с «остановкой стратегии».** Закрытие → cooldown → новый цикл. Остановка (`min_account_balance`) → флаг `stopped` до ручного перезапуска.
4. **Не выставлять стартовый SL ОТДЕЛЬНЫМ tick'ом после открытия.** SL должен быть в **том же** `order_send` через `sl=` поле request'а. Иначе между открытием и SL — окно беззащитности (одно из MQL5-best-practices).
5. **Не считать `min_account_balance` по `account_info().balance`.** Balance не учитывает плавающий PL → триггер сработает только при закрытии позиции, защита запаздывает. Считать по `account_info().equity` — то же, что Аура делает с `max_loss` (floating PL).
6. **Не разрешать `min_account_balance` нулевым или отрицательным.** Бессмысленно (счёт не может быть ≤0 в принципе). Field-валидатор `> 0`.

## Open questions (для v2 / расширения)

Сознательно вынесено за scope v1.0 (MVP):

- **Фильтр скорости импульса.** Сейчас «импульс» = «цена дотянулась до далёкого pending». Если live-торговля покажет много псевдо-импульсов (медленный дрифт до pending) — добавить опциональный параметр «минимальное движение за окно» (например, `min_velocity_pts_per_sec`).
- **Фильтр времени суток / сессий.** Может пригодиться (азиатская сессия — низкая волатильность, ловить импульсы хуже). v2 может добавить «торговать только в окно `HH:MM−HH:MM`».
- **Страховочный SL до активации трейла.** Сейчас защита между входом и первой подтяжкой SL — только `sl_distance_pts` + `min_account_balance`. Если в проде это окажется недостаточным — добавить опциональный «break-even SL после N pts движения в плюс».
- **Multi-symbol.** Сейчас один бот = один символ (как AuraGrid). Multi-symbol — отдельная задача, не связанная конкретно с impulse.

## Доработка 2026-05-28 — cooldown UX + auto-cancel pendings on stop

Пользователь обнаружил два UX-разрыва после реальной MSI-сборки:

1. **Cooldown «висит навсегда».** После закрытия сделки `state.cooldown_until_ts` тикал, но UI не имел доступа: `Snapshot` interface (TypeScript) был AuraGrid-shape — поле `cooldown_seconds_remaining` из `ImpulseEngine.snapshot()` отбрасывалось. Метод `reset_cooldown` отсутствовал в `ImpulseEngine` (был только `reset_stopped` для halt после `min_account_balance`). Перезапуск/смена настроек cooldown не помогали — таймер хранится в SQLite и переживает рестарт.
2. **Pending'и переживали остановку.** `ImpulseEngine.stop()` сохранял state и сбрасывал `running=False`, но pending'и (BUY_STOP/SELL_STOP) оставались в MT5. Без живого бота они могли сработать → позиция без двойной защиты SL/трейла → инвариант «ровно одна позиция + единая формула трейла» нарушался.

**Решения:**

- `python/bot/core/impulse.py::ImpulseEngine.reset_cooldown()` — обнуляет `state.cooldown_until_ts`, возвращает `True` если cooldown был активен (симметрично `reset_stopped` для halt). Логирует `impulse_cooldown_reset_by_user`.
- `python/bot/core/impulse.py::ImpulseEngine.stop()` — перед `running=False` снимает оба pending'а через `_remove_pending`, обнуляет cache в state. Открытая позиция **не** закрывается (её SL уже в MT5 — поведение симметрично AuraGrid `stop()`, в UI пользователь предупреждён модалкой).
- IPC: `reset_cooldown` добавлен в `KNOWN_METHODS` (`bot/ipc/protocol.py`) и `handle_reset_cooldown` в `bot/ipc/handlers.py` (для AuraGrid — no-op, ok=True).
- Rust: `strategy_reset_cooldown` Tauri command (`desktop/src-tauri/src/lib.rs`).
- UI: `Snapshot.cooldown_seconds_remaining?: number` (`desktop/src/store/strategies.ts`) + жёлтый Alert «Бот ждёт окончания паузы» с кнопкой «Снять с паузы» (`pages/Main/StrategyPanel.tsx`), рендерится только для импульса при `cooldown_seconds_remaining > 0` и не пересекается с red-Alert MaxLoss. В confirm-модалке Stop для импульса добавлено уведомление об авто-снятии pending'ов.

**Тесты:** baseline 1278 → **1287 passed** (+9). Новые: 6 в `test_impulse_engine.py` (`test_reset_cooldown_unlocks_watching`, `test_reset_cooldown_returns_false_when_inactive`, `test_reset_cooldown_after_external_close`, `test_stop_removes_pending_orders`, `test_stop_keeps_open_position`, `test_stop_is_idempotent_when_nothing_pending`), 3 в `test_impulse_ipc.py` (`test_reset_cooldown_in_known_methods`, `test_reset_cooldown_clears_active_cooldown`, `test_reset_cooldown_noop_when_inactive`). cargo check Finished, npm run build OK.

**Что НЕ изменилось:** концепция/state machine/13 полей/формула трейлинга/cooldown_sec из YAML/persistence schema — всё прежнее. Surgical правка по [[adr-001-surgical-minimal-vault-updates]].

## Доработка 2026-05-28 (вторая) — Adaptive distance v1.0 (ADR-004)

Пользователь после первой доработки cooldown UX: «Хочу чтобы дистанция pending'а считалась динамически от среднего размера M1-свеч, а не была статичной». Сценарий — стратегия должна сама подстраиваться под текущую волатильность XAUUSD, не требуя ручной правки `first_step` при смене характера рынка.

**Решение (полные детали — [[adr-004-impulse-adaptive-distance]]):**

- В `ImpulseConfig` поле `first_step: int` удалено, добавлены `candle_count: int (≥1)` и `distance_coefficient: float (>0)`. На каждой новой закрытой M1-свече engine считает `avg(high − low) для последних N свечей × coefficient`, делит на `point` → получает дистанцию в pts.
- Если свечей в истории `< candle_count` (warmup после первого старта / длинного выходного) — pending'и не выставляются; уже стоящие — снимаются. UI показывает «прогрев — копим свечи».
- Cooldown floor: `effective_cooldown = max(cooldown_sec, candle_count × 60)`. Между закрытием сделки и следующим расчётом дистанции гарантированно успевают накопиться свежие свечи, не унаследованные от движения, которое только что завершилось стопом. Пользовательский `cooldown_sec` уважается, если он больше пола.
- Кэш по `bar_time`: copy_rates_from_pos дёргается раз в минуту (при смене времени свежей свечи), а не на каждом тике. Скорость горячего пути не страдает.
- `config_version` 2 → 3 (общая для AuraGrid и AuraImpulse). Старые AuraImpulse-пресеты с `first_step` отвергаются с понятным сообщением.

**Файлы:**
- Python: `python/bot/models/config.py` (поля + bump), `python/bot/core/impulse.py` (метод `_refresh_dynamic_distance` + `_enter_warmup`, переписаны `_arm_cooldown` с floor + `_manage_pendings` с warmup-gate + `_place_pending`/`_modify_pending`/`_make_pending_refresher` берут дистанцию из кэша), `python/bot/mt5/protocol.py` (`TIMEFRAME_M1`, `copy_rates_from_pos` в Protocol), `python/bot/mt5/fake.py` (`set_rates`/`append_rate`/`copy_rates_from_pos` для тестов).
- Rust: `desktop/src-tauri/src/strategies.rs` (config_version 3 в обоих override).
- Preset: `desktop/src-tauri/presets/impulse_default.yaml` (candle_count: 7, distance_coefficient: 1.0).
- UI: `desktop/src/store/strategies.ts` (snapshot: `current_first_step_pts`, `warmup`, `candle_count`, `distance_coefficient`), `desktop/src/pages/Wizard/Step3EditorImpulse.tsx` (два поля вместо одного + обновлены pre-flight), `desktop/src/pages/Main/StrategyPanel.tsx` (плашка «Дистанция pending'а сейчас: N pts» или «прогрев — копим свечи»).
- Bump AuraGrid yaml/templates/fixtures с config_version: 2 → 3 (схема AuraGrid не менялась, но версия единая).

**Тесты:** baseline 1287 → **1302 passed** (+15). Новые в `test_impulse_engine.py`: `test_dynamic_distance_calculated_on_first_tick`, `test_dynamic_distance_coefficient_doubles_distance`, `test_dynamic_distance_averages_multiple_candles`, `test_warmup_when_no_bars`, `test_warmup_when_insufficient_history`, `test_warmup_removes_existing_pendings`, `test_dynamic_distance_cached_until_new_bar`, `test_dynamic_distance_recalculated_on_new_bar`, `test_snapshot_exposes_dynamic_distance`, `test_snapshot_exposes_warmup`, `test_cooldown_floor_overrides_cooldown_sec_zero`, `test_cooldown_floor_with_larger_candle_count`, `test_cooldown_sec_overrides_floor_when_higher`. Существующие тесты пересажены на `candle_count=1 + distance_coefficient=1.0 + seeded avg_range=5.0` (эквивалент `first_step=500`). cargo check Finished, npm run build OK (835 modules, bundle 725 kB).

**Тонкости реализации:**
- `copy_rates_from_pos(symbol, TIMEFRAME_M1, 1, N)` — `start_pos=1` пропускает текущую формирующуюся свечу, берёт N ЗАКРЫТЫХ. Это критично — формирующаяся свеча имеет неполный range и зашумит среднее.
- Кэш `_last_bar_time` сравнивает `bars[0].time` (newest closed bar) с сохранённым. Изменение → новая свеча закрылась → пересчёт. Это эквивалент event-based триггера «на закрытии M1», без подписки на тиковые события.
- Защита от вырожденного случая `dist_pts <= 0` (нулевой range при стоящем рынке) → возврат в warmup до следующей свечи.
- Pre-fill SL в pending request'е остаётся (TZ_IMPULSE §2.6 «двойная отправка SL»), пересчитывается под новую динамическую цену pending'а.
- Поля snapshot'а `current_first_step_pts` + `warmup` + `candle_count` + `distance_coefficient` доступны для UI для визуализации текущего состояния расчёта.

## Пробелы логирования (для анализа постфактум)

Зафиксировано при анализе bot.log magic 20260001 от 2026-05-29 (2 сделки 29 мая UTC) на вопрос «какой был спред в моменты сделок»:

- **Спред в trade-events не пишется.** Поле `spread` есть только в событии `impulse_spread_too_wide` ([impulse.py:706](https://github.com/klimG95/auragrid/blob/main/python/bot/core/impulse.py#L706)) — оно срабатывает лишь при **отбое** широкого спреда (pending не выставлен/не модифицирован). В нормальной торговле — `impulse_pending_placed`, `impulse_position_opened`, `impulse_initial_sl_set`, `impulse_trail_updated` — спред не сохраняется. Восстановить пост-фактум невозможно: fill происходит на стороне брокера, бот не делает snapshot spread'а в тот тик.
- **Что можно вытащить из текущих логов:** время и `entry` сделки (`impulse_position_opened`), стартовый SL (`impulse_initial_sl_set`), все шаги трейла (`impulse_trail_updated` с `old_sl`/`new_sl`/`dist_pts`), факт закрытия (`impulse_position_closed_external`).
- **Если нужна реальная картина спреда** — доработать: добавить `spread_pts = int(round((ask − bid) / point))` в `impulse_position_opened` (на момент fill'а), `impulse_pending_placed`/`impulse_pending_modify_attempt` (на момент посыла в MT5). Симметрично для AuraGrid — отдельная задача.

## Связано с

- [[adr-003-impulse-strategy-new-preset-type]] — решение об отдельном preset-type
- [[adr-004-impulse-adaptive-distance]] — переход от статичного `first_step` к адаптивной дистанции (2026-05-28, accepted)
- [[auragrid]] — MOC проекта
- [[auragrid-trading-core]] — для сравнения с архитектурой AuraGrid (engine, sub-engines, profit trailing)
- [[auragrid-trading-settings]] — каталог настроек AuraGrid (для сравнения объёма и структуры)
- [[adr-002-trail-rework-mq5-parity-departure]] — формула трейлинга, которая переиспользуется здесь
- `auragrid/docs/tz/TZ_IMPULSE_STRATEGY_v1.0.md` — реализационное ТЗ (будет создан в этой же сессии)

## Источник

- Концептуальная сессия 2026-05-25 (третья за день) — обсуждение с продакт-владельцем, итоговый набор полей + state machine
- TZ_TRAIL_REWORK v1.0 — формула трейлинга, переиспользуется
- AuraGrid `python/bot/core/profit_trailing.py` — паттерн trailing SL для adopted-инвариантов
