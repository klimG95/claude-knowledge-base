# INSTALL — установка claude-knowledge-base

## Prerequisites

- **Claude Code CLI** (или совместимый агент с поддержкой `AGENTS.md` / `CLAUDE.md`). Проверка: `claude --version`.
- **Obsidian** — для визуализации vault'а и graph-view. Опц.: vault работает и без Obsidian (markdown + frontmatter — стандарт). Скачать: [obsidian.md](https://obsidian.md).
- **Git** — для clone и последующих `git pull` обновлений методологии. Проверка: `git --version`.
- **PowerShell 5.1+** (Windows, входит в систему) или **bash** (macOS/Linux).
- **Administrator-права** (Windows) — нужны только для создания symlink через `mklink`. Если их нет — installer автоматически переключится на copy-fallback (см. ниже).

## Шаги

### 1. Clone репо

```powershell
git clone https://github.com/klimG95/claude-knowledge-base.git <install-dir>
cd <install-dir>
```

`<install-dir>` — путь, где будет жить vault. Можно `.` для текущей папки. Рекомендуется отдельная папка вне рабочих проектов.

### 2. Установка (PowerShell, Windows)

```powershell
.\install.ps1 -InstallDir .
# или конкретный путь:
.\install.ps1 -InstallDir "C:\path\to\install"
```

Параметры:

| Параметр | Назначение |
|----------|------------|
| `-InstallDir <path>` | Где разворачивать. По умолчанию — `.` |
| `-Force` | Перезаписать существующий symlink/копию `AGENTS.md` без вопросов |
| `-SkipSymlink` | Не создавать symlink (полезно для тестов) |
| `-Verbose` | Подробный вывод |

Что делает installer:

1. Проверяет, что запущен из корня репо (наличие `obsidian-aura/AGENTS.md`).
2. Создаёт symlink `<InstallDir>/AGENTS.md` → `<InstallDir>/obsidian-aura/AGENTS.md`. Если прав Admin нет — копирует с warning.
3. Проверяет git-статус папки. Если не git-репо — info про то, что обновления через `git pull` недоступны.
4. Ищет Obsidian на диске — для подсказки, где открыть vault.
5. Опц. предлагает скопировать `.example`-шаблоны auto-memory в `~/.claude/projects/.../memory/`.

### 3. Установка (macOS/Linux, manual)

Скрипта под bash в пакете нет (см. issue #1 если нужен). Manual вариант:

```bash
cd <install-dir>
ln -s obsidian-aura/AGENTS.md AGENTS.md
```

Дальше шаги идентичны Windows-варианту.

### 4. Установка Dataview-плагина в Obsidian (опционально)

Vault использует Dataview для динамических индексов: список ADR, runbook'ов, страниц по тегу. Без Dataview всё читается, но индексы не строятся.

1. Открыть vault в Obsidian: `File → Open vault → Open folder as vault → <install-dir>/obsidian-aura/`.
2. `Settings → Community plugins → Turn on community plugins → Browse`.
3. Найти **Dataview** → `Install` → `Enable`.
4. Перезагрузить vault (Ctrl+R).

После активации в `methodology-overview.md` и MOC-страницах появятся живые таблицы.

### 5. Auto-memory (опционально)

Auto-memory — persistent layer памяти Claude между сессиями. Хранится в `~/.claude/projects/c--<encoded-cwd>/memory/MEMORY.md`. `<encoded-cwd>` — путь к проекту, где `\` и `:` заменены на `-`.

Чтобы Claude помнил твои preferences (язык общения, уровень технического разговора, степень автономности агента):

1. Скопируй нужные `.example`-файлы из `auto-memory-templates/` в свой memory-каталог.
2. Убери суффикс `.example`.
3. Отредактируй под себя.
4. Добавь указатели в `MEMORY.md` (формат описан в `auto-memory-templates/README.md`).

Полный гайд — `auto-memory-templates/README.md`.

### 6. Первая сессия Claude

В корне `<install-dir>` запусти:

```powershell
claude
```

Первый промт:

```
Прочитай BOOTSTRAP.md и приступай.
```

Claude задаст 4 вопроса (язык общения, имя/scope проекта, технический уровень собеседника, степень автономности), затем:

- Создаст project-specific MOC в `obsidian-aura/wiki/`.
- Обновит project-section в `obsidian-aura/AGENTS.md`.
- Предложит набросать первый ADR с контекстом проекта.
- Покажет дальнейшие шаги.

## Verify

После установки запусти smoke-test:

```powershell
.\smoke-test.ps1 -InstallDir .
```

Ожидаемый вывод — все проверки `[OK]`:

```
[OK]   obsidian-aura/AGENTS.md exists
[OK]   AGENTS.md symlink/copy present
[OK]   wiki/templates/ contains 9 files
[OK]   BOOTSTRAP.md readable
[OK]   AGENT-MANUAL.md readable
[OK]   VERSION = 0.1.0
```

Если есть `[FAIL]` — открой `docs/troubleshooting.md`, найди соответствующий пункт.

## Troubleshooting (краткое)

Полный список — [docs/troubleshooting.md](docs/troubleshooting.md). Самое частое:

- **`mklink` требует Administrator** — запусти PowerShell от админа (`Run as Administrator`) и повтори, либо используй `install.ps1` без admin — он сам переключится на copy-fallback (с предупреждением: при обновлении конституции придётся синхронизировать вручную).
- **Dataview не активирован** — индексы пустые. Включи плагин (шаг 4).
- **Auto-memory не подгружается** — проверь, что путь к memory соответствует CWD проекта (encoded `\` → `-`, `:` → `-`).
- **Claude не видит AGENTS.md** — проверь, что symlink/копия в корне install-dir, а не в `obsidian-aura/`.
- **`git pull` ругается на изменённые файлы** — методология обновлена, локальные правки в шаблонах конфликтуют. Создай свою ветку или используй `git stash`.
