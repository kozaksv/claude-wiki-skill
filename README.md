# Claude Wiki Skill

Скіл для Claude Code, який додає LLM Wiki — базу знань за паттерном Karpathy. Замість того щоб щоразу перевідкривати знання, wiki накопичує синтезоване розуміння проєкту між сесіями.

## Що робить

Три операції:
- **ingest** — обробити джерело (spec, фічу, зміну коду) у wiki-сторінки
- **query** — шукати у wiki відповіді на питання про проєкт
- **lint** — перевірка здоров'я wiki (застарілість, суперечності, сироти)

Тригери: `додай до вікі`, `оновити вікі`, `що каже вікі про...`, `вікі лінт`, `перевір вікі`, `знайди у вікі`

## Встановлення

```bash
curl -fsSL https://raw.githubusercontent.com/kozaksv/claude-wiki-skill/master/install.sh | bash
```

## Ініціалізація wiki у проєкті

Після встановлення скіла, відкрийте свій проєкт у Claude Code і скажіть:

```
створи вікі
```

Скіл:

1. Знайде `CLAUDE.md` у корені проєкту
2. Створить `docs/wiki/` з `index.md` та `log.md`
3. Додасть секцію `## Wiki` в `CLAUDE.md` — це реєструє wiki в проєкті, щоб Claude знаходив її у кожній наступній сесії

Після ініціалізації wiki працює автоматично у всіх сесіях цього проєкту.

## Оновлення

Запустіть ту саму команду — скрипт оновить автоматично:

```bash
curl -fsSL https://raw.githubusercontent.com/kozaksv/claude-wiki-skill/master/install.sh | bash
```

## Видалення

```bash
rm ~/.claude/skills/wiki
```

## Вимоги

- [Claude Code](https://claude.ai/claude-code)
