---
type: adr
adr_id: 2
status: accepted
tags: [auragrid, trading, trail, mq5-parity, breaking-change]
created: 2026-05-25
updated: 2026-05-25
---

# ADR-002: Намеренный отход от MQL5-эталона в логике трейлинга

**Status:** accepted
**Date:** 2026-05-25
**Project:** AuraGrid

## Context

В MQL5-эталоне (`mql5/TZ_MT5_GridScalp_Bot_v2.mq5`, см. раздел МQL5-ТЗ v2.0 в `auragrid/AGENTS.md`) логика трейлинга оперирует **четырьмя** независимыми параметрами на каждый из двух режимов (Scalp/CG):

- `PendingOrderOffset` — буфер триггера добора (порог `current_step + offset`)
- `TrailSize` — целевая дистанция pending/SL от цены
- `TrailUpdateDistance` — порог пересчёта pending (сравнение с **абсолютным** расстоянием `|цена − ордер|`)
- `TrailSizeProfit` / `TrailUpdateDistanceProfit` — аналоги для SL после активации профит-трейлинга

На практике эта модель имела три проблемы:

1. `PendingOrderOffset` и `TrailSize` независимы, но обязаны быть согласованы — рассинхронизация искажает шаг сетки незаметно для пользователя.
2. `TrailUpdateDistance{Profit}` сравнивается с **абсолютным** расстоянием цена↔ордер, что требует мутного инварианта `TrailUpdateDistanceProfit > TrailSizeProfit` (без него — спам modify).
3. Пользователю приходится держать в голове разную семантику для pending-трейла и profit-трейла, хотя по сути это один и тот же механизм.

Подробный анализ — `docs/tz/TZ_TRAIL_REWORK_v1.0.md` (внутрипроектное ТЗ переработки, 2026-05-25).

## Considered options

1. **Сохранить полный MQL5-parity** — оставить четыре параметра, документировать ограничения. Минус: контринтуитивная семантика остаётся, мутный инвариант остаётся, добавление параметров через UI не выявляет рассинхронизацию.

2. **Унифицировать вокруг двух интуитивных параметров и удалить `PendingOrderOffset`** (вариант B с overshoot). Семантика для всех четырёх трейлингов одна:
   - `trail_size` — удалённость ордера/SL от цены
   - `trail_update_distance` — частота обновления (доп. ход цены сверх удалённости)
   - порог пересчёта = `trail_size + trail_update_distance`
   - триггер первого выставления pending: `|цена − last_open| ≥ current_step + trail_size`; pending встаёт ровно на `current_step` пт от `last_open_price` (геометрия сетки точна).

   Минус: ломающее изменение схемы (`config_version` 1 → 2), пресеты у клиентов отвергаются с понятным сообщением; parity-фикстуры симулятора пересчитываются.

3. **Переименовать поля yaml** (`pending_order_offset` → `overshoot_buffer`, и т.п.). Минус: бо́льший diff в коде/тестах/доках без выигрыша — Surgical-правила vault'а (см. [[adr-001-surgical-minimal-vault-updates]]) применяю и здесь.

## Decision

Принят вариант 2: **унифицированная двухпараметрическая модель + удаление `pending_order_offset`**, имена yaml-полей не переименовываются (Surgical). `config_version` бампается с 1 на 2, миграция yaml — жёсткое отвержение с инструкцией «пересоздать стратегию через UI».

Реализовано в одном атомарном PR одного дня (2026-05-25), TZ — `docs/tz/TZ_TRAIL_REWORK_v1.0.md`.

## Consequences

**Положительные:**
- Единая семантика для четырёх трейлингов (scalp pending, CG pending, scalp profit-SL, CG profit-SL).
- Снят мутный инвариант `trail_update_distance_profit > trail_size_profit`; заменён на простую проверку `trail_update_distance > 0` (защита от спама modify).
- Геометрия сетки явная: pending в момент выставления стоит ровно на `current_step` от `last_open_price` (ключевой инвариант).
- В логах добавлены поля `trail_size`, `trail_update_distance`, `threshold`, `dist_pts` — трейлинг отслеживается в проде по этим полям.

**Отрицательные:**
- Отход от MQL5-эталона в этом параметре фиксируется здесь как сознательное решение. Сравнение с MQL5 ST (parity-фикстуры) пересчитано — новый baseline не совпадает с исходным MQL5-симулятором.
- Семантика `trail_size` / `trail_update_distance` поменялась без переименования. Тестировщики не должны переносить значения из старых пресетов вручную — все стратегии пересоздаются через UI после установки нового MSI. Чек-лист расширен в [[feedback_release_checklist]].
- 56 файлов касаются параметров трейлинга; ломающее изменение — все обновлены атомарно.

## Migration plan

1. **Серверные пресеты** (репо): обновлены в одном PR — все `*.yaml` без `pending_order_offset`, `config_version: 2`, новые значения trail-параметров согласованы.
2. **Клиентские пресеты** (у тестировщиков): yaml с `config_version: 1` или `pending_order_offset` отвергается схемой pydantic с `IncompatibleConfigVersionError` + понятным сообщением. После установки нового MSI обязательно одно из:
   - в UI каждую стратегию → «Перенастроить» (UI запишет новый yaml с `config_version: 2`);
   - удалить `%APPDATA%\GridScalp\strategies\` и пересоздать стратегии через wizard.
3. **SQLite-state совместим** — формат state не меняется, только параметры конфигурации. Открытые позиции после обновления продолжают работу на новых формулах.
4. **Parity-фикстуры** (6 файлов под `python/tests/fixtures/parity/`) пересчитаны под новую семантику; baseline preset-eval симулятора зафиксирован в коммите.
5. **`.set` импорт** (`tools/set_to_yaml.py`): `PendingOrderOffset` / `CG_PendingOrderOffset` ушли в `IGNORED_KEYS` — при импорте старого MQL5 .set эти значения теряются с warn (это намеренно).

## Verify

Acceptance закрепляется тестом `python/tests/test_trail_rework_acceptance.py` — численный пример из ТЗ §2.5 для SELL и BUY зеркально. 696/696 pytest зелёные на 2026-05-25, TypeScript-сборка десктопа без ошибок, Rust `cargo check` без ошибок.

## Связано с

- [[auragrid-trading-settings]] — каталог настроек после переработки
- [[auragrid-trading-core]] — формулы и инварианты ядра (универсальная формула трейлинга)
- [[auragrid-incidents-log]] — запись 2026-05-25 переработка трейлинга
- [[feedback_release_checklist]] — чек-лист после нового MSI (расширен для config_version 2)
- [[adr-001-surgical-minimal-vault-updates]] — методология vault-правок (Surgical: имена yaml не переименованы)

## Источник

- `auragrid/docs/tz/TZ_TRAIL_REWORK_v1.0.md` — полное ТЗ переработки
- `auragrid/AGENTS.md` раздел «МQL5-ТЗ v2.0» — эталон, от которого мы отходим
- Сессия 2026-05-25 — реализация в одном атомарном PR
