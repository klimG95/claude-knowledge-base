---
type: concept
tags: [<project>, contract, <domain>]
component: cross
layer: contract
shape: contract
created: <YYYY-MM-DD>
updated: <YYYY-MM-DD>
---

# <Contract name>

**TL;DR.** <2-4 строки: какой это контракт, между кем и кем, где спецификация (ссылка на репо), версия.>

## Когда читать эту страницу

- Перед добавлением / изменением метода / endpoint / поля.
- При интеграции нового клиента.
- При расследовании несовместимости версий.

## Поля / методы

| Имя | Тип | Назначение | Обязательное |
|-----|-----|------------|--------------|
| ... | ... | ...        | yes/no       |

## Пример запроса / ответа

```json
{
  "...": "..."
}
```

```json
{
  "...": "..."
}
```

## Версионирование и совместимость

- Текущая версия: `vX.Y`.
- Стратегия breaking changes: <semver / additive only / negotiation>.
- Историческая совместимость: <...>.

## Использующие стороны

- **Producer:** [[<project>-<producer-page>]] — формирует запросы / события.
- **Consumer:** [[<project>-<consumer-page>]] — принимает.
- **Spec:** `../<project>/<path>/<filename>`.

## Связано с

- [[<project>-inventory-endpoints]] — общий обзор API
- <минимум 3 двусторонние связи>

## Источник

<Spec-файл в репо, OpenAPI/JSON Schema, briefing.>
