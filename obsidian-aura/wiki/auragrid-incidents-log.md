---
type: incident-log
tags: [auragrid, incidents, operations]
created: 2026-05-22
updated: 2026-05-22
---

# AuraGrid — Incidents log

Журнал инцидентов проекта AuraGrid. Новые записи добавляются сверху. Формат раздела — [[templates/template-incident]].

**Правила:**
- Запись делается в момент диагностики, не пост-фактум
- Если инцидент → фикс закрыт коммитом, обязательно линковать SHA
- Секция Prevention важнее остальных — это материал для будущих агентов

---

## Incident 2026-05-22 (раунд 5) — Analytics P0: Symbol resolution unblock

**Status:** resolved (бэк + UI + тесты)
**Severity:** S2 (UX deception — окно работало частично без объяснения причины)

### Symptom

На релизе 1.0.1 окно Analytics показывало только Spread + Sessions, остальные 10 секций — null/прочерки. Из assessment-раунда 4 ([[2026-05-22-analytics-assessment]]) — корневая причина: `symbol_not_found` в analytics-процессе. Жёсткий список `['XAUUSD','XAUUSD.s','XAUUSD.m','GOLD','XAU/USD']` не закрывал custom-суффиксы брокеров.

### Investigation

См. assessment-раунд 4. В этой сессии работа была чисто implementation — pre-known root cause.

### Resolution

Трёхэшелонная схема в analytics-процессе:
1. **Dynamic candidates** в `AnalyticsManager._build_symbol_candidates`: base (config) + `mt5.symbol` per-strategy yaml + 11 suffix-вариантов (`.s/.m/.pro/.c/.i/.raw/.x/x/pro/_i`).
2. **Heuristic fallback** в `MT5Client.resolve_symbol(..., heuristic_tokens=["XAU","USD"])`: перебор `mt5.symbols_get()` с поиском имени, содержащего все tokens.
3. **UI degraded badge**: snapshot публикует `system_status: {symbol_resolved, symbol_source, symbol_tried, mt5_connected}`. Окно рисует красный (`not found`) или жёлтый (`heuristic`) Alert.

Тесты: 6 кейсов на `resolve_symbol`, 7 — на `_build_symbol_candidates`. Полный pytest 1147/1147 + vitest 24/24 + tsc чисто.

Журнал: [[2026-05-22-analytics-p0-symbol-resolution]]. Деталь Fix-секции — в [[auragrid-analytics-module]] корневая причина №1.

### Prevention

- **«Hard-coded list + heuristic» — стандартный паттерн.** Применим там, где данные приходят от внешней системы с broker-specific вариациями (символы, ретеркоды, server names).
- **Symbol candidates — это data, не code.** В коде только heuristic-семантика; список имён живёт в `analytics_config.yaml` + per-strategy yaml. Онбординг нового брокера — отредактировал конфиг → перезапуск, без новой сборки.
- **UI degraded-status вместо тихих null'ов.** Любой системный сбой, который ломает UX «по эффекту» (прочерки, disabled-кнопки), должен иметь объясняющий badge с tried/source/инструкцией. Snapshot `system_status` — точка расширения для P1/P2 unblock'ов.
- **Попутный фикс окружения** ([[feedback_fix_found_bugs]]): aiogram добавлен в `python/requirements-dev.txt`, pnpm-зависимости установлены. Чтобы будущие dev-сессии не натыкались на ту же проблему.

### Commits

В рамках сессии (см. git log).

---

## Incident 2026-05-22 — Тестировщик (ключ `6b03bdc5-…`) выявил пять проблем после релизного фикс-пакета

**Status:** resolved (коммиты `85b7c91` + `677811c`)
**Severity:** S1 (close-all сделок не работал) + S2 (точность лота / UX / фантомы)

**⚠ Важный урок этого инцидента:** первый коммит `85b7c91` закрыл UX-симптомы, но **не основную причину**. Только при ре-аудите (та же сессия, после внедрения vault-workflow) был найден реальный root cause через анализ retcode в `desktop.log.2026-05-21:3582-3591`. См. секцию «Re-audit findings» ниже.

### Symptom

Тестировщик с ключом `6b03bdc5-1258-4a2e-aea8-7f45b01fe035` сообщил после установки нового билда:
1. Кнопки «Закрыть все сделки», «Закрыть BUY», «Закрыть SELL» закрывают только 1-2 сделки из N
2. Размер лота рассчитывается «приближенно, но не точно»
3. Иногда всплывают фантомные ордера
4. Не срабатывает `profit_fixing_direction`
5. `auto_calculated_profit` не работает если значение < 1 (гипотеза тестировщика)

