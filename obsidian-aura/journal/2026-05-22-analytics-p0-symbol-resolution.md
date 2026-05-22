---
type: journal
tags: [auragrid, journal, analytics, p0, symbol-resolution, fix]
created: 2026-05-22
updated: 2026-05-22
---

# 2026-05-22 (раунд 5) — Analytics P0: Symbol resolution unblock

## Контекст сессии

Пользователь продолжил работу по [[auragrid-analytics-module]] с шага P0 — symbol resolution. Корневая причина «прочерков» в окне Analytics на релизе 1.0.1: `resolve_symbol` пробовал жёсткий список `['XAUUSD','XAUUSD.s','XAUUSD.m','GOLD','XAU/USD']` и при пустом результате каскадно валился весь snapshot (см. assessment-журнал [[2026-05-22-analytics-assessment]]).

## Vault context (Phase 1)

- [[runbook-vault-integration]] — workflow
- [[auragrid]] — MOC
- [[auragrid-analytics-module]] — секции «Корневые причины» и «Приоритеты unblock»
- [[2026-05-22-analytics-assessment]] — assessment (P0-P6 план)
- [[journal/2026-05-22|journal/2026-05-22]] — раунды 1-3 (релизные фиксы)

## Что сделано (Phase 2)

### Backend: [mt5_client.py:resolve_symbol](auragrid/python/bot/analytics/mt5_client.py#L107)

Расширил сигнатуру: `resolve_symbol(candidates, *, heuristic_tokens=None)`. Если жёсткий список не дал результата и `heuristic_tokens` переданы — перебор `mt5.symbols_get()` с поиском имени, которое содержит **все** tokens (case-insensitive). Логирование `event="symbol_resolved", source="candidates"|"heuristic"` и `event="symbol_not_found", tried=..., heuristic_tokens=...`. В MT5Client добавлены атрибуты `last_resolve_source` и `last_resolve_tried` для публикации в snapshot.

### Backend: [manager.py:_build_symbol_candidates](auragrid/python/bot/analytics/manager.py)

Новый helper собирает приоритезированный список candidates:
1. Base из `analytics_config.yaml` → `system.symbol_candidates`.
2. `mt5.symbol` из каждого `<data_dir>/strategies/*.yaml` (graceful read, malformed yaml не валит сбор).
3. Для каждого base name — 11 типовых broker-suffix вариантов: `""`, `.s`, `.m`, `.pro`, `.c`, `.i`, `.raw`, `.x`, `x`, `pro`, `_i`.
4. Уникализация с сохранением порядка.

В `start()` и `_mt5_health_loop()` (reconnect path) вызов `resolve_symbol` теперь передаёт `heuristic_tokens=self._symbol_heuristic_tokens` (новый ключ `system.symbol_heuristic_tokens` в `analytics_config.yaml`, default `["XAU","USD"]`). После resolve обновляются `manager.symbol_resolved: bool` и `manager.symbol_source: str`.

### Backend: snapshot_builder.build_snapshot

Добавлен блок `system_status` в snapshot:
```python
"system_status": {
    "symbol_resolved": bool,
    "symbol_source": "candidates"|"heuristic"|"none",
    "symbol_tried": [list of tried names],
    "mt5_connected": bool,
}
```

### UI: [Analytics/index.tsx](auragrid/desktop/src/pages/Analytics/index.tsx)

Добавлены два Alert-баннера сверху окна (после initialLoad, перед AlertsTray):
- **Красный** «Analytics: символ не найден» — когда `system_status.symbol_resolved === false`. Показывает tried-список + инструкция «проверь Market Watch / добавь в config».
- **Жёлтый** «Символ найден через эвристику» — когда `symbol_source === "heuristic"`. Рекомендует добавить имя в config для предсказуемости.

Расширен тип `AnalyticsSnapshot` в `useAnalyticsSubscription.ts` — добавлен опциональный `system_status?: SystemStatus`.

### Тесты

- `tests/analytics/test_mt5_client.py::TestResolveSymbol` — 6 кейсов: candidate match, heuristic fallback, requires all tokens, case-insensitive, none-source, heuristic disabled.
- `tests/analytics/test_manager_symbol_candidates.py` — 7 кейсов: base preserved, strategies yaml contributes, dedup, missing dir ok, malformed yaml skipped, no-symbol yaml skipped, suffix variants.

