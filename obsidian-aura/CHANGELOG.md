# Changelog — журнал изменений базы знаний

Записи добавляются сверху вниз, от новых к старым. После каждой рабочей сессии — новая запись с датой `## YYYY-MM-DD` и пунктами о том, что обработано, что создано/обновлено, какие связи установлены. Правила — в [[AGENTS]].

---

## 2026-05-29

### Анализ логов AuraImpulse: пробел в логировании спреда

- Пользователь: «Какие были спреды в моменты сделок?» — на устройстве `bot.log` magic 20260001 за 28-29 мая. Две сделки 29 мая UTC (04:15 BUY @4503.75, 08:01 SELL @4520.90), обе закрыты внешне (трейл сработал).
- Главный вывод: **спред в моменты сделок из логов не восстанавливается**. Поле `spread` есть только в событии `impulse_spread_too_wide` (при отбое широкого спреда); таких событий за период — 0. В trade-events (`impulse_position_opened`, `impulse_pending_placed`, `impulse_initial_sl_set`, `impulse_trail_updated`) спред не сохраняется.
- [[auragrid-impulse-strategy]] — добавлен раздел «Пробелы логирования (для анализа постфактум)» с путём доработки (`spread_pts` в trade-events).
- journal [[2026-05-29]] — создан.
- Auto-memory: добавлен указатель `reference_impulse_log_spread_gap`.

---

## 2026-05-28

### AuraImpulse: прозрачность формулы среднего размера свечи (SHA `461904b`)

- Пользователь после Hotfix `0bab2c7`: «Всё работает, но касательно среднего я имел немного другое. Софт должен прикдывать, что есть 7 свечей — 100, 150, 130, 60, 80, 200, 100. Складывает все их и делит на 7. Это и будет дистанция, а далее коэффициент.» — это **точно та же формула**, что уже работает (`sum(high − low) / N × coefficient`). Путаница из-за того, что лог писал `avg_range_price=1.17` (в долларах), а пользователь думал в pts.
- Фикс — cosmetic: `_refresh_dynamic_distance` теперь считает размеры свечей сразу в pts (`sizes_pts: list[int]`), затем `sum/N × coef`. Арифметика идентична (±1 pt округление). Лог `impulse_dynamic_distance_updated` теперь содержит `avg_candle_size_pts` + `sizes_pts` (список размеров каждой свечи), вместо `avg_range_price` в долларах — можно глазами свериться с примером пользователя. Snapshot обогащён `avg_candle_size_pts`. UI plate в StrategyPanel: «Дистанция pending'а сейчас: N pts = средний размер свечи X pts (по N M1) × coef».
- Tests: 1305 → 1306 passed (+1 в `test_impulse_engine.py`). npm build OK.
- Wiki/ADR не правил — формула концептуально не меняется, только её визуализация (по [[adr-001-surgical-minimal-vault-updates]]).
- journal [[2026-05-28]] — пятый раздел.

### Hotfix AuraImpulse adaptive distance: пропущенный метод в MT5Connection (SHA `0bab2c7`)

