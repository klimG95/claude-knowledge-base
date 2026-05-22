---
type: component
tags: [auragrid, analytics, second-process, ipc, partially-fixed]
component: bot.analytics
layer: code
shape: domain-hub
created: 2026-05-22
updated: 2026-05-22
---

# AuraGrid — Analytics module (состояние и архитектура)

**TL;DR.** Analytics — отдельный python-процесс со своим MT5-инстансом и IPC-портом 8770, который должен снабжать UI 12 виджетами + DeploymentTable (расчёт риска стратегии). На версии HEAD (677811c, релиз 1.0.1) фактически работали только Spread и Sessions, остальное — null'ы. После раундов 5 (P0) и 6 (P1 M15) большая часть pipeline разблокирована: ~~`symbol_not_found` ломает backfill~~ **(P0 пофикшен 2026-05-22)**, ~~M15 buffer отсутствует~~ **(P1 пофикшен 2026-05-22 — backfill + atr_m15 в pipeline → DeploymentTable работает)**. Остаётся **MT5 calendar API mismatch** (`calendar_event_by_currency` отсутствует, календарь всегда пуст — нужен CSV fallback).

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
| Calendar | `analytics/calendar.py` | MT5 calendar_event_by_currency + CSV fallback | ❌ MT5 API mismatch, fallback не подключён |
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

### №2 — MT5 calendar API mismatch (HIGH)

`mt5.calendar_event_by_currency()` отсутствует в установленной версии MetaTrader5 пакета. Try/except в [calendar.py:93-98](auragrid/python/bot/analytics/calendar.py#L93-L98) обработан корректно (нет crash), но возвращается пустой массив. В логе тестировщика 25 180 трейсбэков AttributeError за ~10 часов сессии.

В коде есть `load_csv_fallback` ([calendar.py:266-337](auragrid/python/bot/analytics/calendar.py#L266-L337)) — путь к CSV из конфига, но фактически не подключён или CSV-файл не в дистрибутиве.

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
| `calendar_upcoming` | ✗ | MT5 API mismatch |
| `alerts_active` | пусто | правила не триггерятся без данных |
| DeploymentTable (расчёт риска стратегии) | ✓ после P0+P1 | После 2026-05-22: symbol резолвится → buffers заполняются → atr_m15/h1/d1 ненулевые → кнопка активна |
| RiskMeter (главный экран) | работает независимо | из бота (`core/risk.py`), не из analytics-процесса |

## Сопутствующие проблемы

### Лог-конкуренция

Analytics и бот пишут в один `%APPDATA%/GridScalp/logs/bot.log`. При попытке ротации (`doRollover`) — `PermissionError: WinError 32` (файл занят другим процессом). ~6 400 событий в логе тестировщика. Не блокирует функционал, но захламляет stderr.

### IPC connect refused штук в логе UI

`ipc: connect failed error=IO error: No connection could be made` — это попытки UI подключиться к analytics порту 8770 ДО того как процесс поднялся. Через секунду — успешный коннект (`IPC_READY {"port": 8770}` есть в логе). Это не баг, это race в стартапе.

## Приоритеты unblock

В порядке убывания:

1. ~~**P0 — Symbol resolution.**~~ ✅ **DONE (2026-05-22)** — см. секцию №1 fix выше.
2. ~~**P1 — M15 buffer.**~~ ✅ **DONE (2026-05-22)** — см. секцию №3 fix выше.
3. **P1 — Calendar fallback.** Подключить `load_csv_fallback` (положить CSV в дистрибутив, или подтянуть из ForexFactory/Investing.com).
4. **P2 — Сепарация лог-файлов** analytics → `analytics.log`, бот → `bot.log`.
5. ~~**P2 — Degraded-mode UI badge.**~~ ✅ **DONE (2026-05-22, попутно с P0)** — снапшот публикует `system_status`, UI рисует красный/жёлтый Alert.
6. **P2 — Integration smoke** e2e-тест (fake-MT5 + manager + builder → snapshot.indicators непустые через 10s).

## Связано с

- [[auragrid]] — MOC проекта
- [[auragrid-trading-core]] — torговое ядро, отдельный процесс
- [[auragrid-incidents-log]] — incident 2026-05-22 раунд 4 (диагностика)
- [[auragrid-log-analysis]] — где смотреть, что искать

## Источник

- HEAD `677811c` (релиз 1.0.1, 2026-05-22)
- `desktop.log.2026-05-21` (лог тестировщика, 55 MB) — раздел 15823-15920
- Сессия 2026-05-22 (раунд 4) — диагностика по запросу пользователя
