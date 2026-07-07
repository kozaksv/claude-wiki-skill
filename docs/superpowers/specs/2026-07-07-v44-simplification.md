# Spec — Wiki Skill v4.4.0: wiki-only кристалізація, без вбудованого cleanup-prompt

**Дата:** 2026-07-07
**Версія скіла:** 4.3.0 → 4.4.0 (зміна поведінки агента; `wiki_version` лишається `"4.0"` — нуль міграцій для існуючих вікі)
**Джерело:** брейншторм-сесія `docs/specs/2026-07-07-wiki-skill-v4.4-simplification-design.md` (затверджено)

## Проблема

Практика показала два джерела шуму в поточному скілі:

1. **Skill-тір кристалізації не використовується.** Кристалізація дозволяє
   виносити повторюваний контент у два типи артефактів: wiki-сторінку або
   *скіл* (через делегацію в `superpowers:writing-skills` або direct-create з
   canonical+symlink топологією). Skill-гілка не знайшла практичного
   застосування — вона додає значну поверхню (installer-safety, export-топологія,
   skill-proposal діалог, discrimination-правила «wiki vs skill»), яку доводиться
   тримати узгодженою, але яка ніколи не спрацьовує на користь.
2. **Вбудований cleanup-prompt створює prompt fatigue.** Наприкінці кожного
   РЕФЛЕКСІЯ-блоку агент питає «🧹 Показати список того, що в wiki могло
   застаріти?». Питання після *кожної* рефлексії — шум; той самий cleanup-flow
   вже доступний явно через `wiki status [a]/[b]/[c]`.

## Підхід

Обидва спрощення — **виключно видалення поверхні поведінки**, без нової механіки
і без зміни схеми вікі на диску. Спираємось на вже наявні механізми:

- Кристалізація стає **одноартефактною**: єдиний вихід — wiki-сторінка
  (`concepts/{name}.md`). Критерій судження («I re-derived this content from
  scratch this session…») зберігається дослівно. Скіл більше не є типом
  артефакту — вікі-скіл про скіли не знає нічого. Якщо користувач захоче скіл,
  він скаже «створи скіл», і спрацює окремий спеціалізований скіл.
- Cleanup-flow лишається **повністю функціональним**, але з **єдиним входом** —
  `wiki status`. Вбудований у рефлексію prompt (разом із його safety-contract,
  правилом згасання після 3 ігнорів і anti-recursion rule) видаляється повністю.
- Історія рішень (чому були і зникли scripts-тір v4.1 і skill-тір v4.4) живе
  в Migration Log `references/discovery-versioning.md`, не в операційних
  референсах. Датовані `docs/specs/` і `docs/plans/` не редагуються.

## Зміни

Проєкт — це Claude-скіл, тож замість data-model/API/UI застосовна проєкція:
**дані = схема вікі на диску**, **API = контрактні файли скіла (SKILL.md +
references/)**, **UI = діалоги, які агент показує користувачу (РЕФЛЕКСІЯ-блок,
cleanup-prompt, proposal-формат)**.

### Дані (схема вікі)

Без змін. `wiki_version` лишається `"4.0"`; існуючі вікі працюють без міграції.
Нуль міграцій.

### API (контрактні файли скіла)

- **`references/crystallization.md`** — інтро «one of two artifact types» →
  єдиний артефакт (wiki-сторінка); таблиця типів `wiki|skill` → 1–2 речення.
  Секція `### Skill creation / delegation` видаляється повністю (делегація,
  direct-create fallback, canonical/export топологія, installer-safety,
  skill-proposal блок). Каллаути `Why no scripts/ tier` і `Memory is not a tier`
  стискаються (memory лишається 2–3 рядки: границя wiki vs auto-memory; scripts →
  коротка історична примітка з відсиланням до Migration Log). Explicit-user
  тригер звужується до «збережи у вікі» / «save as wiki page» (без «винеси в
  скіл»). Proposal-формат `{wiki|skill}: {path}` → `wiki: {path}`; гілки
  `[y]/[n]/[пізніше]` без skill-варіантів; `Автоматизував:` записує
  `wiki — {path}` або `нічого + причина`. Anti-noise: правило «Don't propose a
  skill…» видаляється; «Don't crystallize user-runnable scripts» → «wiki-сторінка
  — єдиний артефакт кристалізації».
