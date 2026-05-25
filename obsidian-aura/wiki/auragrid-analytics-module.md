---
type: component
tags: [auragrid, analytics, second-process, ipc, unblocked, integrity-fixed]
component: bot.analytics
layer: code
shape: domain-hub
created: 2026-05-22
updated: 2026-05-26
---

# AuraGrid — Analytics module (состояние и архитектура)

> **🟢 Обновление 2026-05-26 (вечер):** P0 #1-4 и P1 #5-6 из аудита 2026-05-26 закрыты реализацией TZ_ANALYTICS_INTEGRITY_v1.0 — атомарный PR со всеми фиксами, 1278 pytest passed (+25 новых), `npm run build` OK. ATR Analytics ожидаемо ≈ ATR MT5 (Δ <2 %) после установки нового MSI; manual cross-validation см. `docs/qa/scenarios/analytics_smoke.md`. Раздел «Аудит 2026-05-26» ниже сохранён исторически — это диагностика того, что было пофикшено. UI добавлен Alert «Нет активной стратегии» для разведения by-design vs реального бага.

**TL;DR.** Analytics — отдельный python-процесс со своим MT5-инстансом и IPC-портом 8770, который должен снабжать UI 12 виджетами + DeploymentTable (расчёт риска стратегии). На версии HEAD (677811c, релиз 1.0.1) фактически работали только Spread и Sessions, остальное — null'ы. **После раундов 5 (P0 symbol) → 6 (P1 M15) → 7 (P1 Calendar + P2 logs + P2 e2e) — все три корневые причины разблокированы.** Snapshot непустой; UI рисует degraded-status badge при любом fallback (heuristic symbol / CSV calendar / no calendar / mt5 disconnected); ротация логов защищена от PermissionError; integration smoke e2e проверяет `indicators.atr_*` через WebSocket в каждом CI прогоне.

