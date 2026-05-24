# Changelog — журнал изменений базы знаний

Записи добавляются сверху вниз, от новых к старым. После каждой рабочей сессии — новая запись с датой `## YYYY-MM-DD` и пунктами о том, что обработано, что создано/обновлено, какие связи установлены. Правила — в [[AGENTS]].

---

## 2026-05-25

### TZ TRAIL_REWORK v1.0 — переработка логики трейлинга (атомарный PR)

- Реализовано внутрипроектное ТЗ `auragrid/docs/tz/TZ_TRAIL_REWORK_v1.0.md`: ломающее изменение схемы пресета (`config_version` 1 → 2), удалены поля `scalping.pending_order_offset` и `conservative_grid.pending_order_offset`, изменена семантика `trail_size` / `trail_update_distance` (теперь это «удалённость» и «частота»). Универсальная формула трейлинга — `threshold = trail_size + trail_update_distance` — применяется к четырём трейлингам (scalp pending, CG pending, scalp profit-SL, CG profit-SL).
- Создан [[adr-002-trail-rework-mq5-parity-departure]] — Status: accepted. Намеренный отход от MQL5-эталона по этому параметру. Контекст, миграция yaml у клиентов (жёсткое отвержение + понятное сообщение), verify-критерии.
- [[auragrid-trading-settings]] — переписаны разделы про trail/pending параметры (#9, #18-19, #22-23, #27, #29-30, #35-36), TL;DR-блок с TZ-предупреждением, сводка валидаций (новые `trail_update*>0`, снят старый model-инвариант), анти-паттерны #3. Сохранены Surgical-правила: общие разделы не тронуты. `updated: 2026-05-25`.
- [[auragrid-trading-core]] — добавлен раздел «Универсальная формула трейлинга» с триггером первого выставления (вариант B с overshoot) + универсальным трейлингом + сравнением с MQL5-эталоном. `updated: 2026-05-25`.
- [[auragrid-incidents-log]] — добавлен «след решения» 2026-05-25 (не инцидент, а указатель на ADR-002 для будущих сессий).
- [[index]] — добавлена ссылка на adr-002.
- Journal — [[2026-05-25]].
- Auto-memory — указатель на adr-002 добавлен.
- Реализация в auragrid-репо: 56 файлов (pydantic + Python ядро + аналитика + симулятор + UI + Rust + yaml-пресеты + тесты + qa-docs + tools). Acceptance — `python/tests/test_trail_rework_acceptance.py` закрепляет численный пример ТЗ §2.5 для SELL/BUY. Pytest 696/696 ✅, npm build ✅, cargo check ✅.

---

## 2026-05-24

### Каталог торговых настроек AuraGrid (PHASE 1 перед оптимизацией)

- Создана wiki [[auragrid-trading-settings]] — исчерпывающий справочник по 36 редактируемым параметрам торгового пресета (general/scalping/conservative_grid/notifications + торговая часть mt5.symbol) + служебные поля. По каждому: yaml-имя, тип, валидация, назначение, ключевое место использования, UI label/описание.
- Сводка валидаций (13 правил pydantic) + «потенциальные дыры» (поля без явной валидации — кандидаты на оптимизацию).
- Раздел про поведение редактирования (Step3Editor + apply_params live-restart + клиентский pre-flight инвариантов).
- Анти-паттерны (7 пунктов: не редактировать magic, не путать max_loss и max_scalp_loss, cg.spread_buffer отсутствует, секреты mt5 не в файле пресета и т.д.).
- [[auragrid]] MOC — ссылка добавлена в раздел «Операционные знания».
- [[index]] — ссылка добавлена в раздел «Компоненты AuraGrid».
- Auto-memory — указатель `reference_trading_settings` добавлен.
- Цель — заполнить пробел перед сессией оптимизации и отладки настроек торговли.

### Интеграция принципов Карпатого в методологию vault'а (ADR-001)

- Создан [[adr-001-surgical-minimal-vault-updates]] — первый ADR в vault'е. Status: accepted. Решение: точечно интегрировать два из четырёх принципов Карпатого (Surgical Changes, Simplicity First); «Think Before Coding» не добавлять (конфликт с [[feedback_technical_autonomy]]); «Goal-Driven Execution» применить к PHASE 3 runbook'а как verify-критерии.
- Источник анализа — репо [multica-ai/andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills).
- [[AGENTS]] — добавлены два раздела перед «Принципы, которые объединяют всё вышесказанное»:
  - **«Минимализм правок» (Surgical updates)** — менять только то, что относится к текущей задаче; не «улучшать» соседние формулировки; стилистические правки — отдельной сессией под триггером «ревизия».
  - **«Минимализм структуры» (Simplicity First)** — никаких спекулятивных секций/шаблонов/страниц «на будущее»; шаблон возникает после 2-3 однотипных страниц, а не до.
- [[runbook-vault-integration]] — PHASE 3 расширена подразделом **«Verify (явные критерии завершения)»**: битые `[[ссылки]]` = 0, `index.md` синхронизирован, `CHANGELOG.md` содержит запись, `journal/YYYY-MM-DD.md` существует, frontmatter валиден, auto-memory указатель добавлен при появлении ссылочного эталона.
- [[index]] — добавлен новый раздел «ADR» со ссылкой на adr-001.
- Journal — [[2026-05-24]].
- Ретроспективно существующие страницы не правятся (по принципу Surgical из самого ADR); новые правила применяются к будущей работе.

---

## 2026-05-22

### 🚩 Большой чекпоинт — «Analytics unblocked» (baseline для отката)

- Создана wiki [[auragrid-checkpoint-2026-05-22-analytics-unblocked]] с полным описанием состояния и инструкцией rollback.
- Git tags `checkpoint/2026-05-22-analytics-unblocked` поставлены в `klimG95/auragrid` (на `6e39ca8`) и `klimG95/claude-knowledge-base` (на `730e51b`).
- Это первый стабильный baseline после серии релизных фиксов (раунды 1-3) и полного analytics unblock (раунды 5-7). На него возвращаемся, если новые изменения создадут регрессию, которая не чинится быстро.
- Состояние модулей, тестов, и known limitations — в самой checkpoint-странице.

### Раунд 7 — Финиш Analytics unblock: P1 Calendar + P2 Logs + P2 e2e smoke

- **P1 Calendar** ([calendar.py](auragrid/python/bot/analytics/calendar.py) + [manager.py](auragrid/python/bot/analytics/manager.py)):
  - `EconomicCalendar` принимает `csv_fallback_path`; `refresh()` сначала проверяет `hasattr(mt5, "calendar_*")` (anti-25k-AttributeError-pattern), затем MT5, при пустом результате — CSV fallback. `last_source` ∈ {mt5, csv, none}.
  - Default `bot/analytics/data/economic_calendar.csv` положен в дистрибутив (5 примеров событий, формат ForexFactory).
  - Manager wiring: cal_cfg.csv_fallback_path → bundled CSV если null.
  - `analytics_config.yaml`: `calendar.csv_fallback_path: null` с комментарием.
  - Snapshot: `system_status.calendar_source`.
  - UI: жёлтый Alert при "csv", оранжевый при "none" (`Analytics/index.tsx` + `useAnalyticsSubscription.ts`).
- **P2 Лог-конкуренция** ([bot/utils/logging.py:_JSONRotatingHandler](auragrid/python/bot/utils/logging.py)): emit ловит `PermissionError`/`OSError` от `doRollover`, сдвигает `rolloverAt += 3600`, продолжает писать в текущий файл. Запись не теряется.
- **P2 e2e smoke** ([tests/analytics/test_manager_smoke.py](auragrid/python/tests/analytics/test_manager_smoke.py)): новый fixture `mt5_online` (валидный symbol_info + copy_rates_from_pos 60 баров) + `test_manager_e2e_indicators_nonempty` — поднимает manager, через WS get_snapshot проверяет `symbol_resolved=True` + `indicators.atr_primary/atr_m15/atr_h1 != None`. Закрывает gap «unit зелёные, прод сломан».
- **Попутно** ([[feedback_fix_found_bugs]]): pre-existing bug в `snapshot_builder.snapshot_buf` — `buf.size()`/`buf.snapshot()` не существуют у RollingBuffer, ломали snapshot_loop при `levels.enabled=True`. Заменил на `len(buf)`/`buf.get_df()`. Online-mock e2e сразу нашёл.
- **Тесты**: 4 новых для calendar fallback + 1 для rollover-safe + 1 e2e smoke. pytest 1157/1157, vitest 24/24, tsc чисто.
- **Vault**: [[auragrid-analytics-module]] — корневая причина №2 (calendar) FIXED, «Лог-конкуренция» FIXED, все 6 приоритетов ✅ DONE; TL;DR обновлён. [[auragrid-incidents-log]] — incident раунд 7. Journal — [[2026-05-22-analytics-p1-calendar-and-finish]].
- **Урок**: «hasattr guard перед циклом» = anti-25k-AttributeError pattern; online-mock e2e обязателен для модулей с внешним API; system_status — стандартное место для degraded-status badge.
- **Итог 5→6→7**: все 6 приоритетов unblock закрыты за 3 раунда одного дня. Модуль готов к ручной верификации на тестовом MT5-аккаунте.

### Раунд 6 — Analytics P1: M15 buffer + atr_m15 → DeploymentTable

- **Бэк** ([manager.py](auragrid/python/bot/analytics/manager.py) + [indicator_pipeline.py](auragrid/python/bot/analytics/indicator_pipeline.py)):
  - `tfs_to_backfill` теперь включает `Timeframe.M15` — buffer заполняется на старте (buffer_sizes.M15 = 2880, ~30 дней).
  - В `recompute_indicators` после H1-блока добавлен M15-блок: `compute_atr(df, n=14)` при `len(m15_buf) >= 14`. Минимально — atr_m15 единственный потребитель из schema.
- **UI/snapshot/levels/preset_eval** — без правок. Все потребители уже корректно читали atr_m15 / snapshot_buf(M15), ждали только источник данных. После P1 кнопка DeploymentTable активируется автоматически.
- **Тесты**: 3 новых кейса `TestIndicatorPipeline` (warm/short/missing) + новый файл `tests/analytics/test_manager_backfill_m15.py` (M15 в запросах backfill). pytest 1151/1151.
- **Vault**: [[auragrid-analytics-module]] — корневая причина №3 помечена FIXED, P1-M15 ✅ DONE в Приоритетах, TL;DR и component-таблица обновлены. [[auragrid-incidents-log]] — incident раунд 6. Journal — [[2026-05-22-analytics-p1-m15-buffer]].
- **Урок**: schema-first архитектура (atr_m15 был в schema + потребителях ДО источника) → fix 5-строчный без правки контрактов. Применять для будущих TF и индикаторов.

### Раунд 5 — Analytics P0: Symbol resolution unblock (бэкенд + UI + тесты)

- **Бэк** ([mt5_client.py:107](auragrid/python/bot/analytics/mt5_client.py#L107) + [manager.py](auragrid/python/bot/analytics/manager.py)):
  - `resolve_symbol(candidates, *, heuristic_tokens=None)` — добавлен heuristic fallback через `mt5.symbols_get()` с поиском имени, содержащего ВСЕ tokens case-insensitively. Source последней резолюции: `candidates`/`heuristic`/`none` пишется в `MT5Client.last_resolve_source`.
  - `AnalyticsManager._build_symbol_candidates` — динамическая сборка: base из `analytics_config.yaml` + `mt5.symbol` из каждого `<APPDATA>/GridScalp/strategies/*.yaml` + 11 типовых broker-suffix вариантов (`.s/.m/.pro/.c/.i/.raw/.x/x/pro/_i`). Дубли удаляются с сохранением порядка.
  - `analytics_config.yaml` — новый ключ `system.symbol_heuristic_tokens: [XAU, USD]`.
  - В `start()` и `_mt5_health_loop()` (reconnect path) вызов `resolve_symbol` передаёт `heuristic_tokens` + обновляет `manager.symbol_resolved/symbol_source`.
- **Snapshot** ([snapshot_builder.py](auragrid/python/bot/analytics/snapshot_builder.py)): добавлен блок `system_status: {symbol_resolved, symbol_source, symbol_tried, mt5_connected}`.
- **UI** ([Analytics/index.tsx](auragrid/desktop/src/pages/Analytics/index.tsx) + `useAnalyticsSubscription.ts`): два Alert-баннера — красный «символ не найден» (tried-список + инструкция) и жёлтый «найден через эвристику» (рекомендация дополнить config). Тип `SystemStatus` экспортирован из хука.
- **Тесты**: `tests/analytics/test_mt5_client.py::TestResolveSymbol` (6 кейсов) + `tests/analytics/test_manager_symbol_candidates.py` (7 кейсов). pytest 1147/1147 + vitest 24/24 + tsc чисто.
- **Попутно** ([[feedback_fix_found_bugs]]): добавлен `aiogram>=3.13` в `python/requirements-dev.txt` (pre-existing collection error в admin_bot integration tests, 16/16 после фикса); установлен pnpm + dependencies (TS ошибки `@tauri-apps/plugin-dialog` устранены).
- **Vault**: [[auragrid-analytics-module]] — TL;DR помечает P0 как fixed, fix-секция в №1 root cause, чек-листы P0/P2-badge помечены ✅ DONE. [[auragrid-incidents-log]] — incident 2026-05-22 раунд 5. Journal — [[2026-05-22-analytics-p0-symbol-resolution]].
- **Урок**: «hard-coded list + heuristic + UI degraded badge» — переиспользуемый паттерн для broker-specific конфигов. Snapshot `system_status` — точка расширения для P1/P2.

### Раунд 4 — комплексная оценка модуля Analytics + расчёт риска стратегии (без правок)

- Пользователь сообщил: окно Analytics + DeploymentTable не работают в HEAD `677811c` (релиз 1.0.1) — показываются только Spread + Sessions, остальное прочерки. Запрошена комплексная оценка для дальнейшего unblock'а.
- Диагностика по vault-workflow: Phase 1 контекст ([[auragrid]], [[auragrid-trading-core]], journal/2026-05-22, runbook). Phase 2 — два параллельных Agent'а (код + логи) дали разные диагнозы, личная верификация показала, что **реальная корневая причина третья: `symbol_not_found`** в логе `desktop.log.2026-05-21:15890` → `backfill_skipped_no_symbol` → buffers пустые → каскад null'ов во всём snapshot.
- Дополнительные слои: MT5 calendar API mismatch (известный issue, не пофикшен) + M15 buffer не реализован в `tfs_to_backfill` (блокирует DeploymentTable).
- Сопутствующие: лог-конкуренция bot.log между двумя процессами (PermissionError × 6400), IPC connect refused race на старте.
- Vault: создана [[auragrid-analytics-module]] — архитектура второго процесса + три root cause + статус секций + 6 приоритетов unblock'а. В [[auragrid-incidents-log]] добавлен Incident 2026-05-22 раунд 4 с Misdiagnosis/Prevention. `index.md` обновлён.
- **Фиксы не применены** — пользователь запросил только аудит. План на следующую сессию (P0-P2) — в [[auragrid-analytics-module]] секция «Приоритеты unblock».
- Урок: один agent ≠ истина. Два agent'а дали разные ответы, оба частично правы — реальность нашлась личной верификацией кода + лога.

### Инициализация vault для AuraGrid + фиксы релиза по логу тестировщика (раунд 1 + ре-аудит раунд 2)

- Анализ `desktop.log.2026-05-21` (тестировщик с ключом `6b03bdc5-…`): найдены 5 ручных багов + 3 проблемы из лога. Подробности — [[journal/2026-05-22|journal/2026-05-22]] и [[auragrid-incidents-log]].
- **Раунд 1** — коммит `85b7c91`: фиксы `protection.close_channel` (свежий tick + on_retry), `normalize_lot` (digits по volume_step), `engine.start` (sync pending_ticket с MT5), UI labels в Step3Editor.
- **Раунд 2 (ре-аудит через vault-workflow)** — коммит `677811c`: первый раунд закрыл UX, но не root cause. Реальный retcode `10021 NO_PRICES` (не INVALID_PRICE). Добавлены: `NO_PRICES`+`POSITION_CLOSED` в protocol, расширение `_RETRYABLE`, re-scan по ticket после fail, snapshot/restore `last_lot_raw` для anti-drift, фикс infinite re-activation в profit_trailing, multi-pending cleanup в engine.start.
- Vault: создано ядро страниц проекта AuraGrid — [[auragrid]] (MOC), [[auragrid-incidents-log]], [[auragrid-log-analysis]], [[auragrid-trading-core]], [[runbook-vault-integration]] (методологический runbook про обязательный workflow).
- `index.md` обновлён с новой структурой; `journal/2026-05-22.md` — детальная запись сессии (оба раунда).
- Auto-memory выверена под реальные vault-страницы (раньше указатели ссылались на ещё не созданные).
- Hooks: SessionStart + Stop в `~/.claude/settings.json` для механической принуды vault-workflow.
- **Главный урок:** vault-workflow окупился в этой же сессии — ре-аудит запущен пользователем благодаря новому workflow, и нашёл S1, которая иначе ушла бы в релиз.

### Раунд 3 — UX: close-as-trail, pause-keeps-trailing, Save/Load preset как файл

- **Close-кнопки (close_all / close_buy / close_sell)** теперь арят профит-трейлинг вместо мгновенного physical-close: SL=trail на текущей цене + дальше стандартная подтяжка. Реализация — `ProfitTrailer.arm_manual` + `Protection.arm_channel_trail`; IPC `CloseResult.armed_trail: bool`; UI модалки и нотификации переписаны.
- **Пауза** теперь блокирует только открытие новых ордеров и переход SCALP→CG; `profit_trailer.manage()` + reset/partial-close sync продолжают работать. В `engine.process_channel` guard `state.paused` перенесён с начала функции в середину (после блока 3 трейлинга).
- **Сохранение/загрузка пресета как отдельный файл**: Rust-функции `strategies::export_preset` / `import_preset` (исключают/мержат секретные поля), Tauri commands `strategy_export_preset` / `strategy_import_preset`, UI меню «Сохранить/Загрузить пресет в файл…» с system file-dialog через `@tauri-apps/plugin-dialog`.
- **Bonus fix** — `handle_start_bot` приведён к контракту §2.3+§5: при `engine.running=True` возвращает `error=bot_already_running` (раньше был «idempotent» комментарий без реального вызывающего → нарушение контракта).
- **Тесты**: полный pytest suite зелёный (1118 passed). Адаптированы 7 тестов под новый контракт `armed_trail` и pause-keeps-trailing. Pre-existing failing `test_start_bot_returns_already_running_when_engine_up` — починен попутно.
- Vault: дополнена [[auragrid-trading-core]] (разделы про arm_manual и про изменённый guard паузы), запись в [[journal/2026-05-22|journal/2026-05-22]] про раунд 3.
- Memory: добавлен `feedback_fix_found_bugs` — попутные баги чиню через полный цикл дебага, «pre-existing» не оправдание (правило выработано пользователем в этой сессии).

## 2026-XX-XX

### Установка пакета claude-knowledge-base

_Первая запись делается при установке агентом в рамках bootstrap._
