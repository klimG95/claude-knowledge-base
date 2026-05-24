---
type: reference
tags: [auragrid, trading, settings, config, preset, reference]
component: bot.models.config + Wizard/Step3Editor
layer: contract
shape: reference
created: 2026-05-24
updated: 2026-05-25
---

# AuraGrid — Каталог торговых настроек (пресет)

**TL;DR.** Исчерпывающий справочник по всем редактируемым параметрам торгового пресета AuraGrid: yaml-имя, тип, валидация, назначение, ключевое место использования в торговом коде, UI-label. Источник истины для всего: `python/bot/models/config.py` (pydantic-модели) + `desktop/src/pages/Wizard/Step3Editor.tsx` (UI и клиентский pre-flight). Перед оптимизацией/отладкой настроек открывать эту страницу — она держит всю карту параметров и их инвариантов.

> **Обновлено 2026-05-25 (TZ TRAIL_REWORK v1.0, [[adr-002-trail-rework-mq5-parity-departure]]):** удалены поля `scalping.pending_order_offset`, `conservative_grid.pending_order_offset`. Семантика `trail_size` / `trail_update_distance` (и `_profit`-вариантов) изменена — теперь это «удалённость» и «частота обновления». Порог пересчёта = `trail_size + trail_update_distance`. Снят инвариант `trail_update_distance_profit > trail_size_profit`. `config_version` бампнут 1 → 2.

## Когда читать эту страницу

- Перед оптимизацией торговой стратегии (подбор значений параметров)
- При отладке: «параметр X выставлен, но эффекта нет» → найти где он используется
- При добавлении нового параметра в пресет (чтобы не сломать инвариант или дубль)
- При вопросах тестировщика «что значит поле Y» → процитировать UI label + назначение
- Перед миграцией пресетов (config_version) — список всех обязательных полей

## Структура yaml-пресета

```yaml
config_version: 1                  # схема (служебное)
license_key: "..."                 # обязательное, секрет
bot_version: "0.1.0"               # для телеметрии
preset_name: "default"             # имя пресета
log_level: INFO                    # DEBUG | INFO | WARNING | ERROR | CRITICAL

general: {...}                     # торговые: каналы, max_loss, magic
scalping: {...}                    # 19 параметров скальпинг-режима
conservative_grid: {...}           # 13 параметров CG-режима
notifications: {telegram_chat_id}  # уведомления (нерабочее в текущей волне)

mt5:                               # подключение к терминалу
  symbol: "XAUUSD"                 # торгуется в UI как «Торгуемый символ»
  login: 12345                     # секретные кредентшалы (наследуются из base_config
  password: "..."                  # при load_preset_file, не хранятся в файле пресета)
  server: "..."

# Служебные секции (управляются Rust-ом/CLI, в UI не редактируются):
ipc: {port: 8765, enabled: true}
licensing: {server_url: "..."}
log_shipping: {enabled: false, interval_sec, batch_max_lines, ...}
```

`extra="forbid"` на всех секциях — любое незнакомое поле отклоняется при валидации.

## Сводка: торговых полей всего 34 (после TZ TRAIL_REWORK v1.0)

| Секция | Полей | Из них с явной валидацией | UI |
|--------|-------|---------------------------|----|
| general | 4 | 2 (magic_number > 0, max_loss < 0) | 3 поля (magic read-only) |
| scalping | 18 | 6 (4 поля + 1 model-инвариант + trail_update*>0) | 18 |
| conservative_grid | 12 | 5 (3 поля + 1 model-инвариант + trail_update*>0) | 12 |
| notifications | 1 | 0 | 1 |
| mt5 (торговое) | 1 (symbol) + 3 (cred) | 1 model-инвариант (creds all-or-none) | symbol только когда бот остановлен |

---

## Секция: `general`

### 1. `allow_buy` — Разрешить Buy-канал

- **Тип / default:** `bool` / `True`
- **Валидация:** на уровне `BotConfig._check_any_channel` — хотя бы один из `allow_buy`/`allow_sell` должен быть True (config.py:261-265).
- **Назначение:** Разрешает торговлю на BUY-канал. Если False — engine не инициализирует state для BUY, никакие BUY-ордера/позиции не создаются.
- **Где используется:** `bot/core/engine.py` инициализирует ChannelState для BUY только если allow_buy=True; `process_channel` для BUY запускается с allow_buy guard.
- **UI:** `Step3Editor.tsx:42`. Чекбокс «Разрешить Buy-канал».

