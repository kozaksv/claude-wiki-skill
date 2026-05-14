# Wiki Skill

**Version: v4.2.0-dev** — cross-agent install/export model on `master` (not tagged yet).

Скіл для Claude Code, Codex і Gemini CLI, який додає LLM Wiki — базу знань за паттерном Karpathy. Замість того щоб щоразу перевідкривати знання, wiki накопичує синтезоване розуміння проєкту між сесіями.

## Cross-agent install model

Інсталятор zero-config зі спільним canonical registry: користувач запускає одну команду, а скіл стає доступним для трьох агентів.

```text
Git clone:
  ~/claude-wiki-skill

Canonical entrypoint:
  ~/.claude/skills/wiki  ->  ~/claude-wiki-skill

Exports created by install.sh:
  ~/.agents/skills/wiki  -> ~/.claude/skills/wiki
  ~/.gemini/skills/wiki  -> ~/.claude/skills/wiki
```

`doc-extract` встановлюється так само, бо `ingest-binary` залежить від нього. Export links навмисно вказують на canonical entrypoint, а не на `realpath`: якщо користувач перемкне canonical версію skill'а, Codex і Gemini побачать ту саму версію. `doc-extract` є optional dependency і завжди ставиться з `main`, незалежно від pinned версії wiki skill.

`~/.agents/skills/` — спільний user-skill шлях для Codex і Gemini CLI. `~/.gemini/skills/` створюється додатково як direct Gemini user-skill path; це не друга копія skill'а, а сумісний symlink export. Інсталятор створює ці export-папки наперед, навіть якщо користувач ще не запускав Codex або Gemini, щоб майбутнє перемикання клієнтів було zero-config. Gemini CLI discovery tiers documented: https://geminicli.com/docs/cli/using-agent-skills/#discovery-tiers

## What changed in v4.2

- **Shared canonical cross-agent installer.** `install.sh` ставить canonical skill у `~/.claude/skills/wiki`, а потім створює symlink exports для Codex/Gemini.
- **Agent-neutral discovery.** Wiki discovery читає `CLAUDE.md`, `AGENTS.md`, і `GEMINI.md`, а не тільки Claude-specific інструкції.
- **Installer safety tests.** Додано shell-тест для fresh install, idempotency, broken symlink replacement, conflict preservation, і reachability через exports.

## What changed in v4.1

