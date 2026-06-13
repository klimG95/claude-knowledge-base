---
type: moc
tags: [auragrid, trading, core, mql5-port]
component: bot.core
layer: code
shape: domain-hub
created: 2026-05-22
updated: 2026-05-25
---

# AuraGrid — Trading core

**TL;DR.** Главное торговое ядро Python-бота — порт MQL5-эталона. Engine = OnTick dispatcher. Под-движки: Scalping (грид-добор), ConservativeGrid (после выхода скальпа), ProfitTrailer (трейлинг SL на всех позициях), Protection (close-all + max_loss). Risk-table — вычисление просадки. Все цены идут через `normalize_lot` и `normalize_price`.

## Когда читать эту страницу

- Перед изменением логики open/close/grid
- При вопросах «как считается лот / шаг / прибыль»
- При диагностике странного поведения бота на тиках (порядок операций критичен)

## Компоненты и файлы

| Модуль | Файл | Что |
|--------|------|-----|
| Engine | `python/bot/core/engine.py` | OnTick dispatcher, start/stop, sync state с MT5 |
| Scalping | `python/bot/core/scalping.py` | First order + trail pending + grid placement |
| ConservativeGrid | `python/bot/core/conservative_grid.py` | После `MaxScalpOrders` / `MaxScalpLoss` |
| ProfitTrailer | `python/bot/core/profit_trailing.py` | Trail SL на всех позициях канала |
| Protection | `python/bot/core/protection.py` | close_channel + check_max_loss |
| Risk | `python/bot/core/risk.py` | Risk-table (просадка/% по уровням грида) |
| Normalize | `python/bot/utils/normalize.py` | Lot/price округление под брокера |

## Ключевые контракты и инварианты

### Engine.on_tick порядок (mql5:2387)
1. Guard: `not running` → exit
2. Guard: `is_max_loss_hit` → exit
3. Scan BUY + SELL (sync_state)
4. `protection.check_max_loss` (закрывает оба канала, сетит флаг)
5. `process_channel` для каждого канала (если allow_buy/sell)
6. Persist state (SQLite)
7. Risk-table hook (~1 Hz через monotonic clock)

### Engine.process_channel guard паузы (изменено 2026-05-22, раунд 3)
Раньше `if state.paused: return` стоял в самом начале — паузой блокировался ВЕСЬ канал, включая трейлинг профита. Теперь guard перенесён в середину: paused блокирует ТОЛЬКО блок 4 (SCALP→CG transition) и блок 5 (dispatcher по режиму). Продолжают работать на паузе:
- (1) детекция новой позиции,
- (2) reset после full close,
- (2b) partial-close sync (синхронизация grid_count/last_lot после внешнего закрытия),
- (2c) stale pending sync,
- (3) **`profit_trailer.manage(state)`** — выставление initial SL при достижении target и подтяжка SL по `trail_update_distance_profit`.

UX-требование: «во время паузы должно останавливаться только открытие новых сделок; стоплосс и фиксация профита работают».

### close_channel (после фиксов 2026-05-22 в двух коммитах)
- **Порядок: по убыванию объёма (самый большой лот первым), тай-брейк тикет (новые раньше)** — отход от mq5:1729 reversed, см. [[adr-005-largest-lot-first-ordering]] (2026-06-04). То же в `ProfitTrailer.apply_sl_to_all`. Причина — нивелировать риск от медленного последовательного `order_send` (MetaTrader5 без batch/async). Меняется только порядок обхода.
- **Свежий tick перед каждой позицией** (не один на цикл)
- **`on_retry` callback** — обновляет `price` при REQUOTE/INVALID_PRICE
- **`max_retries=5` для close** (вместо дефолтных 3) — у DooTechnology XAUUSD `NO_PRICES (10021)` длится 1-2 сек
- **`10021 NO_PRICES` в retryable**, **`10044 POSITION_CLOSED` — success-by-other-means**
- При неудаче — **re-scan по тикету через `positions_get(ticket=…)`**: если позиция реально закрыта (SL триггернул параллельно), счётчик инкрементируется (`channel_close_position_resolved_externally`). Иначе counter врёт.
- При ошибке одной — лог `channel_close_position_failed`, продолжаем
- В конце — `state.reset()` (грид/лоты/ticket → 0, direction/paused сохраняются)

