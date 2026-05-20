<#
.SYNOPSIS
    Installer для claude-knowledge-base.

.DESCRIPTION
    Создаёт symlink AGENTS.md в корне install-dir, проверяет окружение
    (git, Obsidian), опционально предлагает развернуть auto-memory templates.

.PARAMETER InstallDir
    Путь, где разворачивать пакет. По умолчанию — текущая директория.

.PARAMETER Force
    Перезаписать существующий AGENTS.md без подтверждения.

.PARAMETER SkipSymlink
    Не создавать symlink (полезно для тестов / CI).

.EXAMPLE
    .\install.ps1 -InstallDir .

.EXAMPLE
    .\install.ps1 -InstallDir "C:\projects\kb" -Force
#>

[CmdletBinding()]
param(
    [string]$InstallDir = ".",
    [switch]$Force,
    [switch]$SkipSymlink
)

$ErrorActionPreference = "Stop"

# --- Helpers ----------------------------------------------------------------

function Write-OK    ($msg) { Write-Host "[OK]   $msg" -ForegroundColor Green }
function Write-Warn2 ($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Fail  ($msg) { Write-Host "[FAIL] $msg" -ForegroundColor Red }
function Write-Info  ($msg) { Write-Host "[INFO] $msg" -ForegroundColor Cyan }

function Test-Administrator {
    $current = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($current)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# --- Resolve install dir -----------------------------------------------------

try {
    $InstallDir = (Resolve-Path -Path $InstallDir -ErrorAction Stop).Path
} catch {
    Write-Fail "InstallDir '$InstallDir' не существует."
    exit 1
}

Write-Info "Install dir: $InstallDir"

# --- Pre-checks --------------------------------------------------------------

$vaultAgents = Join-Path $InstallDir "obsidian-aura\AGENTS.md"
$templatesDir = Join-Path $InstallDir "obsidian-aura\wiki\templates"

if (-not (Test-Path $vaultAgents)) {
    Write-Fail "Не найден obsidian-aura\AGENTS.md в $InstallDir."
    Write-Fail "Похоже, installer запущен не из корня репо. Сначала clone:"
    Write-Fail "  git clone https://github.com/klimG95/claude-knowledge-base.git"
    exit 1
}
Write-OK "obsidian-aura\AGENTS.md найден"

if (-not (Test-Path $templatesDir)) {
    Write-Warn2 "Папка obsidian-aura\wiki\templates не найдена. Vault неполный, но продолжаем."
} else {
    Write-OK "Папка templates найдена"
}

# --- Symlink AGENTS.md -------------------------------------------------------

$rootAgents = Join-Path $InstallDir "AGENTS.md"
$relTarget  = "obsidian-aura\AGENTS.md"

if ($SkipSymlink) {
    Write-Info "SkipSymlink: пропускаем создание AGENTS.md в корне"
} else {
    if (Test-Path $rootAgents) {
        if ($Force) {
            Remove-Item $rootAgents -Force
            Write-Info "Старый AGENTS.md удалён (-Force)"
        } else {
            Write-Warn2 "AGENTS.md уже существует в корне. Используй -Force для перезаписи."
        }
    }

    if (-not (Test-Path $rootAgents)) {
        $symlinkCreated = $false
        try {
            New-Item -ItemType SymbolicLink -Path $rootAgents -Target $relTarget -ErrorAction Stop | Out-Null
            $symlinkCreated = $true
            Write-OK "Symlink AGENTS.md -> $relTarget создан"
        } catch {
            Write-Warn2 "Не удалось создать symlink: $($_.Exception.Message)"
            if (-not (Test-Administrator)) {
                Write-Warn2 "Запусти PowerShell от Administrator для создания symlink, либо используй copy-fallback."
            }
            Write-Info "Fallback: копируем AGENTS.md в корень."
            try {
                Copy-Item -Path $vaultAgents -Destination $rootAgents -Force
                Write-OK "Копия AGENTS.md создана"
                Write-Warn2 "ВНИМАНИЕ: это копия, не symlink. При обновлении конституции"
                Write-Warn2 "(obsidian-aura\AGENTS.md) скопируй файл вручную или пересоздай"
                Write-Warn2 "symlink из-под Administrator."
            } catch {
                Write-Fail "Copy-fallback тоже не сработал: $($_.Exception.Message)"
                exit 1
            }
        }
    }
}

# --- Git check ---------------------------------------------------------------

$gitDir = Join-Path $InstallDir ".git"
if (Test-Path $gitDir) {
    Write-OK "Git-репо обнаружен — обновления методологии доступны через git pull"
} else {
    Write-Warn2 "Папка не под git. Обновления методологии через git pull недоступны."
    Write-Warn2 "Рекомендуется: git clone https://github.com/klimG95/claude-knowledge-base.git"
}

# --- Obsidian discovery ------------------------------------------------------

$obsidianCandidates = @(
    "$env:LOCALAPPDATA\Obsidian\Obsidian.exe",
    "$env:ProgramFiles\Obsidian\Obsidian.exe",
    "${env:ProgramFiles(x86)}\Obsidian\Obsidian.exe"
) | Where-Object { $_ -and (Test-Path $_) }

if ($obsidianCandidates.Count -gt 0) {
    Write-OK "Obsidian обнаружен: $($obsidianCandidates[0])"
    Write-Info "Открой vault: File -> Open folder as vault -> $InstallDir\obsidian-aura"
} else {
    Write-Warn2 "Obsidian не найден в стандартных местах."
    Write-Info "Vault работает и без Obsidian (просто markdown), но граф и Dataview-таблицы видны только в Obsidian."
    Write-Info "Скачать: https://obsidian.md"
}

# --- Auto-memory prompt ------------------------------------------------------

$autoMemSrc = Join-Path $InstallDir "auto-memory-templates"
if (Test-Path $autoMemSrc) {
    Write-Host ""
    $answer = Read-Host "Скопировать auto-memory шаблоны в ~/.claude/projects/.../memory/? [y/N]"
    if ($answer -match '^(y|Y|yes|YES)$') {
        $encoded = ($InstallDir -replace '[:\\]', '-')
        # Убираем ведущие минусы
        $encoded = $encoded.TrimStart('-')
        $defaultMemDir = Join-Path $env:USERPROFILE ".claude\projects\c--$encoded\memory"
        Write-Info "Default путь: $defaultMemDir"
        $memDir = Read-Host "Путь к memory-каталогу (Enter — default)"
        if ([string]::IsNullOrWhiteSpace($memDir)) { $memDir = $defaultMemDir }

        if (-not (Test-Path $memDir)) {
            try {
                New-Item -ItemType Directory -Path $memDir -Force | Out-Null
                Write-OK "Создана папка $memDir"
            } catch {
                Write-Fail "Не удалось создать $memDir : $($_.Exception.Message)"
                $memDir = $null
            }
        }

        if ($memDir) {
            $examples = Get-ChildItem -Path $autoMemSrc -Filter "*.example" -File -ErrorAction SilentlyContinue
            if ($examples.Count -eq 0) {
                Write-Warn2 "В auto-memory-templates не найдено .example-файлов"
            }
            foreach ($ex in $examples) {
                $destName = $ex.Name -replace '\.example$',''
                $destPath = Join-Path $memDir $destName
                if ((Test-Path $destPath) -and -not $Force) {
                    Write-Warn2 "  Пропуск $destName — уже существует (используй -Force для перезаписи)"
                    continue
                }
                Copy-Item -Path $ex.FullName -Destination $destPath -Force
                Write-OK "  Скопирован $destName"
            }
            Write-Info "Отредактируй файлы под себя. См. auto-memory-templates\README.md."
        }
    } else {
        Write-Info "Auto-memory пропущен. Можно сделать вручную позже."
    }
} else {
    Write-Warn2 "Папка auto-memory-templates отсутствует — этот шаг пропущен."
}

# --- Final report ------------------------------------------------------------

Write-Host ""
Write-Host "=== Установка завершена ===" -ForegroundColor Green
Write-Host ""
Write-Host "Следующие шаги:" -ForegroundColor Cyan
Write-Host "  1. (Опц.) Открой $InstallDir\obsidian-aura\ в Obsidian и установи Dataview."
Write-Host "  2. Запусти Claude из $InstallDir`:"
Write-Host "       claude" -ForegroundColor White
Write-Host "  3. Первый промт:" -ForegroundColor Cyan
Write-Host "       Прочитай BOOTSTRAP.md и приступай." -ForegroundColor White
Write-Host ""
Write-Host "Проверка установки:" -ForegroundColor Cyan
Write-Host "  .\smoke-test.ps1 -InstallDir `"$InstallDir`"" -ForegroundColor White
Write-Host ""