> **Однако** живой snapshot ≠ корректный snapshot. Независимый аудит 2026-05-26 (после получения первого работающего UI у пользователя) показал, что **корректность данных** требует отдельного раунда фиксов (P0 #1-4). См. ниже.

## Когда читать эту страницу

- Перед любой работой над окном Analytics или DeploymentTable
- При диагностике «прочерки в snapshot»
- При планировании unblock'а (см. секцию «Приоритеты unblock»)

## Архитектура

Analytics — **второй python-процесс** (`python -m bot.analytics.manager`), запускается Tauri-shell'ом параллельно основному боту. У него:
- Свой `mt5.initialize()` (отдельный коннект к терминалу).
- Свой IPC WebSocket на порту 8770 (бот — 8765/8766).
- Свой logger (но пишет в общий `bot.log` — это причина PermissionError ротации).
- Свой config `analytics_config.yaml` с buffer_sizes, alert thresholds, calendar settings.

### Поток данных

```
mt5.initialize() в analytics-процессе
    └─ resolve_symbol([XAUUSD, XAUUSD.s, ...]) ← ЛОМАЕТСЯ ЗДЕСЬ если ни один не подходит
       └─ symbol = <found>
          └─ _backfill(symbol):
              ├─ Timeframe.primary_tf → buffer
              ├─ Timeframe.H1 → buffer
              ├─ Timeframe.D1 → buffer
              └─ Timeframe.M15 → ❌ НЕ ВКЛЮЧЁН в tfs_to_backfill (manager.py:445)
          └─ background loops: tick (10 Hz), bar_close (1 Hz), snapshot (1 Hz)
             └─ snapshot_loop → build_snapshot():
                 ├─ refresh_calendar_if_due() — MT5 calendar API mismatch
                 ├─ refresh_indicators_if_dirty() — empty buffers → all None
                 ├─ build_position_blocks() — нужен ctx + symbol
                 ├─ refresh_levels_if_dirty() — нужны буферы
                 ├─ build_volatility/regime/sessions/spread/...
                 └─ alert_engine.evaluate(snap, calendar)
                 └─ публикация через IPC → UI useAnalyticsSubscription
```

## Компоненты (~50 файлов)

| Подмодуль | Файлы | Что делает | Статус |
|-----------|-------|-----------|--------|
| Manager | `analytics/manager.py` | Entry-point, lifecycle, backfill, loops | ✓ (M15 added 2026-05-22) |
| MT5 client | `analytics/mt5_client.py` | Свой коннект, resolve_symbol, lock() | ✓ (heuristic + dynamic candidates added 2026-05-22) |
| Fetcher | `analytics/fetcher.py` | backfill native TF + bar_close detection | ✓ |
| Buffer | `analytics/buffer.py` | Rolling buffer на TF, thread-safe | ✓ |
| Indicators | `analytics/indicators/*.py` + `indicator_pipeline.py` | ATR/ADX/Bollinger/Choppiness/Hurst/Parkinson/GK/RV + percentiles + intraday profile | ✓ (M15 block added 2026-05-22) |
| Regime | `analytics/regime.py` | Trend/range/squeeze classify + hysteresis stabilizer | ✓ (получает None) |
| Volatility | в `snapshot_builder.build_volatility_block` | Session vol ratio + intraday | ✓ (получает None) |
| Sessions | `analytics/sessions.py` | UTC-based, не зависит от MT5 | ✓ работает всегда |
| Spread | `analytics/spread.py` + `snapshot_builder.build_spread_block` | Sample + median 24h + z-score + heatmap | ✓ live tick canal работает |
| Calendar | `analytics/calendar.py` | MT5 calendar_event_by_currency + CSV fallback | ✓ (CSV fallback wired + hasattr-guard 2026-05-22) |
| Levels | `analytics/levels.py` | Pivot/Camarilla/Fib + PDH/PDL + zigzag + fractals + VP | ✓ (нет данных) |
| Position | `analytics/position.py` | avg_price/breakeven/distance_to_fill/MFE/MAE/cycles | ✓ (нет данных) |
| Alerts | `analytics/alerts.py` + alert_engine | Rules → fire → persist → publish event | ✓ (нет триггеров без данных) |
| Stress test | `analytics/stress.py` + `ipc_handlers` | Stateless симулятор для UI слайдера | ✓ |
| Trade log | `analytics/trade_log.py` + cycles | TZ §15.2-§15.5 | ✓ |
| Preset eval (DeploymentTable) | `analytics/preset_eval/*` | 23 колонки формул + 4 sensitivity-сценария | ⚠ нужны ATR — disabled |
| Storage | `analytics/storage.py` | SQLite для spread history, alerts, snapshots | ✓ |
| IPC handlers | `analytics/ipc_handlers.py` | Dispatch IPC commands → snapshot_builder | ✓ |

## Три корневые причины «не работает»

### №1 — `symbol_not_found` (CRITICAL — **FIXED 2026-05-22**)

[mt5_client.py:124](auragrid/python/bot/analytics/mt5_client.py#L124) — `resolve_symbol` пробует жёсткий список `['XAUUSD', 'XAUUSD.s', 'XAUUSD.m', 'GOLD', 'XAU/USD']`. У тестировщика 2026-05-21 ни один не подошёл. При этом основной бот успешно торговал магиком `20260002` параллельно — значит MT5 работает, но второй процесс получает другие symbols_get() (терминал MT5, ограничения per-connection, или брокер выдаёт несколько имён).

Эффект каскадный: `symbol=None` → `_backfill` skip → buffers empty → indicators all-None → regime/volatility/levels/position all null.

**Лог-сигнатура:** `[warning] symbol_not_found tried=[...]` + `[warning] backfill_skipped_no_symbol`.

**Fix (2026-05-22, journal [[2026-05-22-analytics-p0-symbol-resolution]]):** трёхэшелонная схема резолюции.
  1. **Dynamic candidates**: `AnalyticsManager._build_symbol_candidates` собирает имена из `analytics_config.yaml` + `mt5.symbol` каждого `<APPDATA>/GridScalp/strategies/*.yaml` + 11 типовых broker-suffix вариантов (`.s/.m/.pro/.c/.i/.raw/.x/x/pro/_i`).
  2. **Heuristic fallback**: при провале жёсткого списка `resolve_symbol(..., heuristic_tokens=["XAU","USD"])` перебирает `mt5.symbols_get()` и берёт первое имя, содержащее ВСЕ tokens case-insensitively. Закрывает custom-суффиксы (XAUUSDpro, xauusdmicro, etc.).
  3. **UI degraded badge**: snapshot теперь содержит `system_status: {symbol_resolved, symbol_source, symbol_tried, mt5_connected}`. Окно Analytics рисует красный Alert «символ не найден» с tried-списком и инструкцией, либо жёлтый Alert «найден через эвристику» с рекомендацией добавить имя в config.

Тесты — `tests/analytics/test_mt5_client.py::TestResolveSymbol` (6 кейсов) + `test_manager_symbol_candidates.py` (7 кейсов).

### №2 — MT5 calendar API mismatch (HIGH — **FIXED 2026-05-22**)

`mt5.calendar_event_by_currency()` отсутствует в установленной версии MetaTrader5 пакета. Try/except в [calendar.py:93-98](auragrid/python/bot/analytics/calendar.py#L93-L98) обработан корректно (нет crash), но возвращается пустой массив. В логе тестировщика 25 180 трейсбэков AttributeError за ~10 часов сессии.

В коде есть `load_csv_fallback` ([calendar.py:266-337](auragrid/python/bot/analytics/calendar.py#L266-L337)) — путь к CSV из конфига, но фактически не подключён или CSV-файл не в дистрибутиве.

**Fix (2026-05-22, journal [[2026-05-22-analytics-p1-calendar-and-finish]]):**
1. `EconomicCalendar.refresh()` сначала проверяет `hasattr(mt5, "calendar_event_by_currency")` + `hasattr(... "calendar_value_history")` — если функций нет, сразу возвращает [] (не пытается их дёргать → не плодит 25 тысяч AttributeError).
2. При empty/missing MT5 — автоматически читает `csv_fallback_path` из конфига, фильтрует по window + currencies + min_importance.
3. Manager резолвит default `bot/analytics/data/economic_calendar.csv` (положен в дистрибутив, шаблон с примерами событий ForexFactory-формата).
4. Snapshot публикует `system_status.calendar_source: "mt5"|"csv"|"none"`. UI рисует жёлтый Alert при CSV-fallback или оранжевый при `none`.

### №3 — M15 buffer не реализован (HIGH — **FIXED 2026-05-22**)

[manager.py:445](auragrid/python/bot/analytics/manager.py#L445):
```python
tfs_to_backfill = {self._primary_tf, Timeframe.H1, Timeframe.D1}  # M15 НЕ ВКЛЮЧЁН
```

Но M15 объявлен в `analytics_config.yaml` (buffer_sizes: 2880), используется в:
- [snapshot_builder.py:438](auragrid/python/bot/analytics/snapshot_builder.py#L438) — `atr_m15` для distance_to_fill в position block.
- [levels.py:820](auragrid/python/bot/analytics/levels.py#L820) — VP fallback `volume_profile_from_bars(inputs.df_m15)`.
- [indicator_pipeline.py:73](auragrid/python/bot/analytics/indicator_pipeline.py#L73) — `atr_m15` в `empty_indicators()` schema, но в `recompute_indicators` ([line 155-234](auragrid/python/bot/analytics/indicator_pipeline.py#L155-L234)) блок для M15 отсутствует (есть primary_tf, H1, D1).

UI [Analytics/index.tsx:114](auragrid/desktop/src/pages/Analytics/index.tsx#L114) собирает `deployInputs.atr_m15 = snap.indicators.atr_m15 ?? 0` — fallback на 0, deployment table работает с нулевыми ATR → catastrophic risk estimation = нули.

**Fix (2026-05-22, journal [[2026-05-22-analytics-p1-m15-buffer]]):**
1. `Timeframe.M15` добавлен в `tfs_to_backfill` (manager.py:_backfill) — buffer заполняется из MT5 при старте analytics-процесса.
2. В `recompute_indicators` после H1-блока добавлен M15-блок: `compute_atr(df, n=14)` при `len(m15_buf) >= 14`. Минимально достаточно, потому что atr_m15 — единственный потребитель из indicators schema.
3. UI кнопка «Deployment Table» становится активной автоматически — `deployInputs.atr_m15` теперь приходит ненулевым, проверка `deployInputs && atr_m15 > 0` проходит.

Тесты — `tests/analytics/test_b3_decompose.py::TestIndicatorPipeline` (3 новых кейса: warm/short/missing) + `tests/analytics/test_manager_backfill_m15.py` (1 кейс: backfill включает M15).

## Что показывается в UI и почему

Из 12 секций snapshot работают только 2:

| Секция | Статус | Почему |
|--------|--------|--------|
| `spread` | ✓ | [snapshot_builder.py:380](auragrid/python/bot/analytics/snapshot_builder.py#L380) — если `symbol is None`, sample skip, но возвращает структуру с нулями. Live spread приходит отдельным каналом через `useAnalyticsSubscription.lastTick`, не зависит от snapshot |
| `sessions` | ✓ | UTC-based, без MT5 |
| `indicators` | ✗ | empty buffers → all None |
| `regime` | ✗ | зависит от indicators |
| `volatility` | ✗ | зависит от atr_h1/m15 |
| `levels` | ✗ | без буферов |
| `position_buy/sell` | ✗ | [snapshot_builder.py:416](auragrid/python/bot/analytics/snapshot_builder.py#L416) — `if ctx is None or symbol is None: return None, None` |
| `calendar_upcoming` | ✓ после P1 Calendar | MT5 missing → CSV fallback; `calendar_source` в `system_status` |
| `alerts_active` | пусто | правила не триггерятся без данных |
| DeploymentTable (расчёт риска стратегии) | ✓ после P0+P1 | После 2026-05-22: symbol резолвится → buffers заполняются → atr_m15/h1/d1 ненулевые → кнопка активна |
| RiskMeter (главный экран) | работает независимо | из бота (`core/risk.py`), не из analytics-процесса |

## Сопутствующие проблемы

### Лог-конкуренция (**FIXED 2026-05-22**)

Analytics и бот пишут в один `%APPDATA%/GridScalp/logs/bot.log`. При попытке ротации (`doRollover`) — `PermissionError: WinError 32` (файл занят другим процессом). ~6 400 событий в логе тестировщика. Не блокирует функционал, но захламляет stderr.

**Fix (2026-05-22):** `_JSONRotatingHandler.emit` теперь ловит `PermissionError`/`OSError` от `doRollover()`, сдвигает `rolloverAt` на час вперёд и продолжает писать в текущий файл. Запись не теряется. + `log_name="analytics"` уже передавался из manager.main (раунд A.4) — два процесса физически пишут в разные файлы; защита от ротационных race остаётся для случая когда внешний tail/antivirus держит файл.

### IPC connect refused штук в логе UI

`ipc: connect failed error=IO error: No connection could be made` — это попытки UI подключиться к analytics порту 8770 ДО того как процесс поднялся. Через секунду — успешный коннект (`IPC_READY {"port": 8770}` есть в логе). Это не баг, это race в стартапе.

## Приоритеты unblock

В порядке убывания:

1. ~~**P0 — Symbol resolution.**~~ ✅ **DONE (2026-05-22, раунд 5)** — см. секцию №1 fix выше.
2. ~~**P1 — M15 buffer.**~~ ✅ **DONE (2026-05-22, раунд 6)** — см. секцию №3 fix выше.
3. ~~**P1 — Calendar fallback.**~~ ✅ **DONE (2026-05-22, раунд 7)** — `load_csv_fallback` подключён через `EconomicCalendar(csv_fallback_path=...)`, hasattr-guard на MT5 API, default CSV в дистрибутиве, `calendar_source` в snapshot+UI.
4. ~~**P2 — Сепарация лог-файлов.**~~ ✅ **DONE (2026-05-22, раунд 7 попутно)** — log_name="analytics" уже передавался (Wave A.4), `_JSONRotatingHandler.emit` защищён от PermissionError на ротации.
5. ~~**P2 — Degraded-mode UI badge.**~~ ✅ **DONE (2026-05-22, раунд 5)** — снапшот публикует `system_status`, UI рисует красный/жёлтый/оранжевый Alert (symbol_resolved, symbol_source, calendar_source).
6. ~~**P2 — Integration smoke.**~~ ✅ **DONE (2026-05-22, раунд 7)** — `tests/analytics/test_manager_smoke.py::test_manager_e2e_indicators_nonempty` (online-MT5 mock + WS get_snapshot → проверка `indicators.atr_primary/atr_m15/atr_h1 != None`).

**Все приоритеты закрыты.** Модуль готов к ручной верификации на тестовом MT5-аккаунте.

## Аудит 2026-05-26 — обнаруженные баги данных

Контекст: после раздачи MSI пользователь подтвердил «модуль аналитики впервые заработал», попросил верификацию параметров через внешние независимые источники. Ручная сверка ATR(14) Analytics vs MT5-indicator на XAUUSD.N выявила трёхуровневые расхождения (D1 +4.24%, **H1 +48.67%**, M5 +13.37%) → полный аудит кода тремя параллельными Agent-сессиями.

### P0 #1 — Stale buffers (M15/H1/D1 не обновляются)

`python/bot/analytics/manager.py:653-697` — `_bar_close_loop` polls **только `self._primary_tf` (M5)**. M15/H1/D1 буферы заполняются один раз через `_backfill()` при старте и больше **никогда не освежаются**. Чем дольше работает Analytics, тем сильнее эти данные «застаивают».

Влияет на: `atr_h1`, `atr_d1`, `adx_h1`, `bbw_h1`, `parkinson_d1`, `garman_klass_d1`, `realized_vol_d1`, `intraday_vol_profile`, `atr_percentile_d1`. Объясняет ATR H1 +48.67% (главный «выброс»).

### P0 #2 — Backfill включает формирующийся бар

`python/bot/analytics/fetcher.py:92`:
```python
rates = mt5.copy_rates_from_pos(symbol, native_tf, 0, bars_needed)
```
Стартовая позиция `0` = текущий незакрытый бар (для контраста: `detect_bar_close` в `fetcher.py:230` явно использует `1` с комментарием «1 = последний закрытый»).

Wilder seed ATR/ADX отравлен этим частичным баром. На primary TF эффект «вымывается» ≈5 часов (вес 1/14 в Wilder rectivity), на H1/M15/D1 (вкупе с #1) — никогда. Объясняет ATR M5 +13.37% и часть D1 +4.24%.

### P0 #3 — `session_vol_ratio` структурно неверная формула

`python/bot/analytics/volatility.py:94`:
```python
return safe_div(atr_h1_current, baseline, default=0.0)
```
- `atr_h1_current` — **в цене** (XAUUSD ~$15.12)
- `baseline = mean(abs(np.log(close/open)))` (`volatility.py:81`) — **безразмерный |log-return|** (~0.0013)

Деление одного на другое даёт мусор. Сверка: 15.12 / 0.0013 ≈ 11630 ≈ наблюдаемое **11573.39× ANOMALY** в UI Sessions. Это не «деление на ноль», а архитектурная ошибка.

Правильно: либо `(atr_h1 / close) / baseline` (привести к log-return-эквиваленту), либо считать `realized_vol_h1` (через `compute_realized_vol`) и сравнивать с profile из той же метрики.

### P0 #4 — Spread block: 3 ложных метрики в одном виджете

`python/bot/analytics/snapshot_builder.py:399,406`:

| Поле | Что в коде | Реальность |
|---|---|---|
| `median_24h_pt` | `sum(history) / len(history)` (snapshot_builder.py:399) | mean, не median |
| Окно «24h» | `_spread_history[-7200:]` при 1Hz sampling | ~2h, не 24h |
| `swap_today` | `"swap_today": 0.0` хардкод (snapshot_builder.py:406) | Никогда не считается; `total_swap_of_positions` (spread.py:117) существует, но не вызывается |
| `ticks_per_sec` | `record()` на каждом 10Hz tick_loop + 1Hz snapshot_loop | poll rate (10.5≈11), не tick rate; нет дедупликации по `tick.time_msc` |

### P1 — асимметрия UI vs by-design backend

- **«ATR/PD M15 = —»** — это **не сам ATR на M15**, а ratio `atr_m15 / (PriceDistance × point)` (`volatility.py:33-45`). Требует registered `StrategyContext` (`snapshot_builder.py:321,329`). Если стратегия не RUNNING → `ctx is None` → ratio = None → UI «—». Это by-design (Wave A.6), но диагностически невидимо: `atr_to_pd_ratio_h1` и `atr_to_cg_pd_ratio_h1` тоже None по той же причине, и UI их вообще не показывает — пользователь видит только M15-прочерк и думает что баг локальный.

### P1 — Regime hysteresis на snapshot-ticks, не bar-closes

`snapshot_builder.py:363` — `_regime_stabilizer.push(raw)` на каждом snapshot-tick (~1 Hz). Конфиг `hysteresis_bars_per_tf=3` подразумевает «3 бара», по факту 3 секунды. Эффективно гистерезис отключён.

### Что аудит подтвердил как корректное

- **CHAOS режим** — корректный fallback по `regime.py:93` при `adx_h1 > 20 AND er_primary ≤ 0.4` (mixed signals; ADX выше границы тренда, но ER слишком низкий для подтверждения).
- **Sessions Active=NY** — формула UTC-окон (`sessions.py:27-32`, `current_sessions()`) корректна.
- **Календарь CSV fallback** — ожидаемо после fix 2026-05-22.
- **M15 fix 2026-05-22** живёт без регрессии — `Timeframe.M15` в `tfs_to_backfill` (manager.py:570), блок M15 в `recompute_indicators` (indicator_pipeline.py:217-226), тесты зелёные.
- **«(58%)» рядом с ATR D1** — это percentile rank через 252-баровое окно (`indicators/percentile.py:20-37`), формула корректна.

### Сводка влияния

| Параметр | Статус после аудита | Корень |
|---|---|---|
| ATR D1/H1/M5 | ⚠/❌/⚠ завышены | P0 #1+#2 |
| ATR/PD M15 «—» | ✓ by-design | not-a-bug |
| ADX H1, BBW H1 | ⚠ стейл | P0 #1 |
| Parkinson, GK, Realized D1 | ⚠ стейл | P0 #1 |
| Vol vs hour-baseline 11573× | ❌ сломанная формула | P0 #3 |
| Spread Median 24h / Ticks/sec / Swap today | ❌×3 | P0 #4 |
| Spread Current / Z-score | ⚠ (база сломана) | P0 #4 |
| Regime CHAOS / Sessions Active / Календарь | ✓ корректно | — |

**Итого: 4 системных бага влияют на 13+ из ~20 параметров.** Полный реестр с конкретными `path:line` — в [[auragrid-incidents-log]] «2026-05-26 — Аудит Analytics» и в auto-memory `reference_analytics_audit_2026_05_26`.

### Приоритет следующего раунда фиксов

1. **P0 #2 первым** (1-строчный фикс `fetcher.py:92` `0 → 1`) — самостоятельный, без побочек.
2. **P0 #1** (добавить M15/H1/D1 в `_bar_close_loop`) — после #2, чтобы освежение работало уже с правильным backfill.
3. **P0 #3** (`session_vol_ratio` — переписать формулу + warm-up gate на минимум N полных дней профиля).
4. **P0 #4** (spread block — median вместо mean, swap из MT5 positions, dedup ticks по `time_msc`).
5. **P1** (regime hysteresis на bar-close + UI бейдж «strategy_not_registered» для M15-asymmetry).
6. **Acceptance после фикса:** повторная сверка ATR Analytics vs MT5-indicator на XAUUSD.N — ожидается <2% на всех TF (только seed-noise Wilder).

Реализационный паттерн — атомарный PR со всеми 4 P0 + регрессионные unit-тесты (как было сделано для TRAIL_REWORK 2026-05-25), либо ТЗ → реализация в формате `TZ_ANALYTICS_INTEGRITY_v1.0.md`. Выбор стратегии — за пользователем.

### Roadmap: ТЗ_ANALYTICS_INTEGRITY_v1.0 создан 2026-05-26

Реализационный документ — `auragrid/docs/tz/TZ_ANALYTICS_INTEGRITY_v1.0.md` (структура по образцу TZ_TRAIL_REWORK_v1.0.md). 10 разделов:
- §2 Целевая модель — конкретные «было/стало» формулы для каждого P0/P1 + численный acceptance example на 7 субтестах (§2.7).
- §4 Изменения по 13 слоям (fetcher / manager / volatility / spread / snapshot_builder / UI / тесты / docs / vault).
- §6 Verify-критерии 10 пунктов, включая **manual cross-validation ATR Analytics vs MT5-indicator на XAUUSD.N с допуском Δ <2%**.
- §7 Чек-лист 14 этапов реализации.

### Реализация TZ_ANALYTICS_INTEGRITY_v1.0 — 2026-05-26 (вечер)

**Status:** implemented (закрыто). SHA `fb67723`. Все 4 P0 + 2 P1 реализованы атомарным PR. pytest 1278 passed (1253 baseline + 25 новых), npm build OK, регрессии 0. Manual cross-validation ATR Analytics vs MT5 — отложена пользователю по `docs/qa/scenarios/analytics_smoke.md`.

| Пункт | Где фикс | Что было | Что стало |
|---|---|---|---|
| P0 #1 | `manager._bar_close_loop` | polling только primary TF | tf_order = primary + остальные buffers; sequential; `event=bar_close_detected` per TF |
| P0 #2 | `fetcher._backfill_native:92` | `copy_rates_from_pos(..., 0, N)` | `copy_rates_from_pos(..., 1, N)` |
| P0 #3 | `volatility.session_vol_ratio` + `compute_intraday_vol_profile` | размерностное несоответствие | `(atr_h1 / last_close_h1) / baseline`; warm-up gate `min_obs_per_hour=3` → `None` для часа без данных; `RollingBuffer.last_close()` |
| P0 #4.1 | `manager._spread_history` + `snapshot_builder.build_spread_block` | `list[-7200:]` mean | `deque(maxlen=86400)` + `np.median`; warm-up <60 → `None` |
| P0 #4.2 | `snapshot_builder.build_spread_block` | хардкод `0.0` | `total_swap_of_positions(mt5.positions_get(symbol))` |
| P0 #4.3 | `spread.TickRateTracker.record` + `_tick_loop` | poll rate (10.5) | dedup по `tick_time_msc`; `sample_spread_with_prices` возвращает `time_msc` 5-м tuple-полем; убран дублирующий вызов из `build_spread_block` |
| P1 #5 | `snapshot_builder` system_status + `desktop/...index.tsx` Alert + `widgets.tsx` Tooltip | непонятно «—» в `ATR/PD M15` | `strategy_context_registered: bool`; жёлтый Alert + Tooltip |
| P1 #6 | `snapshot_builder.build_regime_block` + `_indicators_recomputed_this_tick` | push на каждом 1Hz tick | push только на «фронте» bar_close |

**TS UI:** SVR cap ≥99 → «99+×» + `console.warn` outlier; SpreadBlock.median_24h_pt теперь `number | null`; SystemStatus.strategy_context_registered поле; Median 24h tooltip.

**Тесты (новые):**
- `tests/analytics/test_integrity_acceptance.py` (11 тестов) — закрепляет 7 субтестов §2.7 ТЗ (ATR/ADX детерминистично, session_vol_ratio=1.0 на anchor 16.50/3300/0.005, spread median робастный к outlier, swap_today=-2.25 на mock, dedup ticks, regime gate 0 push без bar_close, regime stabilize после 3-х bar_close).
- `tests/analytics/test_integrity_backfill_and_multi_tf.py` (3 теста) — `start_pos=1`, `detect_bar_close` вызывается per TF (M5+M15+H1+D1), новый бар маркирует `_indicators_dirty=True`.
- Обновлены `test_volatility.py`, `test_volatility_b2.py`, `test_spread.py` под новые сигнатуры.

**Что НЕ изменилось (Surgical по ADR-001):** архитектура (второй python-процесс, IPC порт 8770), имена IPC-полей snapshot (`atr_h1`, `session_vol_ratio`, `median_24h_pt`), config_version yaml, unblock-фиксы 2026-05-22 (symbol resolution, M15 buffer, CSV calendar, log rotation, system_status).

## Связано с

- [[auragrid]] — MOC проекта
- [[auragrid-trading-core]] — torговое ядро, отдельный процесс
- [[auragrid-incidents-log]] — incident 2026-05-22 раунд 4 (диагностика)
- [[auragrid-log-analysis]] — где смотреть, что искать

## Источник

- HEAD `677811c` (релиз 1.0.1, 2026-05-22)
- `desktop.log.2026-05-21` (лог тестировщика, 55 MB) — раздел 15823-15920
- Сессия 2026-05-22 (раунд 4) — диагностика по запросу пользователя