- **Crystallization без скриптів.** Tier-модель `bash → python → wiki → skill` (4 рівні з v4.0) спрощено до двох артефактних типів: `wiki` і `skill`. User-runnable скрипти (`scripts/*.sh` / `*.py`) видалено як target крихталізації — вони перекидали mechanical work назад на юзера (Division of Labor). Якщо потрібен скрипт — агент пише inline і виконує сам, без створення файла. Деталі: `## Self-Improvement Loop > ### Crystallization` у SKILL.md.
- **Proactive query trigger.** Скіл активується на природних українських формах питання («як налаштувати X», «що таке X», «де лежить Y», «пам'ятаєш як ми Z», «потрібно знову W», «розкажи про…») — без вимоги вживати ключове слово "wiki" / "вікі". Master rule: query перед генерацією проєктно-специфічного контенту з пам'яті, навіть коли «знаю відповідь». Деталі: `## Operation: Query > ### When to Query` у SKILL.md.
- **Discovery ↔ crystallization pair.** Коли query не знаходить релевантної сторінки — це сигнал-кандидат для крихталізації після того, як агент відповість. Пара двох половин одного циклу: query читає збережене, crystallization зберігає re-derived.

## What's new in v4.0

- **РЕФЛЕКСІЯ block** — після кожного edit/write проходу скіл вмикає короткий refleksiya-крок з anti-noise rule (read-only блоки не тригерять reflection).
- **Telemetry sidecar (`.usage.json`)** — gitignored per-clone metadata: `view_count` / `use_count` / `patch_count` (з timestamp'ами `last_viewed_at` / `last_used_at` / `last_patched_at`) для кожної сторінки. Для пріоритизації, не для flagging.
- **Tiered crystallization** — патерн повторюється 3+ разів → пропозиція (y/n/пізніше) створити concept-сторінку, helper-скрипт або під-скіл. Ніколи silent. *(Перероблено у v4.1 — див. вище.)*
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
- **cleanup** — post-migration / періодична уборка з action menu (`глянь і онови` / `видали` / `захисти` / `merge` / `розбий` / `глянь обидві`)

Плюс мікро-операції: `wiki protect <path>` / `wiki unprotect <path>` — захищає сторінку від cleanup-видалення (детальніше — секція [«Захист сторінок»](#захист-сторінок) нижче).

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
| `master` *(рекомендується, v4.2.0-dev)* | v4.1 + shared canonical cross-agent exports для Codex/Gemini + agent-neutral discovery |
| **v4.0.0** | Karpathy + Hermes self-improvement: РЕФЛЕКСІЯ, telemetry sidecar, tiered crystallization (4 рівні зі скриптами), cleanup-flow, page protection, 8 операцій |
| **v3.0.0** | Чистий Karpathy LLM Wiki: 3 шари (concepts/entities/transcripts), 7 операцій, без self-improvement |

Поки не створено окремий git tag для v4.2.0, не запускайте `bash -s v4.2.0` або `bash -s v4.1.0` — таких тегів ще немає. Без аргумента інсталятор бере `master`.

URL у курлі завжди вказує на `master/install.sh` — це сам інсталятор. **Версію скіла обираєш аргументом** (`bash -s v3.0.0`). Без аргумента — встановлюється `master`.

Тег — це закладка на конкретний коміт; версія, яку ти отримаєш через `v3.0.0` або `v4.0.0`, не зміниться навіть коли вийдуть нові релізи. `master` навпаки рухається вперед.

Після встановлення:

- Claude читає `~/.claude/skills/wiki`
- Codex читає `~/.agents/skills/wiki` → symlink на `~/.claude/skills/wiki`
- Gemini CLI читає `~/.agents/skills/wiki` або `~/.gemini/skills/wiki` → symlink на `~/.claude/skills/wiki`

Усі ці entrypoints ведуть до одного canonical install. Оновлювати окремо Codex/Gemini не треба.

## Ініціалізація wiki у проєкті

Після встановлення скіла, відкрийте свій проєкт у Claude Code, Codex або Gemini CLI і скажіть:

```
створи вікі
```

Скіл визначить стан проєкту і діятиме відповідно:

- **Empty проєкт** — створить `docs/wiki/{concepts,entities,transcripts}/`, `archive/`, `index.md`, `log.md`, `schema.md` (з frontmatter `wiki_version: "4.0"` і Migration Log), `.usage.json`; додасть 1-line pointer на `schema.md` в усі наявні agent instruction files (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`), або створить файл активного агента якщо таких файлів ще немає
- **Існуючі raw-теки з артефактами** (bootstrap) — проаналізує, запропонує план міграції: які MDs стануть concepts, які бінарники підуть в `archive/`, які дублі видалити. Кожна група — з окремим consent'ом
- **Існуюча v1-wiki** (concepts only) — доповнить structure (entities/, transcripts/, archive/)

Якщо в проєкті немає жодного `CLAUDE.md`, `AGENTS.md` або `GEMINI.md` і активний агент неочевидний, скіл запитає, який instruction file створити. Якщо агент очевидний із середовища, він створить відповідний файл автоматично.

Після ініціалізації wiki працює автоматично у всіх сесіях цього проєкту — скіл знаходить її через `## Wiki` секцію в `CLAUDE.md`, `AGENTS.md` або `GEMINI.md`.

## Схема проєкту

Скіл — project-agnostic. Нова схема живе у `docs/wiki/schema.md`; legacy-проєкти можуть ще мати схему в agent instruction file:

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

## Захист сторінок

Деякі сторінки існують для рідкісних моментів — інструкції на випадок інциденту, runbook міграції, recovery-процедури, ротація токенів. Їх ніхто не редагує і не читає роками **за дизайном**; коли треба — вони критично важливі.

Без захисту скіл не знає різниці між «корисна сторінка, до якої ще не звертались» і «сторінка, яка дійсно протухла». Захист — це явна декларація користувача: «ця сторінка не редагується навмисно, не пропонуй її на видалення і не верифікуй у лінті».

### Як захистити сторінку

```bash
wiki protect concepts/security-recovery.md
wiki protect concepts/migration-rollback.md
```

Що дає захист:
- **Лінт пропускає** захищену сторінку при content-verification (повний / швидкий / scope — все одно).
- **Cleanup-flow відмовляється** видаляти захищену сторінку, поки не зробиш `wiki unprotect`.
- **Звіт лінта показує захищені** сторінки окремим рядком — щоб ти пам'ятав, що вони існують.

### Як зняти захист

Коли треба перевірити або редагувати:

```bash
wiki unprotect concepts/security-recovery.md
```

Після цього сторінка повертається у звичайний flow — її можна верифікувати, оновити, видалити.

### Auto-suggest захисту

При `ingest-source` / `ingest-binary` нової сторінки, що виглядає як security / incident / migration / compliance / recovery recipe (за ключовими словами в назві та змісті), скіл сам запитує: «Сторінка виглядає критично-рідкісною. Захистити? [y/n]». Не silent — завжди явна згода.

### Чи воно тобі потрібне

Якщо твоя вікі — **продуктова розробка** (UI patterns, бізнес-flow, data model, gotchas), захист, ймовірно, не потрібен. Усі сторінки активні, всі редагуються, всі читаються. Cleanup-flow і так має double-confirmation проти випадкового видалення.

Захист стає корисним, коли в вікі **з'являються operational runbook'и** — речі, які мусять бути готові на «коли все горить», але до яких не звертаються в нормальний день.

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

Перед видаленням реальних clone-директорій перевірте, що в `~/claude-wiki-skill` або `~/claude-doc-extract-skill` немає ваших незбережених локальних змін.

```bash
rm ~/.claude/skills/wiki
rm ~/.claude/skills/doc-extract
rm ~/.agents/skills/wiki
rm ~/.gemini/skills/wiki
rm ~/.agents/skills/doc-extract
rm ~/.gemini/skills/doc-extract
rm -rf ~/claude-wiki-skill ~/claude-doc-extract-skill
rmdir ~/.agents/skills ~/.agents ~/.gemini/skills ~/.gemini 2>/dev/null || true
```

## Вимоги

- Claude Code, Codex або Gemini CLI
- Для cross-agent support достатньо створених symlink exports; окрема інсталяція під кожен агент не потрібна.
- Інсталятор створює `~/.claude/skills/wiki` як canonical registry навіть якщо користувач працює лише з Codex або Gemini; це не вимагає встановленого Claude.
