# Wiki Skill

**Skill behavior version: 4.2.20** (`SKILL.md` frontmatter). **Install ref:** `master` by default, with `v4.2.0` available as the latest reproducible stable tag. Fresh wikis still use `wiki_version: "4.0"` because v4.1/v4.2 changed agent and installer behavior, not the on-disk schema major.

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

Назва директорії `claude-wiki-skill` — історичний артефакт першої публікації,
а не вимога Claude Code. Функціонально це shared cross-agent canonical install,
який однаково використовують Claude, Codex і Gemini.

`doc-extract` встановлюється так само, бо `ingest-binary` залежить від нього. Export links навмисно вказують на canonical entrypoint, а не на `realpath`: якщо користувач перемкне canonical версію skill'а, Codex і Gemini побачать ту саму версію. `doc-extract` є optional dependency і за замовчуванням піниться на known-good commit `96d6bf9e1df309c4b76d924d3a1f774f7ee33d12`; за потреби його ref можна override'нути через `WIKI_DOC_EXTRACT_REF`.

`~/.agents/skills/` — спільний user-skill шлях для Codex і Gemini CLI. `~/.gemini/skills/` створюється додатково як direct Gemini user-skill path; це не друга копія skill'а, а сумісний symlink export. Інсталятор створює ці export-папки наперед, навіть якщо користувач ще не запускав Codex або Gemini, щоб майбутнє перемикання клієнтів було zero-config. Gemini CLI discovery tiers documented: https://geminicli.com/docs/cli/using-agent-skills/#discovery-tiers

## What changed in v4.2

- **v4.2.1 on master:** `init` now verifies/repairs cross-agent skill exports
  (`~/.agents/skills/wiki`, `~/.gemini/skills/wiki`) so a wiki created in
  Claude is discoverable when the same project is opened in Codex or Gemini.
  Empty projects now bootstrap a minimal wiki with empty `entities/` instead of
  invented starter categories. The installer also supports
  `--repair-exports` for this symlink-only repair path.
- **v4.2.2 on master:** discovery/init now sync project-local instruction
  files too: `CLAUDE.md`, `AGENTS.md`, and `GEMINI.md` get the same short
  `## Wiki` pointer, so another agent does not need manual setup after Claude
  creates the wiki.
- **v4.2.3 on master:** repair behavior tightened after review: instruction
  pointers use paths relative to each instruction file, `wiki status`/`lint` stay
  read-only, and `--repair-exports` reports conflicts/doc-extract state more
  precisely.
- **v4.2.4 on master:** non-absent `init` repairs are consent-gated, bootstrap
  plans no longer leak raw template placeholders, and Gemini/Codex fresh-init
  scenarios are symmetric for cross-agent pointer creation.
- **v4.2.5 on master:** non-absent `init` uses one consent block for
  project-local pointer writes and global export repairs; migration failure
  reporting now uses Execute checklist numbering.
- **v4.2.6 on master:** recovery docs and scenarios now match the consent
  contract: existing wiki repairs inspect first, ask once, and write nothing
  without explicit `[y]`.
- **v4.2.7 on master:** non-absent init wording is tighter: user-facing repair
  labels are consistent, migration plans explain single-repair cases, and the
  recovery check verifies exported `SKILL.md` files.
- **v4.2.8 on master:** git is a hard prerequisite for project wiki operations.
  In a directory without git metadata, `wiki init` asks before running `git
  init`; every other operation stops and explains that git is required for
  snapshots, rollback, and cleanup safety.
- **v4.2.9 on master:** orphan-wiki projects (wiki artifacts exist but no
  `.git/`) get a dedicated repair gate from any wiki operation: the agent
  offers `git init` to preserve the existing wiki instead of suggesting `wiki
  init` for a wiki the user already has.
- **v4.2.10 on master:** small wikis (< 20 active unprotected pages) skip the
  full-lint scope heads-up and start verification immediately; the dialog
  about `швидко` / topic / path remains for larger wikis where the choice is
  meaningful.
