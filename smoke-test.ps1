# smoke-test.ps1 — верификация установки claude-knowledge-base
#
# Проверяет целостность распакованного пакета: структура папок, обязательные файлы,
# отсутствие hardcoded имён реального проекта, формат VERSION, состояние auto-memory.
#
# Параметры:
#   -InstallDir <path>   путь к корню установки (default: текущая директория)
#   -Verbose             подробный вывод каждой проверки
#
# Output: структурированный список [OK]/[WARN]/[FAIL] на проверку + итоговый summary.
# Exit code: 0 при успехе (нет FAIL), 1 при хотя бы одном FAIL.

[CmdletBinding()]
param(
    [string]$InstallDir = (Get-Location).Path
)

$ErrorActionPreference = 'Continue'
$script:Failures = 0
$script:Warnings = 0
$script:Passed   = 0

function Write-Check {
    param(
        [string]$Status,
        [string]$Name,
        [string]$Detail = ''
    )
    $color = switch ($Status) {
        'OK'   { 'Green' }
        'WARN' { 'Yellow' }
        'FAIL' { 'Red' }
        default { 'Gray' }
    }
    $line = "[{0}] {1}" -f $Status.PadRight(4), $Name
    if ($Detail) { $line += " — $Detail" }
    Write-Host $line -ForegroundColor $color

    switch ($Status) {
        'OK'   { $script:Passed++   }
        'WARN' { $script:Warnings++ }
        'FAIL' { $script:Failures++ }
    }
}

function Test-RequiredPath {
    param(
        [string]$Path,
        [string]$Label,
        [switch]$Directory
    )
    $exists = if ($Directory) { Test-Path -Path $Path -PathType Container } else { Test-Path -Path $Path -PathType Leaf }
    if ($exists) {
        Write-Check -Status 'OK' -Name $Label
    } else {
        Write-Check -Status 'FAIL' -Name $Label -Detail "missing: $Path"
    }
}

Write-Host ""
Write-Host "=== claude-knowledge-base smoke-test ===" -ForegroundColor Cyan
Write-Host "InstallDir: $InstallDir"
Write-Host ""

# --- 1. Структура папок ---
Write-Host "-- Структура папок --" -ForegroundColor Cyan
Test-RequiredPath -Path (Join-Path $InstallDir 'obsidian-aura')                 -Label 'obsidian-aura/'                 -Directory
Test-RequiredPath -Path (Join-Path $InstallDir 'obsidian-aura/wiki')            -Label 'obsidian-aura/wiki/'            -Directory
Test-RequiredPath -Path (Join-Path $InstallDir 'obsidian-aura/wiki/templates')  -Label 'obsidian-aura/wiki/templates/'  -Directory
Test-RequiredPath -Path (Join-Path $InstallDir 'obsidian-aura/raw')             -Label 'obsidian-aura/raw/'             -Directory
Test-RequiredPath -Path (Join-Path $InstallDir 'obsidian-aura/journal')         -Label 'obsidian-aura/journal/'         -Directory
Test-RequiredPath -Path (Join-Path $InstallDir 'auto-memory-templates')         -Label 'auto-memory-templates/'         -Directory
Test-RequiredPath -Path (Join-Path $InstallDir 'docs')                          -Label 'docs/'                          -Directory

# --- 2. Обязательные файлы ---
Write-Host ""
Write-Host "-- Обязательные файлы --" -ForegroundColor Cyan
Test-RequiredPath -Path (Join-Path $InstallDir 'obsidian-aura/AGENTS.md')       -Label 'obsidian-aura/AGENTS.md'
Test-RequiredPath -Path (Join-Path $InstallDir 'BOOTSTRAP.md')                  -Label 'BOOTSTRAP.md'
Test-RequiredPath -Path (Join-Path $InstallDir 'AGENT-MANUAL.md')               -Label 'AGENT-MANUAL.md'
Test-RequiredPath -Path (Join-Path $InstallDir 'VERSION')                       -Label 'VERSION'

# --- 3. Шаблоны (9 штук) ---
Write-Host ""
Write-Host "-- Шаблоны --" -ForegroundColor Cyan
$templates = @(
    'template-adr.md',
    'template-incident.md',
    'template-runbook.md',
    'template-weekly-review.md',
    'template-component.md',
    'template-reference.md',
    'template-contract.md',
    'template-domain-hub.md',
    'template-inventory.md'
)
$templatesDir = Join-Path $InstallDir 'obsidian-aura/wiki/templates'
foreach ($tpl in $templates) {
    Test-RequiredPath -Path (Join-Path $templatesDir $tpl) -Label "templates/$tpl"
}

# --- 4. Symlink или fallback ---
Write-Host ""
Write-Host "-- Symlink / fallback корневой AGENTS.md --" -ForegroundColor Cyan
$rootAgents = Join-Path $InstallDir 'AGENTS.md'
if (Test-Path -Path $rootAgents) {
    $item = Get-Item -Path $rootAgents -Force
    if ($item.LinkType -eq 'SymbolicLink' -or $item.LinkType -eq 'Junction') {
        Write-Check -Status 'OK' -Name 'AGENTS.md root link' -Detail "type: $($item.LinkType)"
    } else {
        Write-Check -Status 'WARN' -Name 'AGENTS.md root copy (fallback)' -Detail 'symlink не создан, используется копия — синхронизация ручная'
    }
} else {
    Write-Check -Status 'WARN' -Name 'AGENTS.md root entry' -Detail 'отсутствует — запусти install.ps1 для создания symlink или скопируй вручную'
}

