# Changelog

Все значимые изменения пакета `claude-knowledge-base` фиксируются здесь.

Формат — [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), версионирование — [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

(Здесь накапливаются изменения в `main`, до выкатки следующей версии.)

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

[Unreleased]: https://github.com/klimG95/claude-knowledge-base/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/klimG95/claude-knowledge-base/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/klimG95/claude-knowledge-base/releases/tag/v0.1.0