### 2. `allow_sell` — Разрешить Sell-канал

- **Тип / default:** `bool` / `True`
- **Валидация:** см. `allow_buy` (взаимосвязь).
- **Назначение:** То же, что `allow_buy`, для SELL.
- **UI:** `Step3Editor.tsx:43`.

### 3. `magic_number` — идентификатор стратегии

- **Тип / default:** `int` / `20260001`
- **Валидация:** `> 0` (config.py:31-42, `_magic_positive`). Защита от коллизии с manual-ордерами трейдера (magic=0).
- **Назначение:** Уникальный 32-bit ID стратегии. Все позиции/ордера, выставленные ботом, помечены этим magic — это критерий фильтрации при scan/close/trail.
- **Где используется:** Прокидывается через `EngineDeps.magic` во все под-движки (scalping, conservative_grid, profit_trailing, protection). MT5-фильтры: `positions_get(magic=...)`, `orders_get(magic=...)`.
- **UI:** read-only, отображается отдельной строкой `Magic: {N}` (Step3Editor.tsx:387-393). Закреплён при создании стратегии — менять нельзя, иначе SQLite-state будет привязан к старому magic.

### 4. `max_loss` — глобальный максимальный убыток (USD)

- **Тип / default:** `float` / `-500.0`
- **Валидация:** `< 0` (config.py:44-49, `_max_loss_negative`). Это убыток, значение должно быть отрицательным.
- **Назначение:** Когда суммарный floating+realized P&L всех каналов опустится до или ниже `max_loss`, `protection.check_max_loss` (engine.py: блок 4 on_tick) закрывает оба канала через `close_channel`, удаляет pending и сетит `max_loss_hit` — guard в начале on_tick после этого блокирует весь дальнейший торг.
- **Где используется:** `bot/core/protection.py:check_max_loss`. См. [[auragrid-trading-core]] раздел «Engine.on_tick порядок».
- **UI:** `Step3Editor.tsx:45-50`, max=-0.01. Описание: «Отрицательное число. При достижении — бот останавливает всю торговлю.»

---

## Секция: `scalping` (19 полей)

Все поля **обязательные** (без defaults в pydantic-модели). Пустой пресет валидацию не пройдёт.

### Геометрия сетки

#### 5. `first_step` — дистанция первого pending от цены (pts)

- **Тип:** `int`
- **Валидация:** UI `min=0`. На уровне модели — нет.
- **Назначение:** Первый BUY_STOP/SELL_STOP выставляется на `ask + first_step*point` (BUY) или `bid - first_step*point` (SELL). Если меньше брокерского `stops_level` — `adjust_to_stops_level` подтянет к минимально допустимой дистанции.
- **Где:** `bot/core/scalping.py:place_first_pending` (расчёт цены), `_make_pending_refresher` (рефреш цены при retry).
- **UI:** `Step3Editor.tsx:54`.

#### 6. `price_distance` — базовый шаг сетки (pts)

- **Тип:** `int`
- **Валидация:** UI `min=0`.
- **Назначение:** Базовый шаг скальпинг-сетки. Формула шага на уровне N: `step(N) = max(price_distance × step_multiplier^(N-1), min_grid_step)`.
- **Где:** `scalping.py:calculate_grid_step`, `risk.py:calculate_grid_step_scalp` (таблица рисков).
- **UI:** `Step3Editor.tsx:55`.

#### 7. `step_multiplier` — множитель расширения шага

- **Тип / валидация:** `float`, `>= 1.0` (config.py:91-96, `_step_mult_ge_one`). UI `min=1.0, step=0.1`.
- **Назначение:** Экспонента в формуле шага. `1.0` = статическая сетка с шагом `price_distance`; `>1.0` = расширяющаяся.
- **Где:** `scalping.py:calculate_grid_step`. См. [[auragrid-trading-core]] для CG-варианта.
- **UI:** `Step3Editor.tsx:56`.

#### 8. `min_grid_step` — минимальный шаг (pts, нижняя граница)

- **Тип:** `int`. UI `min=0`.
- **Назначение:** Защищает шаг сетки от схлопывания при больших экспонентах: финальный шаг = `max(price_distance × step_multiplier^(N-1), min_grid_step)`.
- **Где:** `scalping.py:calculate_grid_step` (только если `min_grid_step > raw`).
- **UI:** `Step3Editor.tsx:61`.

#### 9. ~~`pending_order_offset`~~ — **удалено в TZ TRAIL_REWORK v1.0** (2026-05-25)