### Попутные фиксы (по правилу [[feedback_fix_found_bugs]])

При прогоне полного pytest suite обнаружены два pre-existing бага окружения:
1. **aiogram missing** — `tests/integration/test_admin_bot_commands.py` падал на collection с `ModuleNotFoundError: aiogram`. Зависимость есть в `tools/admin_bot/requirements.txt` (subтул), но не в `python/requirements-dev.txt`. Добавил `aiogram>=3.13,<4` + `respx>=0.21` в dev requirements + установил локально. Тесты прошли 16/16.
2. **@tauri-apps/plugin-dialog missing** — `tsc --noEmit` падал на `StrategyPanel.tsx:19`. Пакет указан в `package.json` (был добавлен в раунде 3), но `node_modules` собран без него. Установил pnpm глобально (репо использует pnpm-lock.yaml) + `pnpm install` — TS компилируется чисто.

## Что зафиксировано в vault

- **[[auragrid-analytics-module]]** обновлён: TL;DR помечает P0 как fixed, секция «Корневая причина №1» расширена блоком Fix с описанием трёх эшелонов + ссылками на код. В «Приоритетах unblock» P0 и P2-degraded-badge помечены ✅ DONE.
- **[[auragrid-incidents-log]]** — добавлена запись 2026-05-22 раунд 5 (Resolution + Prevention).
- **CHANGELOG.md** — новая запись.
- **`index.md`** не менялся (новых wiki нет).
- **Auto-memory** — `reference_analytics_module.md` обновлён под актуальный статус (P0 done, осталось P1/P2).

## Тесты

- pytest analytics-suite — 458/458 зелёные.
- pytest full suite — 1147/1147 зелёные (без skipped/xfail flux).
- vitest (desktop) — 24/24 зелёные.
- tsc --noEmit — чисто.

## Что осталось открытым (план на следующие сессии)

Из [[auragrid-analytics-module]] «Приоритеты unblock»:

1. **P1 — M15 buffer** — добавить M15 в `tfs_to_backfill` ([manager.py:445](auragrid/python/bot/analytics/manager.py#L445)) + блок в `recompute_indicators` по образцу H1. Разблокирует DeploymentTable.
2. **P1 — Calendar fallback** — подключить `load_csv_fallback` + положить CSV в дистрибутив или подтянуть из ForexFactory.
3. **P2 — Сепарация лог-файлов** analytics → `analytics.log`, бот → `bot.log` (закрыть PermissionError × 6400).
4. **P2 — Integration smoke e2e** fake-MT5 + manager + builder → `snapshot.indicators` непустые через 10s.

## Что выучили

- **Hard-coded list + heuristic — рабочий паттерн для broker-specific конфигов.** Hard-coded ловит 90% случаев быстро (по индексу `symbol_info`), heuristic закрывает long tail без deep-knowledge о брокерах. UI badge нужен для прозрачности — пользователь видит причину «прочерков» и инструкцию «как починить».
- **Symbol candidates — это data, а не code.** Перенос из жёсткого списка в `analytics_config.yaml` + `strategies/*.yaml` + auto-suffix-варианты позволяет хот-фиксить онбординг нового брокера без релиза.
- **Snapshot `system_status` — место для UI degraded-mode.** Тот же приём пригодится для P1/P2 (mt5_connected, calendar_source, m15_ready). Не плодим разрозненные ipc-методы — клиент уже подписан на snapshot.
- **`feedback_fix_found_bugs` окупается дважды.** Этой сессии два pre-existing бага (aiogram dep + missing node_modules) перестали мешать future-сессиям, не отнимая от основной задачи больше 15 минут.

## Связано с

- [[auragrid]] — MOC
- [[auragrid-analytics-module]] — статус и архитектура (обновлено)
- [[auragrid-incidents-log]] — incident 2026-05-22 раунд 5
- [[2026-05-22-analytics-assessment]] — предыдущий assessment
- [[journal/2026-05-22|journal/2026-05-22]] — раунды 1-3 (релизные фиксы)
- [[runbook-vault-integration]] — workflow
