# Changelog — журнал изменений базы знаний

Записи добавляются сверху вниз, от новых к старым. После каждой рабочей сессии — новая запись с датой `## YYYY-MM-DD` и пунктами о том, что обработано, что создано/обновлено, какие связи установлены. Правила — в [[AGENTS]].

---

## 2026-05-22

### Раунд 4 — комплексная оценка модуля Analytics + расчёт риска стратегии (без правок)

- Пользователь сообщил: окно Analytics + DeploymentTable не работают в HEAD `677811c` (релиз 1.0.1) — показываются только Spread + Sessions, остальное прочерки. Запрошена комплексная оценка для дальнейшего unblock'а.
- Диагностика по vault-workflow: Phase 1 контекст ([[auragrid]], [[auragrid-trading-core]], journal/2026-05-22, runbook). Phase 2 — два параллельных Agent'а (код + логи) дали разные диагнозы, личная верификация показала, что **реальная корневая причина третья: `symbol_not_found`** в логе `desktop.log.2026-05-21:15890` → `backfill_skipped_no_symbol` → buffers пустые → каскад null'ов во всём snapshot.
- Дополнительные слои: MT5 calendar API mismatch (известный issue, не пофикшен) + M15 buffer не реализован в `tfs_to_backfill` (блокирует DeploymentTable).
- Сопутствующие: лог-конкуренция bot.log между двумя процессами (PermissionError × 6400), IPC connect refused race на старте.
- Vault: создана [[auragrid-analytics-module]] — архитектура второго процесса + три root cause + статус секций + 6 приоритетов unblock'а. В [[auragrid-incidents-log]] добавлен Incident 2026-05-22 раунд 4 с Misdiagnosis/Prevention. `index.md` обновлён.
- **Фиксы не применены** — пользователь запросил только аудит. План на следующую сессию (P0-P2) — в [[auragrid-analytics-module]] секция «Приоритеты unblock».
- Урок: один agent ≠ истина. Два agent'а дали разные ответы, оба частично правы — реальность нашлась личной верификацией кода + лога.

### Инициализация vault для AuraGrid + фиксы релиза по логу тестировщика (раунд 1 + ре-аудит раунд 2)

- Анализ `desktop.log.2026-05-21` (тестировщик с ключом `6b03bdc5-…`): найдены 5 ручных багов + 3 проблемы из лога. Подробности — [[journal/2026-05-22|journal/2026-05-22]] и [[auragrid-incidents-log]].
- **Раунд 1** — коммит `85b7c91`: фиксы `protection.close_channel` (свежий tick + on_retry), `normalize_lot` (digits по volume_step), `engine.start` (sync pending_ticket с MT5), UI labels в Step3Editor.
- **Раунд 2 (ре-аудит через vault-workflow)** — коммит `677811c`: первый раунд закрыл UX, но не root cause. Реальный retcode `10021 NO_PRICES` (не INVALID_PRICE). Добавлены: `NO_PRICES`+`POSITION_CLOSED` в protocol, расширение `_RETRYABLE`, re-scan по ticket после fail, snapshot/restore `last_lot_raw` для anti-drift, фикс infinite re-activation в profit_trailing, multi-pending cleanup в engine.start.
- Vault: создано ядро страниц проекта AuraGrid — [[auragrid]] (MOC), [[auragrid-incidents-log]], [[auragrid-log-analysis]], [[auragrid-trading-core]], [[runbook-vault-integration]] (методологический runbook про обязательный workflow).
- `index.md` обновлён с новой структурой; `journal/2026-05-22.md` — детальная запись сессии (оба раунда).
- Auto-memory выверена под реальные vault-страницы (раньше указатели ссылались на ещё не созданные).
- Hooks: SessionStart + Stop в `~/.claude/settings.json` для механической принуды vault-workflow.
- **Главный урок:** vault-workflow окупился в этой же сессии — ре-аудит запущен пользователем благодаря новому workflow, и нашёл S1, которая иначе ушла бы в релиз.

### Раунд 3 — UX: close-as-trail, pause-keeps-trailing, Save/Load preset как файл

- **Close-кнопки (close_all / close_buy / close_sell)** теперь арят профит-трейлинг вместо мгновенного physical-close: SL=trail на текущей цене + дальше стандартная подтяжка. Реализация — `ProfitTrailer.arm_manual` + `Protection.arm_channel_trail`; IPC `CloseResult.armed_trail: bool`; UI модалки и нотификации переписаны.
- **Пауза** теперь блокирует только открытие новых ордеров и переход SCALP→CG; `profit_trailer.manage()` + reset/partial-close sync продолжают работать. В `engine.process_channel` guard `state.paused` перенесён с начала функции в середину (после блока 3 трейлинга).
- **Сохранение/загрузка пресета как отдельный файл**: Rust-функции `strategies::export_preset` / `import_preset` (исключают/мержат секретные поля), Tauri commands `strategy_export_preset` / `strategy_import_preset`, UI меню «Сохранить/Загрузить пресет в файл…» с system file-dialog через `@tauri-apps/plugin-dialog`.
- **Bonus fix** — `handle_start_bot` приведён к контракту §2.3+§5: при `engine.running=True` возвращает `error=bot_already_running` (раньше был «idempotent» комментарий без реального вызывающего → нарушение контракта).
- **Тесты**: полный pytest suite зелёный (1118 passed). Адаптированы 7 тестов под новый контракт `armed_trail` и pause-keeps-trailing. Pre-existing failing `test_start_bot_returns_already_running_when_engine_up` — починен попутно.
- Vault: дополнена [[auragrid-trading-core]] (разделы про arm_manual и про изменённый guard паузы), запись в [[journal/2026-05-22|journal/2026-05-22]] про раунд 3.
- Memory: добавлен `feedback_fix_found_bugs` — попутные баги чиню через полный цикл дебага, «pre-existing» не оправдание (правило выработано пользователем в этой сессии).

## 2026-XX-XX

### Установка пакета claude-knowledge-base

_Первая запись делается при установке агентом в рамках bootstrap._
