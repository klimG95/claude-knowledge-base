---
type: plan-hub
tags: [auragrid, security, licensing, packaging, anti-piracy, release]
status: proposed
created: 2026-05-30
updated: 2026-05-30
---

# AuraGrid — стратегия защиты ПО перед первой продажей

> **Status: in-progress (2026-05-30).** Ф2 + Ф6 реализованы (ветка `protect/anti-piracy`,
> PR #36 → base `rebrand/aura`). Ф1 (подпись) и Ф3 (PyArmor) отложены по решению владельца
> — procurement (сертификат + платная лицензия PyArmor). Ф4/Ф5 — gated.
> Зеркало методологии [[auragrid-performance-strategy]] (диагноз → ярусы → инварианты → статусы).

## TL;DR

Лицензионный контур (server-side activate/heartbeat/HWID/grace/ban) — **зрелый**. Главная дыра —
**весь Python-код бота едет в `.msi` открытым текстом** (`desktop/python-embed/bot/*.py`), а торговля
гейтится двумя plaintext-проверками ([main.py:509](python/bot/main.py#L509) halt-флаг,
[main.py:529](python/bot/main.py#L529) `is_valid`). Отсюда два разом открытых риска: **кража IP**
(вся торговая логика читается) и **тривиальный взлом лицензии** (патч `.py` → запуск
`python -m bot.main` standalone без сервера и ключа). Плюс **MSI не подписан** (HO-0002 открыт).

План закрывает это слоями, **не трогая hot-path** (`on_tick` ~1–3мс после perf-рефакторинга
сохраняется): вся защита — на import/startup/daemon, как и текущая лицензия (heartbeat — отдельный
daemon-поток, 30 мин). Ворота первой продажи: подпись (Ф1) + strip `.py` (Ф2) + PyArmor с привязкой
к лицензии (Ф3). Дальше — gated-усиление (Ф4–6).

## Threat model (что именно защищаем)

| # | Угроза | Сейчас возможно? | Последствие |
|---|--------|------------------|-------------|
| T1 | **Кража IP / клонирование** — извлечь `bot/*.py`, прочитать стратегии (Scalping, ConservativeGrid, ProfitTrailer, Impulse, protection/risk формулы) | ✅ тривиально (plaintext в MSI) | конкурент копирует/перепродаёт продукт |
| T2 | **Взлом лицензии** — пропатчить `is_valid`/halt-флаг или выкинуть `LicenseClient`, запустить standalone | ✅ тривиально (plaintext + client-side bool) | торговля без оплаты/ключа, расшаривание |
| T3 | **Redistribution** — скопировать MSI или установленную папку другому | ⚠️ частично сдерживает HWID-привязка (max_devices) | один ключ на многих, если T2 решён |
| T4 | **Tamper / repackage** — вшить malware в MSI, раздать под брендом Aura; либо подменить бот для кражи MT5-кредов | ✅ (MSI без подписи) | репутационный + кража счетов пользователей |
| T5 | **Атака на сервер** — license-server это crown jewel | ⚠️ есть ban/revoke/max_devices; нужен аудит rate-limit/секретов | падение = halt у всех / или free у всех |

## Текущая защита (что уже есть — не ломать)

- ✅ **Server-side лицензия:** `/api/activate` + heartbeat 30 мин + HWID-bind + grace 6 ч + halt + ban/revoke. Клиент — [client.py](python/bot/licensing/client.py); ошибки лицензии **никогда** не пробрасываются в торговый цикл (инвариант).
- ✅ **Rust/Tauri shell скомпилирован** — UI и process-обвязка не в открытом виде.
- ✅ **HWID = MachineGuid** (Tauri `hwid.rs`), пробрасывается боту через `AURA_HWID` env — единая активация для Tauri и бота.
- ✅ **MSI cleanup при деинсталляции** ([[auragrid-msi-uninstall-cleanup]]).
- ✅ Каркас подписи готов: `scripts/sign-windows.ps1` (Azure Trusted Signing) — но в stub-режиме, ждёт HO-0002.

## Инварианты (нельзя нарушить ни в одной фазе)

1. **Zero hot-path cost.** Защита допускается только на import / startup / в daemon-потоке. Никогда — внутри `on_tick`/`poll_loop`. PyArmor/Cython расшифровывают/грузят на import, лицензия — на heartbeat-потоке. `on_tick` ~1–3мс сохраняется.
2. **Сохранение функциональности.** Полный `pytest` (1325 passed baseline) обязан пройти **против защищённой сборки**; + smoke-embed + MT5 e2e на demo-счёте. Семантика торговли не меняется нигде.
3. **6-часовой grace сохраняется.** Любое серверное усиление (Ф5) не должно убивать live-торговлю при кратком сбое сервера — действующее grace-окно остаётся floor'ом.
4. **Каждая фаза — отдельный шиппируемый шаг** с verify-критериями и явным откатом. База отката — `checkpoint/2026-05-30-pre-restructure`.
5. **Детерминизм сборки.** `requirements-prod-lock.txt` остаётся источником истины; защита встраивается в `prepare-embed.ps1`, а не поверх готового MSI вручную.

## Почему PyArmor, а не Nuitka (ключевое тех-решение)

Стек бота — `MetaTrader5` + `numpy/pandas/scipy` (тяжёлые C-расширения). **Полный Nuitka** (компиляция в нативный бинарь) даёт лучшую защиту, но: высокий риск тонких изменений поведения в связке с этими пакетами, сложная сборка, длинные билды → прямой конфликт с инвариантом «сохранение функциональности» перед первой продажей. **PyArmor** (шифрование байткода + нативный runtime-loader, привязка к машине и сроку) — зрелый промышленный стандарт для коммерческой раздачи Python, оверхед только на import, ставится в существующий `python-embed`. Это baseline. **Cython** для нескольких core-модулей (Ф4) — точечный defense-in-depth на «секретный соус», ниже риск чем полный Nuitka.

## Фазы (последовательно)

### Фаза 0 — Baseline & decision doc ✅ (эта страница)
Threat-модель, инварианты, тех-решения зафиксированы. Замер текущего MSI (размер, startup) — снять до правок как точку сравнения.

### Фаза 1 — Подпись MSI + exe (закрыть HO-0002)  `[trust]`
**Цель:** доверенная установка для продажи + tamper-evidence (T4). Зачем первой: нулевой риск для функциональности, не трогает код, но критична для самого факта продажи (без подписи — SmartScreen-предупреждение при установке у каждого покупателя).
- Получить сертификат подписи (Azure Trusted Signing — каркас уже есть; либо OV/EV code-signing cert).
- Включить реальный режим `sign-windows.ps1` в `desktop-release.yml`; проставить `certificateThumbprint`/`timestampUrl` в `tauri.conf.json`.
- Подписать и `.msi`, и вложенный `Aura.exe`.
- **Verify:** `signtool verify /pa` зелёный; чистая установка на свежей Windows без SmartScreen-блока.

### Фаза 2 — Strip `.py`, ship `.pyc`-only в prod  `[free win]`
**Цель:** убрать тривиальное чтение исходников (T1, casual). Сейчас `prepare-embed.ps1` `compileall`'ит, но **сохраняет `.py`** («для диагностики, решение тимлида ТЗ §4.2») — для prod это решение надо обратить.
- Флаг `-StripSources` в `prepare-embed.ps1`: после `compileall` удалить `*.py` из `bot/`, оставить только `__pycache__/*.pyc` (или разложить `.pyc` рядом без source).
- Диагностику сохранять в dev-сборке (флаг off по умолчанию для prod CI).
- **Verify:** бот стартует из `.pyc`-only (`ipc_server_started`); smoke-embed зелёный; в MSI нет `bot/**/*.py`.
- ⚠️ Слабый слой сам по себе (`.pyc` декомпилируется), но бесплатный и складывается с Ф3.

### Фаза 3 — PyArmor: обфускация `bot/` + привязка к лицензии  `[core]`
**Цель:** закрыть T1 (IP) и резко поднять стоимость T2 (взлом). Это «большая» фаза.
- Встроить `pyarmor gen` в `prepare-embed.ps1` между копированием `bot/` и `compileall`: обфусцировать весь пакет `bot/`, runtime-loader в embed.
- **Привязать runtime PyArmor к лицензии:** machine-binding (HWID) + expiry на уровне нативного loader'а, не Python-bool. Теперь обход T2 требует сломать нативный runtime PyArmor, а не отредактировать `.py` — порядок сложности другой.
- Совместимость: проверить обфускацию против `MetaTrader5/numpy/pandas/scipy`-импортов и dynamic-import мест (structlog, pydantic, websockets).
- **Verify (жёстко):** полный `pytest` 1325 passed против обфусцированной сборки (или адаптированный прогон + e2e, если pytest не идёт по обфусцированному пакету напрямую — тогда тестировать `python/bot` неон обфусцированным, а обфускацию верифицировать smoke+MT5-e2e); smoke-embed; MT5 e2e demo; startup-время в пределах инварианта (Δ на import допустим, hot-path — нет).
- Откат: prod-флаг обфускации выключается → возврат к Ф2-сборке.

### Фаза 4 (gated) — Cython core-стратегий → нативный `.pyd`  `[defense-in-depth]`
**Цель:** «секретный соус» (`bot/core/` — strategies/protection/risk) в нативном машинном коде поверх PyArmor. Gate: запускать только если после Ф3 защита crown-jewel-логики признана недостаточной для цены/риска копирования.
- Cython-компиляция выбранных модулей `core/` в `.pyd`, остальное — под PyArmor.
- Риск: тонкие отличия типов/поведения → инвариант 2 (полный pytest) обязателен. Поэтому gated, не в воротах первой продажи.

### Фаза 5 (gated) — Серверно-доставляемый runtime-артефакт  `[anti-crack hard]`
**Цель:** сделать оффлайн-взломанную копию **нефункциональной** (сильнейший анти-T2). Идея: что-то runtime-необходимое (например, подписанные коэффициенты/параметры пресета или ключ расшифровки core) приходит с сервера по heartbeat и обязательно для работы. Тогда патч лицензии не помогает — без живого сервера и валидного ключа бот не торгует осмысленно.
- **Жёсткое ограничение (инвариант 3):** доставка кэшируется и работает в пределах 6 ч grace — краткий сбой сервера не убивает live-торговлю. Решение о вводе hard-зависимости от сервера в runtime — значимое (операционный риск), поэтому **gated**: вводить только если Ф1–4 признаны недостаточными для модели продаж. Как [[auragrid-performance-strategy]] Ярус 3 — не шиповать рискованное вслепую.

### Фаза 6 — Hardening сервера + ops/legal  `[crown jewel + abuse]`
- Аудит license-server (T5): rate-limit на `/api/activate` и heartbeat; аномалия «один ключ — много HWID»; сила и ротация JWT-signing-key и `ADMIN_TOKEN`.
- Per-customer watermark билда (опц.) — трассировка утечки конкретной копии.
- EULA/лицензионное соглашение в инсталлере.
- Подписанный Tauri-updater (обновления нельзя подменить MITM).

## Реестр статусов

| Фаза | Слой | Риск-покрытие | Hot-path | Статус |
|------|------|---------------|----------|--------|
| 0 | baseline+doc | — | — | ✅ done (эта страница) |
| 1 | подпись MSI/exe | T4 | none | ⏸ deferred (procurement: сертификат) |
| 2 | strip .py | T1 casual | none | ✅ done `e7d22fa` (PR #36) |
| 3 | PyArmor + lic-bind | T1, T2 | import-only | ⏸ deferred (procurement: лицензия PyArmor); совместимость проверена |
| 4 | Cython core | T1 deep | import-only | gated |
| 5 | server runtime-gating | T2 hard, T3 | daemon, 6h grace | gated |
| 6 | server+ops+legal | T5, abuse | none | ✅ done `8f5dc5a` (PR #36) — server-часть |

### Лог реализации 2026-05-30 (ветка `protect/anti-piracy`, PR #36)

- **Ф2 done** `e7d22fa`. `sync-bot-embed.ps1 -StripSources` (`compileall -b` → удаление `.py`/`__pycache__`, fail-fast, без `-OO`); `build-release.ps1` стрипает в prod по умолчанию, `-KeepSources` opt-out. Verify: 105 .py → 105 .pyc на реальном embed, smoke-embed зелёный против стрипнутого дерева, data-файлы (`.sql/.yaml/.csv`) сохранены, `bot.main` импортируется sourcelessly.
- **Ф3 deferred, НО технически верифицирована.** PyArmor 9.2.5 (trial). Trial упирается в лимит на полном пакете («out of license») → полная обфускация и легальная поставка требуют **покупки лицензии** (~$110+/год). Главный риск снят эмпирически: обфусцированные **pydantic-модели импортируются в реальном embed 3.12.7, `model_fields`-интроспекция цела** (BotConfig 14 полей и т.д.), рантайм-`.pyd` (собран на 3.12.10) грузится в 3.12.7. Вывод: default-обфускация PyArmor совместима со стеком; pipeline (флаг `-Obfuscate`) построить после покупки лицензии. **Уточнение к плану:** PyArmor-привязка к железу требует per-машинной сборки → несовместима с «один MSI всем»; реалистичный scope Ф3 = чистая обфускация (обфусцированный код проверки лицензии непатчабелен). Криптопривязка per-customer = Ф5 (gated).
- **Ф6 done (server-часть)** `8f5dc5a`. Аудит: контур зрелый (rate-limit 5/min на activate, max_devices, jti-replay, hwid-bind, ban/revoke, prod запрещает дефолтные секреты). Закрыты 2 пробела: (1) floor `JWT_SECRET_KEY` 8→32 (`_MIN_JWT_SECRET_LEN`) — анти-форджери HS256, безопасно (деплои уже ≥32); (2) warning-лог на `MaxDevicesExceeded` — сигнал шеринга ключа в Loki/Grafana. Серверный набор **236 passed**. EULA / signed-updater (ops/legal часть Ф6) — не делалось, остаётся открытым.
- **Ф1 deferred** — подпись отложена владельцем (как и в исходном запросе сессии), procurement сертификата.

## Связано с

- [[auragrid-performance-strategy]] — методологический шаблон (диагноз→ярусы→инварианты→gated-эскалации); инвариант «не трогать hot-path» общий
- [[auragrid]] — MOC проекта (компонент Licensing)
- [[auragrid-msi-uninstall-cleanup]] — упаковка MSI (WiX), смежно с Ф1/Ф2
- [[auragrid-checkpoint-2026-05-30-pre-restructure]] — база отката под фазы
- [[runbook-vault-integration]] — PHASE 1/3

## Источник

- Аудит кода 2026-05-30: [client.py](python/bot/licensing/client.py), [hwid.py](python/bot/licensing/hwid.py), [bot_process.rs](desktop/src-tauri/src/bot_process.rs), [tauri.conf.json](desktop/src-tauri/tauri.conf.json), [prepare-embed.ps1](desktop/scripts/prepare-embed.ps1), [sign-windows.ps1](scripts/sign-windows.ps1), [main.py:509-529](python/bot/main.py#L509-L529)
- TZ_SIDECAR_PACKAGING (упаковка embed), HO-0002 (подпись)
