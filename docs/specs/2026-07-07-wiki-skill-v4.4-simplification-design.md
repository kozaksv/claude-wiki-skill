# Wiki Skill v4.4.0 — спрощення: wiki-only кристалізація, без вбудованого cleanup-prompt

Дата: 2026-07-07
Статус: затверджено (brainstorming-сесія)
Версія скіла: 4.3.0 → 4.4.0 (agent-behavior change; `wiki_version` лишається `"4.0"`, нуль міграцій для існуючих вікі)

## Мета

Два спрощення за результатами практики:

1. **Видалити процес створення скілів з кристалізації.** Тип артефакту `skill`
   (делегація у `superpowers:writing-skills` або direct-create з canonical+symlink
   топологією) не знайшов практичного застосування. Кристалізація стає
   одноартефактною: єдиний артефакт — wiki-сторінка (`concepts/{name}.md`).
2. **Прибрати вбудований cleanup-prompt** («🧹 Показати список того, що в wiki
   могло застаріти?») з кінця РЕФЛЕКСІЯ-блоку. Питання після кожної рефлексії —
   шум. Cleanup-flow лишається повністю функціональним з єдиним входом —
   `wiki status [a]/[b]/[c]`.

## Затверджені рішення

- Cleanup-prompt прибирається **повністю** (не переформулювання, не рідша частота).
- З кристалізації викидаються **всі** згадки скілів — без речення-запобіжника
  «якщо юзер просить скіл — редіректни». Якщо користувач захоче скіл, він скаже
  «створи скіл», і спрацює окремий спеціалізований скіл для створення скілів.
  Вікі-скіл про скіли не знає нічого.
- Історія рішень (чому були і чому зникли scripts-тір v4.1 і skill-тір v4.4)
  живе в Migration Log, не в операційних референсах.
- Історичні `docs/specs/` і `docs/plans/` не редагуються — це датовані записи.

## Зміни по файлах

### `references/crystallization.md`

- Інтро: «one of two artifact types» → єдиний артефакт, wiki-сторінка; таблиця
  типів `wiki|skill` замінюється одним-двома реченнями (критерій судження — «I
  re-derived this content from scratch this session…» — зберігається дослівно).
- Секція `### Skill creation / delegation` (делегація, direct-create fallback,
  canonical/export топологія, installer-style safety, skill-proposal блок) —
  видаляється повністю.
- Каллаути «Why no scripts/ tier» і «Memory is not a tier either» стискаються:
  memory-каллаут лишається у 2-3 рядках (границя wiki vs auto-memory, «operates
  only on wiki artifacts»); scripts-обґрунтування зводиться до короткої
  історичної примітки з відсиланням до Migration Log.
- Тригер explicit-user: фрази звужуються до «збережи у вікі» / «save as wiki
  page»; «винеси в скіл» зникає. Якщо юзер просить скрипт — запропонувати
  wiki-сторінку-еквівалент (діюча норма v4.1, без змін по суті).
- Proposal-формат: `{wiki | skill}: {proposed-path}` → `wiki: {proposed-path}`.
  Поведінка `[y]/[n]/[пізніше]` без skill-гілок; `Автоматизував:` записує
  `wiki — {path}` або `нічого + причина`.
- Anti-noise: правило «Don't propose a skill when a wiki page covers it»
  видаляється; «Don't crystallize user-runnable scripts» переформульовується як
  «wiki-сторінка — єдиний артефакт кристалізації» (без слова «skill»).

### `references/reflection.md`

- Рядок 10: перелік значень `Автоматизував:` → `wiki — concepts/{name}.md` або
  `нічого` з причиною.
- Шаблон (рядки 18-36): рядок 24 без skill-варіантів; рядки 32-35 (риска +
  🧹-prompt) видаляються — блок закінчується на `Автоматизував:`/`Перевірив:`.
- Рядок 38 (пояснення про trailing prompt) — видаляється.
- Рядок 80: «(entered via `wiki status [a]/[b]/[c]` or via the РЕФЛЕКСІЯ
  cleanup-prompt)» → лише `wiki status`-вхід.

