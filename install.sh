#!/usr/bin/env bash
# install.sh — cross-platform installer для claude-knowledge-base (macOS/Linux).
#
# Создаёт symlink AGENTS.md в корне install-dir, проверяет окружение
# (git, Obsidian), опционально копирует auto-memory templates в
# ~/.claude/projects/<encoded-install-path>/memory/.
#
# Usage:
#   ./install.sh [options]
#
# Options:
#   -d, --install-dir <path>   Целевая директория (default: .)
#   -f, --force                Перезаписывать существующий AGENTS.md
#       --skip-symlink         Не создавать корневой AGENTS.md
#       --copy-memory          Автоматически копировать auto-memory шаблоны
#                              (без интерактивного prompt'а)
#       --copy-settings        Развернуть базовый профиль разрешений в
#                              <install-dir>/.claude/settings.json
#   -v, --verbose              Подробный вывод
#   -h, --help                 Показать help

set -euo pipefail

# --- ANSI colors ------------------------------------------------------------

if [[ -t 1 ]]; then
    C_GREEN=$'\033[0;32m'
    C_YELLOW=$'\033[0;33m'
    C_RED=$'\033[0;31m'
    C_CYAN=$'\033[0;36m'
    C_RESET=$'\033[0m'
else
    C_GREEN=""; C_YELLOW=""; C_RED=""; C_CYAN=""; C_RESET=""
fi

log_ok()   { printf '%s[OK]%s   %s\n'   "$C_GREEN"  "$C_RESET" "$*"; }
log_warn() { printf '%s[WARN]%s %s\n'   "$C_YELLOW" "$C_RESET" "$*"; }
log_fail() { printf '%s[FAIL]%s %s\n'   "$C_RED"    "$C_RESET" "$*" >&2; }
log_info() { printf '%s[INFO]%s %s\n'   "$C_CYAN"   "$C_RESET" "$*"; }
log_verbose() { [[ "$VERBOSE" == "1" ]] && printf '%s[VERB]%s %s\n' "$C_CYAN" "$C_RESET" "$*" || true; }

# --- Defaults ---------------------------------------------------------------

INSTALL_DIR="."
FORCE=0
SKIP_SYMLINK=0
COPY_MEMORY="ask"     # ask | yes | no
COPY_SETTINGS="ask"   # ask | yes | no
VERBOSE=0

# --- Usage ------------------------------------------------------------------

usage() {
    sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# --- Arg parsing ------------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--install-dir)
            INSTALL_DIR="${2:?Missing value for $1}"
            shift 2
            ;;
        -f|--force)
            FORCE=1
            shift
            ;;
        --skip-symlink)
            SKIP_SYMLINK=1
            shift
            ;;
        --copy-memory)
            COPY_MEMORY="yes"
            shift
            ;;
        --copy-settings)
            COPY_SETTINGS="yes"
            shift
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_fail "Unknown argument: $1"
            exit 1
            ;;
    esac
done

# --- Resolve install dir ----------------------------------------------------

if [[ ! -d "$INSTALL_DIR" ]]; then
    log_fail "InstallDir '$INSTALL_DIR' не существует."
    exit 1
fi

# Resolve to absolute path (portable: no readlink -f on macOS by default)
INSTALL_DIR="$(cd "$INSTALL_DIR" && pwd)"
log_info "Install dir: $INSTALL_DIR"

# --- Pre-checks -------------------------------------------------------------

VAULT_AGENTS="$INSTALL_DIR/obsidian-aura/AGENTS.md"
TEMPLATES_DIR="$INSTALL_DIR/obsidian-aura/wiki/templates"

if [[ ! -f "$VAULT_AGENTS" ]]; then
    log_fail "Не найден obsidian-aura/AGENTS.md в $INSTALL_DIR."
    log_fail "Похоже, installer запущен не из корня репо. Сначала clone:"
    log_fail "  git clone https://github.com/klimG95/claude-knowledge-base.git"
    exit 1
fi
log_ok "obsidian-aura/AGENTS.md найден"

if [[ ! -d "$TEMPLATES_DIR" ]]; then
    log_warn "Папка obsidian-aura/wiki/templates не найдена. Vault неполный, но продолжаем."
else
    log_ok "Папка templates найдена"
fi

# --- Symlink AGENTS.md ------------------------------------------------------

ROOT_AGENTS="$INSTALL_DIR/AGENTS.md"
REL_TARGET="obsidian-aura/AGENTS.md"

if [[ "$SKIP_SYMLINK" == "1" ]]; then
    log_info "SkipSymlink: пропускаем создание AGENTS.md в корне"
