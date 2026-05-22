---
type: checkpoint
tags: [auragrid, checkpoint, baseline, rollback-point, stable]
project: auragrid
created: 2026-05-22
updated: 2026-05-22
---

# AuraGrid — Checkpoint 2026-05-22 — «Analytics unblocked»

**TL;DR.** Большой чекпоинт «первый стабильный вариант за долгое время». На него откатываемся, если последующие изменения сломают что-то критичное. На момент чекпоинта закрыты все 6 приоритетов unblock'а analytics-модуля (раунды 5+6+7) + все 5 фиксов релиза 1.0.1 от тестировщика (раунды 1+2+3). Полный test suite зелёный во всех слоях.

## Зачем существует этот чекпоинт

После серии быстрых фиксов всё ещё легко занести регрессию случайным изменением. Эта страница — **точка опоры для отката**. Если новая работа сломает что-то значимое и быстро не чинится — возвращаемся сюда без обсуждения.

## Git coordinates

| Репо | Branch | Tag | Tag SHA (для проверки) |
|------|--------|-----|------------------------|
| `klimG95/auragrid` | `main` | `checkpoint/2026-05-22-analytics-unblocked` | `6e39ca8` |
| `klimG95/claude-knowledge-base` | `main` | `checkpoint/2026-05-22-analytics-unblocked` | коммит, добавивший эту checkpoint-страницу (см. `git show <tag>` для точной SHA) |

Полная цепочка коммитов (нижний → верхний):

**auragrid:**
- `022a321` fix(analytics): P0 symbol resolution + dynamic candidates + UI degraded badge
- `ff86d23` fix(analytics): P1 M15 buffer + atr_m15 → DeploymentTable unblock
- `6e39ca8` fix(analytics): finish unblock — P1 Calendar CSV + P2 logs rollover + P2 e2e smoke ← **checkpoint**

**claude-knowledge-base (vault):**
- `9535655` vault: AuraGrid analytics P0 fix — symbol resolution unblock (round 5)
- `ddc5dd4` vault: AuraGrid analytics P1 fix — M15 buffer + atr_m15 (round 6)
- `730e51b` vault: AuraGrid analytics unblock finish — round 7
- (текущий) vault: big checkpoint — checkpoint wiki + index + CHANGELOG ← **checkpoint tag здесь**

Предшествующий стабильный коммит auragrid: `94dc602` (round 3 — close-as-trail + pause-keeps-trailing + file presets, релиз 1.0.1).

## Состояние модулей в чекпоинте

### Trading core (фиксы релиза 1.0.1, раунды 1-3)

- `protection.close_channel` — свежий tick per item + on_retry для актуализации цены при REQUOTE/INVALID_PRICE/NO_PRICES; закрывает все N сделок.
- `normalize_lot` — digits через `-log10(volume_step)`; точность для 3-знаковых брокеров.
- `engine.start` — sync `state.pending_ticket` с MT5 при старте, multi-pending cleanup; нет фантомов.
- `protocol`: `NO_PRICES (10021)` и `POSITION_CLOSED (10044)` в `_RETRYABLE`/success-set; снижено количество ложных «не закрылось».
- `scalping.place_grid_order` — snapshot/restore `last_lot_raw` при fail; нет мартингейл-drift.
- `profit_trailing` — фикс infinite re-activation при updated=0.
- **Close-as-trail семантика**: `close_all`/`close_buy`/`close_sell` — выставляют SL = trail-level + дальше стандартный профит-трейлер; не мгновенный physical-close.
- **Pause-keeps-trailing**: guard `state.paused` перенесён в середину `engine.process_channel` — на паузе работает profit_trailer.manage, reset, partial-close sync.
- **Save/Load preset как файл**: `strategies::export_preset`/`import_preset` + UI меню + file dialog (исключают/мержат секретные поля).
- **IPC contract**: `start_bot` → `bot_already_running` при повторном вызове (приведено к docs/contracts/ipc.md §2.3+§5).

### Analytics module (раунды 5-7, эта серия)

Все шесть приоритетов unblock закрыты:

| # | Pri | Тема | Что сделано |
|---|-----|------|-------------|
| 1 | P0 | Symbol resolution | heuristic XAU+USD fallback через `mt5.symbols_get()` + dynamic candidates из `strategies/*.yaml` + 11 suffix-вариантов; source ∈ {candidates, heuristic, none} |
| 2 | P1 | M15 buffer | `Timeframe.M15` в `tfs_to_backfill` + atr_m15 блок в `indicator_pipeline.recompute_indicators`; DeploymentTable активна |
| 3 | P1 | Calendar fallback | `EconomicCalendar(csv_fallback_path)` + hasattr-guard сверху refresh() (anti-25k-AttributeError) + bundled `bot/analytics/data/economic_calendar.csv`; source ∈ {mt5, csv, none} |
| 4 | P2 | Лог-конкуренция | `_JSONRotatingHandler.emit` ловит `PermissionError`/`OSError` от `doRollover`, сдвигает `rolloverAt += 3600`, продолжает писать |
| 5 | P2 | Degraded UI badge | `snapshot.system_status: {symbol_resolved/source/tried, mt5_connected, calendar_source}` + красный/жёлтый/оранжевый Alert в `Analytics/index.tsx` |
| 6 | P2 | Integration smoke e2e | `test_manager_e2e_indicators_nonempty` — fixture `mt5_online` + WS get_snapshot + assertions на `indicators.atr_*` |

