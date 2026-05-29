---
type: moc
tags: [auragrid, project, trading-bot, mql5-port]
created: 2026-05-22
updated: 2026-05-30
---

> **TL;DR обновление 2026-05-25 (4-я сессия):** AuraImpulse v1.0 полностью реализована — Python ядро (`python/bot/core/impulse.py`), Engine dispatch (`main.py::build_engine`), IPC handlers, Rust strategies.rs, UI Wizard + Editor + бейджи. Полный pytest 1253 passed, cargo check OK, npm build OK. Manual QA — `docs/qa/scenarios/impulse_lifecycle.md`. Концепция [[auragrid-impulse-strategy]] и ADR-003 без изменений (реализация им полностью соответствует).

# AuraGrid — MOC

**TL;DR.** Тortовый бот для MT5 (XAUUSD), порт MQL5-эталона на Python с Tauri-десктопом. Канонический репо — `klimG95/auragrid`. Архитектура: Python-бот (торговое ядро) ⇄ Tauri (Rust shell + React UI) через WebSocket IPC, лицензионный server-side контроль, опциональный log-shipping в Loki.

## Точки входа

- **Репо:** `c:\Users\Administrator\Desktop\Aura\auragrid\` → GitHub `klimG95/auragrid`
- **Git binary:** `C:\Program Files\Git\bin\git.exe` (не в PATH)
- **Legacy:** `klimG95/my-first-project` — заморожен 2026-05-11, не трогать
- **Канон конституции:** `auragrid/AGENTS.md` (содержит ТЗ MQL5 + Reading map)

## Компоненты

| Слой | Где живёт | Что делает |
|------|-----------|------------|
| Trading core (Python) | `python/bot/core/` | Engine, Scalping, ConservativeGrid, ProfitTrailer, Protection, Risk + **Impulse** (single-shot breakout, см. [[auragrid-impulse-strategy]]) |
| MT5 интеграция | `python/bot/mt5/` | Client wrap, Executor (retry), Scanner, fake-сервер для тестов |
| IPC | `python/bot/ipc/`, `desktop/src-tauri/src/` | WebSocket порт 8765/8766, протокол + handlers |
| Tauri shell | `desktop/src-tauri/` | Rust обёртка процесса бота, IPC bridge |
| React UI | `desktop/src/` | Wizard, Strategy panels, Analytics, License flow |
| Licensing | `python/bot/licensing/`, `server/` | Активация по ключу, heartbeat, ban/revoke |
| Analytics | `python/bot/analytics/` | Indicators, regime, calendar, snapshot-builder |
| Log shipping | `python/bot/log_shipper/`, `server/routes/logs.py` | Tail JSONL → batch → /api/logs/* → Loki |

## Связано с

- [[auragrid-incidents-log]] — журнал инцидентов и анти-паттернов
- [[auragrid-log-analysis]] — методология чтения desktop.log + bot.log
- [[auragrid-trading-core]] — детали торгового ядра (engine/protection/profit_trailing)
- [[auragrid-trading-settings]] — полный каталог настроек пресета (general/scalping/CG/mt5)
- [[auragrid-impulse-strategy]] — концепция новой стратегии `AuraImpulse` (отдельный preset-type, single-shot breakout)
- [[adr-003-impulse-strategy-new-preset-type]] — архитектурное решение об отдельном `strategy_type`
- [[auragrid-msi-uninstall-cleanup]] — деинсталляция MSI с опциональной очисткой `%APPDATA%\GridScalp\` (in-app галочка)
- [[auragrid-performance-strategy]] — стратегия ускорения (зависания/лаги на ультраволатильном рынке): 2 фронта + 5 ярусов
- [[methodology-overview]] — общая методология vault'а

## Источник

- ТЗ MQL5 v2.0 — раздел в `auragrid/AGENTS.md`
- ADR-006 (2026-05-20) — текущая структура vault
- Сессии разработки 2026-05-* — см. `journal/`
