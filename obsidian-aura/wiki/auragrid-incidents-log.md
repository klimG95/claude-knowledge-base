---
type: incident-log
tags: [auragrid, incidents, operations]
created: 2026-05-22
updated: 2026-06-04
---

# AuraGrid — Incidents log

Журнал инцидентов проекта AuraGrid. Новые записи добавляются сверху. Формат раздела — [[templates/template-incident]].

**Правила:**
- Запись делается в момент диагностики, не пост-фактум
- Если инцидент → фикс закрыт коммитом, обязательно линковать SHA
- Секция Prevention важнее остальных — это материал для будущих агентов

---

## 2026-06-04 (часть 3) — demo-валидация финального MSI по живым логам: ✅ торговля корректна (НЕ инцидент)

**Status:** validated — PASSED. Закрывает «требует demo-валидации» для PR #36/#37 (Grid + Bug B). Это НЕ инцидент: первоначально ошибочно заподозрил «тихую смерть бота», но пользователь подтвердил — **стратегию остановил он сам вручную**. Запись оставлена как (а) положительный результат валидации, (б) методологический урок про ложную диагностику.

**Контекст:** пользователь поставил ФИНАЛЬНУЮ продаваемую сборку (`fix/shelve-perf-restore-stability`, PR #37), окно `aura-desktop` поднято непрерывно с **18:58:56 устройства (=10:59Z =13:59 терминала, брокер UTC+3)**. Просьба: досконально проверить логи, корректно ли всё работает с защитой. Это и есть та demo-валидация, которую требовали части 1 и 2.

**Метод:** PHASE 1 vault → `%APPDATA%\Aura\logs\` (ребренд → папка `Aura`, НЕ `GridScalp`; старые GridScalp-логи до 30.05 — мусор). Авторитетные живые логи: `desktop.log.2026-06-04` (24k строк, Tauri+bridge), `20260001/bot.log` (Grid, активная стратегия), `20260002/bot.log` (Impulse, простаивал). Top-level `bot.log` ЗАГРЯЗНЁН pytest-артефактами (temp-пути `pytest-of-Administrator`, `err="disk full"` Traceback = тестовая симуляция) — для живого анализа НЕ использовать. Разбор desktop+Grid делегирован 2 параллельным агентам, живое состояние — прямыми PowerShell-проверками.

**Что подтвердилось ХОРОШЕГО (защита/торговля корректны):**
1. **Защита/лицензия чисто.** Tauri `  ERROR ` = 0, Traceback/panic/stderr = 0. `activate: ok` ×3 (activation_id=3, expiry 2026-06-19, HWID 4edfe8aa), `license_heartbeat interval=1800s`. Unauthorized/ban/revoke/tamper/signature = 0. «401/403» в grep = ложные (подстроки в timestamp `.403Z`/`on_tick_max_ms=403`, НЕ HTTP). **Защита торговлю/лицензию/IPC не сломала.**
2. **Grid торговал корректно весь день** (07:02–11:27, ~116 тикетов): `profit_trail_sl_set` ×168 монотонны (SL никогда не двигался в убыток), `channel_reset_after_close` ×50 (здоровое циклирование), `pending_ticket_synced_after_loss` ×8 (анти-фантомная синхра работает), `pending_ticket_adopted_on_start` = 0, `trade_retries_exhausted` = 0. Прежние баги (фантомы / неработающие SL / незакрытие) НЕ воспроизвелись.
3. **Bug B (часть 1) подтверждён исправленным НА ЖИВОМ:** Impulse-storm `trade_retries_exhausted` 3261→**0**, `impulse_pending_modify_failed` → нет. Заморозки loop из-за ретраев market-closed больше нет.
4. **17× retcode 10016 «Invalid stops» + 6× 10029 + 2× 10036** (`trade_non_retryable`, action=6, модификация корзинного SL) — **безвредны**: построчная проверка каждого тикета показала, что позиция либо УЖЕ была защищена прежним успешным `profit_trail_sl_set`, либо в этот же миг (<0.3с) закрывалась (`partial_close`/`channel_reset`/10036 «position doesn't exist»). Ни одна позиция без SL по вине отказа НЕ осталась. Это рыночный шум ужесточения SL корзины золота при широком спреде. `scalp_*_spread_abnormal` ×602 = корректная фильтрация входа при спреде 61–140 при буфере 20.

**Остановка в 11:27:39Z — РУЧНАЯ (подтверждено пользователем), НЕ сбой:**
- Изначально заподозрил «тихую смерть»: бот перестал писать после нормального `scalp_trail_moved` (BUY ticket 1994263022), далее только IPC reconnect-loop; на момент проверки (20:03) `python.exe` нет, `aura-desktop` (PID 8692) и `terminal64` живы.
- **Пользователь подтвердил: стратегию завершил он сам.** Reconnect-loop при открытом окне после ручного стопа — НОРМА (так же выглядели дневные паузы 73/57/77 мин между перезапусками). Отсутствие `connection lost magic=20260001` объясняется тем, что websocket к Grid на момент стопа уже был в reconnect-состоянии (в 11:27:30-42 connect-failed на 8765 шли вперемешку) — «терять» было нечего. Открытые позиции после ручного стопа не обслуживаются — это ожидаемо и было волей пользователя.

**Урок (методологический, на будущее):**
- **Не диагностировать «креш» без позитивного доказательства краха.** Отсутствие маркера ≠ сбой. Прежде чем бить тревогу о «тихой смерти», учесть штатный сценарий «пользователь остановил стратегию». Tauri-bridge НЕ логирует exit-code дочернего python-процесса → ручной стоп и реальный креш по логам неотличимы. Это слепое пятно реально (кандидат на мелкую доработку: логировать код выхода бота + явный маркер причины), но само по себе НЕ инцидент.
- **«Окно открыто» ≠ «бот торгует»** — при проверке живого состояния смотреть `Get-Process python` + хвост magic-дир `bot.log`, а не только наличие окна. (Полезно и осталось верным.)
- **Top-level `%APPDATA%\Aura\logs\bot.log` загрязнён pytest-прогонами** (эта же машина — dev/build): temp-пути `pytest-of-Administrator`, `err="disk full"` Traceback = тестовая симуляция. Для живого анализа брать ТОЛЬКО magic-диры (`20260001`/`20260002`) + desktop.log.

**Итог demo-валидации:** Grid + Bug B (market-closed storm) = **PASSED на живом рынке**. Защита/лицензия/IPC — чисто. Impulse-торговля сегодня почти не шла (1 активация, без сделок) → live-валидация Bug A/C для Impulse ещё НЕ закрыта.

**Связано с:**
- [[auragrid-log-analysis]] — методология (дополнить: «Get-Process + magic-дир, top-level bot.log загрязнён тестами»)
- [[auragrid-python-embed-packaging]] — кандидатная причина нативного тихого выхода
- части 1 и 2 ниже — фиксы, чью demo-валидацию закрывает эта запись (частично)
- journal `2026-06-04.md` (Часть 3)

---

## 2026-06-04 (часть 2) — perf-рефакторинг: регрессии торгового цикла на живом рынке → откат Ярусов 0–2

**Status:** diagnosed + reverted (коммит `18f18eb`, PR #37). **Требует demo-валидации** пересобранного MSI.

**Симптом (пользователь):** «Это не тот результат что был (до защиты). Расстояние между сеткой не всегда больше минимального. Софт стал работать сильно медленнее, появился лаг. При закрытии по кнопке стопы ставятся по чуть-чуть, а не все сразу. Трейлинг очень медленный.»

**Диагностика:**
1. Запущенная сборка **содержит perf-рефакторинг** (`poll_heartbeat` несёт perf-поля `ticks_skipped`/`on_tick_p50_ms`/`persist_writes` — их добавил Ярус 0). Подтверждено.
2. **git blame:** код сетки (`scalping.py`/`conservative_grid.py`), трейлинга (`profit_trailing.py`), скальпинга — **НЕ менялся**. Менялись только: темп `on_tick` (дедуп тиков, Ярус 1, [main.py]), чтение позиций (`scanner.scan_all`, Ярус 2b), персистентность (Ярус 2a), async-логи (Ярус 2c).
3. **Механизм регрессий:** дедуп тиков (Ярус 1) гейтит `on_tick` → **операции по тику выполняются реже** = медленный трейлинг, закрытие «по чуть-чуть» (close-all обрабатывается порциями по тикам), общий лаг. Изменённый `scan_all` (Ярус 2b: один `positions_get`, локальное деление по magic/type) влияет на чтение состояния сетки → неверный спейсинг. Логи в логах: Grid p99 `on_tick` до 178мс, грид-ордера местами в 13–40pts при минимуме ~100.

**Root cause:** perf-рефакторинг (2026-05-30, Ярусы 0–2,4) делался ради ИСХОДНОЙ жалобы пользователя на лаги на ультраволатильном рынке, но на живом рынке дал **обратный эффект** (медленнее + новые регрессии) и **никогда не валидировался вживую** — [[auragrid-performance-strategy]] сам многократно предупреждал, что корректность нельзя верифицировать без живого MT5 и требует ручного прогона на волатильной сессии (не сделан). pytest на fake-MT5 был зелёным, но не покрывал реальный темп тиков/закрытия.

**Resolution (`18f18eb`):** откат **5 торговых ярусов** (0,1,2a,2b,2c) к checkpoint `461904b` (известно-стабильный hot path). Ярус 4 (UI throttle `cc9453f`) НЕ трогали (к торговым жалобам не относится). Защита (Фаза 2/6) и Impulse-фиксы (`62694f3`) сохранены (другие файлы).
- Детерминированно: `engine.py`/`main.py`/`scanner.py`/`persistence.py`/`channel.py`/`logging.py` восстановлены из `461904b` + переналожен Aura-нейминг (пути `%APPDATA%/Aura/logs`, `AURA_DATA_DIR`, `AURA_SYMBOL` сохранены). Verify: `git diff 461904b` по ним = **только нейминг** (логика == 461904b). Удалены `perfmetrics.py` + `test_perf_*.py`. safety-grep: ничего вне набора не зависит от удалённых perf-API.
- Verify: bot **1309 passed** (0 fail/err).

**Prevention:**
- **Hot-path perf-оптимизации НЕЛЬЗЯ шиповать без живой/demo валидации.** pytest на fake-MT5 не воспроизводит реальный темп тиков/закрытия/брокер. [[auragrid-performance-strategy]] это знал (инвариант про живой MT5) — но Ярусы 0–2 ушли в продаваемую сборку без ручного прогона на волатильной сессии. Урок: «pytest зелёный» ≠ «можно в продакшен» для hot-path/concurrency/order-execution.
- **Дедуп тиков опасен для per-tick семантики.** Любая оптимизация, меняющая ЧАСТОТУ `on_tick`, ломает операции, которые неявно полагались на «каждый тик» (трейл, close-all порциями, управление сеткой). При следующем заходе на perf — расцеплять «частоту обработки рынка» от «частоты обслуживания команд/трейла».
- **Симптом «после новой версии» → сверять git blame, а не корреляцию.** Дважды за день: пользователь винил защиту, blame показывал другое (Impulse-баги / perf). Защита оба раза невиновна.
- **Откат должен сохранять нейминг.** Восстановление файлов из старого checkpoint затирает ребренд → обязательно переналожить (пути логов/env — функциональны).

**Связано с:**
- [[auragrid-performance-strategy]] — откаченные ярусы (status обновлён: reverted из продаваемой сборки)
- [[auragrid-checkpoint-2026-05-30-pre-restructure]] — `461904b`, база отката (для чего и создавалась)
- [[auragrid-protection-strategy]] — защита (снова доказано невиновна)
- Коммит `18f18eb` (PR #37, ветка `fix/shelve-perf-restore-stability` — полная продаваемая сборка)

---

## 2026-06-04 — AuraImpulse: «фантомные сделки / неработающие SL / не закрытие по кнопке» на живом XAU (3 латентных бага)

**Status:** diagnosed + fixed (коммит `62694f3`, PR #36). **Требует demo-валидации** (order-execution фиксы; fake-MT5 не воспроизводит брокер).

**Симптом (пользователь):** «После сборки и установки новой версии — множество багов: фантомные сделки, неработающие стоплосы, не закрытие по кнопке и др. Нужно чтобы софт работал с защитой.» Подразумевалось подозрение на защиту (Фаза 2/6).

**Диагностика по живым логам** (`%APPDATA%\Aura\logs\`, magic-дирами: `20260001`=Grid, `20260002`=Impulse; 06-02…06-04):
1. **Grid здоров** (`profit_trail_sl_set`, `channel_reset_after_close`, `ingest_ok`) — баги только в Impulse.
2. Частоты Impulse за 2 дня: `impulse_pending_modify_failed` 3261, `trade_retries_exhausted` 3261, `trade_retry` 6522. Распределение retcode: **10018 (market closed) ×9783**, 10016 (invalid stops) ×2, 10029 ×3.
3. `poll_heartbeat`: `on_tick_p50_ms` 0.47 (норма после perf), но **p99 253-333мс, max 464-513мс** — петля замирала.
4. **git blame:** `impulse.py`/`executor.py`/`validation.py` не менялись после checkpoint `461904b` (только rebrand-нейминг `f538658`). → **защита и perf-рефакторинг НЕВИНОВНЫ**; баги латентные, в самой стратегии Impulse, проявились на волатильном XAU у DooTechnology.

**Root cause (3 бага):**
- **Bug B (доминанта):** `TRADE_RETCODE_MARKET_CLOSED` (10018) был в `_RETRYABLE` ([executor.py]). Дневной перерыв сессии XAU → каждый pending-modify ретраился 3×0.2с = **0.6с заморозки event loop**, ×9783. Это «окно не отвечает / кнопка закрытия не срабатывает / хаотичные ордера». Закрытый рынок не откроется за 0.6с — ретрай бессмысленен.
- **Bug A:** refined initial SL отвергался брокером с 10016 «Invalid stops» (дистанция от ТЕКУЩЕЙ цены внутри freeze-level на волатильности, хотя от entry = `sl_distance_pts`). Позиция НЕ без защиты (pending открывается с pre-fill SL, шире — `_place_pending` sl=`sl_distance+PRE_FILL_SL_BUFFER`), но `state.initial_sl/trail_sl` всё равно писались в проваленное желаемое → trail считал от несуществующего уровня, его modify'и тоже отклонялись.
- **Bug C:** сервер отвергал telemetry `mode="IMPULSE"` (Pydantic `ModeName=Literal["SCALP","CG"]` + колонка `String(5)`) → 422, **вся телеметрия Impulse дропалась** (`ingest_4xx_drop`).

**Resolution (`62694f3`):**
- Bug B: `MARKET_CLOSED` убран из `_RETRYABLE` ([executor.py]); движок повторит операцию на следующих тиках при открытии рынка. `NO_PRICES` остаётся retryable (транзиентный, важен для закрытия). Тест `test_market_closed_returns_immediately_without_retry_sleep`.
- Bug A: при отказе set'а держим `state` согласованным с фактическим брокерским SL (`effective_sl = current_sl`); лог `position_unprotected` если SL==0 ([impulse.py::_on_position_opened]). Тест `test_initial_sl_set_failure_keeps_state_consistent_with_broker`.
- Bug C: `ModeName += "IMPULSE"`, колонка `String(16)`, миграция `0007_impulse_mode` (Postgres ALTER, SQLite no-op — длина не enforced; MV от `mode` не зависит). Тест `test_ingest_accepts_impulse_mode`.
- Попутно: `tests/integration/conftest.py` `JWT_SECRET_KEY`→≥32 — **регрессия Фазы 6** (floor 8→32 валил 11 integration + 12 admin_bot errors; пропущена, т.к. после Фазы 6 прогонялся только server-набор, не полный bot).
- Verify: bot **1328 passed**, server **237 passed**, 0 fail/err.

**Prevention:**
- **MARKET_CLOSED ≠ retryable.** Ретраить устойчивые состояния (рынок закрыт, торговля запрещена по символу) — антипаттерн: морозит loop без шанса на успех. Retryable = только транзиентные (REQUOTE, NO_PRICES). Пересмотреть и `TRADE_DISABLED`/`NO_MONEY` в `_RETRYABLE` при следующем заходе — тоже сомнительны.
- **fake-MT5 не воспроизводит брокер.** stops_level/freeze-level/session XAU у DooTechnology — источник 10016/10018. pytest зелёный ≠ корректность на живом рынке. **Любой order-execution фикс → обязательная demo-валидация** перед боевым. См. [[auragrid-performance-strategy]] инвариант про живой MT5.
- **При смене серверного контракта (floor/Literal/длина колонки) — прогонять ПОЛНЫЙ bot-набор, не только server.** Bot integration-тесты (`tests/integration/`) спинят серверный `Settings`/app и ловят такие регрессии; server-набор их не покрывает. Урок: коммит Фазы 6 заявил «python/bot не затронут» — неверно.
- **Симптом ≠ причина:** «после новой версии» → подозрение на последнее изменение (защита), но git blame показал, что торговый код не менялся. Всегда сверять blame затронутого кода с baseline, а не доверять корреляции по времени.

**Связано с:**
- [[auragrid-impulse-strategy]] — стратегия; [[adr-004-impulse-adaptive-distance]] — adaptive pending (источник modify-цикла)
- [[auragrid-protection-strategy]] — защита (доказано: невиновна в этом инциденте)
- [[auragrid-log-analysis]] — методология (magic-диры, retcode-распределение, poll_heartbeat)
- Коммит `62694f3` (PR #36, ветка `protect/anti-piracy`)

---

## 2026-05-28 — AuraImpulse adaptive distance: вечный warmup из-за пропущенного метода в MT5Connection

**Status:** diagnosed + fixed в той же сессии.

**Симптом (пользователь):** «Запустил тест на данном устройстве. По итогу прогрев ни к чему не приводит. Стратегия не стартует.»

**Диагностика (5 минут):**
1. `bot.log` для impulse-стратегии (magic 20260001, `%APPDATA%\GridScalp\logs\20260001\bot.log`):
   ```
   "event": "impulse_engine_started", "mode": "watching", ...
   "event": "impulse_dynamic_distance_warmup", "reason": "no_copy_rates_api"
   ```
   `no_copy_rates_api` — это branch в `_refresh_dynamic_distance`: `getattr(self.deps.client, "copy_rates_from_pos", None) is None`.
2. Проверка `bot/mt5/connection.py` (прод-клиент `MT5Connection`) — он явно делегирует только методы из `MT5Client` Protocol, существовавшие до этой сессии: `initialize`, `symbol_info`, `symbol_info_tick`, `positions_get`, `orders_get`, `order_send`, `order_check`, `history_deals_get`. **`copy_rates_from_pos` я добавил в Protocol + FakeMT5Client, но забыл прокинуть через `MT5Connection`.** Каждый тик `_refresh_dynamic_distance` фиксировал warmup → pending'и не выставлялись никогда.

**Root cause:** dual implementation (FakeMT5Client для тестов + MT5Connection для прода) без compile-time проверки полноты Protocol на стороне MT5Connection. Тесты на impulse (108 passed) использовали fake, прод-клиент не покрывался → пропуск.

**Resolution (коммит `0bab2c7`):**
- `bot/mt5/connection.py::MT5Connection.copy_rates_from_pos` — добавлен метод, делегирует пакету `MetaTrader5` + нормализует результат. Реальный пакет возвращает `numpy structured array` (доступ через `r['time']`), нормализуем в `tuple[SimpleNamespace]` — engine работает единообразно на fake и проде.
- Возвращаем `None` если результат пустой/None — engine трактует как warmup без падения.
- Tests: 3 новых в `test_connection_and_main.py` — `test_copy_rates_from_pos_normalizes_numpy_structured_array` (мок numpy.void через класс с `__getitem__` без `.time`), `test_copy_rates_from_pos_returns_none_when_no_history`, `test_copy_rates_from_pos_returns_none_on_empty_result`. Полная impulse suite (108 тестов) — passed.

**Prevention:**
- **Каждое добавление метода в `MT5Client` Protocol — обязательно одновременно в `FakeMT5Client` И в `MT5Connection`.** Это два места, оба обязательные.
- Идея: type-checker (mypy/pyright) с `runtime_checkable` Protocol на `MT5Client` мог бы поймать недостающие методы в `MT5Connection`. Но Python Protocol — структурный, mypy не требует explicit `class MT5Connection(MT5Client)`. Workaround — explicit assertion в тестах: `assert isinstance(MT5Connection(symbol="X"), MT5Client)` поймал бы недостающий метод (Protocol проверяет наличие, не сигнатуру).
- Записать в [[feedback_external_api_defense]]? Уже похожий урок про hasattr-guard перед циклом — но это про другой кейс. Здесь — про **симметрию fake/prod при расширении интерфейса**. Достаточно фиксации здесь.

**Связано с:**
- Реализация adaptive distance: [[adr-004-impulse-adaptive-distance]] + [[auragrid-impulse-strategy]] раздел «Доработка 2026-05-28 (вторая)»
- Коммит в `klimG95/auragrid` — `0bab2c7` (запушен в `origin/main`)

---

## 2026-05-26 — Аудит Analytics: 4 системных бага в данных snapshot

**Status:** diagnosed (утро) → **implemented (вечер)**. Фикс закрыт PR/коммитом, см. Resolution ниже.

**Resolution (2026-05-26, реализация по TZ_ANALYTICS_INTEGRITY_v1.0, SHA `fb67723`):**
- **Закрыты все 4 P0 + 2 P1.** Реализация атомарным PR по §7 чек-листу ТЗ:
  - P0 #2 (`fetcher.py:92` `start_pos=0 → 1`) — backfill только закрытыми барами.
  - P0 #1 (`manager._bar_close_loop` multi-TF) — polling по всем TF из `self.buffers` (primary first), `event=bar_close_detected` логируется per TF.
  - P0 #3 (`session_vol_ratio` + warm-up) — новая сигнатура `(atr, last_close_h1, profile, hour)`, обе стороны в |log-return|; `compute_intraday_vol_profile` с warm-up gate `min_obs_per_hour=3` → 3-5 дней наполнения, до этого `None`; `RollingBuffer.last_close()` добавлен.
  - P0 #4.1 (spread median) — `deque(maxlen=86400)` вместо `list[-7200:]`, `np.median` вместо `sum/len`, warm-up < 60 → `None`.
  - P0 #4.2 (swap_today) — `total_swap_of_positions(mt5.positions_get(symbol))` вместо хардкода `0.0`.
  - P0 #4.3 (ticks dedup) — `TickRateTracker.record(tick_time_msc=...)` с защитой от повтора msc; единая точка вызова — `_tick_loop` (дублирующий вызов из `build_spread_block` удалён); `sample_spread_with_prices` теперь возвращает `time_msc` 5-м tuple-полем.
  - P1 #5 (`strategy_context_registered`) — поле в `system_status` + желтый Alert в Analytics UI + Tooltip на «ATR/PD M15».
  - P1 #6 (regime gate) — `push()` в `RegimeStabilizer` строго на «фронте» bar_close через `_indicators_recomputed_this_tick`.
- **TS UI:** session_vol_ratio cap ≥99 → «99+×» + `console.warn`; Median 24h tooltip; SystemStatus.strategy_context_registered поле; SpreadBlock.median_24h_pt теперь `number | null`.
- **Тесты:** 1278 passed (+25 новых: 11 acceptance `test_integrity_acceptance.py` §2.7, 3 multi-TF/backfill `test_integrity_backfill_and_multi_tf.py`, +11 в обновлённых `test_volatility*.py` / `test_spread.py`). Регрессии 0.
- **Build:** `tsc --noEmit && vite build` — без ошибок.
- **Docs:** добавлен `docs/qa/scenarios/analytics_smoke.md` (manual cross-validation ATR Analytics vs MT5 Δ<2%, spread block sanity, SVR warm-up, strategy_context Alert).
- **Manual cross-validation на тестовом MT5 — отложена пользователю (см. analytics_smoke §1):** acceptance Δ ATR < 2 % на D1/H1/M5 после установки нового MSI.

**Что НЕ изменилось (по ADR-001 Surgical):** архитектура (отдельный python-процесс + IPC порт 8770), IPC схема (имена полей `atr_h1`, `session_vol_ratio`, `median_24h_pt` сохранены), config_version yaml, unblock-фиксы 2026-05-22 (symbol resolution, M15 buffer, CSV calendar, log rotation, system_status).

---

**Триггер:** Пользователь подтвердил «модуль аналитики впервые заработал» после fix'ов 2026-05-22 и попросил верифицировать параметры через внешние источники. Ручная сверка ATR(14) на XAUUSD.N через MT5-indicator выявила расхождения по трём TF (D1 +4.24%, H1 **+48.67%**, M5 +13.37%) → переход на полный аудит кода.

**Метод:** PHASE 1 vault → параллельно три Agent-сессии по направлениям (Indicators / Sessions+Spread+Regime / Buffers+M15-pipeline). Каждый агент прочитал 12-15 файлов и нашёл `path:line` для findings.

**Найдено — 4 P0 системных бага:**

1. **Stale buffers (M15/H1/D1 не обновляются после старта).** `python/bot/analytics/manager.py:653-697` (`_bar_close_loop`) polls только `self._primary_tf`. Прочие буферы заморожены на момент `_backfill()`. Влияет на: ATR H1/D1, ADX H1, BBW H1, Parkinson D1, GK D1, Realized D1, intraday_vol_profile. Объясняет ATR H1 +48.67%.

2. **Backfill включает формирующийся бар.** `python/bot/analytics/fetcher.py:92` — `copy_rates_from_pos(symbol, native_tf, 0, bars_needed)`. Стартовая позиция `0` = текущий незакрытый бар (для контраста: `detect_bar_close` в `fetcher.py:230` явно использует `1` с комментарием «1 = последний закрытый»). Wilder seed ATR отравлен этим частичным баром. Объясняет ATR M5 +13.37% и часть D1 +4.24%.

3. **`session_vol_ratio` структурно неверная формула.** `python/bot/analytics/volatility.py:94` — `safe_div(atr_h1_current, baseline, default=0.0)`. Размерностное несоответствие: ATR в цене (~$15) делится на |log-return| (~0.0013) → мусор. Сверка: 15.12 / 0.0013 ≈ 11630 ≈ наблюдаемое **11573.39× ANOMALY** в виджете Sessions.

4. **Spread block: 3 ложных метрики.** `python/bot/analytics/snapshot_builder.py:399,406`:
   - «Median 24h» = `sum/len` (mean, не median); окно ~2h при 1Hz sampling, не 24h.
   - «Swap today» = хардкод `0.0`; `total_swap_of_positions` существует в `spread.py:117-124`, но не вызывается.
   - «Ticks/sec» = polling rate (10.5 ≈ 10Hz tick_loop + 1Hz snapshot), не реальный тик-поток; нет дедупликации по `tick.time_msc`.

**P1 (улучшения диагностики, не дефекты данных):**

- **«ATR/PD M15 = —» это by-design.** Поле в UI — не `atr_m15`, а ratio `atr_m15 / (PriceDistance × point)` (`volatility.py:33-45`). Требует registered `StrategyContext` (`snapshot_builder.py:321,329`). Если стратегия не RUNNING — ratio = None → UI «—». Асимметрия UI: `atr_to_pd_ratio_h1` и `atr_to_cg_pd_ratio_h1` тоже None, но в виджете не показаны — пользователь видит только M15-прочерк и думает что это локальный баг.
- **Regime hysteresis работает на snapshot-ticks, не bar-closes.** `snapshot_builder.py:363` — `_regime_stabilizer.push()` на каждом ~1Hz snapshot. Конфиг `hysteresis_bars_per_tf=3` подразумевает «3 бара», по факту 3 секунды. Гистерезис эффективно отключён.

**Что НЕ баг (подтверждено аудитом):**
- CHAOS — корректный fallback по `regime.py:93` при `adx_h1=21.2` (выше 20) и `er_primary ≤ 0.4` (mixed signals).
- Sessions Active=NY, формула UTC-окон корректна (`sessions.py:27-32`).
- Spread Current=24pt сам по себе корректен (только база сравнения сломана).
- Календарь CSV fallback — ожидаемо (фикс 2026-05-22 живёт).
- M15 fix 2026-05-22 живёт — `Timeframe.M15` в `tfs_to_backfill` (`manager.py:570`), M15-блок в `indicator_pipeline.py:217-226`, тесты `test_b3_decompose.py` + `test_manager_backfill_m15.py` зелёные.

**Сводка по ~20 параметрам UI:** 4 системных бага влияют на 13+ значений. Полная таблица — в [[2026-05-26]] и в auto-memory `reference_analytics_audit_2026_05_26`.

**Что НЕ сломалось:** unblock от 2026-05-22 не регрессировал — symbol resolution (heuristic), M15-buffer (наличие в `tfs_to_backfill`), CSV calendar fallback, log rotation guard, system_status snapshot field. Эти fix'ы живы. Обнаруженные баги — это другой пласт (формулы и обновление данных, а не доступность).

**Prevention:**
- При следующих manual-проверках Analytics — сразу сверять через MT5-indicator на том же символе (не TradingView; разница котировок XAUUSD.N vs OANDA маскирует баги). См. [[2026-05-26]] описание метода.
- Cross-check ATR Analytics vs MT5 на одинаковых барах должен войти в acceptance до релиза Analytics-фиксов.
- При добавлении новых производных метрик («ratio», «ratio vs baseline») — проверять размерности обеих сторон до коммита. `safe_div` не защищает от unit mismatch.

**Источники:** [[2026-05-26]] (детальный аудит 3-х направлений), auto-memory `reference_analytics_audit_2026_05_26` (приоритезированный реестр + конкретные `path:line`), [[auragrid-analytics-module]] (обновлено блоком «Аудит 2026-05-26»).

**Roadmap фикса:** `auragrid/docs/tz/TZ_ANALYTICS_INTEGRITY_v1.0.md` создан 2026-05-26 (вторая фаза сессии) — реализационный документ по образцу TZ_TRAIL_REWORK_v1.0.md. Атомарный PR со всеми 4 P0 + 2 P1 + acceptance numerical example (§2.7) + manual cross-validation ATR Δ<2% (§6.5). Реализация — отдельной сессией по §7 чек-листу.

---

## След решения 2026-05-25 (аудит) — независимая верификация AuraImpulse v1.0

**Status:** audit completed — реализация соответствует отчёту, дефектов не найдено, есть список улучшений.
**Тип записи:** не инцидент — независимый пост-имплементационный аудит 4-й сессии 2026-05-25. Поднял отдельным сеансом, чтобы дать второй взгляд на ~660 строк нового ImpulseEngine, IPC/Rust/UI-диспатч и vault PHASE 3.

**Метод:** PHASE 1 vault → построчная сверка отчёта с кодом по 12 направлениям §9 ТЗ → запуск `pytest --collect-only` (1272 теста собрано — точное совпадение с заявленными 1253+1+16+2), явный прогон 84 impulse-тестов (зелёные), `cargo check` (8 pre-existing warnings, 0 новых), `npm run build` (bundle 722.31 kB — точно как в отчёте).

**Подтверждено:**
- Все fast-path заявления — присутствуют в коде: pre-fill SL в pending request, точный SLTP после fill, `_save_if_dirty` гард, trail БЕЗ `spread_buffer`, gap-handling в `_find_my_position`.
- Pydantic dispatch через `_select_config_class` корректен; backward-compat AuraGrid через default `strategy_type="auragrid"` сохранён; `extra="forbid"` симметрично у обоих корневых моделей.
- IPC polymorphism через `isinstance(engine, ImpulseEngine)` — 7 точек диспатча (pause/pause_all/close_channel/close_all/get_status/reset_stopped/get_snapshot).
- Rust `StrategyEntry.strategy_type` через `#[serde(default)]`; функции `create_impulse`/`override_config_impulse`/`known_impulse_presets`; `clone_strategy` сохраняет type источника; export/import обрабатывают секцию `impulse`.
- UI Step2 Radio + Step3EditorImpulse (13 полей) + бейджи `[AuraImpulse]`/`[AuraGrid]` + dispatch в WizardShell и StrategyPanel.
- vault PHASE 3 в стиле ADR-001 (Surgical): концептуальная [[auragrid-impulse-strategy]] и [[adr-003-impulse-strategy-new-preset-type]] не переписаны — реализация им соответствует.

**Найденные неточности отчёта (не баги в коде):**
- Число тестов: в отчёте 79, реально **84** (parametrize в `test_impulse_config.py` даёт 35 эффективных при 18 функциях).
- Pre-flight инвариантов в `Step3EditorImpulse` — **9**, не 10 (отсутствует `spread_buffer >= 0`). Pydantic это всё равно поймает на бэке, но клиент увидит ошибку медленнее.
- `GeneralImpulseConfig.magic_number` имеет default `20260002` (не упомянуто в отчёте); `impulse_default.yaml` — template для Rust override, грузить напрямую через `load_config()` нельзя (нет license_key/mt5/ipc — в QA-сценарии не подсвечено).

**Список рекомендаций** (13 пунктов, 3 критичных + 5 средних + 5 низких) — в [[2026-05-25]] раздел «Аудит AuraImpulse v1.0 (5-я сессия)» и в auto-memory `reference_impulse_audit_2026_05_25.md`. Критичные перед раздачей пользователю: (R1) воспроизвести 1253 passed в чистой среде с сохранением лога; (R2) Manual QA по `docs/qa/scenarios/impulse_lifecycle.md` на fake-MT5; (R3) pre-flight `tauri build --bundles msi` на dev-машине до передачи тестировщику.

**Что не сломалось:** независимая верификация подтвердила исходный отчёт. Сильные стороны реализации — двойная отправка SL (окно беззащитности = 0), `_make_pending_refresher` для slippage-гигиены, детерминированная gap-сортировка по `(time_msc, time, ticket)`, унифицированный UX-сигнал «блокировка» через `max_loss_hit` alias.

**Источники:** [[2026-05-25]] раздел «Аудит» (детальное прохождение и список рекомендаций), [[auragrid-impulse-strategy]] (концепция — не менялась), [[adr-003-impulse-strategy-new-preset-type]] (архитектурное решение — все 7 Verify-критериев подтверждены аудитом), auto-memory `reference_impulse_audit_2026_05_25` (приоритезированный список действий).

---

## След решения 2026-05-25 — TZ TRAIL_REWORK v1.0: переработка трейлинга

**Status:** designed → implemented → tested (атомарный PR одного дня).
**Тип записи:** не инцидент — намеренное архитектурное решение, оформленное как ADR-002. Запись здесь — указатель «почему изменилась формула трейлинга после 2026-05-25», чтобы будущие сессии не искали в commit log.

**Что изменилось:**
- Удалены `scalping.pending_order_offset` и `conservative_grid.pending_order_offset` из BotConfig (`extra="forbid"` → старые yaml отвергаются).
- Семантика `trail_size` / `trail_update_distance` (и `_profit`-вариантов) изменена: `trail_size` — удалённость, `trail_update_distance` — частота. Порог пересчёта = `trail_size + trail_update_distance`.
- Триггер первого выставления pending: `|цена − last_open| ≥ current_step + trail_size` (вариант B с overshoot); pending встаёт ровно на `current_step` пт от `last_open_price`.
- Снят инвариант `trail_update_distance_profit > trail_size_profit`; заменён на `trail_update_distance > 0` и `trail_update_distance_profit > 0`.
- `config_version` 1 → 2, миграция yaml — жёсткое отвержение с `IncompatibleConfigVersionError` + понятным сообщением.

**Источники:** [[adr-002-trail-rework-mq5-parity-departure]] (контекст + миграция), `auragrid/docs/tz/TZ_TRAIL_REWORK_v1.0.md` (детали по слоям), [[2026-05-25]] (хронология сессии), [[auragrid-trading-settings]] / [[auragrid-trading-core]] (обновлённые wiki).

**Что не сломалось:** 696/696 pytest зелёные, npm build OK, cargo check OK. Manual smoke acceptance — закрыт `python/tests/test_trail_rework_acceptance.py` (численный пример ТЗ §2.5 для SELL и BUY).

**Чек-лист для будущих сессий:** при следующем релизе MSI тестировщик обязан **пересоздать все стратегии через UI** (или удалить `%APPDATA%\GridScalp\strategies\`). Семантика trail-параметров поменялась — старые значения переносить вручную нельзя, геометрия сетки и пороги пересчёта будут другими.

---

## Incident 2026-05-22 (раунд 7) — Analytics P1 Calendar + P2 Logs + P2 e2e: финиш unblock

**Status:** resolved — все 6 приоритетов unblock закрыты.
**Severity:** S2 (UX deception — календарь молча пустой; defensive — лог-конкуренция; preventive — отсутствие e2e smoke)

### Symptom

После P0 (раунд 5) + P1 M15 (раунд 6) остались три неисправленных пункта из assessment'а раунда 4:
1. **Calendar** — `mt5.calendar_event_by_currency` отсутствует в установленной MetaTrader5 → 25180 AttributeError × 10 часов, виджет календаря пуст без объяснения.
2. **Лог-конкуренция** — 6368 WinError 32 при ротации `bot.log`.
3. **Integration smoke gap** — unit-тесты зелёные, прод не работает (классический gap, не было e2e через WS).

### Resolution

**P1 Calendar:**
- `EconomicCalendar` принимает `csv_fallback_path`. `refresh()` сначала проверяет `hasattr(mt5, "calendar_*")` — если нет, сразу `[]` (нет 25k AttributeError). При пустом MT5 → CSV fallback c фильтрами window/currencies/min_importance. `last_source ∈ {mt5, csv, none}`.
- Default `bot/analytics/data/economic_calendar.csv` положен в дистрибутив (5 примеров событий, формат ForexFactory).
- Manager wiring: `cal_cfg.csv_fallback_path` resolve'ится к bundled CSV если null.
- Snapshot `system_status.calendar_source` публикуется. UI: жёлтый Alert при CSV, оранжевый при none.

**P2 Лог-конкуренция:**
- `_JSONRotatingHandler.emit` ловит `PermissionError`/`OSError` от `doRollover` → `rolloverAt += 3600`, продолжаем писать. Запись не теряется. (Базовый кейс bot.log vs analytics.log уже был решён `log_name="analytics"` в раунде A.4 — раздельные файлы; защита остаётся для antivirus/tail-индексаторов.)

**P2 Integration smoke e2e:**
- `tests/analytics/test_manager_smoke.py::test_manager_e2e_indicators_nonempty` — fixture `mt5_online` с валидным symbol_info + copy_rates_from_pos (60 баров). Тест поднимает manager, шлёт `analytics.get_snapshot` через WS, asserts `system_status.symbol_resolved=True`, `indicators.atr_primary/atr_m15/atr_h1 != None`.

**Попутно (feedback_fix_found_bugs):**
- `snapshot_builder.snapshot_buf` использовал несуществующие `buf.size()` / `buf.snapshot()` — pre-existing bug ломал snapshot_loop при `levels.enabled=True` с непустыми буферами. Online-mock e2e сразу высветил. Заменил на `len(buf)` / `buf.get_df()`. Без этого фикса всё остальное unblock не работало бы end-to-end.

Тесты: pytest 1157/1157, vitest 24/24, tsc чисто. Journal: [[2026-05-22-analytics-p1-calendar-and-finish]].

### Prevention

- **`hasattr` guard перед циклом** для опциональных API внешней библиотеки. Try/except внутри for-loop не защищает от шума в логе (вызов всё равно происходит N раз). Pattern: `if not hasattr(mt5, "foo"): log_warning(...); return []` сверху.
- **Online-mock e2e — обязателен для модулей, зависящих от внешнего API.** Это последний рубеж между unit-зелёным и прод-сломанным. Стандарт: mock MT5 (или другой API) с валидным минимумом данных → проверка двух-трёх ключевых полей snapshot/response через настоящий WS.
- **Defensive logging на ротацию.** PermissionError на `doRollover` — типичный Windows-кейс. Skip-rollover-and-retry лучше чем потеря записи.
- **System_status — стандартное место degraded-status.** Все P0/P1/P2 fix'ы сошлись на одном паттерне: добавить ключ в `snapshot.system_status` + Alert в UI. Будущие источники данных пойдут так же.

### Commits

В рамках сессии (см. git log).

---

## Incident 2026-05-22 (раунд 6) — Analytics P1: M15 buffer + atr_m15 → DeploymentTable

**Status:** resolved (бэк + тесты, UI не требует правок)
**Severity:** S2 (catastrophically заниженная оценка риска в DeploymentTable — ATR=0)

### Symptom

После P0-фикса (раунд 5) symbol резолвится, snapshot не пустой, но кнопка DeploymentTable оставалась с риском ≈ 0 — `deployInputs.atr_m15 ?? 0` падал на 0, потому что `atr_m15 = None` (нет M15 buffer). Эффект: pre-trade оценка max-loss за час показывала катастрофически малые цифры.

### Resolution

Двухстрочный fix:
1. `Timeframe.M15` добавлен в `tfs_to_backfill` ([manager.py](auragrid/python/bot/analytics/manager.py)) — buffer заполняется на старте, buffer_sizes.M15=2880 (≈30 дней).
2. После H1-блока в `recompute_indicators` ([indicator_pipeline.py](auragrid/python/bot/analytics/indicator_pipeline.py)) добавлен M15-блок: `compute_atr(df, n=14)` при `len(m15_buf) >= 14`.

UI/snapshot_builder/levels/preset_eval — ничего не правится. Все потребители уже корректно читали `m._last_indicators.get("atr_m15")` и `snapshot_buf(Timeframe.M15)`, ждали только источник данных.

Тесты: 3 кейса в `TestIndicatorPipeline` (warm/short/missing) + новый `test_manager_backfill_m15.py` (M15 в запросах backfill). pytest 1151/1151.

Журнал: [[2026-05-22-analytics-p1-m15-buffer]]. Деталь fix-секции — в [[auragrid-analytics-module]] корневая причина №3.

### Prevention

- **Schema-first архитектура окупается на расширениях.** `atr_m15` был объявлен в `empty_indicators()` и корректно потреблялся четырьмя модулями ДО реализации источника. Поэтому fix был 5-строчным — не пришлось менять контракты. **Лучшая практика для будущих TF / индикаторов:** сначала добавляй ключ в schema + потребителей с `?? None`/`?? 0`, потом — источник.
- **Backfill ≠ live update.** В analytics-процессе bar_close_loop детектит close только primary TF. H1/D1/M15 буферы — снимок на старте, stale через несколько часов. Не блокирует UX, но при долгих uptimes ATR M15 устаревает. Future scope: bar_close detection для всех refTF.
- **Тестировать TF-блоки в pipeline по шаблону 3 кейсов.** `warm` (буфер ≥ N), `short` (буфер < N), `missing` (буфер отсутствует) — стандарт для проверки независимости блоков. Применять для H4, W1 и future-индикаторов.

### Commits

В рамках сессии (см. git log).

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