### `references/cleanup-flow.md`

- Секція `### Cleanup-prompt embedded in reflection` (рядки 1-21: сам prompt,
  safety contract, правило згасання після 3 ігнорів, anti-recursion rule) —
  видаляється разом із причинами існування.
- `### Cleanup-flow` інтро + таблиця `#### Two entry points…` → одне речення:
  вхід у cleanup-flow один — `wiki status` (`[a]`/`[b]`/`[c]`), далі механіка
  без змін (subset selection → content-verification → action menu).
- Рядок 50 (`захисти`): «future cleanup-prompts skip this page» → «cleanup-flow
  пропускає цю сторінку».

### Косметичні трими крос-згадок

- `references/operation-wiki-status.md:3` — «active counterpart to the embedded
  cleanup-prompt…» → wiki status як єдиний вхід у cleanup-flow.
- `references/operation-wiki-status.md:101`, `references/operation-lint.md:388`,
  `tests/scenarios/staleness-content-verification.md:99` — «РЕФЛЕКСІЯ block or
  cleanup-prompt» → «РЕФЛЕКСІЯ block» (guard-фраза `never emit a separate
  РЕФЛЕКСІЯ block` в operation-lint.md зберігається — на неї є контрактний
  guard).
- `references/maintenance-and-mistakes.md:60` — рядок анти-патерн-таблиці
  переформульовується: «no reflection after lint/status/cleanup» лишається,
  згадки cleanup-prompt зникають.
- `references/self-improvement.md` — опис crystallization.md без «wiki page or
  user-level skill / direct-create fallback / installer topology»; опис
  cleanup-flow.md без «embedded cleanup prompt»; рядок 21 без «or
  cleanup-prompt».
- `SKILL.md:109` — рядок Reference Loading Map «Reflection / crystallization /
  new skill creation» → «Reflection / crystallization».

### `tests/skill-contracts.sh`

- Guard рядка 383 (`grep -q 'set_skill_link' references/crystallization.md`)
  **перевертається** на анти-return: наявність `set_skill_link` у
  crystallization.md — фейл («skill-creation tier removed in v4.4»).
- Нові анти-return guard'и в ідіомі файлу:
  - `🧹` не повертається ніде у `references/`;
  - `Two entry points` не повертається у `references/cleanup-flow.md`;
  - `writing-skills` не повертається ніде у `references/`.
- Наявні guard'и полів РЕФЛЕКСІЇ (`Автоматизував:` тощо) і version-major match
  проходять без змін (мажор лишається 4).
- **Атомарність (обов'язково, знімає ризик неузгодженого CI).** Ці зміни тестів —
  частина implementation-фази, НЕ spec-коміту. Перевертання guard'а 383 і нові
  анти-return guard'и МАЮТЬ landing-итися **тим самим комітом**, що видаляє
  відповідні токени (`set_skill_link`, `🧹`, `Two entry points`, `writing-skills`)
  з `references/`. Жодна половина не йде окремо:
  - guard-flip без видалення токенів → CI ламається (анти-return бачить токен);
  - видалення токенів без flip'а → CI ламається (старий guard 383 вимагає
    наявності `set_skill_link`).
  Тому spec-коміт свідомо НЕ чіпає `tests/skill-contracts.sh`: зелений CI на
  spec-коміті **очікуваний і коректний** — старі guard'и стережуть ще не змінену
  поведінку references. Це не «мовчазна втрата покриття»; покриття переноситься
  атомарно разом зі зміною references у implementation-коміті.

### Тест-сценарії

- `tests/scenarios/crystallization-tiers.md` → **перейменувати** на
  `tests/scenarios/crystallization.md` («tiers» — хибна назва при одному
  артефакті). Видалити Sub-scenario 2 (skill via writing-skills) разом із
  «Separation-of-concerns check» і «wiki-vs-skill discrimination check».
  Sub-scenario 3 (анти-патерн: повторювана команда ≠ пропозиція скрипта)
  доповнити очікуванням, що і скіл не пропонується. Оновити внутрішню
  нумерацію та всі посилання на старе ім'я файлу.