- **v4.2.20 on master:** three contract clarifications close iterations
  4.2.11–4.2.19, which kept finding edge cases in heuristic
  orphan-wiki detection. (1) **Orphan-wiki repair is fully manual** —
  when wiki exists on disk but git doesn't, the skill shows an
  informational gate explaining the fix (`cd` to project root →
  `git init` → retry) and ends the operation without writing
  anything; `[y]` applies only to the absent-state Init gate.
  (2) **Wiki location is contract-bound** — a wiki lives at
  `docs/wiki/` or wherever a `## Wiki` pointer resolves to; nothing
  else counts. Files at non-canonical paths without a pointer are not
  treated as wikis. Users who want a wiki elsewhere must add a
  `## Wiki` pointer first. (3) **Partial wiki state is protected** —
  a wiki directory with `schema.md`/`log.md`/`.usage.json`/`concepts/`
  but missing `index.md` is detected as damaged state, not absent;
  the skill shows recovery instructions and refuses to bootstrap a
  fresh wiki on top of the existing files. This makes discovery and
  Init fully deterministic, with no heuristic edge cases.
- **Shared canonical cross-agent installer.** `install.sh` ставить canonical skill у `~/.claude/skills/wiki`, а потім створює symlink exports для Codex/Gemini.
- **Agent-neutral discovery.** Wiki discovery читає `CLAUDE.md`, `AGENTS.md`, і `GEMINI.md`, а не тільки історичний Claude entrypoint.
- **Thin skill entrypoint.** `SKILL.md` лишився trigger/routing contract, а операційні інструкції винесено в `references/`, щоб не вантажити весь 1600+ рядковий body на кожну активацію.
- **Release safety tests.** Додано shell-тести для install/export edge-cases, safe uninstall, і статичний contract-test для `SKILL.md`/`references/` layout.

## What changed in v4.1

v4.1 describes behavior changes that shipped on the path to v4.2. There is no
separate `v4.1.0` install tag; use `v4.2.0` for the stable cross-agent release.

