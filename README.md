# Claude Wiki Skill

**Version: v4.0.0** — self-improvement release.

Скіл для Claude Code, який додає LLM Wiki — базу знань за паттерном Karpathy. Замість того щоб щоразу перевідкривати знання, wiki накопичує синтезоване розуміння проєкту між сесіями.

## What's new in v4.0

- **РЕФЛЕКСІЯ block** — після кожного edit/write проходу скіл вмикає короткий refleksiya-крок з anti-noise rule (read-only блоки не тригерять reflection).
- **Telemetry sidecar (`.usage.json`)** — gitignored per-clone metadata: `view_count` / `use_count` / `patch_count` (з timestamp'ами `last_viewed_at` / `last_used_at` / `last_patched_at`) для кожної сторінки. Для пріоритизації, не для flagging.
- **Tiered crystallization** — патерн повторюється 3+ разів → пропозиція (y/n/пізніше) створити concept-сторінку, helper-скрипт або під-скіл. Ніколи silent.
- **`wiki status` operation** — інтроспективний звіт: hot pages, cold pages, drift candidates, telemetry summary.
- **Karpathy lint reformulation** — staleness визначається content-verification (читання сторінки + judgement), не timestamp-евристикою.
- **Versioning + migration** — поле `wiki_version` у `schema.md`. Структурні зміни — explicit plan-then-confirm; field-level backfill в `.usage.json` — silent.

Architectural patterns inspired by [Hermes-Agent](https://github.com/NousResearch/hermes-agent) by Nous Research.

## Що робить

**Три шари знань у `docs/wiki/`:**
- `concepts/` — теми, процеси, правила, gotchas (synthesis)
- `entities/` — конкретні сутності (люди, компанії, договори, об'єкти...) — hub-сторінки
- `transcripts/` — повний текст бінарників (PDF/DOCX) для grep і LLM-контексту

**Бінарники — у `archive/`** (поза git через `.gitignore`).

**Вісім операцій:**
- **init** (bootstrap-aware) — ініціалізувати wiki АБО мігрувати існуючу структуру проєкту
- **ingest-source** — обробити MD-спеку / статтю → оновити concept-сторінки
- **ingest-binary** — обробити PDF/DOCX з `tmp/` → entity + transcript + бінарник в `archive/`
- **query** — шукати у wiki відповіді на питання про проєкт (крос-просторово)
- **wiki status** — інтроспективний звіт: hot/cold pages, drift candidates, telemetry summary
- **lint** — Karpathy content-verification: trinity integrity, orphans, frontmatter, drift
- **split** — розбити monolithic page на focused topics
- **cleanup** — post-migration / періодична уборка з action menu (`глянь і онови` / `видали` / `pin` / `merge` / `розбий` / `глянь обидві`)

Плюс мікро-операції: `wiki pin <path>` / `wiki unpin <path>` — захищає сторінку від cleanup-видалення.

Тригери: `додай до вікі`, `оновити вікі`, `що каже вікі про...`, `вікі лінт`, `вікі статус`, `перевір вікі`, `знайди у вікі`. Також проактивно при появі бінарників у `tmp/`.

## Встановлення

Остання версія (за замовчуванням — master):

```bash
curl -fsSL https://raw.githubusercontent.com/kozaksv/claude-wiki-skill/master/install.sh | bash
```

Конкретна версія (передається аргументом скрипту):

```bash
curl -fsSL https://raw.githubusercontent.com/kozaksv/claude-wiki-skill/master/install.sh | bash -s v3.0.0
```

### Доступні версії

| Тег | Що це |
|---|---|
| **v4.0.0** *(рекомендується)* | Karpathy + Hermes self-improvement: РЕФЛЕКСІЯ, telemetry sidecar, tiered crystallization, cleanup-flow, pin protection, 8 операцій |
| **v3.0.0** | Чистий Karpathy LLM Wiki: 3 шари (concepts/entities/transcripts), 7 операцій, без self-improvement |
| `master` | Поточний HEAD: остання випущена версія + усі коміти після неї |

URL у курлі завжди вказує на `master/install.sh` — це сам інсталятор. **Версію скіла обираєш аргументом** (`bash -s v3.0.0`). Без аргумента — встановлюється `master`.

Тег — це закладка на конкретний коміт; версія, яку ти отримаєш через `v3.0.0` або `v4.0.0`, не зміниться навіть коли вийдуть нові релізи. `master` навпаки рухається вперед.

## Ініціалізація wiki у проєкті

Після встановлення скіла, відкрийте свій проєкт у Claude Code і скажіть:

```
створи вікі
```

Скіл визначить стан проєкту і діятиме відповідно:

- **Empty проєкт** — створить `docs/wiki/{concepts,entities,transcripts}/`, `archive/`, `index.md`, `log.md`, `schema.md` (з frontmatter `wiki_version: "4.0"` і Migration Log), `.usage.json`; додасть 1-line pointer на `schema.md` у `CLAUDE.md`
- **Існуючі raw-теки з артефактами** (bootstrap) — проаналізує, запропонує план міграції: які MDs стануть concepts, які бінарники підуть в `archive/`, які дублі видалити. Кожна група — з окремим consent'ом
- **Існуюча v1-wiki** (concepts only) — доповнить structure (entities/, transcripts/, archive/)

Після ініціалізації wiki працює автоматично у всіх сесіях цього проєкту — скіл знаходить її через `## Wiki` секцію в `CLAUDE.md`.

## Схема проєкту (задається в CLAUDE.md)

Скіл — project-agnostic. Конкретика — в CLAUDE.md як schema:

```markdown
## Entity Categories
| Category | Шлях | Опис |
|---|---|---|
| ... | entities/.../ | ... |

## Document Types
| Type | Опис |
|---|---|
| ... | ... |

## File Naming
{YYYY-MM-DD}_{type}_{slug}.{ext}
```

Скіл читає ці секції при `ingest-binary` і додає рядки при появі нових категорій/типів.

## Оновлення

Запустіть ту саму команду без аргумента — скіл оновиться до останнього master:

```bash
curl -fsSL https://raw.githubusercontent.com/kozaksv/claude-wiki-skill/master/install.sh | bash
```

Щоб переключитись на конкретну версію (наприклад, з master на v3.0.0 або з v3.0.0 на v4.0.0) — запустіть з аргументом:

```bash
curl -fsSL https://raw.githubusercontent.com/kozaksv/claude-wiki-skill/master/install.sh | bash -s v4.0.0
```

Скрипт переключиться на потрібний тег у вже клонованому репо. Ваші wiki у проєктах не чіпаються.

## Видалення

```bash
rm ~/.claude/skills/wiki
```

## Вимоги

- [Claude Code](https://claude.ai/claude-code)
