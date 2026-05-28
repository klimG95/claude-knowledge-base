---
type: adr
tags: [auragrid, adr, impulse, adaptive, breaking-change]
status: accepted
date: 2026-05-28
component: bot.core.impulse + bot.models.config
deciders: продакт-владелец + разработчик (Claude)
config_version: "2 → 3"
created: 2026-05-28
updated: 2026-05-28
---

# ADR-004 — Adaptive distance для AuraImpulse (M1-based)

**Статус:** accepted, реализовано в той же сессии 2026-05-28 (третья часть). 1302 pytest passed (+15 над baseline 1287), cargo check Finished, npm build OK.

## Контекст

AuraImpulse v1.0 (TZ §4.1, концепция [[auragrid-impulse-strategy]]) использовал статичную дистанцию pending'а — поле `impulse.first_step: int` (pts). Тестировщик подкручивал её под характер рынка вручную через Step3EditorImpulse: при «волатильном» XAUUSD имело смысл ставить большой `first_step` (например, 500-700 pts) чтобы ловить только резкие движения; при «спокойном» — маленький (100-200 pts) чтобы вообще иметь срабатывания.

Проблема — рынок меняется быстрее, чем пользователь подстраивает параметры. После релиза 2026-05-28 (первого с AuraImpulse в продовой MSI) пользователь сформулировал запрос:

> «Появляется 2 настройки — количество свечей и коэффициент дистанции. Логика: софт берёт размеры M1-свеч (от фитиля до фитиля), считает среднее за N свечей, умножает на коэффициент, использует это как дистанцию pending'а. Пересчёт после закрытия каждой новой свечи. Также: после успешно закрытой сделки — минимум N минут паузы. Приоритет — скорость, она не должна страдать.»

Это шаг в open question, который уже был зафиксирован в концепции AuraImpulse: «Фильтр скорости импульса. Сейчас «импульс» = «цена дотянулась до далёкого pending». Если live-торговля покажет много псевдо-импульсов — добавить опциональный параметр» — только не velocity, а волатильность (high-low за окно).

## Решение

`impulse.first_step` удалён. Введены два новых поля в `ImpulseConfig`:

- `candle_count: int (≥1)` — окно M1-свечей для расчёта.
- `distance_coefficient: float (>0)` — множитель.

Дистанция вычисляется в engine как:
```
dist_price = avg(high - low for last N closed M1 bars) * distance_coefficient
dist_pts = round(dist_price / point)
```

Пересчёт триггерится только при закрытии новой M1-свечи (сравнение `last_bar_time` от `copy_rates_from_pos(start_pos=1, count=N)`). На горячем пути проверка дешёвая, реальный пересчёт — ~раз в минуту.

**Warmup-гейт.** Если истории < `candle_count` свечей (первый старт / длинный выходной / переподключение терминала) — pending'и не выставляются, уже стоящие снимаются. UI показывает «прогрев — копим свечи».

**Cooldown floor.** `effective_cooldown = max(cooldown_sec, candle_count * 60)`. Между закрытием сделки и следующим расчётом должны успеть накопиться **свежие** свечи, не унаследованные от движения, которое только что завершилось стопом. Пользовательский `cooldown_sec` уважается, если он больше пола.

**Snapshot.** Поля `current_first_step_pts: int`, `warmup: bool`, `candle_count: int`, `distance_coefficient: float` — для UI-визуализации текущей дистанции.

**Config version bump:** 2 → 3 (общий для AuraGrid и AuraImpulse). Старые AuraImpulse-пресеты с `first_step` отвергаются с понятным сообщением. AuraGrid-схема не менялась, но bump необходим, чтобы UI/wizard'ы старых версий не пытались загрузить новый yaml.

## Альтернативы, которые рассмотрел и отверг

### 1. ATR вместо простого high-low

Классический ATR = `max(H-L, |H-prev_close|, |L-prev_close|)` — учитывает gap между свечами. Для XAUUSD M1 внутри торговой сессии gap'ы редки (брокеры дают непрерывный поток котировок), но возможны на открытии после выходных. Решение: пользователь явно сказал «от фитиля до фитиля» — это `H-L`, без gap-учёта. Это проще, интуитивнее, и для целевого инструмента (XAUUSD M1) — достаточно точно. ATR можно ввести в v2 как опциональный режим, если live-торговля покажет проблемы с gap-волатильностью.

### 2. Тиковая дистанция / volume-based

Например, считать дистанцию по `tick_volume` за последние N секунд. Отверг — пользователь сформулировал чётко через «размеры свеч», и tick_volume на разных брокерах считается по-разному (Doo даёт filtered ticks, MetaQuotes — все).

### 3. Использовать analytics модуль