Параллельно — лог `desktop.log.2026-05-21` (55 MB, 354k строк) показал два дополнительных дефекта релиза (см. ниже).

### Misdiagnosis

- Гипотеза «auto-profit < 1 — int-каст» — оказалась неверной: код использует float корректно. Реальная причина — misleading UI label `"Auto calculated profit (%)"`, тогда как семантика — USD за каждые 0.01 лота.
- Гипотеза «profit_fixing_direction не реагирует на маленькие значения» — тоже неверна. Семантика верная (активация trail SL), но не совпадает с ожиданием тестировщика (мгновенное закрытие).

### Root cause

1. **close-all only 1-2:** `python/bot/core/protection.py:close_channel` брал `bid/ask` один раз перед циклом и не передавал `on_retry` в executor. На 3-й+ позиции цена уходила, MT5 возвращал `REQUOTE` / `INVALID_PRICE (10015)`, executor ретраил с устаревшим `price` → `result=None` → позиция пропущена.
2. **Лот неточен:** `python/bot/utils/normalize.py:normalize_lot` финальный `round(normalized, 2)` — жёсткие 2 знака. Для брокеров с `volume_step=0.001` это коллапсировало `0.025` → `0.03` (и могло уйти в `0.02` через banker rounding).
3. **Фантомы:** `engine.start()` не сверял `state.pending_ticket` (из SQLite) с реальным MT5. Два сценария: (a) бот упал после `order_send` но до `save_channel_state` → orphan в MT5; (b) pending в state есть, в MT5 нет → stale.
4. **profit_fixing_direction:** семантика правильная (порт MQL5: активирует trailing SL), UI label вводил в заблуждение.
5. **auto_calc_profit < 1:** UI label `"... (%)"` ложный, реальные единицы — USD на 0.01 лота.

Дополнительно из `desktop.log.2026-05-21`:

6. **log_shipper crash:** `AttributeError: 'StateStore' object has no attribute 'load_log_cursor'` — 134 повтора, отправка логов не работала. **Уже исправлено** до этой сессии в `d9f003c` — но билд тестировщика собран ДО коммита.
7. **MT5 calendar API:** `module 'MetaTrader5' has no attribute 'calendar_event_by_currency'` — устаревший пакет в python-embed, ~25 180 трейсбеков в логе, календарь не работает.
8. **PermissionError на ротации `bot.log`:** 6 368 повторов — bot и analytics пишут в один файл, второй процесс не может ротировать.

### Fix

Коммит `85b7c91` (2026-05-22):

| # | Файл | Правка |
|---|------|--------|
| 1 | `python/bot/core/protection.py` | Свежий tick перед каждой позицией в цикле; `on_retry` callback освежает `price` при REQUOTE/INVALID_PRICE |
| 2 | `python/bot/utils/normalize.py` | `digits = -log10(volume_step)` вместо жёсткого `round(_, 2)` |
| 3 | `python/bot/core/engine.py:start()` | Sync `state.pending_ticket` с реальным MT5: clear stale, adopt orphan, reassign mismatch |
| 4-5 | `desktop/src/pages/Wizard/Step3Editor.tsx` | Labels: `"Trail activation @ profit (USD)"` и `"Auto profit per 0.01 lot (USD)"` + описания семантики |

Тесты: 23 normalize+protection ✅, 46 engine+integration ✅, 804 unit-suite ✅. Один pre-existing fail (документирован в `d9f003c`) не связан.

**Не исправлено в этой сессии (нужны отдельные задачи):**
- MT5 calendar API mismatch — обновить пакет `MetaTrader5` в python-embed (см. [[auragrid-python-embed-packaging]])
- bot.log rotation conflict (PermissionError × 6368) — разделить логи bot и analytics в разные файлы

### Prevention

1. **Любая операция close-multiple должна освежать tick per item + передавать `on_retry`.** Шаблон в `protection.close_channel` — пример для будущих похожих циклов.
2. **`normalize_lot` тесты теперь должны покрывать `volume_step=0.001`** — добавить параметризацию `(0.025, 0.001, 0.001, 100.0, 0.025)`.
3. **`engine.start()` всегда сверяет state с MT5 перед `running=True`** — pending_ticket, и в будущем — open positions (orphan close может появиться).
4. **UI labels не должны указывать единицы, которых нет в коде.** Если параметр интерпретируется как `value * (total_lot/0.01) USD`, label должен это говорить, не `"(%)"`.
5. **Релизный smoke-чек должен прогонять testbench с `volume_step ≠ 0.01`** — XAUUSD у Doo Technology имеет другой шаг.
6. **Билд тестировщика сверять с HEAD before deploy** — иначе исправленные баги ловятся повторно.