else
    if [[ -e "$ROOT_AGENTS" || -L "$ROOT_AGENTS" ]]; then
        if [[ "$FORCE" == "1" ]]; then
            rm -f "$ROOT_AGENTS"
            log_info "Старый AGENTS.md удалён (--force)"
        else
            log_warn "AGENTS.md уже существует в корне. Используй --force для перезаписи."
        fi
    fi

    if [[ ! -e "$ROOT_AGENTS" && ! -L "$ROOT_AGENTS" ]]; then
        if (cd "$INSTALL_DIR" && ln -s "$REL_TARGET" "AGENTS.md") 2>/dev/null; then
            log_ok "Symlink AGENTS.md -> $REL_TARGET создан"
        else
            log_warn "Не удалось создать symlink. Fallback: копируем AGENTS.md в корень."
            if cp "$VAULT_AGENTS" "$ROOT_AGENTS"; then
                log_ok "Копия AGENTS.md создана"
                log_warn "ВНИМАНИЕ: это копия, не symlink. При обновлении конституции"
                log_warn "(obsidian-aura/AGENTS.md) скопируй файл вручную."
            else
                log_fail "Copy-fallback тоже не сработал."
                exit 1
            fi
        fi
    fi
fi

# --- Git check --------------------------------------------------------------

if [[ -d "$INSTALL_DIR/.git" ]]; then
    log_ok "Git-репо обнаружен — обновления методологии доступны через git pull"
else
    log_warn "Папка не под git. Обновления методологии через git pull недоступны."
    log_warn "Рекомендуется: git clone https://github.com/klimG95/claude-knowledge-base.git"
fi

if ! command -v git >/dev/null 2>&1; then
    log_warn "git не установлен в системе — установи для возможности обновлений."
else
    log_verbose "git найден: $(command -v git)"
fi

# --- Obsidian discovery -----------------------------------------------------

OBSIDIAN_FOUND=""
case "$(uname -s)" in
    Darwin*)
        if [[ -d "/Applications/Obsidian.app" ]]; then
            OBSIDIAN_FOUND="/Applications/Obsidian.app"
        elif command -v obsidian >/dev/null 2>&1; then
            OBSIDIAN_FOUND="$(command -v obsidian)"
        fi
        ;;
    Linux*)
        if command -v obsidian >/dev/null 2>&1; then
            OBSIDIAN_FOUND="$(command -v obsidian)"
        elif command -v flatpak >/dev/null 2>&1 && flatpak list 2>/dev/null | grep -qi obsidian; then
            OBSIDIAN_FOUND="flatpak (md.obsidian.Obsidian)"
        elif command -v snap >/dev/null 2>&1 && snap list 2>/dev/null | grep -qi obsidian; then
            OBSIDIAN_FOUND="snap (obsidian)"
        fi
        ;;
    *)
        log_verbose "Unknown OS: $(uname -s) — Obsidian discovery пропущен"
        ;;
esac

if [[ -n "$OBSIDIAN_FOUND" ]]; then
    log_ok "Obsidian обнаружен: $OBSIDIAN_FOUND"
    log_info "Открой vault: File -> Open folder as vault -> $INSTALL_DIR/obsidian-aura"
else
    log_warn "Obsidian не найден в стандартных местах."
    log_info "Vault работает и без Obsidian (просто markdown), но граф и Dataview-таблицы видны только в Obsidian."
    log_info "Скачать: https://obsidian.md"
fi

# --- Encoded path для auto-memory -------------------------------------------

# Правило кодирования (matches install.ps1 и Claude Code CLI):
#   - Windows-style path "C:\foo\bar"  -> "c--foo-bar" (drive letter lowercased)
#   - POSIX path        "/home/u/foo"  -> "-home-u-foo"
# tr используется вместо ${var//\\/-} для устойчивости в Git Bash / MSYS.
encode_path() {
    local p="$1"
    if [[ "$p" =~ ^([A-Za-z]):(.*)$ ]]; then
        local drive="${BASH_REMATCH[1]}"
        local rest="${BASH_REMATCH[2]}"
        # Lowercase drive letter
        drive="$(printf '%s' "$drive" | tr '[:upper:]' '[:lower:]')"
        # Replace \ then / with - (sequential — двух-символьный set в tr ведёт себя
        # непредсказуемо в некоторых сборках)
        rest="$(printf '%s' "$rest" | tr '\\' '-' 2>/dev/null | tr '/' '-')"
        # Strip leading dash (path starts with separator)
        rest="${rest#-}"
        printf '%s--%s' "$drive" "$rest"
    else
        # POSIX: replace / with -, keep leading dash
        local rest
        rest="$(printf '%s' "$p" | tr '/' '-')"
        printf '%s' "$rest"
    fi
}

# --- Auto-memory ------------------------------------------------------------

AUTO_MEM_SRC="$INSTALL_DIR/auto-memory-templates"

if [[ ! -d "$AUTO_MEM_SRC" ]]; then
    log_warn "Папка auto-memory-templates отсутствует — этот шаг пропущен."