- `tests/scenarios/reflection-triggers.md` — прибрати 🧹-хвіст із трьох
  expected outputs; асерції про сам prompt (рядки ~179-207) видалити або
  переробити на «блок закінчується на Автоматизував:/Перевірив:».
- `tests/scenarios/cleanup-flow.md` — сценарії входу через РЕФЛЕКСІЯ-prompt
  переробити на вхід через `wiki status`.
- `tests/scenarios/integration-checklist.md` — пункти 60, 125, 143, 145
  оновити під нові контракти (wiki-only кристалізація, один вхід у cleanup).

### Версія та документація

- `SKILL.md` frontmatter: `version: "4.3.0"` → `"4.4.0"`.
- `references/discovery-versioning.md`:
  - Migration Log, новий запис після блоку 4.3.0:
    `### 4.4.0 (2026-07-07)` — no schema migration; crystallization спрощено до
    wiki-only (skill-тір видалено — не знайшов практичного застосування);
    вбудований cleanup-prompt видалено з РЕФЛЕКСІЯ-блоку; cleanup-flow має
    єдиний вхід `wiki status`. Мотивація: prompt fatigue + unused feature.
  - Оновити застарілий приклад версії у тексті («The skill itself has a version
    … `version: "4.2.0"`» → актуальна).
- `README.md`: булети про кристалізацію (рядки ~118, ~126) переписати під
  wiki-only з приміткою «(Перероблено у v4.1 і v4.4)»; додати рядок v4.4.0 у
  таблицю версій.

## Що явно НЕ змінюється

- `install.sh` / `uninstall.sh` — їхні `set_skill_link`/`export_skill_link`
  обслуговують інсталяцію самого вікі-скіла, не кристалізацію.
- Wiki-кристалізація як механізм: тригери (periodic nudge, pre-commit,
  task-completion, pre-compression flush, explicit user, `nudge_interval`),
  proposal-діалог `[y]/[n]/[пізніше]`, anti-noise правила.
- РЕФЛЕКСІЯ-блок як такий (формат полів, тригери, anti-noise).
- Механіка `wiki status` / lint / cleanup-flow: subset selection,
  content-verification, action menu, double-confirm для `видали`, snapshot
  перед деструктивними діями, page protection.
- Схема вікі на диску (`wiki_version: "4.0"`) — існуючі вікі працюють без
  міграції.

## Верифікація

1. `bash tests/skill-contracts.sh` — зелений на кожному кроці. На spec-коміті
   тест не змінюється (лишається зеленим на старій поведінці). На
   implementation-коміті той самий діф одночасно видаляє токени з `references/`
   і додає анти-return guard'и (перевернутий 383 + `🧹`/`Two entry points`/
   `writing-skills`) — після чого тест знову зелений уже на новій поведінці.
   Проміжного стану з червоним CI не існує (див. «Атомарність» вище).
2. Grep-sweep: `🧹`, `writing-skills`, `cleanup-prompt`, `Two entry points`,
   `set_skill_link` (поза `install.sh`/`uninstall.sh`), `винеси в скіл`,
   `skill — delegated`, `skill — created` — нуль збігів у `SKILL.md`,
   `references/`, `tests/scenarios/`, `README.md`, за винятком Migration Log
   (історичний запис) і датованих `docs/specs/` / `docs/plans/`.
3. Ручна перевірка зв'язності: `references/cleanup-flow.md` починається з
   `### Cleanup-flow`; РЕФЛЕКСІЯ-шаблон закінчується на
   `Автоматизував:`/`Перевірив:`.

## Деплой

`~/.claude/skills/wiki` — симлінк безпосередньо на цей репозиторій, тому зміни
в master живі одразу локально. Пуш у GitHub потрібен лише для інших машин та
інсталяцій через `install.sh`.