- **Crystallization без скриптів.** Tier-модель `bash → python → wiki → skill` (4 рівні з v4.0) спрощено до двох артефактних типів: `wiki` і `skill`. User-runnable скрипти (`scripts/*.sh` / `*.py`) видалено як target крихталізації — вони перекидали mechanical work назад на юзера (Division of Labor). Якщо потрібен скрипт — агент пише inline і виконує сам, без створення файла. Деталі: `references/crystallization.md`.
- **Proactive query trigger.** Скіл активується на природних українських формах питання («як налаштувати X», «що таке X», «де лежить Y», «пам'ятаєш як ми Z», «потрібно знову W», «розкажи про…») — без вимоги вживати ключове слово "wiki" / "вікі". Master rule: query перед генерацією проєктно-специфічного контенту з пам'яті, навіть коли «знаю відповідь». Деталі: `references/operation-query.md`.
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

Тригери: `створи вікі`, `ініціалізуй wiki`, `init wiki`, `bootstrap wiki`, `додай до вікі`, `оновити вікі`, `що каже вікі про...`, `вікі лінт`, `вікі статус`, `перевір вікі`, `знайди у вікі`. Також проактивно при появі бінарників у `tmp/`.

## Встановлення

Остання rolling-версія (zero-config, за замовчуванням — master):

```bash
curl -fsSL https://raw.githubusercontent.com/kozaksv/claude-wiki-skill/master/install.sh | bash
```

Інсталятор створює `~/.claude/skills/` як shared canonical registry навіть для Codex-only або Gemini-only користувачів. Це не вимагає встановленого Claude: Codex і Gemini отримують доступ через symlink exports.

Стабільний reproducible release:

```bash
curl -fsSL https://raw.githubusercontent.com/kozaksv/claude-wiki-skill/master/install.sh | bash -s v4.2.0
```

### Доступні версії

| Тег | Що це |
|---|---|
| **v4.2.0** *(рекомендується для pin)* | Shared canonical cross-agent exports для Codex/Gemini + agent-neutral discovery + thin `SKILL.md` entrypoint |
| `master` *(rolling)* | Найновіший стан інсталятора й skill references; може рухатись після останнього тегу |
| **v4.0.0** | Karpathy + Hermes self-improvement: РЕФЛЕКСІЯ, telemetry sidecar, tiered crystallization (4 рівні зі скриптами), cleanup-flow, page protection, 8 операцій |
| **v3.0.0** | Чистий Karpathy LLM Wiki: 3 шари (concepts/entities/transcripts), 7 операцій, без self-improvement |

URL у курлі завжди вказує на `master/install.sh` — це сам інсталятор. **Версію скіла обираєш аргументом** (`bash -s v3.0.0`). Без аргумента — встановлюється `master`.

Тег — це закладка на конкретний коміт; версія, яку ти отримаєш через `v3.0.0`, `v4.0.0` або `v4.2.0`, не зміниться навіть коли вийдуть нові релізи. `master` навпаки рухається вперед.

`doc-extract` є optional dependency для `ingest-binary` і за замовчуванням ставиться з pinned known-good commit, щоб `bash -s v4.2.0` був відтворюваним end-to-end. Якщо треба навмисно протестувати інший extractor ref, передайте env override:

```bash
curl -fsSL https://raw.githubusercontent.com/kozaksv/claude-wiki-skill/master/install.sh | WIKI_DOC_EXTRACT_REF=main bash
```

Для PDF/DOCX ingest є другий системний setup-крок: після install запустіть
`bash ~/.claude/skills/doc-extract/bin/install-deps.sh` і
`bash ~/.claude/skills/doc-extract/bin/doctor.sh`. Решта wiki operations працюють
без цих системних залежностей.

Не плутайте install-ref з `wiki_version`: `version: "4.2.0"` у `SKILL.md` описує behavior release, а `wiki_version: "4.0"` у `docs/wiki/schema.md` описує schema major. Вони можуть відрізнятися і лишатися сумісними, якщо major однаковий.

Після встановлення:

- Claude читає `~/.claude/skills/wiki`
- Codex читає `~/.agents/skills/wiki` → symlink на `~/.claude/skills/wiki`
- Gemini CLI читає `~/.agents/skills/wiki` або `~/.gemini/skills/wiki` → symlink на `~/.claude/skills/wiki`

Усі ці entrypoints ведуть до одного canonical install. Оновлювати окремо Codex/Gemini не треба.

Якщо canonical entrypoint уже є, але Codex/Gemini exports зникли, можна
полагодити тільки symlinks без fetch/checkout:

```bash
bash ~/.claude/skills/wiki/install.sh --repair-exports
```

### Recovery cookbook

Якщо ви відкрили проєкт у Codex/Gemini, але `wiki` skill не активується взагалі,
спершу полагодьте global skill exports:

```bash
bash ~/.claude/skills/wiki/install.sh --repair-exports
```

Перевірити exports можна так:

```bash
ls -L ~/.agents/skills/wiki/SKILL.md ~/.gemini/skills/wiki/SKILL.md 2>&1
```

Якщо обидва `SKILL.md` відкриваються через export-шляхи, базова доступність
exports OK; якщо бачите помилки, запустіть `--repair-exports`.

Потім у проєкті скажіть `init wiki`. Якщо wiki вже існує, скіл не створить другу
wiki: він знайде `docs/wiki/`, перевірить версію, перевірить project-local
pointer-файли і global skill exports, і якщо щось потребує ремонту — покаже
один consent block. Без [y] жодних файлів не пишеться.

Якщо `wiki` skill у Codex/Gemini вже активується, але в проєкті бракує
`AGENTS.md` або `GEMINI.md`, просто скажіть у цьому проєкті `init wiki`. Для
поточних wiki це працює як repair: скіл синхронізує project-local pointer-файли
після підтвердження `[y]` і не створить другу wiki.

Якщо `~/.claude/skills/wiki` уже існує як plain file або real directory,
installer не буде його перезаписувати. Перейменуйте або видаліть цей шлях
вручну після перевірки вмісту, потім запустіть install повторно.

## Ініціалізація wiki у проєкті

Після встановлення скіла, відкрийте свій проєкт у Claude Code, Codex або Gemini CLI і скажіть:

```
створи вікі
```

Скіл спершу перевірить, що проєкт є git-репозиторієм. Git — основа wiki:
snapshots, rollback, lint auto-fixes і cleanup спираються на commits. Якщо
git-маркер (`.git/` або файл `.git`) не знайдено, скіл шукає сліди існуючої
wiki у проєкті (`docs/wiki/index.md` або `## Wiki` pointer у
`CLAUDE.md`/`AGENTS.md`/`GEMINI.md`):

- Якщо wiki вже існує (orphan wiki), будь-яка операція покаже
  **інформаційний** gate з поясненням ситуації та інструкціями manual
  fix (`cd` у project root → `git init` → повторити операцію). Скіл
  сам `git init` не виконує — лише ви знаєте, де project root.
- Якщо wiki ще не існує, `wiki init` пропонує створити wiki разом із
  `git init` (це підтверджується `[y]`). Інші операції (`lint`,
  `query`, `status`, `cleanup`, `split`, `ingest`) у проєкті без git
  відмовляють і просять запустити `wiki init`.

`[y]` потрібен лише для absent-state (немає wiki, немає git). Orphan-wiki
gate жодного підтвердження не приймає — він informational only.

**Розташування wiki — частина контракту.** Wiki живе у `docs/wiki/` або
там, куди вказує `## Wiki` pointer у `CLAUDE.md`/`AGENTS.md`/`GEMINI.md`.
Якщо хочете wiki у іншому місці — додайте `## Wiki` pointer **перед**
запуском `wiki init`. Інакше скіл не побачить файли поза стандартним
шляхом і створить нову wiki у `docs/wiki/`.

Після цього скіл визначить стан проєкту і діятиме відповідно:

- **Empty проєкт** — без додаткових питань створить мінімальну wiki: `docs/wiki/{concepts,entities,transcripts}/`, `archive/`, `index.md`, `log.md`, `schema.md` (з frontmatter `wiki_version: "4.0"` і Migration Log), `.usage.json`; `entities/` лишиться порожньою, без вигаданих `people/` чи `documents/`; додасть 1-line pointer на `schema.md` в усі наявні agent instruction files (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`), або створить файл активного агента якщо таких файлів ще немає
- **Існуючі raw-теки з артефактами** (bootstrap) — проаналізує, запропонує план міграції: які MDs стануть concepts, які бінарники підуть в `archive/`, які дублі видалити. Кожна група — з окремим consent'ом
- **Існуюча v1-wiki** (concepts only) — доповнить structure (entities/, transcripts/, archive/)

Якщо в проєкті немає жодного `CLAUDE.md`, `AGENTS.md` або `GEMINI.md` і активний агент неочевидний, скіл запитає, який instruction file створити. Якщо агент очевидний із середовища, він створить відповідний файл автоматично.

Після ініціалізації wiki працює автоматично у всіх сесіях цього проєкту — скіл знаходить її через `## Wiki` секцію в `CLAUDE.md`, `AGENTS.md` або `GEMINI.md`. Fresh init синхронізує всі три project-local pointer-файли після bootstrap consent, щоб wiki, створена в Claude, одразу мала resident hint для Codex і Gemini. Для вже існуючих wiki такий repair відбувається тільки після окремого `[y]`. Init також перевіряє global skill exports, щоб після створення wiki в Claude Codex бачив той самий skill через `~/.agents/skills/wiki`.

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

Безпечне видалення symlink entrypoints/exports:

```bash
bash ~/claude-wiki-skill/uninstall.sh
```

За замовчуванням real clone-директорії `~/claude-wiki-skill` і `~/claude-doc-extract-skill` лишаються на диску, щоб не видалити локальні зміни випадково.

Щоб прибрати й real clones, якщо вони є clean git repos:

```bash
bash ~/claude-wiki-skill/uninstall.sh --remove-clones
```

`uninstall.sh` ідемпотентний: missing symlink показує як already absent, plain file / real directory не перезаписує і не видаляє, а clone з локальними змінами пропускає.
Foreign symlink'и у відомих слотах теж не видаляються: скрипт прибирає тільки ті entrypoints/exports, які вказують на expected canonical topology. Порожні `*/skills` підпапки може прибрати через `rmdir`, але parent-директорії `~/.claude`, `~/.agents`, `~/.gemini` лишаються на місці.

## Тести

```bash
bash -n install.sh
bash -n uninstall.sh
bash -n tests/install-cross-agent-links.sh
bash -n tests/uninstall.sh
bash -n tests/skill-contracts.sh
bash tests/install-cross-agent-links.sh
bash tests/uninstall.sh
bash tests/skill-contracts.sh
```

## Вимоги

- Claude Code, Codex або Gemini CLI
- Для cross-agent support достатньо створених symlink exports; окрема інсталяція під кожен агент не потрібна.
- Інсталятор створює `~/.claude/skills/wiki` як canonical registry навіть якщо користувач працює лише з Codex або Gemini; це не вимагає встановленого Claude.
