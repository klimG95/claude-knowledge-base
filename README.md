# claude-knowledge-base

> Переносимая методология ведения базы знаний в Obsidian + работы над проектами через Claude Code (или совместимый AI-агент).

## Что это

`claude-knowledge-base` — это не библиотека и не плагин, а **методология** работы AI-агента с проектом. Пакет даёт vault-скелет, шаблоны страниц, конституцию для агента (`AGENTS.md`), playbook (`AGENT-MANUAL.md`) и bootstrap-промт. Всё это упаковано в self-contained git-репо и разворачивается одной командой.

В основе — концепция «второго мозга»: vault выступает операционным центром между сессиями. Агент перед началом работы читает MOC (map of content) → переходит по [[wikilinks]] к нужным domain hub / runbook / ADR → получает контекст и принимает решения. Сам код проекта при этом остаётся источником правды про «как сейчас», а vault — про «почему так».

Память агента разделена на три слоя. **Semantic** — стабильные факты и принципы (vault: концепции, ADR, runbook'и, contracts). **Procedural** — авто-память (`~/.claude/projects/.../memory/MEMORY.md`), preferences, persistent инструкции пользователя. **Episodic** — журнал сессий (`vault/journal/`), incident-log, raw-выгрузки до обработки. Каждый слой имеет свой жизненный цикл и свои правила обновления.

Каждая страница vault — agent-first. Это значит: TL;DR в первых строках, декларативный стиль (что делать, не как), inline-ссылки на конкретные файлы/строки кода через wiki-style `[[file#section]]`, frontmatter с типом страницы и тегами для Dataview-индексов. Five page types: **concept** (доменная сущность), **reference** (как-делать), **contract** (wire/API), **domain-hub** (точка входа в подсистему), **inventory** (карта кода).

Над крупными задачами агенты работают параллельно по waves. Один файл — один агент. Конфликтов нет. После каждой wave — reviewer pass + объединение в общий результат. Паттерн доказан на проекте из 52 vault-страниц.

## Кому полезно

- Тем, кто работает с Claude Code на проекте дольше одной сессии и устал каждый раз восстанавливать контекст.
- Тем, кто хочет AI-агента в режиме «коллеги-аналитика», а не «справочника» — чтобы агент сам понимал scope, читал нужные страницы и принимал технические решения.
- Тем, кто ведёт коммерческий/предрелизный проект, где важна agent-friendly документация: ADR пережил три переписывания кода, а runbook отработал инцидент в 03:00.
- Тем, кто уже использует Obsidian и хочет связать vault с AI-агентом без vendor lock-in.

## Что внутри

| Артефакт | Назначение |
|----------|------------|
| `README.md` | Этот файл — overview |
| `INSTALL.md` | Пошаговая установка |
| `BOOTSTRAP.md` | Промт первой сессии Claude — адаптация под проект |
| `AGENT-MANUAL.md` | Playbook агента — читается в любой нетривиальной сессии |
| `install.ps1` | PowerShell-installer (symlink + проверки) |
| `smoke-test.ps1` | Verification после установки |
| `VERSION` | Semver текущей версии пакета |
| `LICENSE` | MIT |
| `obsidian-aura/` | Vault-скелет: конституция, шаблоны, methodology-страницы |
| `obsidian-aura/AGENTS.md` | Generalized конституция для агента |
| `obsidian-aura/wiki/templates/` | 9 шаблонов страниц (ADR, runbook, concept, reference, contract, domain-hub, inventory, incident, page) |
| `obsidian-aura/wiki/methodology-overview.md` | Карта методологии — как устроены три слоя памяти |
| `auto-memory-templates/` | Стартовые `.example`-файлы для `~/.claude/projects/.../memory/` |
| `docs/concepts.md` | Концепции: три слоя памяти, ADR, runbook, MOC, inventory, domain-hub |
| `docs/workflows.md` | Типичные сценарии: обработка raw, оформление ADR, параллельные waves |
| `docs/customization.md` | Как агенту кастомизировать vault под конкретный проект |
| `docs/troubleshooting.md` | Частые проблемы и решения |

## Как развернуть

1. Clone репо в выбранную папку.
2. Запустить `install.ps1` — создаст symlink `AGENTS.md` → `obsidian-aura/AGENTS.md`, проверит зависимости.
3. (Опц.) Установить Dataview в Obsidian для динамических индексов.
4. (Опц.) Скопировать `.example`-файлы из `auto-memory-templates/` в свой `~/.claude/projects/.../memory/`.
5. Запустить Claude из install-dir, в первом промте — `Прочитай BOOTSTRAP.md и приступай.`

Полная инструкция — [INSTALL.md](INSTALL.md).

## Быстрый старт

```powershell
git clone https://github.com/klimG95/claude-knowledge-base.git
cd claude-knowledge-base
.\install.ps1 -InstallDir .
# Затем в Claude Code:
# > Прочитай BOOTSTRAP.md и приступай.
```

После bootstrap-сессии vault настроен под твой проект: создан project-specific MOC, обновлён `AGENTS.md`, проставлены auto-memory указатели. Дальше — обычная работа.

## Принципы

- **Vault — источник истины про «почему», код — про «как сейчас».** Не дублируй в vault то, что есть в коде. Ссылайся через `[[file#section]]`.
- **Связывай страницы двусторонне.** Если A ссылается на B, B должна иметь backlink на A. Dataview-индексы строятся на этом.
- **Декларативность.** Страница говорит «что делать», а не «как именно». Конкретику агент возьмёт из кода/прежних сессий.
- **ADR пережил много переписываний кода — это фича, не баг.** Решение фиксируется в vault на уровне контекста и trade-off'ов, а не на уровне сигнатур функций.
- **Один файл — один агент.** При параллельной работе агентам выдаются непересекающиеся файлы. Reviewer-pass объединяет.
- **TL;DR в первых строках.** Любая страница должна быть полезна агенту даже при чтении первых 10 строк.

## Лицензия

MIT — см. [LICENSE](LICENSE). Copyright 2026 klimG95.

## История

Методология разработана в рамках реального предрелизного проекта 2026-05. Полная structural documentation паттерна (ADR-006-стиль) применена и доказала свою работоспособность на проекте из 52 vault-страниц. Этот пакет — generalize-выжимка: убраны project-specific детали, оставлены переносимые шаблоны и playbook.

## Связано

- [INSTALL.md](INSTALL.md) — установка
- [BOOTSTRAP.md](BOOTSTRAP.md) — первая сессия Claude
- [AGENT-MANUAL.md](AGENT-MANUAL.md) — полный playbook для агента
- [docs/concepts.md](docs/concepts.md) — концепции методологии
- [docs/workflows.md](docs/workflows.md) — типичные сценарии
- [docs/customization.md](docs/customization.md) — кастомизация под проект
- [docs/troubleshooting.md](docs/troubleshooting.md) — частые проблемы
