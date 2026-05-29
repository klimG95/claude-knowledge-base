---
type: checkpoint
tags: [auragrid, checkpoint, baseline, rollback-point, stable]
project: auragrid
created: 2026-05-30
updated: 2026-05-30
---

# AuraGrid — Checkpoint 2026-05-30 — «Pre-restructure»

**TL;DR.** Точка опоры для отката **перед серией комплексных изменений и перестроек** (в первую очередь — performance-рефакторинг [[auragrid-performance-strategy]]). Захватывает последнюю полностью работоспособную версию: AuraImpulse v1.0 + адаптивная дистанция (ADR-004), trail rework (ADR-002), analytics integrity, MSI uninstall cleanup. Проверено зелёным во всех слоях (Python 1306 / TypeScript / Vitest / cargo). HEAD `461904b`.

## Зачем существует этот чекпоинт

Планируется performance-рефакторинг ([[auragrid-performance-strategy]]) — затрагивает горячий путь торгового ядра, persistence, IPC/threading, возможно расцепление потоков (Ярус 3). Это рискованный класс изменений. Эта страница — **точка опоры для отката**: если ярус сломает торговую семантику или стабильность и быстро не чинится — возвращаемся сюда. Заменяет [[auragrid-checkpoint-2026-05-22-analytics-unblocked]] в роли «ближайшей базы отката» (тот остаётся как более глубокий fallback).

## Git coordinates

| Репо | Branch | Tag | Tag SHA (для проверки) |
|------|--------|-----|------------------------|
| `klimG95/auragrid` | `main` | `checkpoint/2026-05-30-pre-restructure` | `461904b` |
| `klimG95/claude-knowledge-base` | `main` | `checkpoint/2026-05-30-pre-restructure` | коммит, добавивший эту страницу (см. `git show <tag>`) |

Цепочка коммитов auragrid от предыдущего чекпоинта (нижний → верхний):

- `6e39ca8` ← **checkpoint/2026-05-22-analytics-unblocked**
- `b70b66b` feat(trail): TZ TRAIL_REWORK v1.0 — унификация трейлинга, удаление `pending_order_offset` (ADR-002, config_version 1→2)
- `fb67723` fix(analytics): TZ_ANALYTICS_INTEGRITY v1.0 — 4 P0 + 2 P1 data correctness fixes
- `2c13f5b` feat(release): AuraImpulse v1.0 strategy + MSI uninstall cleanup (ADR-003)
- `8972a5e` feat(impulse): manual cooldown reset + auto-cancel pendings on stop
- `bc07885` feat(impulse): adaptive M1-based distance + cooldown floor (ADR-004, config_version 2→3)
- `0bab2c7` fix(impulse): MT5Connection.copy_rates_from_pos — was missing, broke adaptive distance
- `461904b` chore(impulse): expose avg M1 candle size in pts (snapshot + UI + log) ← **checkpoint/2026-05-30-pre-restructure**

## Состояние модулей в чекпоинте

- **Trading core** — trail rework (ADR-002) применён: унифицированная семантика `trail_size`/`trail_update_distance`, `pending_order_offset` удалён, config_version 2.
- **AuraImpulse** — v1.0 + все доработки: cooldown UX, адаптивная дистанция по M1 (ADR-004, config_version 3), MT5Connection hotfix, UX-прозрачность среднего размера свечи в pts. См. [[auragrid-impulse-strategy]].
- **Analytics** — unblock 2026-05-22 + TZ_ANALYTICS_INTEGRITY v1.0 (4 P0 + 2 P1) закрыты; данные корректны. См. [[auragrid-analytics-module]].
- **MSI** — uninstall cleanup (опциональная очистка `%APPDATA%\GridScalp\`). См. [[auragrid-msi-uninstall-cleanup]].

## Что тестировалось перед чекпоинтом (2026-05-30)

| Слой | Команда | Результат |
|------|---------|-----------|
| Python full suite | `pytest -q` (python/) | **1306 passed**, 1 skipped, 16 xfailed, 2 xpassed, 0 failed, 0 errors (603с) |
| TypeScript | `tsc --noEmit -p tsconfig.build.json` (desktop/) | чисто (exit 0) |
| Vitest | `vitest run` (desktop/) | **24/24 passed** |
| Rust (Tauri) | `cargo check` (desktop/src-tauri/) | exit 0; 8 безобидных dead-code warnings (`port`/`magic`) |

Baseline `1306 passed` совпадает с числом, на которое опирается [[auragrid-performance-strategy]] (инварианты безопасности: полный pytest после каждого яруса).

## Замечание по окружению (важно для воспроизведения зелёного прогона)

Полный pytest-набор требует, чтобы в venv были установлены **все** объявленные зависимости, включая:

- `aiogram` — объявлен в `python/requirements-dev.txt` (admin_bot integration tests, иначе collection падает на `import aiogram`).
- `python-multipart` — объявлен в `python/server/requirements.txt` (нужен FastAPI для Form-роутов `logs.py`; без него интеграционные тесты, поднимающие сервер in-process, падают с `RuntimeError: Form data requires "python-multipart"`).

На момент чекпоинта локальный `.venv` был устаревшим (не хватало этих двух). **Дефекта в репозитории нет** — requirements-файлы корректны. Правильный провижининг dev/CI-окружения: установить `requirements-dev.txt` + `server/requirements.txt`. Симптом «collection error на aiogram» или «RuntimeError python-multipart» = устаревший venv, а не регрессия кода.

## Как откатиться к чекпоинту

```powershell
# auragrid
cd c:\Users\Administrator\Desktop\Aura\auragrid
git fetch --tags origin
git checkout main
git reset --hard checkpoint/2026-05-30-pre-restructure
# Только если поверх уже запушен мусор:
# git push --force-with-lease origin main

# vault
cd c:\Users\Administrator\Desktop\claude-knowledge-base
git fetch --tags origin
git checkout main
git reset --hard checkpoint/2026-05-30-pre-restructure
```

### Сравнить состояние с чекпоинтом / откатить отдельные файлы

```powershell
git log --oneline --decorate checkpoint/2026-05-30-pre-restructure..HEAD
git diff checkpoint/2026-05-30-pre-restructure..HEAD -- python/bot/
git checkout checkpoint/2026-05-30-pre-restructure -- <путь к файлу>
```

## Условия для использования

- **Используй**: если ярус performance-рефакторинга ([[auragrid-performance-strategy]]) сломал торговую семантику/стабильность и не чинится быстро (>30 мин диагностики), или эксперимент оставил несогласованное состояние. План предписывает «ярус = отдельная ветка», поэтому обычно достаточно отбросить ветку; reset к чекпоинту — крайняя мера.
- **НЕ используй**: при мелкой локальной регрессии, которую проще починить новым коммитом — каждый rollback теряет полезное после чекпоинта.

## Связано с

- [[auragrid]] — MOC проекта
- [[auragrid-performance-strategy]] — план изменений, ради которого создан этот чекпоинт (база отката для ярусов)
- [[auragrid-checkpoint-2026-05-22-analytics-unblocked]] — предыдущий чекпоинт (более глубокий fallback)
- [[auragrid-impulse-strategy]], [[auragrid-analytics-module]], [[auragrid-trading-core]] — состояние модулей на чекпоинте
- [[runbook-vault-integration]] — workflow задачи