else
    do_copy=0
    case "$COPY_MEMORY" in
        yes) do_copy=1 ;;
        no)  do_copy=0 ;;
        ask)
            echo ""
            if [[ -t 0 ]]; then
                printf '%sСкопировать auto-memory шаблоны в ~/.claude/projects/.../memory/?%s [y/N] ' "$C_CYAN" "$C_RESET"
                read -r answer || answer=""
                case "$answer" in
                    y|Y|yes|YES) do_copy=1 ;;
                    *) do_copy=0 ;;
                esac
            else
                log_info "Не интерактивный режим — auto-memory пропущен (используй --copy-memory для авто-копирования)."
                do_copy=0
            fi
            ;;
    esac

    if [[ "$do_copy" == "1" ]]; then
        encoded="$(encode_path "$INSTALL_DIR")"
        MEM_DIR="$HOME/.claude/projects/$encoded/memory"
        log_info "Auto-memory target: $MEM_DIR"

        if ! mkdir -p "$MEM_DIR"; then
            log_fail "Не удалось создать $MEM_DIR"
        else
            shopt -s nullglob
            templates=("$AUTO_MEM_SRC"/*.example)
            shopt -u nullglob
            if [[ ${#templates[@]} -eq 0 ]]; then
                log_warn "В auto-memory-templates не найдено .example-файлов"
            fi
            for tpl in "${templates[@]}"; do
                base="$(basename "$tpl")"
                dest_name="${base%.example}"
                dest_path="$MEM_DIR/$dest_name"
                if [[ -e "$dest_path" && "$FORCE" != "1" ]]; then
                    log_warn "  Пропуск $dest_name — уже существует (используй --force для перезаписи)"
                    continue
                fi
                cp "$tpl" "$dest_path"
                log_ok "  Скопирован $dest_name"
            done
            log_info "Отредактируй файлы под себя. См. auto-memory-templates/README.md."
        fi
    else
        log_info "Auto-memory пропущен. Можно сделать вручную позже."
    fi
fi

# --- Базовый профиль разрешений ---------------------------------------------

SETTINGS_SRC="$INSTALL_DIR/claude-settings/settings.json.example"

if [[ ! -f "$SETTINGS_SRC" ]]; then
    log_warn "Файл claude-settings/settings.json.example отсутствует — этот шаг пропущен."
else
    do_settings=0
    case "$COPY_SETTINGS" in
        yes) do_settings=1 ;;
        no)  do_settings=0 ;;
        ask)
            echo ""
            if [[ -t 0 ]]; then
                printf '%sРазвернуть базовый профиль разрешений в .claude/settings.json?%s [y/N] ' "$C_CYAN" "$C_RESET"
                read -r answer || answer=""
                case "$answer" in
                    y|Y|yes|YES) do_settings=1 ;;
                    *) do_settings=0 ;;
                esac
            else
                log_info "Не интерактивный режим — профиль разрешений пропущен (используй --copy-settings)."
                do_settings=0
            fi
            ;;
    esac

    if [[ "$do_settings" == "1" ]]; then
        CLAUDE_DIR="$INSTALL_DIR/.claude"
        SETTINGS_DEST="$CLAUDE_DIR/settings.json"

        if ! mkdir -p "$CLAUDE_DIR"; then
            log_fail "Не удалось создать $CLAUDE_DIR"
        elif [[ -e "$SETTINGS_DEST" && "$FORCE" != "1" ]]; then
            log_warn ".claude/settings.json уже существует — не трогаю (используй --force для перезаписи)."
            log_info "Слить вручную: правила из claude-settings/settings.json.example в секцию permissions.allow."
        elif cp "$SETTINGS_SRC" "$SETTINGS_DEST"; then
            log_ok "Профиль разрешений развёрнут: $SETTINGS_DEST"
            log_warn "Профиль включает defaultMode=acceptEdits — правки файлов применяются без спроса."
            log_info "Границы профиля и что дописать под проект — claude-settings/README.md."
        else
            log_fail "Не удалось скопировать профиль разрешений."
        fi
    else
        log_info "Профиль разрешений пропущен. Развернуть позже: --copy-settings (см. INSTALL.md шаг 6)."
    fi
fi

# --- Final report -----------------------------------------------------------

echo ""
printf '%s=== Установка завершена ===%s\n' "$C_GREEN" "$C_RESET"
echo ""
printf '%sСледующие шаги:%s\n' "$C_CYAN" "$C_RESET"
echo "  1. (Опц.) Открой $INSTALL_DIR/obsidian-aura/ в Obsidian и установи Dataview."
echo "  2. Запусти Claude из $INSTALL_DIR:"
echo "       claude"
printf '  3. Первый промт:\n'
echo "       Прочитай BOOTSTRAP.md и приступай."
echo ""
printf '%sПроверка установки:%s\n' "$C_CYAN" "$C_RESET"
echo "  ./smoke-test.sh --install-dir \"$INSTALL_DIR\"   # если есть"
echo "  или вручную: ls -la AGENTS.md && cat VERSION"
echo ""

exit 0
