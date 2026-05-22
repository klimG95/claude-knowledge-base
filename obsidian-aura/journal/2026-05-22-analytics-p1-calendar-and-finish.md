---
type: journal
tags: [auragrid, journal, analytics, p1, p2, calendar, csv-fallback, logs, e2e-smoke, fix]
created: 2026-05-22
updated: 2026-05-22
---

# 2026-05-22 (раунд 7) — Финиш Analytics unblock: P1 Calendar + P2 Logs + P2 e2e smoke

## Контекст сессии

После раундов 5 (P0 symbol) и 6 (P1 M15) пользователь попросил **добить остальные приоритеты unblock** одной сессией: P1 Calendar fallback, P2 сепарация лог-файлов, P2 integration smoke. Цель — перейти к ручной верификации модуля с полным аудитом готовности.

## Vault context (Phase 1)

- [[auragrid-analytics-module]] — корневые причины №2 (calendar) + «Сопутствующие проблемы» (лог-конкуренция) + Приоритеты unblock 3-6.
- [[2026-05-22-analytics-p0-symbol-resolution]], [[2026-05-22-analytics-p1-m15-buffer]] — предыдущие раунды.
- [[runbook-vault-integration]] — workflow.

## Что сделано (Phase 2)

### P1 Calendar — CSV fallback + hasattr-guard

**[calendar.py:EconomicCalendar](auragrid/python/bot/analytics/calendar.py)**:
- Конструктор принимает `csv_fallback_path: Path | str | None`.
- `refresh()` разделён на `_refresh_from_mt5()` и `_load_csv_window()`. Сначала MT5; если функций нет (`hasattr` guard) или пустой результат — CSV; иначе `[]`.
- Поле `last_source: "mt5"|"csv"|"none"` для публикации в snapshot.
- `_load_csv_window` фильтрует bundled CSV по `lookback_hours`/`lookahead_days` + currencies + min_importance.

**[manager.py](auragrid/python/bot/analytics/manager.py)** — в инициализации EconomicCalendar: если `cal_cfg.csv_fallback_path is None` — резолвится default `python/bot/analytics/data/economic_calendar.csv` (положен в дистрибутив). Это закрывает кейс «yaml не сконфигурирован, но CSV должен подхватиться».

**[analytics_config.yaml](auragrid/python/bot/analytics/config/analytics_config.yaml)** — добавлен ключ `calendar.csv_fallback_path: null` с комментарием как переопределять.

**[data/economic_calendar.csv](auragrid/python/bot/analytics/data/economic_calendar.csv)** — новый файл с 5 примерами событий (NFP, FOMC, CPI, GDP). Формат ForexFactory — `ts_utc,currency,importance,name,forecast,previous,actual`.

**[snapshot_builder.build_snapshot](auragrid/python/bot/analytics/snapshot_builder.py)** — `system_status.calendar_source` публикуется в каждом snapshot.

**[useAnalyticsSubscription.ts](auragrid/desktop/src/hooks/useAnalyticsSubscription.ts)** — `SystemStatus.calendar_source?: "mt5"|"csv"|"none"`.

**[Analytics/index.tsx](auragrid/desktop/src/pages/Analytics/index.tsx)** — два новых Alert:
- Жёлтый «Календарь: CSV fallback» при `calendar_source === "csv"`.
- Оранжевый «Календарь недоступен» при `calendar_source === "none"`.

### P2 Лог-конкуренция — PermissionError-safe rollover

**[bot/utils/logging.py:_JSONRotatingHandler](auragrid/python/bot/utils/logging.py)** — в `emit()`:
- Если `shouldRollover` True и `doRollover()` бросает `PermissionError`/`OSError` — НЕ падаем; сдвигаем `rolloverAt += 3600` (retry через час), продолжаем писать в текущий файл.
- Запись не теряется. Поведение защитное; основной кейс (race между bot.log и analytics.log) уже решён `log_name="analytics"` в раунде A.4.

### P2 Integration smoke e2e

**[tests/analytics/test_manager_smoke.py](auragrid/python/tests/analytics/test_manager_smoke.py)** — новый fixture `mt5_online` (валидный `symbol_info(XAUUSD)`, `copy_rates_from_pos` возвращает структурированный array из 60 баров) + новый test `test_manager_e2e_indicators_nonempty`:
- start + WS-клиент.
- Команда `analytics.get_snapshot`.
- Asserts: `system_status.symbol_resolved == True`, `symbol_source == "candidates"`, `indicators.atr_primary != None`, `indicators.atr_m15 != None`, `indicators.atr_h1 != None`.