В проекте уже есть `bot/analytics/` со свечным буфером и fetcher'ом. Можно было бы переиспользовать. Отверг — analytics это отдельный python-процесс, торговое ядро (`bot/core/`) не должно зависеть от его lifecycle. Лёгкий собственный fetcher через `MT5Client.copy_rates_from_pos` — несколько строк, минимальная связанность.

### 4. Не делать cooldown floor

Просто пересчитать дистанцию на каждом тике после close. Отверг — на конце движения, которое стопнуло позицию, последние M1-свечи будут с большим range (волатильность пика). Если бы мы немедленно ставили pending по этой дистанции, мы бы ловили ретест на ещё больших расстояниях, чем стоило бы. Пользовательский запрос «после закрытия — пауза на время обновления дистанции» явно зафиксирован.

### 5. Сохранять `_dynamic_first_step_pts` в SQLite

Можно было бы персистить кэш для мгновенной готовности после рестарта. Отверг — на первом тике после рестарта мы всё равно сразу вызываем `copy_rates`, и история (если она доступна) даёт актуальное значение. Persist добавил бы риск stale data (свечи могли измениться между шатдауном и рестартом). Кэш в памяти проще и safer.

## Последствия

### Положительные

- Стратегия автоматически адаптируется к смене волатильности — пользователь больше не подкручивает `first_step` руками.
- Cooldown floor защищает от ловли «эха» только что закрытого движения.
- UI прозрачно показывает текущее значение дистанции — пользователь видит, на чём стоят ордера, без логов.
- Скорость не страдает: один `copy_rates` в минуту вместо на каждый тик — внутренний кэш по `bar_time`.

### Отрицательные

- Поведение «pending на 200pt от цены» больше не воспроизводимо буквально — дистанция плавающая. Для пользователя, который хочет фиксированную — поставить `distance_coefficient` так, чтобы при текущем avg high-low получалось нужное значение, и держать рынок в окне.
- Breaking change для существующих AuraImpulse-пресетов (yaml с `first_step` отвергнется). Окно использования AuraImpulse — короткое (релиз 2026-05-28, та же сессия), поэтому пользовательских пресетов «в обороте» немного; смягчается понятным сообщением + UI Step3EditorImpulse предлагает новые поля.
- Cooldown floor может удивить пользователя, если он установил `candle_count=30` (получит 30-минутную минимальную паузу). Описание в UI это явно проговаривает.

### Что не меняется

- State machine (WATCHING → TRADING → COOLDOWN → WATCHING), 9 полей секции `impulse` сохраняются (минус `first_step`, плюс `candle_count` + `distance_coefficient` = +1 поле, итого 10).
- Формула трейлинга (`trail_size_profit` + `trail_update_distance_profit`).
- Двойная отправка SL (pre-fill в pending request + SLTP после fill).
- Persistence schema (`ImpulseState` не менялся — кэш дистанции в памяти).
- `min_account_balance` guard.

## Verify (закрытие критериев)

- ✅ Pydantic-схема обновлена: `first_step` удалён, `candle_count` + `distance_coefficient` с валидаторами.
- ✅ `config_version` bumped: 2 → 3 во всех yaml templates / fixtures / presets / Rust override.
- ✅ Engine: `_refresh_dynamic_distance` + `_enter_warmup`, `_arm_cooldown` с floor, `_manage_pendings` с warmup-gate, `_place_pending` / `_modify_pending` / `_make_pending_refresher` берут дистанцию из кэша.
- ✅ MT5 protocol + Fake: `TIMEFRAME_M1` константа, `copy_rates_from_pos` в Protocol и FakeMT5Client (+ `set_rates`/`append_rate` helpers).
- ✅ Snapshot: `current_first_step_pts`, `warmup`, `candle_count`, `distance_coefficient`.
- ✅ UI Step3EditorImpulse: два поля вместо одного, обновлены pre-flight, описание cooldown'а упоминает floor.
- ✅ StrategyPanel: плашка «Дистанция pending'а сейчас: N pts» / «прогрев — копим свечи».
- ✅ Tests: 13 новых импульсных тестов + обновление существующих fixture'ов. 1302 pytest passed (0 fail). cargo check Finished. npm run build OK.

## Связано с

- [[auragrid-impulse-strategy]] — концепция (обновлена разделом «Доработка 2026-05-28 (вторая)»)
- [[adr-003-impulse-strategy-new-preset-type]] — изначальное решение про отдельный preset-type
- [[adr-001-surgical-minimal-vault-updates]] — методология surgical правки (применяется и здесь)
- `auragrid/python/bot/core/impulse.py::_refresh_dynamic_distance` — главный метод
- `auragrid/python/bot/models/config.py::ImpulseConfig` — pydantic-модель

## Источник

- Сессия 2026-05-28 (третья за день) — запрос пользователя после установки MSI с первой реализацией AuraImpulse и доработкой cooldown UX