Поле растворилось в новой семантике `trail_size` (overshoot-буфер). Триггер первого выставления pending теперь: `|цена − last_open| ≥ current_step + trail_size`. См. [[adr-002-trail-rework-mq5-parity-departure]].

#### 10. `spread_buffer` — буфер спреда (pts)

- **Тип:** `int`. UI `min=0`.
- **Назначение:** Двойная роль:
  1. В `check_spread_normal` — при волатильном расширении спреда бот не выставляет ордера.
  2. Влияет на эффективную дистанцию: `effective = max(trail_size + spread_buffer, stops_level)`.
- **Где:** `scalping.py:93, 208, 330-333, 571-573, 640-646`; CG тоже использует scalping.spread_buffer (`conservative_grid.py:195`).
- **UI:** `Step3Editor.tsx:60`.

### Лимиты канала

#### 11. `max_scalp_orders` — максимум позиций в скальпинг-режиме

- **Тип:** `int`. UI `min=1`.
- **Назначение:** При достижении `grid_count == max_scalp_orders` канал переходит в режим CG (`engine.process_channel` блок SCALP→CG transition, см. [[auragrid-trading-core]]).
- **Где:** `engine.process_channel` (блок 4), `conservative_grid.py:transition_from_scalp`.
- **UI:** `Step3Editor.tsx:58`.

#### 12. `max_scalp_loss` — максимальный убыток скальпинга (USD)

- **Тип:** `float`. Нет валидации значения (может быть любое).
- **Назначение:** Альтернативный триггер перехода SCALP→CG. Если `floating_pl канала <= max_scalp_loss` — переход в CG раньше, чем достигнут `max_scalp_orders`. Защита от убыточной сетки.
- **Где:** `engine.process_channel` (блок 4 transition).
- **UI:** `Step3Editor.tsx:59`. (Может быть отрицательным; ограничений в UI нет — должно быть < 0 для срабатывания, иначе условие всегда False.)

### Лоты и мартингейл

#### 13. `lot_size` — базовый лот первой позиции

- **Тип:** `float`. UI `min=0.01, step=0.01`.
- **Назначение:** Размер первой позиции. Семантика зависит от `lot_type`:
  - `fixed` → ровно `lot_size` (нормализованный под `volume_step`).
  - `dynamic` → процент от свободной маржи: `lot = free_margin × (lot_size / 100) / margin_per_lot`.
- **Где:** `scalping.py:calculate_first_lot` (135-189). Fallback для `calculate_next_lot` если `state.last_lot_raw <= 0`.
- **UI:** `Step3Editor.tsx:62`.

#### 14. `lot_type` — режим расчёта лота

- **Тип:** `Literal["fixed", "dynamic"]` (config.py:66).
- **Назначение:** См. `lot_size`. `dynamic` требует доступа к `account_info()` (free_margin, margin_per_lot) — в режиме fake-MT5 для тестов есть mock.
- **Где:** `scalping.py:calculate_first_lot` switch.
- **UI:** `Step3Editor.tsx:63`. Select из двух опций.

#### 15. `martingale_coeff` — множитель мартингейла

- **Тип / валидация:** `float`, `>= 1.0` (config.py:84-89, `_mart_ge_one`).
- **Назначение:** Формула роста лота: `lot_next_raw = (last_raw + increase_lot_size) × martingale_coeff`. `1.0` = классический grid без мартингейла; `>1.0` = пирамида.
- **Где:** `scalping.py:calculate_next_lot` (~507). См. инвариант #6 в [[auragrid-trading-core]] про snapshot/restore `last_lot_raw`.
- **UI:** `Step3Editor.tsx:64`, min=1.0, step=0.1.

#### 16. `increase_lot_size` — аддитивная прибавка к мартингейлу

- **Тип:** `float`. UI `min=0, step=0.01`.
- **Назначение:** Аддитивный компонент в формуле перед множителем. Может быть `0` — тогда чистый мартингейл.
- **Где:** `scalping.py:calculate_next_lot`.
- **UI:** `Step3Editor.tsx:65`.

#### 17. `max_lot_size` — верхняя граница лота

- **Тип / валидация:** `float`, `> 0` (config.py:77-82, `_max_lot_positive`). UI `min=0.01, step=0.01`.
- **Назначение:** Кламп мартингейла: `lot_next_raw = min(lot_next_raw, max_lot_size)`. Критичен для управления капиталом — без этого пирамида растёт без границ.
- **Где:** `scalping.py:calculate_next_lot` (~512-514). Также применяется в `risk.py` при расчёте таблицы рисков.
- **UI:** `Step3Editor.tsx:66`.