- **`references/reflection.md`** — перелік значень `Автоматизував:` →
  `wiki — concepts/{name}.md` / `нічого` + причина; шаблон без skill-варіантів;
  риска + 🧹-prompt та пояснення про trailing prompt видаляються — блок
  закінчується на `Автоматизував:`/`Перевірив:`; згадка cleanup-prompt-входу →
  лише `wiki status`.
- **`references/cleanup-flow.md`** — секція `### Cleanup-prompt embedded in
  reflection` видаляється разом із причинами існування; інтро `### Cleanup-flow`
  + таблиця `#### Two entry points` → одне речення (єдиний вхід — `wiki status`,
  далі механіка без змін: subset selection → content-verification → action menu);
  `захисти`-рядок «future cleanup-prompts skip this page» → «cleanup-flow
  пропускає цю сторінку». **Файл має починатися з `### Cleanup-flow`.**
- **Крос-згадки (косметика):** `operation-wiki-status.md:3,101`,
  `operation-lint.md:388`, `maintenance-and-mistakes.md:60`,
  `self-improvement.md` (опис crystallization.md/cleanup-flow.md + рядок 21),
  `SKILL.md:109` (Reference Loading Map: «Reflection / crystallization / new
  skill creation» → «Reflection / crystallization»). **Guard-фраза `never emit a
  separate РЕФЛЕКСІЯ block` в `operation-lint.md` зберігається** — на неї є
  контрактний тест.
- **`SKILL.md`** frontmatter: `version: "4.3.0"` → `"4.4.0"`.
- **`references/discovery-versioning.md`** — новий Migration Log запис
  `### 4.4.0 (2026-07-07)` (no schema migration; crystallization → wiki-only,
  skill-тір видалено; cleanup-prompt видалено; cleanup-flow single-entry
  `wiki status`; мотивація: prompt fatigue + unused feature); оновити застарілий
  приклад версії в тексті.

### Контрактні тести (`tests/skill-contracts.sh`)

- Guard рядка 383 (`grep -q 'set_skill_link' references/crystallization.md`)
  **перевертається** на анти-return: наявність `set_skill_link` у
  crystallization.md → фейл.
- Нові анти-return guard'и в ідіомі файлу: `🧹` ніде в `references/`;
  `Two entry points` ніде в `references/cleanup-flow.md`; `writing-skills` ніде
  в `references/`.
- Наявні guard'и полів РЕФЛЕКСІЇ (`Автоматизував:` тощо) і version-major match
  проходять без змін (мажор лишається `4`).

### Тест-сценарії

- `crystallization-tiers.md` → **перейменувати** на `crystallization.md`
  (git mv). Видалити Sub-scenario 2 (skill via writing-skills) + «Separation-of-
  concerns check» + «wiki-vs-skill discrimination check». Sub-scenario 3
  (повторювана команда ≠ пропозиція скрипта) доповнити очікуванням, що і скіл
  не пропонується. Оновити нумерацію та всі посилання на старе ім'я.
- `reflection-triggers.md` — прибрати 🧹-хвіст із трьох expected outputs;
  асерції про prompt (~179–207) → «блок закінчується на Автоматизував:/Перевірив:».
- `cleanup-flow.md` — сценарії входу через РЕФЛЕКСІЯ-prompt → вхід через
  `wiki status`.
- `integration-checklist.md` — пункти 60, 125, 143, 145 під нові контракти.

### UI (діалоги для користувача)

- РЕФЛЕКСІЯ-блок більше не закінчується 🧹-питанням — закінчується на
  `Автоматизував:`/`Перевірив:`.
- Кристалізаційний proposal показує лише `wiki: {path}` (без вибору wiki/skill).
- Cleanup викликається користувачем явно (`wiki status` → `[a]/[b]/[c]`);
  агент більше не ініціює cleanup наприкінці рефлексії.

### Документація