### Lot calculation (после фиксов 2026-05-22)
- Формула: `(last_lot_raw + increase_lot_size) * martingale_coeff`
- `last_lot_raw` — нескруглённый, сохраняется ДО execute (инвариант #2)
- **При failed execute (NO_PRICES/INVALID_VOLUME) `last_lot_raw` откатывается на prev**. Иначе мартингейл-drift: база сдвинута, ордер не выставлен → следующий тик считает от уже-увеличенной базы. Это была реальная причина «лот приближён, не точен» на XAUUSD (`volume_step=0.01`, где normalize_lot работает корректно).
- `normalize_lot`:
  - `volume_step <= 0` → 0 (защита от inf)
  - `lot < volume_min` → 0 (нельзя торговать)
  - `steps = floor(lot/step + 0.5)` (MQL5 half-away-from-zero)
  - **`digits = -log10(volume_step)`** (не жёстко 2, иначе теряется младший разряд для 0.001-step брокеров)

### ProfitTrailer.arm_manual / Protection.arm_channel_trail (2026-05-22 раунд 3)
UX-семантика IPC `close_channel`/`close_all` изменена: вместо мгновенного physical-close (TRADE_ACTION_DEAL по каждой позиции) теперь арим трейлинг. Цепочка:

1. `IPC.handle_close_*` → `Protection.arm_channel_trail(state, profit_trailer)`.
2. `Protection.arm_channel_trail` → `ProfitTrailer.arm_manual(state)`.
3. `ProfitTrailer.arm_manual` вычисляет `initial_sl = bid - adjusted_stops × point` (для BUY) или `ask + ...` (для SELL), вызывает `apply_sl_to_all`, фиксирует `state.trail_sl = initial_sl`. Возвращает `ArmResult.{NONE, ARMED, ALREADY_ACTIVE}`.
4. `Protection.arm_channel_trail` при `ARMED` — удаляет pending-ордера канала (паттерн ACTIVATED-ветки в `engine.process_channel`, mq5:1412), `state.pending_ticket = 0`.
5. Дальше обычный `profit_trailer.manage()` подтягивает SL по `trail_update_distance_profit`.

Поведение:
- Цена пойдёт в плюс → SL ползёт за ней (стандартный trail).
- Цена откатится на `trail_size_profit + spread_buffer` (или `stops_level` если больше) → брокер закроет позиции по SL.

Гард двойной активации: если `state.trail_sl != 0` (трейлинг уже активен) → `arm_manual` возвращает `ALREADY_ACTIVE`, не трогает `state.trail_sl` (иначе можно понизить SL — нарушение инварианта #4).

IPC `CloseResult` теперь содержит `armed_trail: bool` (default False для backward-compat); UI рисует разный текст уведомления в зависимости от флага.

### Универсальная формула трейлинга (TZ TRAIL_REWORK v1.0, 2026-05-25)

Применяется одинаково к pending-трейлингу (scalp/CG) и profit-SL-трейлингу (scalp/CG) — четыре трейлинга, одна формула. См. [[adr-002-trail-rework-mq5-parity-departure]].

**Триггер первого выставления pending (вариант B с overshoot):**
```
BUY : ask <= last_open_price − (current_step + trail_size) × point
SELL: bid >= last_open_price + (current_step + trail_size) × point
```
Действие: pending выставляется на `bid ± trail_size × point` — это **ровно `current_step` пт от `last_open_price`**. Ключевой инвариант геометрии сетки.

**Универсальный трейлинг (pending и profit-SL):**
```
threshold = trail_size + trail_update_distance
на каждом тике:
    dist = |цена − ордер/SL|
    если dist > threshold И сторона = «прибыль/добор»:
        ордер/SL → (цена ± trail_size)
```
«Сторона»: для pending — в сторону добора (BUY ниже, SELL выше); для SL — в сторону прибыли (BUY выше, SELL ниже). Обратно никогда не двигается (инвариант #4 для SL, аналог для pending).

**Что изменилось vs MQL5-эталона:**
- Удалён параметр `PendingOrderOffset` (scalp + CG); семантика растворилась в `trail_size`.
- Порог пересчёта трейлинга = `trail_size + trail_update_distance` (раньше сравнивалось с абсолютным `|цена − ордер|` против только `trail_update_distance`).
- Снят инвариант `trail_update_distance_profit > trail_size_profit`; заменён на простую проверку `trail_update_distance > 0`.

Acceptance: `python/tests/test_trail_rework_acceptance.py` — закрепляет численный пример из ТЗ §2.5.

### profit_fixing_direction vs auto_calculated_profit
- **profit_fixing_direction (USD):** активирует trailing SL когда `floating_pl ≥ value`
- **auto_calculated_profit (USD на 0.01 лот):** активирует trail когда `floating_pl ≥ value * (total_lot/0.01)`
- **Хотя бы один должен быть > 0** (валидация в `ScalpingConfig._check_trail_and_profit`)
- **Не закрывает позиции мгновенно** — закрытие через SL, когда цена откатывается на `trail_size_profit + spread_buffer` (или `stops_level` если больше)
- UI labels с 2026-05-22: `"Trail activation @ profit (USD)"` + `"Auto profit per 0.01 lot (USD)"`
- **2026-05-22:** при `apply_sl_to_all` возвращает `updated=0` И все позиции канала уже имеют SL близкий к `initial_sl` (delta < point), всё равно фиксируем `state.trail_sl = initial_sl`. Иначе тик за тиком пытается активировать заново — infinite re-activation loop. Helper: `_all_positions_already_at`.

### pending_ticket sync (после фиксов 2026-05-22 в двух коммитах)
- `engine.start()` сверяет state.pending_ticket с реальным MT5:
  - cached != 0, нет реальных → clear stale (`pending_ticket_cleared_on_start`)
  - cached == 0, есть реальные → adopt самый свежий (`pending_ticket_adopted_on_start`)
  - cached != 0, не совпадает с реальными → reassign на самый свежий (`pending_ticket_reassigned_on_start`)
  - **Multi-pending (2+ в MT5 после краха между двумя `order_send`)** → оставить adopted, остальные удалить через `TRADE_ACTION_REMOVE` (`pending_ticket_extras_cleanup_on_start`). Иначе они навсегда фантомы.
- В `process_channel` блок 2c — runtime sync (mql5:1069-79), срабатывает при `position_count == grid_count`
- В `process_channel` блок 2b — partial close detection, обновляет `grid_count := position_count` если позиции закрыты внешне

## Анти-паттерны

1. **Не цикл по позициям с кэшированной ценой.** REQUOTE/INVALID_PRICE на 3-й итерации → задним числом позиции не закрываются. Шаблон в `close_channel` теперь корректный.
2. **Не `round(_, 2)` на лот.** Зависит от `volume_step` брокера; жёсткое значение ломает точность.
3. **Не доверять `state.pending_ticket` без MT5-проверки на старте.** Может быть stale (DB опередил MT5) или orphan (бот упал до save).
4. **Не путать `profit_fixing_direction` с TP.** Это активация trail, не закрытие. Закрытие — когда SL триггерит после отката.
5. **Не считать closed_count по `result is not None`.** Позиция может быть закрыта параллельно (SL/TP race) → MT5 вернёт не-DONE retcode → counter не учтёт, хотя позиции уже нет. Всегда верифицируй `positions_get(ticket=…)` после fail.
6. **Не менять state перед `execute()` без snapshot/restore.** Любое поле `state.*`, изменяемое до execute, должно откатываться при `result is None`. Иначе drift накапливается тихо: тестировщик видит «лот не точный», логи чистые.
7. **Не предполагать `_RETRYABLE` универсальным.** У каждого брокера свой набор «временных» retcode'ов. У DooTechnology XAUUSD это NO_PRICES (10021); у других брокеров могут быть другие. Проверять при онбординге нового брокера.
8. **Не оставлять `state.trail_sl = 0` при `updated=0`.** Если все позиции уже имеют целевой SL — логически trail активирован. Иначе infinite re-activation.

## Связано с

- [[auragrid]] — MOC проекта
- [[auragrid-incidents-log]] — инциденты, где появляются эти модули
- [[auragrid-log-analysis]] — что искать в логах когда что-то не так

## Источник

- MQL5 эталон `mql5/TZ_MT5_GridScalp_Bot_v2.mq5` (порт)
- Сессия 2026-05-22 (раунд 1) — UX-симптомы, коммит `85b7c91`
- Сессия 2026-05-22 (раунд 2, ре-аудит) — root cause фиксы, коммит `677811c`. Через `runbook-vault-integration` workflow.
- Сессия 2026-05-22 (раунд 3) — UX: close-as-trail (`Protection.arm_channel_trail` + `ProfitTrailer.arm_manual`), pause-keeps-trailing (guard перенесён), Save/Load preset как файл (Rust `strategies::{export,import}_preset` + Tauri commands + UI меню).