Попутно (`feedback_fix_found_bugs`):
- `snapshot_builder.snapshot_buf` — заменил несуществующие `buf.size()`/`buf.snapshot()` на `len(buf)`/`buf.get_df()`.
- `python/requirements-dev.txt` — добавлены `aiogram>=3.13`, `respx>=0.21` (admin_bot integration tests).
- `desktop/pnpm-lock.yaml` — восстановлен `@tauri-apps/plugin-dialog` (TS компилируется).

### Vault и методология

- AGENTS.md vault'а и [[runbook-vault-integration]] действуют — три фазы (Context / Work / Capture) применялись в каждом раунде.
- Hooks SessionStart + Stop в `~/.claude/settings.json` — механическая принуда workflow.
- Auto-memory сверена с реальными vault-страницами.

## Что тестировалось перед чекпоинтом

| Слой | Команда | Результат |
|------|---------|-----------|
| Python full suite | `pytest --tb=short -q` | 1157 passed, 1 skipped, 16 xfailed, 2 xpassed |
| TypeScript | `npx tsc --noEmit` | чисто |
| Vitest | `npx vitest run` | 24/24 passed |
| Analytics suite | `pytest tests/analytics/ -q` | 468 passed |
| Admin bot integration | `pytest tests/integration/test_admin_bot_commands.py` | 16/16 passed (после фикса requirements) |

## Что НЕ покрыто (известные ограничения)

Эти пункты — **не блок UX**, но осознанные ограничения на момент чекпоинта:

- **Live update H1/D1/M15 буферов после backfill отсутствует.** `bar_close_loop` детектит close только для primary TF; H1/D1/M15 — снимок на старте, через несколько часов индикаторы становятся stale до рестарта analytics-процесса.
- **CSV `economic_calendar.csv` — статический в дистрибутиве.** Нет автоматического update'а из ForexFactory/Investing.com.
- **M15 индикаторный набор — только ATR.** Без ADX/Bollinger/intraday для M15.
- **Per-strategy view** (Wave C-lite, мульти-стратегии в одном окне) — не реализован.
- **Ручная верификация на тестовом MT5** ещё не проведена — это следующий шаг.

## Как откатиться к чекпоинту

### Полный rollback (auragrid + vault)

```powershell
# auragrid
cd c:\Users\Administrator\Desktop\Aura\auragrid
git fetch --tags origin
git checkout main
git reset --hard checkpoint/2026-05-22-analytics-unblocked
# Только если уже запушили мусор поверх — иначе достаточно reset:
# git push --force-with-lease origin main

# vault
cd c:\Users\Administrator\Desktop\claude-knowledge-base
git fetch --tags origin
git checkout main
git reset --hard checkpoint/2026-05-22-analytics-unblocked
# Принуждение к force-push — только при необходимости.
```

### Сравнить состояние с чекпоинтом

```powershell
cd c:\Users\Administrator\Desktop\Aura\auragrid
git log --oneline checkpoint/2026-05-22-analytics-unblocked..HEAD
git diff checkpoint/2026-05-22-analytics-unblocked..HEAD -- python/bot/analytics/
```

### Откат отдельных файлов без полного reset

```powershell
git checkout checkpoint/2026-05-22-analytics-unblocked -- python/bot/analytics/manager.py
```

### Не уверен? — посмотреть PR/коммиты, что между чекпоинтом и HEAD

```powershell
git log --oneline --decorate checkpoint/2026-05-22-analytics-unblocked..HEAD
```

## Условия для использования чекпоинта

- **Используй**: если регрессия в analytics/trading-core критическая и не чинится быстро (>30 минут диагностики), или если новый эксперимент создал неконсистентное состояние, которое сложно распутывать.
- **НЕ используй**: при мелких локальных regressions, которые проще починить новым коммитом — каждый rollback теряет полезные изменения после чекпоинта.

## Связано с

- [[auragrid]] — MOC проекта
- [[auragrid-analytics-module]] — статус модуля на чекпоинте (все P0/P1/P2 ✅ DONE)
- [[auragrid-trading-core]] — состояние торгового ядра
- [[auragrid-incidents-log]] — журнал инцидентов (раунды 1-7)
- Journal'ы серии: [[journal/2026-05-22|раунды 1-3]], [[2026-05-22-analytics-assessment|раунд 4 assessment]], [[2026-05-22-analytics-p0-symbol-resolution|раунд 5]], [[2026-05-22-analytics-p1-m15-buffer|раунд 6]], [[2026-05-22-analytics-p1-calendar-and-finish|раунд 7]].

## Следующий шаг

Ручная верификация на тестовом MT5-аккаунте — поднять билд, открыть Analytics, проверить заполненный snapshot, активную кнопку DeploymentTable, корректный degraded-badge при тестовых сценариях (отключить терминал → должен показать `mt5_connected=false` и т.д.).
