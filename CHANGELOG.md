# Changelog

Все значимые изменения пакета `claude-knowledge-base` фиксируются здесь.

Формат — [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), версионирование — [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

(Здесь накапливаются изменения в `main`, до выкатки следующей версии.)

## [0.3.0] — 2026-07-31

Тема релиза — подтверждения: как сократить их число, не расширив права. Плюс починка двух скриптов, которые не запускались на Windows PowerShell 5.1.

### Added
- `claude-settings/` — базовый профиль разрешений: `settings.json.example` (разворачивается в `.claude/settings.json`) и `README.md` с границами профиля и списком того, что нельзя добавлять в `allow` никогда.
- `docs/permissions.md` — методика: почему правила помогают меньше, чем кажется; порядок «сменить инструмент → стандартизировать форму → узкое правило»; таблица можно/нельзя; готовый скрипт замера транскриптов; две ловушки замера на Windows.
- `obsidian-aura/wiki/runbook-permission-audit.md` — процедура аудита подтверждений (Prerequisites / Procedure / Verification / What NOT to do / Rollback).
- `auto-memory-templates/feedback_tool_choice_over_shell.md.example` — поведенческое правило: Read/Grep/Glob вместо shell, git через Bash, канонические формы запуска.
- `install.ps1` / `install.sh` — флаг `-CopySettings` / `--copy-settings`: разворачивает профиль в `<install-dir>/.claude/settings.json`, существующий файл без `-Force` не трогает.
- `smoke-test.ps1` — две новые группы проверок: контроль опасных правил в поставляемом профиле (wildcard на интерпретаторы, раннеры, `git log`, `gh api`, `curl`; правила с пайпом или редиректом) и контроль кодировки/синтаксиса всех `.ps1`.
- `AGENT-MANUAL.md` §5.8 «Аудит подтверждений» + строка в таблице триггеров §3.1.
- `docs/troubleshooting.md` — два раздела: «`.ps1` не запускается: The string is missing the terminator» и «Claude спрашивает подтверждение почти на каждую команду».

### Fixed
- **`install.ps1` и `smoke-test.ps1` не запускались на Windows PowerShell 5.1.** Файлы были сохранены в UTF-8 без BOM, PowerShell 5.1 читает `.ps1` как ANSI, и длинное тире превращалось в последовательность с типографской кавычкой `”`, которую парсер считает закрывающей кавычкой строки. `smoke-test.ps1` падал с 18 ошибками разбора, `install.ps1` — с одной. Оба пересохранены как UTF-8 with BOM; регресс закрыт проверкой в самом smoke-test.
- `install.sh`: диапазон `sed` в `usage()` захватывал строку `set -euo pipefail` и печатал её в help.

### Changed
- `README.md`: `claude-settings/` в структуре пакета, `-CopySettings` в quick start, новый принцип «против подтверждений сначала меняй инструмент, а не права».
- `INSTALL.md`: новый шаг 6 «Профиль разрешений» (первая сессия Claude стала шагом 7), флаги в обеих таблицах параметров, актуализирован ожидаемый вывод smoke-test.
- `VERSION`: 0.2.0 → 0.3.0.

## [0.2.0] — 2026-05-21

### Added
- `install.sh` — cross-platform installer (macOS/Linux), функциональный паритет с `install.ps1`.
- Auto-memory automation в обоих installer'ах: генерация encoded-пути `~/.claude/projects/c--<encoded>/memory/` + копирование шаблонов одной командой через `-CopyMemory` / `--copy-memory`.
- `BOOTSTRAP.md`: раздел Recovery — продолжение прерванного bootstrap.
- `BOOTSTRAP.md`: idempotency-проверки в каждом из 8 шагов адаптации.
- `README.md`: Mermaid workflow-диаграмма, ASCII-структура папок, shields.io badges (version/license/platform/agent).
- Корневой `CHANGELOG.md` (этот файл).
- Git tag `v0.1.0` ретроактивно + `v0.2.0` + GitHub Releases.
- GitHub topics: obsidian, claude-code, claude, anthropic, second-brain, methodology, agent-first, knowledge-base.

### Changed
- `BOOTSTRAP.md` Q1: «проект и окружение» — переведён из «свободного ввода через AskUserQuestion» (что не поддерживалось) в обычный текстовый вопрос Claude.
- `BOOTSTRAP.md`: раздел «Что если пользователь хочет содержательную работу до завершения bootstrap» — добавлена прагматичная логика разрешения.
- `INSTALL.md`: обновлены инструкции под install.sh + auto-memory automation.
- `VERSION`: 0.1.0 → 0.2.0.

### Fixed
- Auto-memory путь больше не требуется кодировать вручную пользователем (закрыт P1 trip-wire #1 из аудита v0.1.0).

## [0.1.0] — 2026-05-21

### Added
- Generalized vault skeleton: `obsidian-aura/AGENTS.md` + 3 methodology pages + 9 шаблонов страниц (4 базовых: adr/incident/runbook/weekly-review + 5 agent-first: component/reference/contract/domain-hub/inventory).
- `AGENT-MANUAL.md` — playbook для Claude в любой сессии (1085 строк).
- `BOOTSTRAP.md` — исполняемый промт первой сессии (4 вопроса + 8 шагов адаптации).
- `auto-memory-templates/` — 5 .example файлов (MEMORY + user_language + user_role + feedback_technical_autonomy + feedback_confirm_before_mutations) + README.
- `install.ps1` (PowerShell) — установщик с symlink + copy-fallback.
- `smoke-test.ps1` — верификация инсталляции.
- `docs/` — concepts.md, workflows.md, customization.md, troubleshooting.md.
- `README.md`, `INSTALL.md`, `LICENSE` (MIT), `VERSION` (0.1.0), `.gitignore`.

### Notes
- Initial release. Методология основана на реальном предрелизном проекте.

[Unreleased]: https://github.com/klimG95/claude-knowledge-base/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/klimG95/claude-knowledge-base/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/klimG95/claude-knowledge-base/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/klimG95/claude-knowledge-base/releases/tag/v0.1.0