- Пользователь после установки билда с ADR-004: «Прогрев ни к чему не приводит. Стратегия не стартует.»
- Диагностика через `bot.log` (magic 20260001): `impulse_dynamic_distance_warmup reason=no_copy_rates_api` сразу после `impulse_engine_started`. Корень: `MT5Connection.copy_rates_from_pos` не существует — в ADR-004 коммите я добавил метод в `MT5Client` Protocol и в `FakeMT5Client` (тесты), но забыл в прод-обёртке `bot/mt5/connection.py`. `getattr(client, "copy_rates_from_pos", None) is None` → engine навсегда в warmup → нет pending'ов.
- Сопутствующий gotcha: реальный пакет `MetaTrader5` возвращает `numpy structured array`, доступ через subscript (`r['time']`), а engine ожидает атрибуты (`bar.high`/`bar.low` — работает только для SimpleNamespace из fake). Фикс нормализует результат в `tuple[SimpleNamespace]` на границе с MT5 — engine работает единообразно.
- Resolution: `MT5Connection.copy_rates_from_pos` добавлен + нормализация + 3 новых теста в `test_connection_and_main.py` (мок `numpy.void` через класс с `__getitem__` без атрибутов, тесты на None и empty). Полная impulse suite 108/108 passed + 11 connection passed. Коммит `0bab2c7` запушен в `klimG95/auragrid`.
- [[auragrid-incidents-log]] — добавлен раздел 2026-05-28 с Resolution и Prevention («каждое добавление метода в MT5Client Protocol — одновременно в FakeMT5Client И в MT5Connection; Python Protocol структурный, mypy не ловит пропуск»).
- journal [[2026-05-28]] — добавлен четвёртый раздел (Hotfix).
- Wiki/ADR-004 не правил — концепция и архитектурное решение остались валидными, баг был чисто в реализации обёртки.
- **Тестировщику:** нужна новая сборка MSI с этим фиксом, после установки запустить impulse заново. На первом тике engine получит исторические M1 свечи через `copy_rates_from_pos` → выйдет из warmup мгновенно (если терминал уже подтянул историю на нужную глубину).

### AuraImpulse: adaptive distance v1.0 (ADR-004) — first_step → candle_count + distance_coefficient

- Пользовательский запрос после первой доработки cooldown UX: «Стратегия должна быть более гибкой и адаптивной к рынку. Две настройки — количество свечей и коэффициент дистанции (заменяет first_step). Дистанция = среднее (high-low) за N M1-свечей × коэффициент, пересчёт после закрытия каждой новой свечи. Также пол cooldown'а = candle_count минут. Приоритет — скорость.»
- Решение зафиксировано в [[adr-004-impulse-adaptive-distance]] (accepted): `impulse.first_step` удалён, добавлены `candle_count: int (≥1)` и `distance_coefficient: float (>0)`. Engine на каждой смене `last_bar_time` пересчитывает дистанцию через `copy_rates_from_pos(start_pos=1, count=N)` — start_pos=1 пропускает формирующуюся, берём только закрытые. Warmup-гейт: при истории < N pending'и не выставляются (и снимаются уже стоящие). Cooldown floor: `effective = max(cooldown_sec, candle_count*60)`. Snapshot обогащён 4 полями для UI (`current_first_step_pts`, `warmup`, `candle_count`, `distance_coefficient`).
- Производительность: кэш по `bar_time` означает один `copy_rates` в минуту вместо на каждый тик. Скорость горячего пути не страдает.
- `config_version` 2 → 3 (общий для AuraGrid и AuraImpulse; AuraGrid схема не менялась, но bump необходим). Bumped 14 yaml/templates/fixtures/test_data файлов + 2 Rust override-функции.
- Файлы кода: `python/bot/models/config.py` (поля + bump + сообщение), `python/bot/core/impulse.py` (методы `_refresh_dynamic_distance` + `_enter_warmup`, обновлены `_arm_cooldown` / `_manage_pendings` / `_place_pending` / `_modify_pending` / `_make_pending_refresher` / `snapshot()`), `python/bot/mt5/protocol.py` (`TIMEFRAME_M1` + `copy_rates_from_pos`), `python/bot/mt5/fake.py` (`set_rates`/`append_rate`/`copy_rates_from_pos`), `desktop/src-tauri/src/strategies.rs`, `desktop/src-tauri/presets/impulse_default.yaml`, `desktop/src/store/strategies.ts`, `desktop/src/pages/Wizard/Step3EditorImpulse.tsx`, `desktop/src/pages/Main/StrategyPanel.tsx`.
- Тесты: 1287 → **1302 passed** (+15: 13 в `test_impulse_engine.py` про адаптивную дистанцию/warmup/cooldown floor/bar-time кэш, 1 в `test_impulse_config.py` про rejection легаси `first_step`, +1 от обновления существующих). Регрессий 0. Существующие impulse тесты пересажены на `candle_count=1 + coef=1.0 + seeded avg_range=5.0` (эквивалент `first_step=500`). `test_impulse_full_lifecycle` перепроектирован под cooldown floor (cooldown=0 → factual cooldown=60 → ручной reset). cargo check Finished, npm run build OK (835 modules, 725 kB).
- Wiki: создан [[adr-004-impulse-adaptive-distance]] (accepted) + добавлен раздел реализации в [[auragrid-impulse-strategy]] («Доработка 2026-05-28 (вторая)»). [[index]] синхронизирован.
- journal [[2026-05-28]] — добавлен третий раздел про adaptive distance.