### Трейлинг pending-ордеров (TZ TRAIL_REWORK v1.0)

#### 18. `trail_update_distance` — частота обновления pending (pts)

- **Тип:** `int`. UI `min=1`. **Валидация: `> 0`** (защита от спама `TRADE_ACTION_MODIFY`).
- **Назначение:** Дополнительный ход цены сверх удалённости (`trail_size`), после которого pending переставляется. Порог пересчёта = `trail_size + trail_update_distance`.
- **Где:** `scalping.py:trail_pending_order` (формула `threshold = trail_size + trail_update`).
- **UI:** «Частота обновления (pts)» — `Step3Editor.tsx`.

#### 19. `trail_size` — удалённость pending от цены (pts)

- **Тип:** `int`. UI `min=0`.
- **Назначение:** Двойная роль (TZ TRAIL_REWORK v1.0 §2.2-2.3):
  1. **Overshoot-буфер триггера первого выставления** (заменил старый `pending_order_offset`): триггер добора `|цена − last_open| ≥ current_step + trail_size`; pending встаёт ровно на `current_step` пт от `last_open_price` — точная геометрия сетки.
  2. **Удалённость pending от цены при трейлинге**: pending держится на `max(trail_size + spread_buffer, broker stops_level)` от цены.
- **Где:** `scalping.py:should_place_grid_order`, `place_grid_order`, `trail_pending_order`. Также `profit_trailing.py:arm_manual` (косвенно).
- **UI:** «Удалённость ордера (pts)» — `Step3Editor.tsx`.

### Трейлинг прибыли (SL)

#### 20. `profit_fixing_direction` — активация трейлинга при фиксированной прибыли (USD)

- **Тип:** `float`. Связь: см. инвариант ниже.
- **Назначение:** Когда `floating_pl канала >= profit_fixing_direction` — активируется трейлинг SL. Не закрывает позиции мгновенно; закрытие случится когда цена откатится и заденет SL.
- **Где:** `profit_trailing.py:is_target_reached` (условие 1, 131-135), `_mode_params` выбирает по режиму SCALP/CG.
- **UI:** `Step3Editor.tsx:70-75`. Label: «Trail activation @ profit (USD)». Описание: «Активирует трейлинг SL по достижении этой прибыли (USD). Не закрывает позиции мгновенно — фиксация произойдёт когда цена откатится и заденет SL. 0 = отключено.»

#### 21. `auto_calculated_profit` — активация трейлинга, масштабируемая по объёму (USD на 0.01 лот)

- **Тип:** `float`.
- **Назначение:** Альтернатива `profit_fixing_direction`. Условие: `floating_pl >= auto_calculated_profit × (total_lot / 0.01)`. Например, при 0.05 лота нужно `value × 5` USD прибыли.
- **Где:** `profit_trailing.py:is_target_reached` (условие 2, 138-143).
- **UI:** `Step3Editor.tsx:77-82`. Описание: «Альтернатива: активация трейлинга при прибыли = value × (total_lot / 0.01) USD. Масштабируется по объёму. 0 = отключено.»

#### 22. `trail_update_distance_profit` — частота обновления SL (pts)

