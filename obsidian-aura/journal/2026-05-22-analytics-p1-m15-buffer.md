---
type: journal
tags: [auragrid, journal, analytics, p1, m15, indicators, deployment-table, fix]
created: 2026-05-22
updated: 2026-05-22
---

# 2026-05-22 (раунд 6) — Analytics P1: M15 buffer + atr_m15 → DeploymentTable

## Контекст сессии

Продолжение работы по [[auragrid-analytics-module]] — после фикса P0 (symbol resolution, [[2026-05-22-analytics-p0-symbol-resolution]]) пользователь попросил сразу же закрыть P1 — M15 buffer.

Root cause (из assessment-журнала [[2026-05-22-analytics-assessment]]): `tfs_to_backfill = {primary, H1, D1}` — M15 не включён. При этом `atr_m15` объявлен в schema (`indicator_pipeline.empty_indicators`), потребляется в трёх местах кода (position block, levels VP fallback, preset_eval atr_per_hour) и в UI (`deployInputs.atr_m15 ?? 0`). Эффект: даже после P0 (symbol резолвится) DeploymentTable работала бы с ATR=0 — catastrophically заниженная оценка риска.

## Vault context (Phase 1)

- [[auragrid-analytics-module]] — корневая причина №3 (M15 missing) + Приоритеты unblock P1.
- [[2026-05-22-analytics-p0-symbol-resolution]] — предыдущий раунд (P0).
- [[2026-05-22-analytics-assessment]] — assessment с план unblock.
- [[runbook-vault-integration]] — workflow.

## Что сделано (Phase 2)

### Backend: [manager.py:_backfill](auragrid/python/bot/analytics/manager.py)

```diff
-tfs_to_backfill = {self._primary_tf, Timeframe.H1, Timeframe.D1}
+tfs_to_backfill = {self._primary_tf, Timeframe.M15, Timeframe.H1, Timeframe.D1}
```

M15 buffer теперь заполняется из MT5 на старте (buffer_sizes.M15 = 2880 уже был в `analytics_config.yaml`, ~30 дней истории).

### Backend: [indicator_pipeline.py:recompute_indicators](auragrid/python/bot/analytics/indicator_pipeline.py)

После H1-блока добавлен минимальный M15-блок:

```python
m15_buf = buffers.get(Timeframe.M15)
if m15_buf is not None and len(m15_buf) >= 14:
    df = m15_buf.get_df()
    atr_m15_series = compute_atr(df, n=14)
    out["atr_m15"] = _last_or_none(atr_m15_series)
```

Минимально — atr_m15 единственный потребитель из indicators schema (другие виджеты живут на H1/D1). Полный набор индикаторов на M15 — отдельный future scope.

### Что НЕ нужно было править

- **UI Analytics/PresetEval**: `deployInputs.atr_m15 = snap.indicators.atr_m15 ?? 0` уже корректно — теперь приходит ненулевое значение, кнопка DeploymentTable активируется автоматически.
- **snapshot_builder**: `m._last_indicators.get("atr_m15")` уже использует pipeline output — индикаторы рассчитываются и попадают в snapshot.
- **levels.py**: `df_m15=self.snapshot_buf(Timeframe.M15)` уже корректен — после backfill buffer существует, snapshot_buf вернёт непустой df.
- **preset_eval/deployment_table.py**: `atr_per_hour = inp.atr_m15 * 4` уже корректно.

### Тесты

- `tests/analytics/test_b3_decompose.py::TestIndicatorPipeline` — 3 новых кейса:
  - `test_atr_m15_computed_when_buffer_warm` — буфер ≥14 баров → atr_m15 > 0
  - `test_atr_m15_none_when_buffer_short` — <14 баров → None (warm-up)
  - `test_atr_m15_none_when_buffer_missing` — нет M15 буфера → None, primary всё ещё работает
- `tests/analytics/test_manager_backfill_m15.py` (новый файл) — `test_backfill_requests_m15` мокает `fetcher.backfill`, проверяет что вызов с `Timeframe.M15` присутствует и buffer создан в `mgr.buffers`.

## Что зафиксировано в vault

- [[auragrid-analytics-module]] — корневая причина №3 помечена FIXED с описанием fix; Приоритеты unblock — P1 (M15) помечен ✅ DONE; TL;DR обновлён; статусы компонентов в таблице (Manager, Indicators, MT5 client) обновлены.
- [[auragrid-incidents-log]] — добавить incident 2026-05-22 раунд 6 (Resolution + Prevention).
- CHANGELOG.md — запись о раунде 6.
- Auto-memory — `reference_analytics_module.md` обновлён под актуальный статус (P0+P1-M15+P2-badge done).

## Тесты

- pytest analytics-suite + новые M15 тесты — все зелёные (3+1 новых).
- pytest full suite — 1151/1151 passed (+4 от P1 после раунда 5).

## Что осталось открытым

Из [[auragrid-analytics-module]] «Приоритеты unblock»:

1. **P1 — Calendar fallback** — `load_csv_fallback` подключение + CSV в дистрибутиве (ForexFactory/Investing.com).
2. **P2 — Сепарация лог-файлов** analytics → `analytics.log`, бот → `bot.log` (PermissionError × 6400 в логе тестировщика).
3. **P2 — Integration smoke e2e** fake-MT5 + manager + builder → snapshot.indicators непустые через 10s.

## Что выучили

- **Корректная schema → минимальная имплементация.** `atr_m15` уже был в `empty_indicators()` + потребители уже корректно его читали — нужен был только источник данных (backfill + 5-строчный блок в pipeline). Это победа архитектуры B.3.1 (extract pipeline в отдельный модуль) — gap был один на pipeline-уровне, не размазан по 4 файлам.
- **Тестирование TF-блоков по образцу.** Шаблон `test_X_computed_when_buffer_warm/short/missing` (3 кейса) — стандартный для проверки независимости блоков в pipeline. Применим для будущих расширений (H4, W1, синтетические S-TF).
- **Несколько P-багов одной природы — фиксятся одной техникой.** P0 и P1 — оба «MT5-связанные источники данных отсутствуют» → схожий fix паттерн (расширить источник + UI/snapshot status). P1-calendar пойдёт по той же траектории (источник = MT5 API → CSV fallback).
- **Backfill ≠ live update.** В analytics-процессе bar_close_loop детектит close только primary TF; H1/D1/M15 буферы заполняются один раз на старте. Это известное ограничение (см. также [[2026-05-22-analytics-assessment]] раздел «Сопутствующие проблемы»). ATR M15 stable первые часы после restart, дальше становится постепенно stale. Future scope: bar_close detection для всех refTF — но это не блок Pacient UX.

## Связано с

- [[auragrid]] — MOC
- [[auragrid-analytics-module]] — статус обновлён
- [[auragrid-incidents-log]] — incident 2026-05-22 раунд 6
- [[2026-05-22-analytics-p0-symbol-resolution]] — предыдущий раунд
- [[2026-05-22-analytics-assessment]] — assessment с план unblock
- [[runbook-vault-integration]] — workflow
