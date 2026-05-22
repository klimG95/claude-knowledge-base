---
type: runbook
tags: [auragrid, operations, logging, troubleshooting]
automation_status: manual
created: 2026-05-22
updated: 2026-05-22
---

# AuraGrid — Log analysis (операционная методология)

**TL;DR.** Как читать логи AuraGrid когда тестировщик прислал лог, или после инцидента. Главное правило: **`desktop.log` первым** (Tauri stderr — ловит крах Python-бота когда `bot.log` уже не пишется), **фильтруй по timestamps позже момента обновления** (иначе мешается история до фикса).

## Когда читать эту страницу

- Перед запуском Agent для анализа большого лога (>10k строк)
- После релиза, когда тестировщик прислал issue + логи
- Когда нужно сравнить два запуска бота (до/после фикса)

## Где живут логи

| Файл | Где | Что |
|------|-----|-----|
| `desktop.log` | `%LOCALAPPDATA%\GridScalp\logs\` | Tauri (Rust) stderr — обёртка процесса бота + bridge stdout/stderr Python-бота через `bot_process:` |
| `bot.log` | `%APPDATA%\GridScalp\logs\<magic>\` | Python-бот напрямую (JSONL для log_shipper) |
| `bot.log.YYYY-MM-DD` | там же | Ротация (предыдущие сутки) |
| Loki (server-side) | `loki.gridscalp.internal` | Если log_shipping включён через admin |

## Порядок чтения

1. **Сначала `desktop.log`** — если Python-бот упал, `bot.log` остановится а `desktop.log` запишет stderr exit-маркер.
2. **Фильтр по дате обновления** — если билд развёрнут в `T`, всё до `T` — мусор от старой версии. `grep "^2026-05-21T11:" desktop.log...` если апдейт был в 11:00.
3. **Поиск маркеров** в порядке убывания критичности:
   - `^\d{4}-.*  ERROR ` (две пробела перед ERROR — стандарт tracing) — Tauri-уровень
   - `panic`, `fatal`, `Traceback`, `Exception:` — Python-уровень через bridge
   - `connect failed` (>5 минут подряд = IPC сломан)
   - `activate_ok` / `Unauthorized` / `401` / `403` — лицензия
   - `MT5`, `order_send`, `position_close` — торговые ошибки

## Большой лог (>50k строк): делегировать Agent

Не читать сырой большой лог в основном контексте. Шаблон prompt:

```
Полностью проанализируй <path>. Файл <size>MB, <lines> строк. Формат:
<timestamp>Z  <LEVEL> <module>: <message>. bot_process: пробрасывает stdout/stderr
Python-бота (с вложенным timestamp+уровнем + stream="stdout"|"stderr").

Контекст: <зачем читаем — релиз, инцидент, конкретный ключ X>.

Что искать:
1. Временной диапазон (первая/последняя строка)
2. Все ERROR-level Tauri (паттерн `^\d{4}-.*  ERROR `, отличать от `error=` внутри WARN)
3. panic / fatal / Traceback / Exception
4. IPC периоды >5 минут connect failed подряд
5. Рестарты Tauri и бота (Starting / boot / init / magic= / pid=)
6. license / activation / Unauthorized / 401 / 403
7. update / updater / Перенастроить / migration / config
8. ConnectionError / Timeout / refused / unreachable / DNS / SSL
9. log_shipper / log shipping / dump_logs / cursor
10. poll_heartbeat пропуски (>60s) или tps_engine < 10
11. trade / order / position / signal / strategy ошибки
12. MT5 / MetaTrader / mt5 ошибки

Группируй: «N таких строк в период X-Y, пример: …». Не цитируй сотни одинаковых.

Финал по 5 секциям: Critical / Errors / Warnings / Info / Anomalies.
Ссылки на строки в формате `desktop.log:LINE`. Финал на русском.
```

## Типичные паттерны и их значение

| Паттерн | Значение | Серьёзность |
|---------|----------|-------------|
| `ipc: connect failed os error 10061` | Tauri пытается к боту, который ещё не стартанул | Норма первые ~5 сек после старта; >5 мин — проблема |
| `poll_heartbeat ... tps_engine=15-17` | Бот живёт, тики идут | Норма |
| `tps_engine=<10` | Цикл подвисает (нагрузка, диск, calendar-tracebacks) | S3, симптом |
| `ingest_ok accepted=0 batch=0 dropped=0` | Analytics не запущен, бот не накапливает | Норма до старта analytics |
| `pending_ticket_synced_after_loss` | Pending исчез из MT5, бот корректно очистил state | Норма (штатный синк) |
| `pending_ticket_adopted_on_start` | Бот нашёл orphan pending в MT5 без записи в state | Анти-паттерн прошлого; теперь явно обрабатывается |
| `partial_close_detected` | Часть позиций закрыта внешне | Норма, если пользователь действительно закрыл |
| `activate_ok activation_id=N expiry=…` | Лицензия активирована | Норма, ожидать каждый старт |
| `log_shipper_tick_failed` | Отправка логов крашится | Зависит от текста — `load_log_cursor` починен в `d9f003c` |
| `multiple_pending_orders` | В канале >1 pending — потенциальная фантомная история | Анти-паттерн, проверить engine.start sync |

## Анти-паттерны (что НЕ делать)

1. **Не читать `bot.log` первым** — он остановится при крахе Python-бота, и ты пропустишь причину.
2. **Не игнорировать timestamps до апдейта** — выдашь старые баги за актуальные.
3. **Не цитировать каждую WARN-строку IPC retry** — они идут пакетами по сотням-тысячам, цени группой.
4. **Не доверять `grep -c "ERROR"` без `-i`** — `error=IO error` внутри WARN-строки тоже считается. Используй `^\d{4}-.*  ERROR ` (две пробела).

## Связано с

- [[auragrid]] — MOC проекта
- [[auragrid-incidents-log]] — журнал, где находят применение эти методики
- [[runbook-session-start]] — общий чек-лист начала сессии

## Источник

- AGENTS.md `auragrid/` репо (Reading map)
- Сессия 2026-05-22 (анализ desktop.log.2026-05-21 → коммит `85b7c91`)
- ADR-006 (2026-05-20) — разнесение логирования на 5 страниц (предусмотрено, эта первая)
