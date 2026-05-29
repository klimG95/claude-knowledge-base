---
type: plan
tags: [auragrid, performance, hot-path, ipc, strategy]
component: bot.core + ipc + desktop
layer: cross-cutting
shape: plan-hub
created: 2026-05-30
updated: 2026-05-30
status: in-progress
---

# AuraGrid — Стратегия ускорения (performance)

**TL;DR.** На ультраволатильном рынке бот отстаёт и окно «замерзает». Две независимые причины: (1) торговый цикл имеет жёсткий потолок ~20 тиков/сек из-за фиксированного `sleep(50 мс)` + работа по устаревшим тикам; (2) торговый цикл и IPC-сервер делят **один** event loop, поэтому блокирующие операции в `on_tick` (2 синхр. записи SQLite/тик, 4–5 блокирующих MT5-вызовов, ретраи `sleep 0.2с×3`, `flush()` логов) морозят и интерфейс. Аналитика уже в отдельном процессе — не виновата. План: 5 ярусов, начиная с измерения, по убыванию эффект/риск.

## Когда читать эту страницу

- Перед любой работой по «ускорению / лагам / зависаниям» бота.
- При вопросах «почему бот не успевает за импульсом» или «почему окно подвисает».
- Как чек-лист прогресса оптимизации (статусы ярусов внизу).

## Диагноз (два фронта)