Закрывает gap «unit-тесты зелёные, прод не работает» — теперь регрессия в backfill / resolve / pipeline ловится одним тестом.

### Попутно (feedback_fix_found_bugs)

Pre-existing баг в [snapshot_builder.snapshot_buf](auragrid/python/bot/analytics/snapshot_builder.py): `buf.size()` и `buf.snapshot()` — методы которых у `RollingBuffer` нет (публичный API — `__len__` + `get_df()`). До фикса при `levels.enabled=True` весь snapshot_loop валился AttributeError. Прошлые тесты этого не ловили потому что `mt5_offline` фикстура давала пустые буферы, levels отключался по `cur_price=None`. Online-mock e2e сразу высветил баг. Заменил `buf.size()` → `len(buf)`, `buf.snapshot()` → `buf.get_df()`.

### Тесты

- `tests/analytics/test_calendar.py` — 4 новых кейса: `test_csv_fallback_used_when_mt5_api_missing`, `test_csv_fallback_filters_window_and_currency`, `test_mt5_takes_priority_over_csv`, `test_no_mt5_no_csv_returns_none_source`.
- `tests/test_logging.py` — `test_rollover_permission_error_does_not_lose_record`.
- `tests/analytics/test_manager_smoke.py` — `test_manager_e2e_indicators_nonempty`.

## Что зафиксировано в vault

- [[auragrid-analytics-module]] — корневая причина №2 (calendar) помечена FIXED, «Сопутствующие проблемы → Лог-конкуренция» FIXED. Все 6 приоритетов unblock ✅ DONE. TL;DR обновлён («все три корневые причины разблокированы»). Компонент-таблица: Calendar → ✓.
- [[auragrid-incidents-log]] — incident 2026-05-22 раунд 7 (calendar + logs + smoke + RollingBuffer pre-existing fix).
- CHANGELOG.md — запись о раунде 7.
- Auto-memory — `reference_analytics_module.md` отражает «все приоритеты закрыты, готов к ручной верификации».

## Тесты

- pytest analytics suite + новые → все зелёные.
- pytest full suite — 1157/1157 passed (+6 от раунда 6: 4 calendar + 1 logs + 1 e2e smoke).
- vitest — 24/24 зелёные.
- tsc --noEmit — чисто.

## Что осталось

**Из плана unblock — ничего. Все 6 приоритетов закрыты.**

Открытые задачи для будущих сессий (не из этого плана):
- Live update H1/D1/M15 буферов (сейчас snapshot на старте; bar_close detection только primary TF). Не блок UX, но при долгих uptimes индикаторы stale.
- CSV-обновление economic_calendar.csv (кто и когда подтягивает из ForexFactory/Investing.com).
- Полный M15 индикаторный набор (сейчас только ATR; ADX/BB/intraday — если потребуется).
- Per-strategy view (Wave C-lite) — мульти-стратегии в одном окне.

## Что выучили

- **«Hasattr-guard before method call» = anti-25k-AttributeError-pattern.** Когда внешняя библиотека может не иметь метода (`mt5.calendar_event_by_currency`), проверяй `hasattr` ДО цикла try/except — иначе 25 тысяч записей в логе за 10 часов. Этот же приём применим для других MT5 API, которые могут варьироваться между версиями пакета.
- **Online-mock e2e окупается на pre-existing багах.** Тест `test_manager_e2e_indicators_nonempty` сразу нашёл `RollingBuffer.size()`/`.snapshot()` баг, который unit-тесты не ловили. Online MT5 mock — это стандарт для smoke-тестов модулей, зависящих от внешнего API: его дешевле написать чем чинить прод-регрессии.
- **Defensive logging на ротацию.** PermissionError при `doRollover` — типичный Windows-кейс (antivirus, tail, search-indexer). Без защиты ~6400 stderr-traceback'ов в логе тестировщика; с защитой — 0 потерянных записей.
- **Schema-first + degraded-status badge — переиспользуемый pattern.** `system_status: {symbol_*, calendar_*, mt5_connected}` теперь стандартное место для расширения UI degraded-mode. Будущие fallback'и (live update, новые источники данных) пойдут по той же траектории: ключ в `system_status` + Alert в UI.

## Связано с

- [[auragrid]] — MOC
- [[auragrid-analytics-module]] — все приоритеты ✅ DONE
- [[auragrid-incidents-log]] — incident раунд 7
- [[2026-05-22-analytics-assessment]] — assessment с план unblock
- [[2026-05-22-analytics-p0-symbol-resolution]] — раунд 5
- [[2026-05-22-analytics-p1-m15-buffer]] — раунд 6
- [[runbook-vault-integration]] — workflow