### AuraImpulse: ручной сброс cooldown + auto-cancel pending'ов на stop()

- Пользовательский баг-репорт после установки MSI 2026-05-28: после первой сделки таймер `cooldown_sec` зависает «навсегда» в восприятии пользователя — UI не показывает оставшееся время, а перезапуски/смена настроек cooldown не сбрасывают. Второй пункт: при остановке стратегии стоящие pending'и (BUY_STOP/SELL_STOP) остаются в MT5 и могут сработать без бота.
- Корень #1 (cooldown): UI вообще не парсил impulse-snapshot (нет `cooldown_seconds_remaining` в `Snapshot` interface) и не было метода `reset_cooldown` в `ImpulseEngine`. Был только `reset_stopped` (для halt после `min_account_balance`) — пользователь видел кнопку «Сбросить блокировку» только при equity-halt'е.
- Корень #2 (pending'и при stop): `ImpulseEngine.stop()` сохранял state и сбрасывал `running=False`, но pending'и в MT5 не трогал — без бота они могли сработать → позиция без двойной защиты SL/трейла.
- Фиксы:
  - `python/bot/core/impulse.py`: новый метод `ImpulseEngine.reset_cooldown()` (обнуляет `state.cooldown_until_ts`, симметрично существующему `reset_stopped`); расширен `stop()` для снятия обоих pending'ов перед `running=False` (открытая позиция остаётся — её SL уже в MT5, как и в AuraGrid).
  - `python/bot/ipc/protocol.py` + `handlers.py`: новый IPC-метод `reset_cooldown` (по аналогии с `reset_stopped` — унифицированная UX-команда, для AuraGrid no-op).
  - `desktop/src-tauri/src/lib.rs`: новый Tauri command `strategy_reset_cooldown`.
  - `desktop/src/store/strategies.ts`: `Snapshot.cooldown_seconds_remaining?: number` (optional — у AuraGrid отсутствует).
  - `desktop/src/pages/Main/StrategyPanel.tsx`: жёлтый Alert «Бот ждёт окончания паузы» с кнопкой «Снять с паузы» при `cooldown_seconds_remaining > 0` (только для импульса); пояснение в confirm-модалке Stop про авто-снятие pending'ов для импульса.
- Тесты: 1287 passed (baseline 1278 + 9 новых — 6 в `test_impulse_engine.py` про `reset_cooldown` и `stop()`, 3 в `test_impulse_ipc.py` про IPC-метод). Регрессий 0. cargo check OK; npm run build OK.
- Wiki: дополнен раздел реализации в [[auragrid-impulse-strategy]] (новый блок «Доработка 2026-05-28») — концепция/state machine без изменений, перечислены изменённые файлы.
- journal [[2026-05-28]] — добавлен раздел «Вторая часть сессии: cooldown UX».

### Релизный коммит AuraImpulse v1.0 + MSI uninstall (SHA `2c13f5b`)

