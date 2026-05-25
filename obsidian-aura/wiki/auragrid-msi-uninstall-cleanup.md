---
type: concept
tags: [auragrid, packaging, msi, wix, uninstall, ux]
component: installer
layer: ops
shape: concept
created: 2026-05-25
updated: 2026-05-25
---

# AuraGrid — деинсталляция с опцией очистки данных

**TL;DR.** При деинсталляции GridScalp Bot пользователь может поставить галочку «также удалить все мои данные и настройки», после чего инсталлятор сотрёт `%APPDATA%\GridScalp\` (лицензия, пресеты, стратегии, логи). Без галочки данные сохраняются для следующей установки — это безопасный default, который закрывает [[feedback_release_checklist|боль тестировщика]] (старый yaml не перезаписывается новой сборкой). Галочка показывается в самом приложении (Settings → «Удалить программу»), потому что Tauri/WiX MSI не даёт показать кастомный диалог при запуске uninstall через «Программы и компоненты».

## Когда читать эту страницу

- При вопросе «как пользователь может удалить программу с данными».
- Перед изменением WiX-фрагмента или `request_uninstall` команды.
- Если в `%APPDATA%\GridScalp\` появилось новое имя файла/папки, которое тоже надо стирать.
- При жалобе «удалил программу — данные не стёрлись» (или «стёрлись, а я не хотел»).

## Идея

Стандартный MSI-uninstall через «Установка и удаление программ» запускается с **basic UI** (только progress bar) — никаких диалогов с галочками. Tauri использует `WixUI_InstallDir`, который тоже не показывает MaintenanceTypeDlg в этом сценарии. Кастомизировать WiX UI dialog для uninstall в Tauri-сборке — нетривиально и хрупко.

**Решение**: переносим галочку в **само приложение**. В Settings → «Опасная зона» добавлена кнопка «Удалить программу». При нажатии открывается confirm-диалог с галочкой «также удалить все мои данные и настройки». При подтверждении Tauri-команда `request_uninstall(delete_user_data)`:

1. Находит ProductCode по фиксированному UpgradeCode (WindowsInstaller COM через PowerShell).
2. Спавнит `msiexec /x {ProductCode} DELETE_USER_DATA={0|1} /qb` detached.
3. Через 500 мс закрывает окно приложения, чтобы msiexec не наткнулся на занятые файлы (Files in Use dialog).

MSI читает свойство `DELETE_USER_DATA` и при `=1` выполняет CustomAction (PowerShell `Remove-Item -Recurse -Force %APPDATA%\GridScalp`) перед `RemoveFiles` в `InstallExecuteSequence`.

## Реализация

| Подмодуль | Файл | Что делает |
|-----------|------|------------|
| WiX-фрагмент | `desktop/src-tauri/installer/cleanup.wxs` | `Property DELETE_USER_DATA` (default `0`, Secure), `CustomAction GridScalpRemoveUserData` (deferred + impersonate, ExeCommand=PowerShell rm), `InstallExecuteSequence` с условием `REMOVE="ALL" AND DELETE_USER_DATA="1"`, обёртка в `ComponentGroup GridScalpUserDataCleanup` (anchor для линкера) |
| Tauri config | `desktop/src-tauri/tauri.conf.json` | `bundle.windows.wix.fragmentPaths: ["./installer/cleanup.wxs"]` + `componentGroupRefs: ["GridScalpUserDataCleanup"]` — иначе фрагмент не попадёт в финальный MSI |
| Rust-команда | `desktop/src-tauri/src/uninstall.rs` | `find_product_code()` через `WindowsInstaller.Installer` COM + `RelatedProducts(UPGRADE_CODE)`; `#[tauri::command] request_uninstall(delete_user_data: bool)` — спавнит `msiexec /x` с флагами `CREATE_NO_WINDOW | DETACHED_PROCESS` |
| UI | `desktop/src/components/SettingsModal.tsx` | Кнопка «Удалить программу» в разделе «Опасная зона»; вложенный `Modal` с `Checkbox` «также удалить все мои данные и настройки» + красный `Alert` при выбранной галочке; на confirm — `invoke("request_uninstall", { deleteUserData })` → `setTimeout 500 ms` → `window.close()` |

### Поток событий

```
User clicks «Удалить программу»
   ↓
SettingsModal opens nested confirm Modal with Checkbox
   ↓
User toggles checkbox (default OFF — safe)
   ↓
User clicks «Удалить»
   ↓
invoke("request_uninstall", { deleteUserData })
   ├─ PowerShell: WindowsInstaller.Installer.RelatedProducts(UPGRADE_CODE) → ProductCode
   └─ msiexec.exe /x {ProductCode} DELETE_USER_DATA={0|1} /qb (detached)
   ↓
setTimeout(500) → window.close()
   ↓
msiexec executes uninstall:
   ├─ ... [стандартный flow: ProcessComponents, MsiUnpublishAssemblies, ...]
   ├─ Before RemoveFiles: IF DELETE_USER_DATA=1 → GridScalpRemoveUserData CA
   │     ↳ powershell Remove-Item -Recurse -Force %APPDATA%\GridScalp
   ├─ RemoveFiles, RemoveFolders, RemoveRegistryValues, ...
   └─ InstallFinalize
```