### Re-audit findings (коммит `677811c`)

Ре-аудит в той же сессии (после внедрения vault-workflow) обнаружил, что первый коммит `85b7c91` решил **симптомы**, но не **корни**:

| Проблема | Гипотеза в `85b7c91` | Реальная причина (найдена в логах) | Закрыто в `677811c` |
|----------|----------------------|-----------------------------------|--------------------|
| Close 1-2 of N | REQUOTE/INVALID_PRICE | `TRADE_RETCODE_NO_PRICES (10021)` — у DooTechnology XAUUSD при быстром движении котировки временно недоступны 1-2 сек. 10021 НЕ был в `_RETRYABLE`. Также `closed_count` врал — позиция могла закрыться по SL параллельно (race), но MT5 вернул не-DONE → counter не учёл | ✅ 10021 в retryable, 10044 (POSITION_CLOSED) как success, re-scan по `ticket` после fail, `max_retries=5` для close |
| Лот неточен | `round(_,2)` теряет младший разряд | XAUUSD `volume_step=0.01` → старый код корректен. Реальная причина: `scalping.py:687` ставит `last_lot_raw = lot_next_raw` **ДО** execute → при fail мартингейл-drift | ✅ snapshot/restore `last_lot_raw` при failed execute |
| profit_fixing_direction | Только UX-label | + бонус-баг: при `updated=0` в `apply_sl_to_all` (все позиции уже имеют SL близкий к target) → `state.trail_sl` не обновляется → infinite re-activation loop | ✅ `_all_positions_already_at` helper — фиксируем trail_sl даже если updated=0 |
| Фантомы | Single stale/orphan | `scanner.find_pending_order()` возвращает **первый** — multi-pending остаётся фантомным | ✅ engine.start обходит ВСЕ pending, adopt самый свежий, остальные TRADE_ACTION_REMOVE |

### Lessons learned (для будущих incidents)

1. **Симптом не равен root cause.** Гипотезу про retcode подтверждай **по реальным логам**, не предполагай. Я предположил INVALID_PRICE — в логах был NO_PRICES. Без vault-workflow я бы закрыл сессию на `85b7c91` думая что всё ок.
2. **Счётчик успехов должен отражать реальность, а не return value.** Если позиция реально закрыта (любым способом), counter инкрементируется. Иначе UI и тестировщик видят ложь.
3. **`_RETRYABLE` нужно проверять при каждом новом брокере.** У DooTechnology появился 10021 — у других брокеров могут быть другие коды (например, Pepperstone иногда возвращает 10006). Это не статичный набор.
4. **Snapshot/restore паттерн для state перед side-effects.** Любое поле state, изменяемое до execute, должно откатываться при fail. Иначе drift накапливается тихо.
5. **`updated == 0` — двусмысленность.** Различать «не было что менять» (все позиции на месте — фактически активация) и «ошибка/нет позиций» (не активация). Phantom-cases дают первое.
6. **Vault-workflow реально работает.** Первый коммит был сделан без `runbook-vault-integration`. Ре-аудит — после внедрения hooks/memory. Найдено что иначе было бы упущено.

### Связано с

- [[auragrid]] — MOC проекта
- [[auragrid-log-analysis]] — методология чтения desktop.log
- [[auragrid-trading-core]] — close_channel / lot calc / profit_trailing
- [[runbook-vault-integration]] — workflow, который дал ре-аудит

---

## Incident 2026-05-22 (раунд 4) — Analytics module: окно открывается, но 90% snapshot null

**Status:** diagnosed, fix pending (next session)
**Severity:** S2 (модуль фактически не работает с пользовательской точки зрения, но не блокирует торговлю)

### Symptom

Пользователь сообщил: в последней версии (1.0.1, HEAD `677811c`) раздел Analytics + расчёт риска стратегии не работает. Окно открывается, отображаются только Spread и торговая Session, остальное — прочерки.

### Investigation