- Пользователь подтвердил: «Последняя версия ПО была удачной, установлена и проверена. Нужен коммит и пуш».
- Атомарный релизный коммит `2c13f5b` (29 файлов, +5886 / −105) — объединяет две фичи 2-й и 4-й сессий 2026-05-25: AuraImpulse v1.0 + MSI uninstall с галочкой. `git push origin main`: `fb67723..2c13f5b` без конфликтов.
- Решение делать один коммит, а не два по фичам: `desktop/src-tauri/src/lib.rs` смешивает обе фичи в одном hunk (mod uninstall + два impulse-handler'а + смешанный invoke_handler), hunk-level split болезненный из non-interactive bash, а пользователь проверил обе фичи совокупно установкой MSI — атомарная единица доставки.
- Закрыто из [[reference_impulse_audit_2026_05_25]]: R3 (pre-flight MSI build не упал на новом коде) + R2 (manual smoke на dev-окружении пользователя подтверждает базовую работоспособность). R1 (clean-room 1253 passed) и R4-R13 остаются открытыми.
- Wiki не трогали по ADR-001 Surgical: обе фичи уже полностью описаны в [[auragrid-impulse-strategy]] / [[adr-003-impulse-strategy-new-preset-type]] / [[auragrid-msi-uninstall-cleanup]]. Релизный коммит не добавляет нового знания.
- journal [[2026-05-28]] создан.

---

## 2026-05-26

### Реализация TZ_ANALYTICS_INTEGRITY_v1.0 — атомарный PR (третья фаза, SHA `fb67723`)

- Пользователь поручил сразу же приступить к реализации после создания ТЗ: «Ты технический специалист, который будет заниматься доработкой. Продумай процесс реализации и приступай».
- Атомарный PR со всеми фиксами по §7 чек-листу ТЗ. Закрыто **4 P0 + 2 P1**:
  - P0 #1 `_bar_close_loop` polling all TFs; P0 #2 `fetcher.py:92` start_pos 0→1; P0 #3 `session_vol_ratio` dimension + warm-up gate 3 obs/hour; P0 #4.1 spread `deque(86400)` + `np.median`; P0 #4.2 `swap_today` из live MT5 positions; P0 #4.3 ticks dedup по `time_msc`; P1 #5 `strategy_context_registered` + UI Alert + Tooltip «ATR/PD M15»; P1 #6 regime push на «фронте» bar_close через `_indicators_recomputed_this_tick`.
- TypeScript: `SpreadBlock.median_24h_pt: number | null`; `SystemStatus.strategy_context_registered` поле; SVR cap ≥99 → «99+×» + console.warn outlier; Median 24h Tooltip.
- Тесты: 1278 passed (baseline 1253 + 25 новых: `test_integrity_acceptance.py` 11 субтестов §2.7 ТЗ + `test_integrity_backfill_and_multi_tf.py` 3 unit-кейса + 11 в обновлённых `test_volatility*.py` / `test_spread.py`). Регрессии 0.
- Build: `cd desktop && npm run build` — без ошибок.
- Docs: `auragrid/docs/qa/scenarios/analytics_smoke.md` — manual cross-validation ATR Δ<2% + spread sanity + SVR warm-up + Alert на отсутствие strategy_context.
- Surgical по ADR-001: имена IPC-полей snapshot не переименовываются, архитектура второго python-процесса + порт 8770 без изменений, config_version yaml без bump'а.
- [[auragrid-analytics-module]] — раздел «Реализация TZ_ANALYTICS_INTEGRITY_v1.0 — 2026-05-26 (вечер)» с таблицей фиксов; TL;DR с 🔴 на 🟢; tag `audit-findings → integrity-fixed`.
- [[auragrid-incidents-log]] — блок Resolution внутри 2026-05-26 секции; статус diagnosed → implemented.
- journal [[2026-05-26]] дополнен «Третья фаза — реализация».
- Auto-memory: `reference_analytics_audit_2026_05_26` помечен closed; `reference_analytics_module` снова отражает работающее состояние.
- **Открытое:** manual cross-validation на тестовом MT5 (Δ ATR <2%) — пользователю по `docs/qa/scenarios/analytics_smoke.md`. Не блокирует merge.

### ТЗ Analytics Integrity v1.0 (вторая фаза сессии)

- Пользователь выбрал вариант «сначала ТЗ, потом реализация» (по аналогии с TRAIL_REWORK / Impulse).
- Создан `auragrid/docs/tz/TZ_ANALYTICS_INTEGRITY_v1.0.md` — структурированный документ по образцу TZ_TRAIL_REWORK_v1.0.md.
- Покрывает 4 P0 + 2 P1 из аудита 2026-05-26 (см. ниже): §2.1-2.6 формулы «было/стало», §2.7 acceptance numerical example на 7 субтестах, §3 решения по дискуссионным вопросам, §4 изменения по 13 слоям, §5 backwards-compat (IPC additive), §6 Verify (10 пунктов вкл. manual cross-validation ATR Δ<2%), §7 14 этапов реализации, §8 риски/анти-паттерны.
- Ключевые решения: deque(maxlen=86400) вместо SQLite для spread history (проще); backend cap для session_vol_ratio — нет, только UI 99+×; warm-up gate 3 obs/hour для intraday profile; IPC ключи snapshot не переименовываем (Surgical).
- Реализация — отдельной сессией по §7 чек-листу. Атомарный PR со всеми фиксами + acceptance + vault capture.

### Аудит Analytics: 4 системных бага в данных snapshot

- Пользователь подтвердил, что Analytics впервые заработал после fix'ов 2026-05-22, попросил верификацию через внешние независимые источники истины. Начали с ручной сверки ATR на XAUUSD.N через MT5-indicator: три расхождения (D1 +4.24%, H1 **+48.67%**, M5 +13.37%) на трёх TF → пользователь перешёл к полному аудиту кода.
- Метод — параллельно три Agent-сессии: (1) Indicators — формулы ATR/ADX/ER/BBW/Hurst/Parkinson/GK/RV; (2) Sessions/Spread/Regime — корни аномалии «Vol vs hour-baseline = 11573.39×»; (3) Buffers/Pipeline — статус M15 buffer + UI-маппинг «ATR/PD M15» (прочерк).
- **Найдено 4 P0 системных бага:**
  - **#1 Stale buffers.** `manager.py:653-697` обновляет только primary TF. M15/H1/D1 буферы заморожены с момента `_backfill()`. Объясняет ATR H1 +48.67%, ADX/BBW/Parkinson/GK/RV «стейл».
  - **#2 Backfill включает формирующийся бар.** `fetcher.py:92` использует `copy_rates_from_pos(..., 0, N)` (должно быть `1` как в `detect_bar_close`). Wilder seed ATR отравлен. Объясняет ATR M5 +13.37%.
  - **#3 `session_vol_ratio` сломана.** `volatility.py:94` делит ATR в цене на |log-return| (размерностное несоответствие). Сверка: 15.12 / 0.0013 ≈ 11630 ≈ наблюдаемое 11573.39 в виджете.
  - **#4 Spread block: 3 ложных метрики.** «Median 24h» = mean при окне ~2h (`snapshot_builder.py:399`); «Swap today» = хардкод 0 (`snapshot_builder.py:406`); «Ticks/sec» = poll rate, не tick rate.
- **P1 находки:** «ATR/PD M15 = —» это by-design (ratio, требует registered StrategyContext); regime hysteresis работает на snapshot-ticks вместо bar-closes.
- **Не баг:** CHAOS режим — корректный fallback; Sessions Active формула корректна; M15 fix 2026-05-22 живёт без регрессии.
- Сводка: 4 системных бага влияют на 13+ из ~20 параметров UI. Полная таблица — в [[2026-05-26]] и в auto-memory `reference_analytics_audit_2026_05_26`.
- [[auragrid-incidents-log]] — новая запись «2026-05-26 — Аудит Analytics» сверху с конкретными `path:line` для каждого бага.
- [[auragrid-analytics-module]] — блок «Аудит 2026-05-26» в TL;DR + раздел «Что обнаружено» (Surgical по ADR-001: история unblock 2026-05-22 не переписана, аудит — отдельная добавка).
- Auto-memory: новый указатель `reference_analytics_audit_2026_05_26` с приоритезированным реестром, существующий `reference_analytics_module` обновлён («unblock закрыт, но обнаружены 4 P0»).

---

## 2026-05-25

### Аудит AuraImpulse v1.0 — независимая верификация реализации (5-я сессия)

- Пользователь поручил «полную проверку» отчёта о реализации 4-й сессии. Поднял отдельным сеансом для независимого взгляда.
- Метод — сверка отчёта с кодом по 12 направлениям §9 ТЗ + явный прогон 84 impulse-тестов (зелёные) + `pytest --collect-only` (1272 теста — точное совпадение с заявленными 1253+1+16+2) + `cargo check` (8 pre-existing, 0 новых) + `npm run build` (bundle 722.31 kB).
- **Вердикт:** реализация полностью соответствует отчёту, серьёзных дефектов не найдено. Все fast-path заявления подтверждены кодом: pre-fill SL в pending request, точный SLTP после fill, `_save_if_dirty` гард, trail БЕЗ `spread_buffer`, gap-handling. Backward-compat AuraGrid соблюдён, vault PHASE 3 в стиле ADR-001.
- Найдены 4 мелкие неточности в самом отчёте (не баги в коде): число тестов 79→84 (отчёт занижает), pre-flight 10→9 в Step3EditorImpulse (нет `spread_buffer >= 0`), невыделенный default `magic_number=20260002` в `GeneralImpulseConfig`, не указанная template-природа `impulse_default.yaml`.
- Список из **13 рекомендаций** (3 критичных перед раздачей пользователю + 5 средних + 5 низких) — детально в [[2026-05-25]] раздел «Аудит» и в auto-memory `reference_impulse_audit_2026_05_25`. Критичные: R1 — воспроизвести 1253 passed в чистой среде с сохранением лога; R2 — manual QA по `docs/qa/scenarios/impulse_lifecycle.md` на fake-MT5; R3 — pre-flight `tauri build --bundles msi` на dev-машине.
- [[auragrid-incidents-log]] — добавлен «След решения 2026-05-25 (аудит)» сверху, формат не-инцидента (как у TRAIL_REWORK ADR-002).
- Auto-memory — указатель `reference_impulse_audit_2026_05_25` (приоритезированный список 13 рекомендаций).

### AuraImpulse — полная реализация v1.0 (Python ядро + Rust + UI)

- Четвёртая сессия дня, реализация по `auragrid/docs/tz/TZ_IMPULSE_STRATEGY_v1.0.md` (11 этапов). Главный приоритет пользователя — **скорость работы для максимизации прибыли при импульсах** — зафиксирован двумя fast-path решениями: двойная отправка SL (pre-fill SL в request pending'а + точный modify после fill — окно беззащитности 0 на gap'ах) и `_dirty`-флаг для пропуска SQLite UPSERT на тиках без изменений.
- Python pydantic: расширен `BotConfig` discriminator-полем `strategy_type: Literal["auragrid"] = "auragrid"` (backward-compat для пресетов до TZ_IMPULSE); создан параллельный `AuraImpulseBotConfig` с `GeneralImpulseConfig` (4 поля, `min_account_balance` вместо `max_loss`) и `ImpulseConfig` (9 полей). `load_config`/`load_preset_file` диспатчат на правильный класс по `strategy_type` в yaml-dict (без discriminated union — простой и минимально-инвазивный для существующих тестов).
- Python state: dataclass `ImpulseState` в `python/bot/models/impulse_state.py`, SQLite таблица `impulse_state` (id=1, idempotent CREATE) + `save_/load_impulse_state` в `StateStore`. Cooldown переживает рестарт (wall clock `time.time()`), persistence-test закрепляет это.
- Python engine: `ImpulseEngine` в `python/bot/core/impulse.py` — FSM `WATCHING → TRADING → COOLDOWN → WATCHING`, сквозные guard'ы `stopped` и `min_account_balance` (по equity), gap-сценарий (две позиции на одном тике — оставить раннюю по time_msc, закрыть позднюю market), orphan adopt / stale clear при `start()`. IPC handlers: `manual_pause/manual_pause_all/manual_close_channel/manual_close_all/reset_stopped`.
- Engine dispatch: `main.py::build_engine` и `build_wiring` выбирают `ImpulseEngine` либо `Engine` по `isinstance(config, AuraImpulseBotConfig)`. `Wiring.engine` теперь `Any` (полиморфно). `_make_snapshot`, `_on_reconnect`, `start_wiring::paused_reset`, `Protection` создание — обёрнуты `isinstance`-проверками.
- IPC: добавлен метод `reset_stopped` в `KNOWN_METHODS`. `handle_pause_channel/pause_strategy/close_channel/close_all/get_status/get_snapshot` диспатчат на `ImpulseEngine` (polymorphism). Для AuraImpulse: `get_status.max_loss_hit = state.stopped` (унифицированный UX-сигнал), `get_snapshot` возвращает Impulse-shape (`strategy_type`, `mode`, `pending`, `position`, `cooldown_seconds_remaining`, `stopped`, `paused_buy/sell`, `account`).
- Rust `desktop/src-tauri/src/strategies.rs`: добавлено поле `strategy_type: String` в `StrategyEntry` (serde default = `"auragrid"` — backward-compat). Новый built-in template `presets/impulse_default.yaml`. Функции `create_impulse(...)`, `override_config_impulse(...)`, `known_impulse_presets()`. `clone_strategy` сохраняет type источника. `export_preset/import_preset` поддерживают секцию `impulse`. Tauri-команды `strategies_create_impulse` + `strategies_known_impulse_presets` зарегистрированы в `invoke_handler!`. `cargo check` — 8 pre-existing warnings, новых нет.
- UI React: `StrategyMeta.strategy_type?: "auragrid" | "auraimpulse"` (optional, default через serde). `Step2CreateStrategy` — Radio для выбора type перед формой (read-only после создания), `useEffect` перегружает список пресетов при смене type. Создан `Step3EditorImpulse.tsx` (13 полей, pre-flight инварианты совпадают с pydantic-валидаторами). `WizardShell` и `StrategyPanel` модалка edit — dispatch на `Step3EditorImpulse` по `strategy_type`. Бейдж `[AuraImpulse]` (Mantine Text c="grape") в шапке Strategy panel и в Editor. `npm run build` — без ошибок.
- Тесты: новые файлы — `test_impulse_config.py` (35 тестов pydantic + discriminator + extra="forbid" симметрично), `test_impulse_state_persistence.py` (9 тестов SQLite + cooldown survives restart), `test_impulse_engine.py` (22 unit-теста FSM, trail, gap, stopped, reset, snapshot), `test_impulse_acceptance.py` (3 теста — numeric example §2.9 для BUY + SELL зеркально + двойная отправка SL), `test_impulse_ipc.py` (10 тестов polymorphism handlers), `integration/test_impulse_lifecycle.py` (5 lifecycle тестов через `build_engine`). Полный pytest: **1253 passed, 1 skipped, 16 xfailed, 2 xpassed**. Регрессии AuraGrid — 0.
- Документация: создан `docs/qa/scenarios/impulse_lifecycle.md` (manual QA по §2.9 + anti-checklist 5 потенциальных багов). `AGENTS.md` — параграф о том что AuraImpulse не имеет MQL5-предка.
- vault: концепция [[auragrid-impulse-strategy]] и [[adr-003-impulse-strategy-new-preset-type]] обновлять не пришлось — реализация полностью соответствует ТЗ §4 (state machine, формулы, 13 полей, gap-обработка, двойная отправка SL — TZ §2.6 «принять решение в реализации» — выбрано двойная отправка как соответствующее приоритету скорости).

### AuraImpulse — концепция новой стратегии замёрзла + методология сохранена в vault

- Третья сессия дня. Продакт-владелец сформулировал новую стратегию `AuraImpulse` — single-shot breakout без сетки, мартингейла и CG-фазы. Четыре раунда уточнений до замёрзшей концепции (13 полей vs 38 у AuraGrid).
- Создана [[auragrid-impulse-strategy]] — концептуальная wiki: state machine (Watching / Trading / Cooldown), формулы (единая формула трейл-SL без фазы активации, переиспользует TZ TRAIL_REWORK v1.0), каталог 13 настроек (4 в `general` включая `min_account_balance`; 9 в новой секции `impulse`), сравнение с AuraGrid (что заимствуется, что нет), численный пример «трейл стартует на первом тике если `sl_distance_pts > trail_size_profit + trail_update_distance_profit`», open questions для v2.
- Создан [[adr-003-impulse-strategy-new-preset-type]] — Status: accepted. Решение: импульс реализуется как отдельный preset-type (`strategy_type: "auragrid" | "auraimpulse"` в yaml, default `"auragrid"` для backward-compat). Три отвергнутые альтернативы (режим внутри стратегии, отдельный репо). Migration plan: добавление optional поля без bump `config_version`, существующие пресеты — `"auragrid"` по умолчанию.
- [[auragrid]] MOC — ссылки на [[auragrid-impulse-strategy]] и [[adr-003-impulse-strategy-new-preset-type]] в «Связано с», `Trading core` строка дополнена `(+ Impulse — будущее)`.
- [[index]] — ссылки в «Компоненты AuraGrid» и «ADR».
- Реализационное ТЗ `auragrid/docs/tz/TZ_IMPULSE_STRATEGY_v1.0.md` создано в репо проекта (структура как у TZ_TRAIL_REWORK_v1.0).
- Auto-memory — указатель `reference_impulse_strategy` добавлен.
- Реализация в коде — **не начата**, ждёт отдельной сессии. Концепция замёрзла, ТЗ написан.

### MSI uninstall с опцией очистки %APPDATA%\GridScalp\

- Реализована возможность при деинсталляции поставить галочку «также удалить все мои данные и настройки». Галочка показывается в самом приложении (Settings → «Опасная зона» → «Удалить программу»), потому что стандартный uninstall через «Программы и компоненты» в Tauri/WiX MSI идёт с basic UI без диалогов.
- Создана [[auragrid-msi-uninstall-cleanup]] — концептуальная страница с UX-сценариями, инвариантами, потоком событий и анти-паттернами.
- В auragrid-репо:
  - `desktop/src-tauri/installer/cleanup.wxs` — WiX-фрагмент: `Property DELETE_USER_DATA` (default `0`, Secure), `CustomAction GridScalpRemoveUserData` (deferred + impersonate, PowerShell `Remove-Item -Recurse -Force`), `InstallExecuteSequence` с условием `REMOVE="ALL" AND DELETE_USER_DATA="1"`, обёртка в `ComponentGroup` для линкера.
  - `desktop/src-tauri/tauri.conf.json` — `bundle.windows.wix.fragmentPaths` + `componentGroupRefs: ["GridScalpUserDataCleanup"]`.
  - `desktop/src-tauri/src/uninstall.rs` — новый mod: поиск ProductCode по фиксированному UpgradeCode через `WindowsInstaller.Installer.RelatedProducts` (PowerShell COM, без новых крейтов); Tauri-команда `request_uninstall(delete_user_data)` спавнит `msiexec /x` с флагами `CREATE_NO_WINDOW | DETACHED_PROCESS`.
  - `desktop/src-tauri/src/lib.rs` — `mod uninstall;` + регистрация команды.
  - `desktop/src/components/SettingsModal.tsx` — кнопка «Удалить программу» + вложенный confirm-Modal с Checkbox + красный Alert при выбранной галочке; после invoke — `setTimeout 500 ms → window.close()` чтобы msiexec не наткнулся на Files in Use.
- [[auragrid]] MOC — ссылка добавлена в «Связано с»; frontmatter updated → 2026-05-25.
- [[index]] — ссылка добавлена в раздел «Операционные знания AuraGrid».
- Verify: `cargo check` ✅ (8 pre-existing warnings, ни одной новой); `npm run build` (tsc + vite) ✅. Полная `tauri build --bundles msi` не запускалась — требует WiX 3.x на хосте сборщика.
- Default — данные сохраняются. Чистка только при явном согласии пользователя через in-app галочку или CLI `msiexec /x ... DELETE_USER_DATA=1`. ARP-uninstall через «Программы и компоненты» — оставляет данные (намеренно, защита от случайного удаления при reinstall).
- Auto-memory — указатель `reference_msi_uninstall_cleanup` добавлен.
- Journal — [[2026-05-25]] (раздел дополнен).

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