### Фронт 1 — бот отстаёт от рынка
- `POLL_INTERVAL_SEC = 0.05`; в конце каждой итерации `await asyncio.sleep(tick_interval_sec)` — [main.py:510](python/bot/main.py#L510). Потолок ~20 тиков/сек независимо от реального потока (XAUUSD в импульсе 50–400/сек). Лишние тики копятся в буфере MT5 → бот считает по **устаревшей цене**.
- `on_tick` гоняет полную обработку даже когда цена не изменилась (нет дедупликации тиков).

### Фронт 2 — окно приложения «замерзает»
- Торговый `poll_loop` ([main.py:431](python/bot/main.py#L431)) и WebSocket IPC-сервер — на **одном** asyncio event loop. Блокирующая операция в торговом тике останавливает отдачу данных в UI.
- Блокировки на горячем пути:
  - 2 синхронные UPSERT в SQLite на тик — [persistence.py:108](python/bot/state/persistence.py#L108).
  - На тик: `symbol_info_tick` + `positions_get`×2 ([scanner.py:89](python/bot/mt5/scanner.py#L89)) + `account_info` — все синхронные, без `to_thread`.
  - Executor: `sleep(0.2с × 3)` при `NO_PRICES (10021)` — [executor.py:94](python/bot/mt5/executor.py#L94); `NO_PRICES` это именно симптом волатильности.
  - Логирование: `flush()` на каждую строку — [logging.py:151](python/bot/utils/logging.py#L151).
- UI-сторона: Rust-мост шлёт отдельное событие на каждый тик без батчинга ([ipc.rs:279](desktop/src-tauri/src/ipc.rs#L279)); React перерисовывает все панели на каждое обновление ([StrategyPanel.tsx:82](desktop/src/pages/Main/StrategyPanel.tsx#L82)), секундные «часы» каскадят перерисовку ([ConnectionBadge.tsx:16](desktop/src/components/ConnectionBadge.tsx#L16)); store растит снапшоты без лимита ([strategies.ts:102](desktop/src/store/strategies.ts#L102)).

### Что НЕ виновато
- Аналитика (indicators/regime/levels) — отдельный OS-процесс с собственным event loop и MT5-коннектом; GIL не делит с торговлей. См. [[auragrid-analytics-module]].
- log_shipper / telemetry / license-heartbeat — daemon-потоки на редких интервалах (10с/60с/30мин), сеть не на торговом потоке.

## Ключевое уточнение подхода (детализация 2026-05-30)

При погружении в код выяснилось: как только блокирующая работа уходит с единственного event loop (обязательно для устранения «замерзаний»), появляется **разделяемое между потоками состояние** — снапшот-цикл IPC читает `engine.buy/sell` напрямую ([server.py:190], [handlers.py:732-736]), а `emit_risk_if_changed` использует `asyncio.Queue.put_nowait` без `call_soon_threadsafe`. Поэтому план разделён на **безопасное ядро (Ярусы 0–2, без новых потоков)** и **рискованную эскалацию (Ярус 3, потоки) — условную, по данным измерений**. Прежняя редакция смешивала «разнести потоки» с write-behind в одном Ярусе 2; это переработано.

## План по ярусам

### Ярус 0 — измерительный каркас (фундамент)
- Расширить `poll_heartbeat` ([main.py:498](python/bot/main.py#L498)): `tick_skip_count`, перцентили `on_tick` p50/p99, разбивка по фазам (scan/process/persist/risk), `ipc_queue_depth`.
- Первый перф-тест на `FakeMT5Client` ([fake.py:33](python/bot/mt5/fake.py#L33)) + генератор тиков (перф-тестов сейчас нет вообще). Риск нулевой.

### Ярус 1 — снять потолок пропускной способности (один поток)
1. Убрать фиксированный `await asyncio.sleep(50мс)` ([main.py:510](python/bot/main.py#L510)) → адаптивная пауза (1–5 мс) только когда нового тика нет.
2. Дедупликация тиков по `time_msc`/bid/ask: `on_tick` только при реальном изменении.
- Краевой случай: внешнее ручное закрытие при стоячей цене → принудительный full-tick раз в ~250 мс; halt/reconnect по своим таймерам независимо от дедупа.

### Ярус 2 — разблокировать горячий путь (один поток — основной выигрыш)
3. **Write-behind SQLite**: in-memory `engine.buy/sell` уже источник истины; flush на таймере (~1с) **в том же потоке** (начало итерации poll_loop) + обязательный flush при критических событиях (open/close/reset/SCALP→CG/max_loss/pause-resume) + при stop. Сейчас 2–4 синхр. UPSERT/тик ([engine.py:261-273](python/bot/core/engine.py#L261-L273), [persistence.py:108](python/bot/state/persistence.py#L108)). Зеркально `save_impulse_state` для AuraImpulse.
4. **Асинхронное логирование**: `QueueHandler` + фоновый писатель, убрать `flush()` на строку ([logging.py:151](python/bot/utils/logging.py#L151)).
5. **Один `positions_get` вместо двух**: сейчас `sync_state(buy)`+`sync_state(sell)` = 2 round-trip ([engine.py:254-255](python/bot/core/engine.py#L254-L255), [scanner.py:85-138](python/bot/mt5/scanner.py#L85-L138)); забрать все позиции символа одним вызовом, делить локально по `(magic,type)`.
6. **`account_info()` по таймеру**, не на каждый тик (убрать из `_make_snapshot` [main.py:486](python/bot/main.py#L486), оставить в IPC-цикле 1 Гц).
7. **Подрезать ретраи executor'а** ([executor.py:94](python/bot/mt5/executor.py#L94)): `sleep(0.2с×3)` = до 0.6с полной заморозки loop при `NO_PRICES` (симптом волатильности); тюнинг по данным Яруса 0.

### Ярус 3 — расцепление торгового потока и IPC (РИСКОВАННЫЙ, условный)
Запускать **только если** после 0–2 измерения всё ещё показывают «замерзания». Целевая архитектура: торговый цикл в выделенном OS-потоке, IPC на главном asyncio-loop. Четыре обязательных механизма:
1. **publish-snapshot** — торговый поток публикует неизменяемый снимок, IPC читает его (lock-free swap), не лезет в живые `engine.buy/sell`.
2. **command-queue** — 17 IPC-команд ([handlers.py]) = синхронный RPC; кладут команду в очередь, торговый поток исполняет между тиками, ответ через `Future`/`Event`.
3. **MT5-сериализация** — пакет процесс-глобальный; все вызовы через единый lock (расширить `RLock` [connection.py:52](python/bot/mt5/connection.py#L52) на все методы). Аналитика не затронута (отдельный процесс).
4. **thread-safe эмит** — `call_soon_threadsafe` вместо прямого `put_nowait`.

### Ярус 4 — интерфейс (независим, можно параллельно)
8. Батчинг + throttle событий в Rust-мосте ([ipc.rs:279](desktop/src-tauri/src/ipc.rs#L279)) (~10–15 Гц, всегда последнее).
9. React: мемоизация панелей, точечные подписки store, отвязать секундные «часы» ([ConnectionBadge.tsx:16](desktop/src/components/ConnectionBadge.tsx#L16)) от панелей данных ([StrategyPanel.tsx:82](desktop/src/pages/Main/StrategyPanel.tsx#L82)).
10. Кольцевые буферы для растущих массивов ([strategies.ts:102](desktop/src/store/strategies.ts#L102)) + виртуализация списков.

## Реестр рисков (что предусмотрено)

| Риск | Ярус | Митигация |
|---|---|---|
| Гонки многопоточности | 3 | publish-snapshot + command-queue + MT5-lock + `call_soon_threadsafe`; изолировано и условно |
| Потеря состояния при крахе | 2 | flush по триггерам+таймеру+shutdown; реконсиляция с MT5 на старте ([engine.py:144-220](python/bot/core/engine.py#L144-L220)) |
| Пропуск внешнего закрытия при дедупе | 1 | принудительный full-tick раз в ~250 мс; независимые таймеры halt/reconnect |
| MT5-терминал — общий bottleneck для N ботов + аналитики | deploy | сокращение вызовов/процесс (Ярус 2) — сверхлинейный выигрыш при нескольких ботах |
| AuraImpulse — отдельная ветка кода | все | шаги дублируются для `ImpulseEngine`/`save_impulse_state`/impulse-MT5-вызовов |
| Семантика торговли | все | формулы/инварианты [[auragrid-trading-core]] не меняются — только скорость и поток данных |
| Backward-compat | все | схема config/state не меняется → не нужна ни миграция пресетов, ни сброс `%APPDATA%` |
| Регресс | все | ярус = отдельная ветка + полный pytest (baseline 1306); откат на checkpoint |

## Инварианты безопасности (нельзя нарушить)

- Семантика торговли не меняется ни в одном шаге. Эталон — [[auragrid-trading-core]].
- Каждый ярус — отдельная ветка с полным pytest (baseline 1306 passed) + ручной прогон на волатильной сессии.
- Дедуп не отключает защиту: при неизменной цене просадка/`max_loss` не меняются → пропуск безопасен; периодические проверки по таймеру.
- Write-behind: гарантированный flush при shutdown и важных переходах; recovery опирается на сверку с MT5 на старте.
- База отката: checkpoint `checkpoint/2026-05-30-pre-restructure` (см. [[auragrid-checkpoint-2026-05-30-pre-restructure]]) — свежий baseline, созданный именно перед этим рефакторингом (HEAD `461904b`, все слои зелёные, pytest 1306). Более глубокий fallback — [[auragrid-checkpoint-2026-05-22-analytics-unblocked]].

## Рекомендованный порядок и оценка

**0 → 1 → 2** строго по порядку (0 даёт цифры для 1–2); **4** независим, параллельно; **3** — только по данным измерений. Оценка: Я0 ~0.5д · Я1 ~0.5д · Я2 ~1.5–2д (основной выигрыш) · Я4 ~1–1.5д · Я3 (если нужен) ~2–3д. 0→1→2 (+4) закрывают проблему почти полностью при низком риске.

## Валидация на живом рынке

После каждого яруса: полный pytest → ручной прогон demo/боевой в волатильную сессию → сверка метрик (`tps_engine` ↑, `tick_skip_count` > 0, p99 `on_tick` ↓, глубина IPC-очереди стабильна). Откат — по тегу чекпоинта.

## Статус ярусов

Реализация 2026-05-30 на ветке `perf/acceleration-tiers` (от checkpoint
`checkpoint/2026-05-30-pre-restructure`, 461904b). Полный pytest 1325 passed.

| Ярус | Статус | Коммит/дата |
|---|---|---|
| 0 — измерительный каркас | **done** | `10887d4` (2026-05-30) |
| 1 — потолок пропускной способности | **done** | `658bdbe` (2026-05-30) |
| 2 — разблокировать горячий путь (1 поток) | **done** | `59503b1`+`aef0967`+`07c6f0a` |
| 3 — расцепление потоков (условный) | proposed (gated) | — (ждёт замеров на живом рынке) |
| 4 — интерфейс | proposed | — |

### Что сделано в Ярусе 2 (3 коммита)
- **2a** `59503b1` — write-on-change персистентность каналов (вместо timer-based: строго безопаснее — каждое изменение пишется немедленно) + батч обоих каналов одной транзакцией. AuraImpulse уже был на write-behind (`_dirty`).
- **2b** `aef0967` — один `positions_get` на оба канала (`scanner.sync_both`/`scan_all`) + кеш `account_info` (TTL 1с).
- **2c** `07c6f0a` — async лог-pump (фоновый писатель, off-thread write+flush) + `flush_logging`/`shutdown_logging`. Тюнинг ретраев executor **сознательно отложен** (укорачивание окна `NO_PRICES` рискует надёжностью закрытия ордеров; правильное место — Ярус 3 off-thread).

### Метрики Яруса 0 (для валидации эффекта на живом рынке)
`poll_heartbeat` теперь несёт: `on_tick_p50_ms`/`p99`/`max`, `ticks_skipped`, `persist_writes`. Ожидаемо после 1–2: `ticks_skipped` > 0 (дедуп), `persist_writes`/сек ↓ в разы (write-on-change), `on_tick` p99 ↓ (меньше MT5/SQLite на тик). `StateStore.write_count` — счётчик записей.

## Связано с

- [[auragrid]] — MOC проекта
- [[auragrid-trading-core]] — порядок `on_tick`, инварианты, которые нельзя сломать
- [[auragrid-analytics-module]] — почему аналитика не виновата (отдельный процесс)
- [[auragrid-log-analysis]] — `poll_heartbeat` метрики (tps_loop/tps_engine) для замеров
- [[runbook-vault-integration]] — workflow задачи

## Источник

- Сессия 2026-05-30 — параллельный аудит 4 слоёв (hot path / MT5+IPC / analytics+logging / Tauri+React), запрос пользователя «стратегия максимального ускорения с сохранением работоспособности». См. journal `2026-05-30.md`.
</content>
</invoke>