## Инварианты

1. **Default — данные сохраняются.** `DELETE_USER_DATA` имеет дефолт `0` в WiX-фрагменте. Все альтернативные сценарии запуска uninstall (через «Программы и компоненты», через прямой запуск .msi без UI, через `msiexec /x` без флага) **не удаляют данные**.
2. **Только при `REMOVE="ALL"`.** CustomAction условие включает `REMOVE="ALL"` — это защита от срабатывания на Modify/Repair (хотя Tauri их и так отключает через `ARPNOREPAIR=yes` и `ARPNOMODIFY=1`).
3. **`Impersonate="yes"` обязательно.** Без него `%APPDATA%` в PowerShell укажет на `C:\Windows\System32\config\systemprofile\AppData\Roaming\`, а не на пользовательский профиль. CustomAction в этом случае молча ничего не удалит.
4. **UpgradeCode фиксирован.** Константа `UPGRADE_CODE` в `uninstall.rs` должна совпадать с `tauri.conf.json` → `bundle.windows.wix.upgradeCode`. При изменении одного — обновить другое.
5. **`Return="ignore"` на CustomAction.** Если папки нет или файл занят antivirus'ом — uninstall не должен падать. Стирание данных — best-effort, основная цель (удалить программу) должна завершиться.

## UX-сценарии

| Сценарий | Откуда запуск | Видит галочку | Данные удалятся |
|----------|---------------|---------------|-----------------|
| In-app | Settings → «Удалить программу» | ✅ | Если поставил галочку |
| ARP (Программы и компоненты) | Windows ARP → «Удалить» | ❌ | ❌ (data stays) |
| Прямой .msi | Двойной клик по .msi → Remove | ❌ | ❌ (data stays) |
| CLI | `msiexec /x {ProductCode} DELETE_USER_DATA=1` | ❌ | ✅ |

In-app — основной канал для тестировщика/пользователя. ARP оставляет данные намеренно (защита от случайного удаления при reinstall).

## Что считается «пользовательскими данными»

Папка `%APPDATA%\GridScalp\` целиком:

- `license.json` — JWT, activation_id, license_key
- `wizard.json` — состояние визарда
- `settings.json` — язык, autostart, server_url override
- `strategies.json` — индекс multi-strategy
- `strategies/<magic>.yaml` — пресеты каждой стратегии
- `state.sqlite` (+ WAL/SHM) — runtime state бота
- `logs/desktop.log.*` — десктоп-логи
- `logs/bot.log` — логи python-бота

Логи бота за пределами `%APPDATA%\GridScalp\` (например, `%LOCALAPPDATA%\GridScalp\` для python-embed runtime cache) **не удаляются**. Если в будущем туда что-то начнёт писаться — добавить второй PowerShell-rm в CustomAction.

## Анти-паттерны / gotchas

1. **`Execute="immediate"` вместо `deferred`** — иммедиатные CA не имеют write-доступа к файловой системе в MSI sandbox. Только `deferred`.
2. **Забыть `Impersonate="yes"`** — `%APPDATA%` укажет на SYSTEM, ничего не удалится. Без ошибки.
3. **Не подключить `componentGroupRefs` в tauri.conf.json** — фрагмент не попадёт в финальный MSI (WiX-линкер игнорирует фрагменты без референсов). Property и CA молча отсутствуют.
4. **Хардкодить ProductCode** — Tauri/WiX генерирует `*` (рандомный per-build). Только UpgradeCode фиксирован. Поэтому ищем ProductCode через `RelatedProducts(UpgradeCode)`.
5. **Не закрыть окно после `msiexec`** — Tauri-app продолжит держать `.exe`/`.dll`, msiexec покажет диалог «Files in Use» с просьбой закрыть. Поэтому `setTimeout 500 ms → window.close()` сразу после invoke.
6. **Спавнить msiexec **не** detached** — если msiexec будет child нашего процесса, при закрытии Tauri-app окно msiexec может тоже умереть (наследование handle). `CREATE_NO_WINDOW | DETACHED_PROCESS` решает.

## Связано с

- [[auragrid]] — MOC проекта (точки входа, компоненты)
- [[auragrid-incidents-log]] — журнал инцидентов (рядом — релизные чек-листы и след-решения)
- [[feedback_release_checklist|release-checklist-msi]] (auto-memory) — память про «после обновления нужно перенастроить», теперь in-app uninstall-with-data решает часть кейсов

## Источник

- WiX-фрагмент: `desktop/src-tauri/installer/cleanup.wxs`
- Rust: `desktop/src-tauri/src/uninstall.rs`
- UI: `desktop/src/components/SettingsModal.tsx` (раздел «Опасная зона» → «Удалить программу»)
- Tauri config: `desktop/src-tauri/tauri.conf.json` → `bundle.windows.wix.fragmentPaths`/`componentGroupRefs`
- Сессия 2026-05-25 — реализация по запросу пользователя