- **Тип:** `int`. UI `min=1`. **Валидация: `> 0`** (защита от спама SL modify).
- **Назначение:** Аналог `trail_update_distance` для SL. Порог подтяжки SL = `trail_size_profit + trail_update_distance_profit`. SL двигается только в сторону прибыли (инвариант #4).
- **Где:** `profit_trailing.py:manage` (Б-ветка).
- **UI:** «Частота обновления SL (pts)» — `Step3Editor.tsx`.

#### 23. `trail_size_profit` — удалённость SL от цены при трейлинге (pts)

- **Тип:** `int`. UI `min=0`.
- **Назначение:** При активации трейлинга и при каждой подтяжке: `new_sl = bid ± adjusted(trail_size_profit) × point`. Adjusted = `max(trail_size_profit, broker stops_level)`.
- **Где:** `profit_trailing.py:manage` (А-ветка активации + Б-ветка подтяжки). `arm_manual` (ручной арм SL при close_channel/close_all через UI) использует ту же формулу — см. [[auragrid-trading-core]] раздел «ProfitTrailer.arm_manual / Protection.arm_channel_trail».
- **UI:** «Удалённость SL (pts)» — `Step3Editor.tsx`.

### Инварианты ScalpingConfig (model_validator, config.py)

1. **`trail_update_distance > 0`** (field-валидатор) — защита от спама `TRADE_ACTION_MODIFY` на pending. Заменил старый абсолютный инвариант после TZ TRAIL_REWORK v1.0.
2. **`trail_update_distance_profit > 0`** (field-валидатор) — то же для SL-трейлинга.
3. **Хотя бы одно из `profit_fixing_direction` / `auto_calculated_profit` != 0.** Иначе позиции скальпинг-канала никогда не зафиксируют прибыль трейлингом и доедут только до `max_scalp_loss` / общего `max_loss` → переход в CG или close.

> **Снят 2026-05-25:** старый инвариант `trail_update_distance_profit > trail_size_profit` — в новой формуле порог пересчёта = `trail_size + trail_update`, строгое неравенство не нужно. См. [[adr-002-trail-rework-mq5-parity-departure]].

UI делает **клиентский pre-flight** новых инвариантов (`Step3Editor.tsx`, `invariantErrors` useMemo) — кнопка сохранить дизейблится с человекочитаемой ошибкой. Это сделано чтобы не ждать 60 сек READY_TIMEOUT при `strategy_apply_params`.

---

## Секция: `conservative_grid` (CG, 13 полей)

CG активируется после SCALP→CG transition (`max_scalp_orders` достигнуто **или** `max_scalp_loss` пробит). Структурно поля повторяют scalping, но **без** `lot_size`/`lot_type`/`max_lot_size`/`first_step`/`max_*` лимитов — лот наследуется из мартингейла, базовый лот = `state.last_lot_raw` после последней SCALP-позиции.

Все поля **обязательные** (без defaults).

### Геометрия CG-сетки

#### 24. `cg.price_distance` — базовый шаг CG (pts)

- **Тип:** `int`. UI `min=0`.
- **Назначение:** Базовый шаг для CG; формула шага: до `step_multiplier_start_order` шаг = `price_distance`, дальше `price_distance × step_multiplier^(cg_num - start)`.
- **Где:** `conservative_grid.py:calculate_step` (~105-112), `risk.py` (таблица рисков для CG-фазы).
- **UI:** `Step3Editor.tsx:94`.

#### 25. `cg.step_multiplier` — множитель шага CG

- **Тип / валидация:** `float`, `>= 1.0` (config.py:141-146, ошибка с префиксом «cg.»).
- **Назначение:** Аналог scalping.step_multiplier, но действует только начиная с позиции `step_multiplier_start_order`.
- **UI:** `Step3Editor.tsx:95`.

#### 26. `cg.step_multiplier_start_order` — номер CG-позиции для старта расширения

- **Тип:** `int`. UI `min=1`.
- **Назначение:** До этой позиции — фиксированный шаг `price_distance`; начиная с неё — `price_distance × step_multiplier^(cg_num - start)`. Позволяет «плоский старт» CG-сетки.
- **Где:** `conservative_grid.py:calculate_step`.
- **UI:** `Step3Editor.tsx:97-101`.

#### 27. ~~`cg.pending_order_offset`~~ — **удалено в TZ TRAIL_REWORK v1.0** (2026-05-25)

Аналогично scalping — растворилось в `cg.trail_size`. Триггер CG-добора: `|цена − last_open| ≥ current_step + cg.trail_size`. См. [[adr-002-trail-rework-mq5-parity-departure]].

### Лимиты CG

#### 28. `cg.max_orders` — максимум CG-позиций

- **Тип:** `int`. UI `min=1`.
- **Назначение:** Когда `cg_count` (позиции в CG-фазе, т.е. `grid_count - scalp_positions`) достигает `max_orders` — новые CG-доборы не выставляются. Канал ждёт закрытия по профит-трейлингу или общему `max_loss`.
- **Где:** `conservative_grid.py:process` (~575-576).
- **UI:** `Step3Editor.tsx:103`.

### Трейлинг CG-pending

#### 29. `cg.trail_update_distance` — частота обновления CG-pending (pts)

- **Тип:** `int`. UI `min=1`. **Валидация: `> 0`.** Аналог scalping (TZ TRAIL_REWORK v1.0).
- **Назначение:** Порог пересчёта = `cg.trail_size + cg.trail_update_distance`.
- **Где:** `conservative_grid.py:_trail_pending`.
- **UI:** «CG частота обновления (pts)».

#### 30. `cg.trail_size` — удалённость CG-pending от цены (pts)

- **Тип:** `int`. UI `min=0`.
- **Назначение:** Аналог scalping.trail_size (TZ TRAIL_REWORK v1.0):
  1. Overshoot-буфер триггера CG-добора: `threshold = current_step + cg.trail_size`.
  2. Удалённость pending от цены: `effective = max(cg.trail_size + scalping.spread_buffer, stops_level)`.
- **Важно:** CG берёт `spread_buffer` из секции `scalping`, своего поля нет.
- **Где:** `conservative_grid.py:_trail_pending`, `should_place_order`, `place_order`.
- **UI:** «CG удалённость ордера (pts)».

### Мартингейл CG

#### 31. `cg.martingale_coeff` — множитель мартингейла в CG

- **Тип / валидация:** `float`, `>= 1.0` (config.py:134-139).
- **Назначение:** Аналог scalping.martingale_coeff. Формула: `lot_next_raw = (last_raw + cg.increase_lot_size) × cg.martingale_coeff`. Кламп `max_lot_size` берётся из секции **scalping** (нет отдельного `cg.max_lot_size`).
- **Где:** `conservative_grid.py:calculate_next_lot` (~138).
- **UI:** `Step3Editor.tsx:106`.

#### 32. `cg.increase_lot_size` — аддитивная прибавка в CG

- **Тип:** `float`. UI `min=0, step=0.01`.
- **Где:** `conservative_grid.py:calculate_next_lot`.
- **UI:** `Step3Editor.tsx:107`.

### Трейлинг прибыли CG

#### 33. `cg.profit_fixing_direction` — активация SL-трейла в CG (USD)

- **Тип:** `float`. Связь: см. инвариант.
- **Назначение:** Аналог scalping.profit_fixing_direction для CG-фазы. `ProfitTrailer._mode_params` выбирает значение по `Mode.CG`.
- **UI:** `Step3Editor.tsx:109-114`.

#### 34. `cg.auto_calculated_profit` — масштабируемая активация (USD на 0.01 лот)

- **Тип:** `float`. Связь: см. инвариант.
- **UI:** `Step3Editor.tsx:116-121`.

#### 35. `cg.trail_update_distance_profit` — частота обновления CG SL (pts)

- **Тип:** `int`. UI `min=1`. **Валидация: `> 0`.**
- **Назначение:** Порог подтяжки SL в CG = `cg.trail_size_profit + cg.trail_update_distance_profit`.
- **UI:** «CG частота обновления SL (pts)».

#### 36. `cg.trail_size_profit` — удалённость SL от цены в CG (pts)

- **Тип:** `int`. UI `min=0`.
- **UI:** «CG удалённость SL (pts)».

### Инварианты ConservativeGridConfig (config.py)

1. **`cg.trail_update_distance > 0`** (field-валидатор) — защита от спама modify.
2. **`cg.trail_update_distance_profit > 0`** (field-валидатор) — то же для SL.
3. **Хотя бы одно из `cg.profit_fixing_direction` / `cg.auto_calculated_profit` != 0.**

> **Снят 2026-05-25:** старый инвариант `cg.trail_update_distance_profit > cg.trail_size_profit` — см. [[adr-002-trail-rework-mq5-parity-departure]].

UI делает тот же клиентский pre-flight для CG (`Step3Editor.tsx`, `check("conservative_grid", ...)`).

---

## Секция: `notifications`

### 37. `notifications.telegram_chat_id`

- **Тип / default:** `str` / `""` (пустая строка).
- **Назначение:** ID Telegram-чата для уведомлений. **В текущей волне инфраструктура нерабочая** — поле принимается схемой, но прямой Telegram-интеграции в `bot/` нет (телеметрия идёт через `LicenseClient` heartbeat).
- **UI:** `Step3Editor.tsx:134-138`. Описание: «Опционально. Для уведомлений через бота в Telegram.»

---

## Секция: `mt5` (торговое — `symbol`; секреты — `login/password/server`)

### 38. `mt5.symbol` — торгуемый инструмент

- **Тип / default:** `str | None` / `None`.
- **Fallback:** При None бот берёт env `GRIDSCALP_SYMBOL`, иначе hardcoded `XAUUSD` (`main.py:91`).
- **Назначение:** Точное имя инструмента у брокера (`XAUUSD`, `XAUUSD.s`, `GOLD`, etc). Все pending/позиции открываются на нём.
- **Где используется:** `engine.py:49 EngineDeps.symbol`, `engine.py:132 PositionScanner`, `scalping.py:59` (получение тика), `profit_trailing.py:107-108`, `protection.py:52`.
- **UI:** `Step3Editor.tsx:395-407`, отдельная карточка вне аккордеона.
  - **Редактируется только при остановленном боте.** SQLite-state привязан к текущему символу (`state.last_open_price`, grid_count) — смена символа на живом боте сломает state. Условие в UI: `symbolEditable = !runningRestart`.

### 39-41. `mt5.login` / `mt5.password` / `mt5.server` — кредентшалы

- **Тип:** `int | None` / `str | None` / `str | None`. Defaults — все `None`.
- **Валидация:** `_creds_all_or_none` (config.py:196-205) — все три либо заданы вместе, либо все три None.
- **Назначение:** При заданных всех трёх — бот вызывает `mt5.initialize(login=, password=, server=)` и сам логинится. Иначе — `mt5.initialize()` цепляется к уже открытому терминалу (legacy dev-режим).
- **В UI:** не редактируются. Из соображений безопасности секреты в пресет-файлы (export/import preset) не уходят: в `load_preset_file` они наследуются из `base_config` (config.py:292-326, см. также Rust `strategies::export_preset` который выкидывает эти поля при экспорте, см. [[auragrid-trading-core]] раздел «Раунд 3 — Save/Load пресет»).
- **Источник секрета:** хранится только в основном yaml `<APPDATA>/GridScalp/config.yaml`, не в файлах пресетов под `<APPDATA>/GridScalp/strategies/<magic>.yaml`.

---

## Служебные поля (не торговые, но в схеме BotConfig)

| Поле | Тип / default | Где |
|------|---------------|-----|
| `config_version` | `int = 1` | для миграций схемы |
| `license_key` | `str` (required) | `LicenseClient` |
| `bot_version` | `str = "0.1.0"` | телеметрия |
| `preset_name` | `str = "default"` | идентификация в логах |
| `log_level` | `Literal[DEBUG/INFO/WARNING/ERROR/CRITICAL] = "INFO"` | `configure_logging` |
| `ipc.port` | `int [1..65535] = 8765` | `bot/ipc/server.py` |
| `ipc.enabled` | `bool = True` | IPC-сервер для Tauri |
| `licensing.server_url` | `str = ""` | `LicenseClient` |
| `log_shipping.enabled` | `bool = False` | модуль `bot.log_shipper` (по умолчанию off) |
| `log_shipping.interval_sec` | `int [1..3600] = 10` | частота flush батча |
| `log_shipping.batch_max_lines` | `int [10..10000] = 1000` | размер батча |
| `log_shipping.request_timeout_sec` | `int [1..120] = 15` | HTTP timeout |
| `log_shipping.max_backoff_sec` | `float [1..3600] = 300.0` | retry backoff |

При экспорте пресета через Rust `strategies::export_preset` все эти поля **исключаются** — пресет содержит только торговые секции. См. [[auragrid-trading-core]] раздел «Раунд 3».

---

## Сводка валидаций (один взгляд)

| Уровень | Правило | Источник |
|---------|---------|----------|
| GeneralConfig.magic_number | `> 0` | field-validator |
| GeneralConfig.max_loss | `< 0` | field-validator |
| ScalpingConfig.max_lot_size | `> 0` | field-validator |
| ScalpingConfig.martingale_coeff | `>= 1.0` | field-validator |
| ScalpingConfig.step_multiplier | `>= 1.0` | field-validator |
| ScalpingConfig.trail_update_distance | `> 0` (TZ TRAIL_REWORK v1.0) | field-validator |
| ScalpingConfig.trail_update_distance_profit | `> 0` (TZ TRAIL_REWORK v1.0) | field-validator |
| ScalpingConfig (model) | `profit_fixing_direction != 0 OR auto_calculated_profit != 0` | model-validator |
| ConservativeGridConfig.martingale_coeff | `>= 1.0` | field-validator |
| ConservativeGridConfig.step_multiplier | `>= 1.0` | field-validator |
| ConservativeGridConfig.trail_update_distance | `> 0` (TZ TRAIL_REWORK v1.0) | field-validator |
| ConservativeGridConfig.trail_update_distance_profit | `> 0` (TZ TRAIL_REWORK v1.0) | field-validator |
| ConservativeGridConfig (model) | `profit_fixing_direction != 0 OR auto_calculated_profit != 0` | model-validator |
| MT5Config (model) | `login/password/server` — all or none | model-validator |
| BotConfig (model) | `allow_buy OR allow_sell` | model-validator |
| BotConfig.config_version | `== 2` (TZ TRAIL_REWORK v1.0) | `_assert_compatible_version` |

**Не валидируется** (потенциальные дыры, кандидаты на оптимизацию):
- Все pts-поля (first_step, trail_size, etc.) — отрицательные значения не отлавливаются на уровне модели (только UI `min=0`); pydantic-схема пропустит yaml с `trail_size: -100`.
- `lot_size` — отрицательный пропустится; защита только UI (`min=0.01`).
- `profit_fixing_direction` / `auto_calculated_profit` — могут быть отрицательными, валидация только на `!= 0`. Отрицательное `profit_fixing_direction` сделает условие `floating_pl >= profit_fixing_direction` всегда истинным → трейлинг активируется на любом тике. Это потенциальный bug.
- `max_scalp_loss` — может быть положительным, тогда условие `floating_pl <= max_scalp_loss` ловится всегда → бессмысленный переход в CG.

---

## Поведение редактирования (UI ↔ apply_params)

Контекст: после редактирования в Step3Editor пользователь жмёт «Сохранить» или «Применить (перезапуск)».

- **Бот остановлен:** `strategies_write_params` — Rust пишет yaml. Никаких side-effects.
- **Бот запущен (`runningRestart=true`):** `strategy_apply_params` (Tauri command) — пишет yaml, выполняет graceful shutdown (`stop_bot`), spawn нового бота с обновлённым yaml. SQLite-state сохраняется (привязан к magic + symbol). Пауза в управлении ≈3-5 секунд. UI должен ждать события `bot://connection connected=true` или timeout.
- **Смена `mt5.symbol`:** запрещена при запущенном боте (`symbolEditable = !runningRestart`). Причина: SQLite-state хранит `last_open_price`, `grid_count` от старого символа — смена сломает инварианты.
- **Смена `magic_number`:** запрещена в UI (read-only field).

## Анти-паттерны

1. **Не предполагать что pydantic поймает любое некорректное значение.** Pts/USD поля без явной валидации могут быть отрицательными (см. «потенциальные дыры» выше). UI спасает в большинстве случаев, но прямой edit yaml через файловую систему обходит UI.
2. **Не редактировать `magic_number` в файле пресета.** SQLite-state, файл стратегии и UI-store знают конкретный magic — смена ломает ссылки.
3. **Не выставлять `trail_update_distance == 0` или `trail_update_distance_profit == 0`.** TZ TRAIL_REWORK v1.0: порог пересчёта = `trail_size + trail_update`. При `trail_update == 0` любое движение цены > `trail_size` триггерит modify — `TRADE_ACTION_MODIFY` на каждом тике + race с брокером. Защищено field-валидатором + UI pre-flight.
4. **Не отключать оба способа фиксации прибыли.** Если `profit_fixing_direction == 0 AND auto_calculated_profit == 0` — позиции скальпинга никогда не зафиксируют профит, доедут только до `max_scalp_loss` → CG, дальше до `max_loss` → close.
5. **Не путать `max_loss` (всего бота) и `max_scalp_loss` (только скальпинг-канала).** Первый — терминальное выключение; второй — переход режима.
6. **Не считать что `cg.spread_buffer` существует.** Его нет в схеме — CG берёт `scalping.spread_buffer`. При независимой настройке CG-канала это может удивить.
7. **Не редактировать секреты `mt5.login/password/server` через файл пресета.** Они туда не пишутся (выкидываются при `export_preset`); реальный источник — основной `config.yaml`.

## Связано с

- [[auragrid]] — MOC проекта
- [[auragrid-trading-core]] — детали торгового ядра, инварианты `last_lot_raw`, `arm_manual`, и пр.
- [[auragrid-incidents-log]] — инциденты, в которых правились конкретные настройки
- [[adr-001-surgical-minimal-vault-updates]] — структура страницы выдержана в Surgical-режиме (без спекулятивных секций)

## Источник

- `python/bot/models/config.py` (полная схема pydantic-моделей, валидаторы и инварианты)
- `desktop/src/pages/Wizard/Step3Editor.tsx` (UI labels, описания, клиентский pre-flight)
- `python/bot/core/{engine,scalping,conservative_grid,profit_trailing,protection,risk}.py` (использование параметров в торговом коде)
- Сессия 2026-05-24 — инвентаризация перед задачей «оптимизация и отладка настроек торговли»