- `README.md` — булети про кристалізацію (~118, ~126) → wiki-only з приміткою
  «(Перероблено у v4.1 і v4.4)»; додати рядок v4.4.0 у таблицю версій.

## Edge-cases

- **Existing wikis:** `wiki_version` не змінюється → Step-0 detect не бачить
  mismatch, жодного migration-prompt для існуючих вікі. Перевірити, що
  version-major guard (`4`) у контрактах не спрацьовує через bump мінора.
- **Guard-фраза колізія:** у `operation-lint.md` фраза `never emit a separate
  РЕФЛЕКСІЯ block` має контрактний guard і НЕ підпадає під заміну «РЕФЛЕКСІЯ block
  or cleanup-prompt» → «РЕФЛЕКСІЯ block». Не зачепити її при sed-подібних правках.
- **`set_skill_link` подвійне значення:** символ живе і в `install.sh`/
  `uninstall.sh` (обслуговує інсталяцію *самого* вікі-скіла — лишається), і в
  `crystallization.md` (кристалізація — видаляється). Анти-return guard має
  цілити лише crystallization.md, не install/uninstall.
- **Rename-consistency:** після `crystallization-tiers.md` → `crystallization.md`
  жодне посилання (у сценаріях, checklist, референсах) не має вказувати на старе
  ім'я.
- **Порожній cleanup-flow.md заголовок:** після видалення першої секції файл
  мусить починатися з `### Cleanup-flow` — інакше зламається структурний guard/
  ручна перевірка зв'язності.

## Ризики

- **Розсинхрон worktree (операційний):** роботу веде окремий worktree
  `claude-wiki-skill-v44-simplification`, тоді як `~/.claude/skills/wiki` —
  симлінк на основний репозиторій. Зміни в цьому worktree НЕ живі локально, доки
  не змерджені в master основного репо. Всі git/файлові операції — тільки за
  абсолютними шляхами під коренем worktree.
- **Пропущена крос-згадка:** видалення розкидане по ~10 файлах; залишкова згадка
  🧹/`writing-skills`/`cleanup-prompt`/`Two entry points` пройде повз контракти,
  якщо guard неповний. Мітиґація — grep-sweep у Верифікації.
- **Regressed test-сценарій:** сценарії — це промпт-контракти, не виконуваний
  код; помилка в них тихо змінює очікувану поведінку агента. Мітиґація —
  `bash tests/skill-contracts.sh` зелений + ручне читання перейменованого
  сценарію.

## Верифікація

1. `cd <корінь> && bash tests/skill-contracts.sh` — зелений.
2. Grep-sweep (нуль збігів у `SKILL.md`, `references/`, `tests/scenarios/`,
   `README.md`, крім Migration Log і датованих `docs/specs/`|`docs/plans/`):
   `🧹`, `writing-skills`, `cleanup-prompt`, `Two entry points`, `set_skill_link`
   (поза `install.sh`/`uninstall.sh`), `винеси в скіл`, `skill — delegated`,
   `skill — created`.
3. Ручна зв'язність: `references/cleanup-flow.md` починається з `### Cleanup-flow`;
   РЕФЛЕКСІЯ-шаблон закінчується на `Автоматизував:`/`Перевірив:`.

## Поза скоупом

- `install.sh` / `uninstall.sh` — їхні `set_skill_link`/`export_skill_link`
  обслуговують інсталяцію самого вікі-скіла, не кристалізацію. Не чіпати.
- Wiki-кристалізація як механізм: тригери (periodic nudge, pre-commit,
  task-completion, pre-compression flush, explicit user, `nudge_interval`),
  proposal-діалог `[y]/[n]/[пізніше]`, anti-noise правила — лишаються.
- РЕФЛЕКСІЯ-блок як такий (формат полів, тригери, anti-noise) — лишається.
- Механіка `wiki status` / lint / cleanup-flow: subset selection, content-
  verification, action menu, double-confirm для `видали`, snapshot перед
  деструктивними діями, page protection — лишаються.
- Схема вікі на диску (`wiki_version: "4.0"`) — без міграції.
- Історичні `docs/specs/` і `docs/plans/` — датовані записи, не редагуються.
