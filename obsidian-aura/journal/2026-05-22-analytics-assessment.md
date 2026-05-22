---
type: journal
tags: [auragrid, journal, analytics, assessment, diagnosis]
created: 2026-05-22
updated: 2026-05-22
---

# 2026-05-22 (раунд 4) — Комплексная оценка модуля Analytics + расчёт риска стратегии

## Контекст сессии

Пользователь сообщил: в последней версии ПО (HEAD `677811c`, релиз 1.0.1) раздел «аналитики и расчёта риска стратегии» **никак не работает**. Окно открывается, отображаются только Spread и торговая Session, остальное — прочерки. Просил **комплексную оценку состояния модуля** для дальнейшего выхода на доработку, без правок кода.

## Что сделано

### Vault context (Phase 1)
- [[runbook-vault-integration]] — workflow
- [[auragrid]] — MOC, точки входа, компонент `Analytics` указан как `python/bot/analytics/`
- [[auragrid-trading-core]] — поняли границу: trading core ≠ analytics module
- [[journal/2026-05-22|journal/2026-05-22]] (раунды 1-3) — известный issue: MT5 calendar API mismatch × 25180 в логе тестировщика, PermissionError ротации × 6368

### Backend audit (Phase 2)
Два параллельных Agent'а (один на код, один на логи) дали разные диагнозы:
- Code agent: главная проблема — M15 buffer не инициализирован.
- Logs agent: главная проблема — calendar API mismatch блокирует pipeline.

Личной верификацией нашёл, что **оба правы частично, но реальная корневая причина третья — `symbol_not_found`**. В логах `[warning] symbol_not_found tried=['XAUUSD', 'XAUUSD.s', 'XAUUSD.m', 'GOLD', 'XAU/USD']` → `[warning] backfill_skipped_no_symbol`. Buffers вообще пустые. Это объясняет каскадно весь набор null'ов в snapshot, а calendar/M15 — отдельные слои поверх (которые в любом случае нужно чинить).

Code agent ошибочно считал calendar refresh «graceful» — формально да, не падает, но UX-эффект эквивалентен «не работает».

### UI audit
- [Analytics/index.tsx](auragrid/desktop/src/pages/Analytics/index.tsx) — окно подписывается на snapshot через `useAnalyticsSubscription`, рисует 12 виджетов + DeploymentTable кнопку (расчёт риска стратегии).
- [PresetEval/DeploymentTableModal.tsx](auragrid/desktop/src/pages/PresetEval/DeploymentTableModal.tsx) — модалка, кнопка disabled пока нет magic + grid_params + atr_*.
- [RiskMeter.tsx](auragrid/desktop/src/components/RiskMeter.tsx) — отдельный компонент на главном экране, источник — `strategies.runtime[magic].risk` от бота (`core/risk.py`), не из analytics-процесса.

Спред показывается потому что live-tick идёт отдельным каналом `useAnalyticsSubscription.lastTick`. Sessions — UTC-based, всегда работает.

### Финальная оценка пользователю
Отдана развёрнутая оценка (см. ответ в чате): три корневые причины + per-секционный статус + сопутствующие проблемы + 6 приоритетов unblock'а. Без фиксов — пользователь запросил только аудит.

## Что зафиксировано в vault

- **[[auragrid-analytics-module]]** — новая wiki-страница. Архитектура (второй процесс, IPC 8770, отдельный MT5), список 50+ файлов по подмодулям, три корневые причины с код-ссылками, статус каждой секции snapshot, сопутствующие проблемы, приоритеты unblock'а.
- **[[auragrid-incidents-log]]** — добавлен Incident 2026-05-22 раунд 4 с Investigation/Root cause/Misdiagnosis/Prevention.
- **`index.md`** — обновлён, добавлен пункт про [[auragrid-analytics-module]].
- **CHANGELOG.md** — запись о раунде 4.
- **Auto-memory** — указатель на [[auragrid-analytics-module]] (это reference-эталон для следующих сессий).

## Открытые вопросы (то, что нужно делать в следующих сессиях)

Из новой страницы [[auragrid-analytics-module]], секция «Приоритеты unblock»:

1. **P0** — Symbol resolution: расширить candidates (брать из BotConfig.mt5.symbol + перебор `mt5.symbols_get()` с эвристикой XAU+USD). UI badge `Analytics: символ не найден` вместо тихих прочерков.
2. **P1** — M15 buffer: добавить в `tfs_to_backfill` (manager.py:445) + блок в `recompute_indicators` по образцу H1. Это разблокирует DeploymentTable (расчёт риска стратегии).
3. **P1** — Calendar fallback: подключить `load_csv_fallback` (положить CSV в дистрибутив или подтянуть из ForexFactory/Investing.com).
4. **P2** — Сепарация лог-файлов: analytics → `analytics.log`, бот → `bot.log`.
5. **P2** — Degraded-mode UI badge.
6. **P2** — Integration smoke e2e-тест: fake-MT5 + manager + builder → snapshot.indicators непустые через 10s.

**Оценка работы по unblock'у**: P0-P3 — один-два дня плотной сессии разблокируют пользовательский опыт. P4-P6 — ещё день, превентивные.

## Что выучили

- **Не доверять одному agent'у — два дают разные диагнозы, оба частично правы.** В этой сессии backend-agent сказал «calendar обработан корректно», logs-agent сказал «calendar блокирует всё», реальность — третья причина, которую оба упустили. Личная верификация ключевых строк решает.
- **Каждый второй python-процесс — отдельный риск отказа.** Аналог: бот работает успешно → не значит что analytics-процесс работает. Имеют отдельные MT5-инстансы, разные resolve пути.
- **Smoke-теста «end-to-end модуль работает» нет.** Unit-тесты зелёные, прод не работает — классический gap. Это должно быть в чек-листе релиза.
- **Hardcoded списки кандидатов ломаются на онбординге.** Symbol должен идти из конфига стратегии, не из жёсткого списка в коде analytics.

## Связано с

- [[auragrid]] — MOC
- [[auragrid-analytics-module]] — новая wiki по модулю
- [[auragrid-incidents-log]] — incident 2026-05-22 раунд 4
- [[journal/2026-05-22|journal/2026-05-22]] — раунды 1-3 (trading core)
- [[runbook-vault-integration]] — workflow