Открыты файлы:
- UI: [Analytics/index.tsx](auragrid/desktop/src/pages/Analytics/index.tsx), [PresetEval/DeploymentTableModal.tsx](auragrid/desktop/src/pages/PresetEval/DeploymentTableModal.tsx), [RiskMeter.tsx](auragrid/desktop/src/components/RiskMeter.tsx) — ожидают 12 секций snapshot
- Backend: [manager.py](auragrid/python/bot/analytics/manager.py), [snapshot_builder.py](auragrid/python/bot/analytics/snapshot_builder.py), [indicator_pipeline.py](auragrid/python/bot/analytics/indicator_pipeline.py), [calendar.py](auragrid/python/bot/analytics/calendar.py)
- Логи: `desktop.log.2026-05-21:15823-15920`

### Root cause (три каскадных)

1. **`symbol_not_found`** — analytics-процесс (отдельный) не нашёл XAUUSD в `mt5.symbols_get()`. Candidates захардкожены в `resolve_symbol`. Buffers empty → `recompute_indicators` all-None → каскад null'ов во всём snapshot.
2. **MT5 calendar API mismatch** — `mt5.calendar_event_by_currency()` отсутствует, exception обработан в try/except, но `calendar_upcoming` всегда `[]`. Известно с раунда 1 как открытый вопрос, не закрыт.
3. **M15 buffer не реализован** — `tfs_to_backfill` в [manager.py:445](auragrid/python/bot/analytics/manager.py#L445) включает только `{primary_tf, H1, D1}`. M15 объявлен в конфиге, используется в [snapshot_builder.py:438](auragrid/python/bot/analytics/snapshot_builder.py#L438), [levels.py:820](auragrid/python/bot/analytics/levels.py#L820), [indicator_pipeline.py:73](auragrid/python/bot/analytics/indicator_pipeline.py#L73), но никогда не заполняется. Блокирует DeploymentTable (расчёт риска стратегии) даже при работающем символе.

### Почему Spread+Sessions показываются

- Spread: `build_spread_block` отдаёт структуру с нулями даже при `symbol=None`; live spread приходит отдельным каналом `useAnalyticsSubscription.lastTick`, не зависит от `build_snapshot`.
- Sessions: чисто UTC-вычисление, не зависит ни от MT5, ни от символа.

### Misdiagnosis (фиксируем для следующих сессий)

- Первичный agent-обзор кода считал, что calendar refresh «обработан корректно с graceful degradation» и не блокирует snapshot. Это **верно для логики** (snapshot не падает), но **неверно для UX** — пользователь видит пустой календарь и думает «не работает».
- Логи-agent предположил, что calendar exception блокирует весь pipeline. Это неверно — try/except есть.
- Реальная корневая ситуация: каждый блок независимо не получает данных, и UI получает «частичный» snapshot с большинством полей null.

### Сопутствующие проблемы

- **Конкуренция за `bot.log`** между analytics и ботом → PermissionError на ротации (×6400 в логе тестировщика). Известно с раунда 1.
- **IPC connect refused** в логе UI на старте — race-condition стартапа, не баг.

### Что не делалось (план)

Фиксы не применены, пользователь запросил только **оценку состояния**. План на следующую сессию:
1. Расширить symbol resolution + degraded-mode UI badge.
2. Добавить M15 в backfill + recompute.
3. Подключить calendar CSV fallback.
4. Сепарировать лог-файлы.
5. Добавить e2e smoke-тест «snapshot после 10s имеет ≥10 непустых секций».

### Prevention

1. **Каждый второй python-процесс с отдельным MT5-инстансом — отдельный риск отказа.** Не предполагать, что если основной бот работает, то и analytics работает.
2. **Конфиг и реальный pipeline должны быть в sync.** M15 объявлен в analytics_config.yaml — должен заполняться и считаться.
3. **Hardcoded списки candidates ломаются при онбординге нового брокера.** Symbol должен идти из BotConfig.mt5.symbol + variants, а не из жёсткого списка.
4. **Пустой snapshot должен сигнализироваться в UI, не показываться прочерками.** Пользователь не отличит «грузится» от «сломано».
5. **Smoke-теста «модуль работает end-to-end» нет.** Unit-тесты зелёные, прод не работает — классический gap. Перед релизом — обязательная проверка реального snapshot.

### Связано с

- [[auragrid-analytics-module]] — состояние модуля и архитектура
- [[auragrid-trading-core]] — отдельный процесс, не пересекается
- [[auragrid-log-analysis]] — как читать analytics-секцию логов
- [[runbook-vault-integration]] — workflow, который дал эту диагностику