# --- 5. VERSION формат (semver) ---
Write-Host ""
Write-Host "-- VERSION --" -ForegroundColor Cyan
$versionPath = Join-Path $InstallDir 'VERSION'
if (Test-Path -Path $versionPath) {
    $version = (Get-Content -Path $versionPath -Raw).Trim()
    if ($version -match '^\d+\.\d+\.\d+(-[A-Za-z0-9.-]+)?$') {
        Write-Check -Status 'OK' -Name 'VERSION semver' -Detail $version
    } else {
        Write-Check -Status 'FAIL' -Name 'VERSION semver' -Detail "не semver: '$version'"
    }
} else {
    Write-Check -Status 'FAIL' -Name 'VERSION semver' -Detail 'VERSION отсутствует'
}

# --- 6. Generalize-проверки (запрещённые имена) ---
Write-Host ""
Write-Host "-- Generalize: запрещённые имена --" -ForegroundColor Cyan
$forbiddenPatterns = @('auragrid', 'AuraGrid', 'klimG95', 'GridScalp')
$agentsPath = Join-Path $InstallDir 'obsidian-aura/AGENTS.md'
if (Test-Path -Path $agentsPath) {
    $agentsContent = Get-Content -Path $agentsPath -Raw
    $hit = $false
    foreach ($pat in $forbiddenPatterns) {
        if ($agentsContent -match [regex]::Escape($pat)) {
            Write-Check -Status 'FAIL' -Name "obsidian-aura/AGENTS.md mentions '$pat'" -Detail 'generalize пропущен'
            $hit = $true
        }
    }
    if (-not $hit) {
        Write-Check -Status 'OK' -Name 'obsidian-aura/AGENTS.md generalized'
    }
} else {
    Write-Check -Status 'FAIL' -Name 'obsidian-aura/AGENTS.md generalize check' -Detail 'файл отсутствует'
}

# --- 7. Шаблоны — запрещённые имена ---
Write-Host ""
Write-Host "-- Шаблоны: запрещённые имена --" -ForegroundColor Cyan
if (Test-Path -Path $templatesDir) {
    $tplFiles = Get-ChildItem -Path $templatesDir -Filter '*.md' -File
    $tplHit = $false
    foreach ($file in $tplFiles) {
        $content = Get-Content -Path $file.FullName -Raw
        foreach ($pat in $forbiddenPatterns) {
            if ($content -match [regex]::Escape($pat)) {
                Write-Check -Status 'FAIL' -Name "templates/$($file.Name) mentions '$pat'"
                $tplHit = $true
            }
        }
    }
    if (-not $tplHit) {
        Write-Check -Status 'OK' -Name 'templates/ generalized'
    }
} else {
    Write-Check -Status 'WARN' -Name 'templates/ generalize check' -Detail 'папка отсутствует'
}

# --- 8. auto-memory: warning при активированных шаблонах без кастомизации ---
Write-Host ""
Write-Host "-- auto-memory-templates --" -ForegroundColor Cyan
$memTplDir = Join-Path $InstallDir 'auto-memory-templates'
if (Test-Path -Path $memTplDir) {
    $allFiles = Get-ChildItem -Path $memTplDir -File
    $liveFiles = $allFiles | Where-Object { $_.Extension -eq '.md' -and -not ($_.Name -like '*.example') -and $_.Name -ne 'README.md' }
    $exampleFiles = $allFiles | Where-Object { $_.Name -like '*.example' }

    if ($exampleFiles.Count -gt 0) {
        Write-Check -Status 'OK' -Name 'auto-memory-templates: examples present' -Detail "$($exampleFiles.Count) шаблонов"
    } else {
        Write-Check -Status 'WARN' -Name 'auto-memory-templates: нет .example файлов'
    }

    if ($liveFiles.Count -gt 0) {
        Write-Check -Status 'WARN' -Name 'auto-memory-templates: активированы живые шаблоны' -Detail "$($liveFiles.Count) файлов без .example — проверь кастомизацию или перенос в memory/-папку"
    }
} else {
    Write-Check -Status 'WARN' -Name 'auto-memory-templates check' -Detail 'папка отсутствует'
}

# --- 9. docs/ — наличие основных страниц ---
Write-Host ""
Write-Host "-- docs/ --" -ForegroundColor Cyan
Test-RequiredPath -Path (Join-Path $InstallDir 'docs/concepts.md')        -Label 'docs/concepts.md'
Test-RequiredPath -Path (Join-Path $InstallDir 'docs/workflows.md')       -Label 'docs/workflows.md'
Test-RequiredPath -Path (Join-Path $InstallDir 'docs/troubleshooting.md') -Label 'docs/troubleshooting.md'

# --- Финальный отчёт ---
Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host ("Passed:   {0}" -f $script:Passed)   -ForegroundColor Green
Write-Host ("Warnings: {0}" -f $script:Warnings) -ForegroundColor Yellow
Write-Host ("Failures: {0}" -f $script:Failures) -ForegroundColor Red
Write-Host ""

if ($script:Failures -gt 0) {
    Write-Host "RESULT: FAIL — см. строки [FAIL] выше" -ForegroundColor Red
    exit 1
} elseif ($script:Warnings -gt 0) {
    Write-Host "RESULT: OK with warnings" -ForegroundColor Yellow
    exit 0
} else {
    Write-Host "RESULT: OK — установка целостна" -ForegroundColor Green
    exit 0
}
