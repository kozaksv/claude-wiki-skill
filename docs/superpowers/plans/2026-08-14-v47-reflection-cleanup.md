# Plan — Wiki Skill v4.7.0: прибрати залишки вирізаної tier-моделі кристалізації

**Date:** 2026-08-14
**Spec:** `docs/superpowers/specs/2026-08-14-v47-reflection-cleanup.md`
**Design:** `docs/superpowers/specs/2026-08-14-v47-reflection-cleanup-design.md`
**Settled-леджер:** `docs/superpowers/plans/2026-08-14-v47-reflection-cleanup-settled.md` — **ОКРЕМИЙ файл, НЕ переносити сюди, НЕ видаляти, НЕ перейменовувати** (`r6`).
**Working root (ALL paths absolute under):** `/Users/a/AI/claude-wiki-skill/.claude/worktrees/v47-reflection`
**Slug:** `v47-reflection-cleanup`. База: `666fb45` (`docs(spec): v47-reflection-cleanup`) у воркtree `v47-reflection`.
**Nature:** doc/behavior-only. Дельта — виключно текст контрактних файлів скіла, тестових сценаріїв і чотири grep-гарди. Skill bump `4.6.1` → `4.7.0`. **On-disk нуль:** `wiki_version` = `"4.0"`, форма запису `.usage.json` — ті самі десять полів, `_hooks.hook_version` = `"1"`, міграцій нуль. `hooks/`, `install.sh`, `uninstall.sh` **не редагуються взагалі**.

**Commit-контракт посадок (обов'язковий):** subject коміта кожної задачі — `feat(v47-reflection-cleanup): <канонічний id> — <опис>`. Лончер конвеєра деривує knownDone РІВНО з патерна `feat(v47-reflection-cleanup): <id>` на гілці (інші типи/subjects невидимі), тож відхилення від формату означає фантомну переробку задачі наступним раном. Канонічні id перелічені в кожній задачі і в таблиці хвиль.

---

## Worktree discipline (читати ПЕРЕД будь-якою задачею)

- Це **окремий worktree**; твій shell cwd може бути ІНШИМ worktree. НІКОЛИ голий `git`.
- Усі git: `git -C "/Users/a/AI/claude-wiki-skill/.claude/worktrees/v47-reflection" …`.
- Усі Read/Edit/Write і файлові Bash — ЛИШЕ за АБСОЛЮТНИМИ шляхами під коренем вище.
- Будь-який run/тест: `cd "/Users/a/AI/claude-wiki-skill/.claude/worktrees/v47-reflection" && …`.
- Перед КОЖНИМ комітом: `git -C "…root…" status --short` МАЄ показувати САМЕ твої файли. Порожньо / не ті → писав не туди, виправ абсолютний шлях ПЕРШ ніж комітити.
- Коміть лише файли своєї задачі явними абсолютними шляхами.
- **Симлінк-пастка:** `~/.claude/skills/wiki` — симлінк на ОСНОВНИЙ репо, не на цей worktree. Ніколи не перевіряй правки через `~/.claude/…` чи `~/.qwen/…`.

## Канонічна повна сюїта (verify-крок КОЖНОЇ задачі — без винятків)

```
cd "/Users/a/AI/claude-wiki-skill/.claude/worktrees/v47-reflection" && \
  bash tests/hooks/run.sh && \
  bash tests/skill-contracts.sh && \
  bash tests/install-cross-agent-links.sh && \
  bash tests/uninstall.sh
```

Сюїта МАЄ бути зеленою після КОЖНОЇ задачі. Тому кожна задача нижче — **форма (а)**: текстова правка і grep-гард, що її асертить, в ОДНОМУ комміті. Жодна задача не лишає «падаючу перевірку для наступної», жодна задача не додає expected-fail маркерів.

## Три пастки цього циклу (читати ПЕРЕД правкою `tests/skill-contracts.sh`)

Це не стилістика — кожна з трьох робить сюїту червоною або провалює Done-when.

**Пастка 1 — самозбіг гарда.** `tests/skill-contracts.sh` містить літерал власного grep-патерна. Тому **область жодного нового гарда НЕ СМІЄ включати `$ROOT/tests/` або сам `$ROOT/tests/skill-contracts.sh`** — гард знайде сам себе і впаде завжди. Легальні області: `$ROOT/references/`, `$ROOT/SKILL.md`, `$ROOT/README.md`, `$ROOT/tests/scenarios/`. `$ROOT` як область — заборонено (`Δ6`: `docs/` навмисно зберігає старі слова за `r5`).

**Пастка 2 — Done-when vs. власний текст гарда.** Done-when №2 вимагає `grep -rn 'Автоматизував' … tests/` → **нуль** влучань, а Done-when №4 — те саме для `крихталіз` по `tests/`. Але гарди на ці слова живуть саме в `tests/skill-contracts.sh`. Тому **патерн обох гардів збирається з двох half-літералів**, щоб суцільного слова у файлі не було:

```bash
legacy_reflection_field="Автомат""изував"
legacy_spelling="крихт""аліз"
```

Це не косметика: без розщеплення Done-when №2/№4 провалюються на власному гарді. Обов'язковий коментар над кожним — інакше наступний читач «почистить» його назад. Текст `fail`-повідомлення теж не сміє містити суцільного старого слова. Гард на `state == "active"` розщеплювати НЕ треба: Done-when №3 має область `references/ tests/scenarios/`, `skill-contracts.sh` туди не входить.

**Пастка 3 — Migration Log не сміє цитувати старі літерали.** Запис `### 4.7.0` живе у `references/discovery-versioning.md`, тобто **всередині області** гарда на старе ім'я поля (посадка у хвилі 2) і гарда на фільтр (посадка у хвилі 3), а також в області Done-when №2 і №3. Тому текст запису **не сміє містити ні суцільного `Автоматизував`, ні суцільного `state == "active"`** — описуй перейменування й зняття фільтра без цитування старих літералів (готове формулювання — у T5).

## Спільні інваріанти (НЕ ослаблювати в жодній задачі)

- **On-disk нуль.** `wiki_version` = `"4.0"`; форма запису `.usage.json` — ті самі десять полів; `_hooks.hook_version` = `"1"`. Поля `state` / `protected` / `archived_at` **лишаються** у записі (`r3`); видалення полів = схемна міграція = інший, дорогий цикл.
- **`hooks/` не входить у скоуп зовсім.** Жоден хук-скрипт і жоден хук-тест не правиться. Асерт `tests/hooks/run.sh:1483` «backfilled state defaults to active» лишається зеленим і є доказовою базою формулювання Δ4.
- **Паркан лишається** (`r4`). Негативні гарди `set_skill_link` (`tests/skill-contracts.sh:412-413`), `🧹` (`:415-416`), `writing-skills` (`:418-419`), `Two entry points` (`:420-421`), асерт строгого шаблону (`:423-424`), `never emit a separate РЕФЛЕКСІЯ block` (`:430-431`), ліміти рядків `SKILL.md` (`:11-14`) і `self-improvement.md` (`:407-410`), історичний асерт `### 4.6.0` (`:603-604`), регресійні суб-сценарії у `tests/scenarios/crystallization.md`, рядок `references/maintenance-and-mistakes.md:43` — **не чіпати**. Гард на ім'я поля (`:427`) **перенацілюється**, а не видаляється.
- **`protected` недоторканий.** Фільтр `protected == false` лишається всюди; операції `wiki protect` / `wiki unprotect` у `references/cleanup-flow.md` не змінюються; field-rename compat `pinned` → `protected` (`references/telemetry.md:36`) не чіпається.
- **Історія недоторкана** (`r5`). `docs/specs/`, `docs/plans/`, наявні записи Migration Log 4.0–4.6.0 (включно з `references/discovery-versioning.md:451-454`, де історично стоїть «fewer than 20 active unprotected pages» — це запис 4.2.10, НЕ залишок), таблиця «Доступні версії» `README.md:370`.
- **Друковані рядки звіту й діалогу — байт-у-байт.** Змінюються ЛИШЕ машиночитані правила фільтра. Блок `🔍 Готую повний лінт: N активних сторінок. / Pin-protected (skipped): K сторінок.` і `references/operation-lint.md:33` (`Verified subset: full — N active pages`) лишаються дослівно (`R8`). Число `N` не змінюється за конструкцією: фільтр `state == "active"` завжди пропускав усе.
- **Обидва рядки блоку РЕФЛЕКСІЯ** — `Зберіг у wiki:` і `Кристалізація:` — лишаються й відповідають на різні питання (`r2`). Не зливати, не видаляти жодного.
- **Написання — рівно `Кристалізація`.** Форма «Крихталізація» заборонена (`r8`).
- **Самотактування моделі** — «немає harness-лічильника, модель сама себе тактує» лишається чинним (`r7`). Жодних лічильників, env, хук-поведінок, нових полів (`r1`).
- **Не додавати механізмів.** Це цикл видалення. Будь-яка пропозиція «заодно автоматизувати нудж», «заодно викинути мертві поля», «заодно узгодити термінологію в `docs/`» — відхиляється як спіраль рев'ю (`r1`, `r3`, `r5`, `r7`).

## Замір старого імені поля — 21 рядок у 7 файлах (не 14)

Спека у Δ1 пише «14 влучань», але її ж таблиця перелічує 21 рядок; таблиця авторитетна, звірено `grep -rn` на `666fb45`. **Повний список — виконуй по ньому, не по числу:**

| Файл | Рядки | Задача |
|---|---|---|
| `references/reflection.md` | 10, 24, 33, 69 | T1 |
| `references/self-improvement.md` | 16 | T1 |
| `references/crystallization.md` | 3, 41, 42, 43 | T2 |
| `tests/skill-contracts.sh` | 427 | T1 (перенацілення = тест для T1) |
| `tests/scenarios/crystallization.md` | 7, 20, 69, 186, 233, 276 | T6 |
| `tests/scenarios/reflection-triggers.md` | 51, 97, 184, 192 | T6 |
| `tests/scenarios/query-discovery.md` | 133 | T6 |

Плюс прозові влучання Δ3 (`references/reflection.md:3`, `references/crystallization.md:19`) — вони не містять імені поля, але ставлять те саме питання про «автоматизацію».

## Топологія хвиль

Кожна задача = окрема хвиля. Паралелізації немає **свідомо**: п'ять із шести робочих задач торкаються `tests/skill-contracts.sh`, паралельні хвилі дали б merge-конфлікти в тих самих секціях; крім того T4 і T5 обидві правлять `SKILL.md` (`R10` вимагає різних хвиль).

| Хвиля | Задача | Головні файли | Залежить від |
|---|---|---|---|
| 1 | T1 `t1-field-rename-reflection` — перейменування поля в reflection/self-improvement + перенацілення гарда `:427` | `references/reflection.md`, `references/self-improvement.md`, `tests/skill-contracts.sh` | — |
| 2 | T2 `t2-crystallization-cleanup` — чистка `crystallization.md` + гард A на старе ім'я | `references/crystallization.md`, `tests/skill-contracts.sh` | T1 (гард A сканує `references/` цілком) |
| 3 | T3 `t3-state-filter-unmask` — зняття мертвого фільтра + чесний `telemetry.md` + гард C | `references/operation-lint.md`, `references/operation-wiki-status.md`, `references/telemetry.md`, `tests/skill-contracts.sh` | — (ставиться 3-ю через спільний `skill-contracts.sh`) |
| 4 | T4 `t4-skill-readme-touchups` — `SKILL.md:158`, правопис і статус v4.0 у README, буліт v4.7 | `SKILL.md`, `README.md` | — |
| 5 | T5 `t5-version-migration-log` — бамп 4.7.0 + version-пін + запис Migration Log | `SKILL.md`, `tests/skill-contracts.sh`, `references/discovery-versioning.md` | T4 (спільний `SKILL.md`, `R10`) |
| 6 | T6 `t6-scenarios-cleanup` — сценарії: ім'я поля, фільтр, правопис + гард B + розширення областей A/C | `tests/scenarios/*.md`, `tests/skill-contracts.sh` | T4 (гард B сканує `README.md`) |
| 7 | T7 `t7-final-verify` — наскрізна верифікація Done-when 1–10 | — | усі |

---

## Task 1 — перейменування поля у `reflection.md` + `self-improvement.md`

**Канонічний id: `t1-field-rename-reflection`**

**Хвиля 1.** Незалежна. Диф ~8 рядків.

### Що зробити

Правки — заміни в межах рядка; значення полів, порядок рядків, склад блоку не змінюються.

1. `references/reflection.md:3` (Δ3) — «…surfaces what was learned, where it was filed, and whether anything is worth **automating**» → «…worth **crystallizing**». Решта абзацу дослівно.
2. `references/reflection.md:10` — «the reflection block names what was crystallized in the `Автоматизував:` field» → `` `Кристалізація:` ``. Дужковий хвіст (`wiki — concepts/{name}.md`, or `нічого` with reason) без змін.
3. `references/reflection.md:24` (рядок строгого шаблону) — `Автоматизував: {wiki — concepts/{name}.md  /  нічого + причина}` → `Кристалізація: {wiki — concepts/{name}.md  /  нічого + причина}`. **Подвійні пробіли всередині фігурних дужок зберегти байт-у-байт.** Рядок `Зберіг у wiki:` (`:23`) лишається на місці й вище (`r2`).
4. `references/reflection.md:33` — «The block ends on `Автоматизував:` (or `Перевірив:` when present)» → `` `Кристалізація:` ``.
5. `references/reflection.md:69` — «- **Автоматизував** is mandatory.» → «- **Кристалізація** is mandatory.». **Решта рядка дослівно:** чотири канонічні `нічого`-значення, заборона counter-style («поточний 2/3»), посилання на «Read the room».
6. `references/self-improvement.md:16` — «only load `references/crystallization.md` when the `Автоматизував:` field plausibly needs a proposal» → `` `Кристалізація:` ``.

### Тести (той самий коміт — форма (а))

7. `tests/skill-contracts.sh:427` — у циклі `for field in 'Дізнався:' 'Чому це краще:' 'Зберіг у wiki:' 'Автоматизував:' 'Перевірив:'; do` замінити `'Автоматизував:'` на `'Кристалізація:'`. **Перенацілити, не видаляти** (`r4`); порядок і решту чотирьох полів зберегти — цикл grep'ає `references/reflection.md`, тобто це і є асерт правок 3 і 5.

### Не чіпати

`### РЕФЛЕКСІЯ block format (strict template)` заголовок і його асерт (`:423-424`); `never emit a separate РЕФЛЕКСІЯ block` (`:430-431`); ліміт 90 рядків `self-improvement.md` (файл 20 рядків, запас великий); секцію `Anti-noise rule`; `references/crystallization.md` (це T2).

### Verify

```
cd "/Users/a/AI/claude-wiki-skill/.claude/worktrees/v47-reflection" && \
  grep -n 'Кристалізація' references/reflection.md references/self-improvement.md && \
  grep -rn 'Автоматизував' references/reflection.md references/self-improvement.md tests/skill-contracts.sh; \
  [ $? -eq 1 ] || echo "FAIL: legacy name survived"
```
Далі — **повна канонічна сюїта** (див. вище). Обидва рядки блоку присутні: `grep -n 'Зберіг у wiki:\|Кристалізація:' references/reflection.md` → щонайменше по одному.

### Коміт

`feat(v47-reflection-cleanup): t1-field-rename-reflection — перейменувати поле блоку РЕФЛЕКСІЯ на Кристалізація:`

---

## Task 2 — чистка `references/crystallization.md` + негативний гард на старе ім'я

**Канонічний id: `t2-crystallization-cleanup`**

**Хвиля 2.** Залежить від T1: гард A сканує `references/` цілком, тому може приземлитись лише коли `reflection.md` і `self-improvement.md` уже чисті. Диф ~30 рядків.

### Що зробити

Файл — 62 рядки. Правки за анкерами (номери звірені на `666fb45`).

1. `:3` — «The reflection's `Автоматизував:` field isn't decorative…» → «The reflection's `Кристалізація:` field isn't decorative…». Решта речення (питання «is anything worth saving…», «**proposes** (never silently creates) a single wiki-page artifact») дослівно.
2. `:5-7` — **таблиця на один рядок → абзац.** Таблиця з однією тілесною строкою обіцяє відсутню множинність. Той самий зміст прозою; цільове формулювання (можна дослівно):

   > The single crystallization artifact is a wiki page: a new or extended `concepts/{name}.md` (recipe, ready-made block, concept explanation) stored under `{wiki}/concepts/`. The judgment during a periodic nudge is one question: "I re-derived this content from scratch this session — the next session would need it too." File it so the next read finds it instead of regenerating.

   Зміст, що МУСИТЬ вціліти: артефакт = новий або розширений `concepts/{name}.md`; сховище = `{wiki}/concepts/`; критерій = «вивів з нуля цієї сесії, наступна сесія теж потребуватиме».
3. `:9` + `:11` — **два окремі пояснення «чому це не рівень» → одне речення.** Зараз: `:9` «**Why no `scripts/` tier.**» і `:11` «**Memory is not a tier either.**». Цільове формулювання (можна дослівно):

   > **No other tier exists.** User-runnable scripts (`scripts/{name}.sh` / `scripts/{name}.py`) and a separate skill tier were both proposal targets in v4.0 and were removed as Division-of-Labor violations (v4.1 and v4.4 — see the Migration Log in `references/discovery-versioning.md`); auto-memory is a perpendicular, volatile layer this skill does not operate on. The wiki page is the only crystallization artifact.

   Зміст, що МУСИТЬ вціліти: скрипти І skill-tier прибрані як порушення Division of Labor; auto-memory перпендикулярний і не є ціллю; єдиний артефакт — wiki-сторінка; посилання на Migration Log.
4. `:13` — абзац «**These are heuristics for the model's holistic judgment… Read the room.**» лишається **дослівно** (`r7` прямо забороняє автоматизацію нуджа).
5. `:19` (рядок таблиці «Periodic nudge») — «ask yourself "є щось варте автоматизації?"» → «ask yourself "є щось варте збереження, щоб наступна сесія не виводила це заново?"». **Механіка без змін:** «Every ~15 tool-calling iterations», «Self-checked», «there is no harness-side counter; the model is responsible for self-pacing» — дослівно (`r7`).
6. `:23` (рядок «Explicit user») — скрипт-гілку стиснути до однієї фрази, ЗБЕРІГШИ заборону: «If the user asks for a script (`scripts/*.sh` / `*.py`), explain that this skill doesn't crystallize user-runnable scripts and offer the wiki-page equivalent; the user can still create one manually.» Перша половина рядка («Manual override — skip judgment, go straight to a wiki proposal») без змін.
7. `:41`, `:42`, `:43` — три згадки поля у поведінці `y` / `n` / `пізніше` → `` `Кристалізація:` ``. **Значення без змін:** `wiki — {path}`, `нічого — юзер відмовив раніше`, `нічого — відкладено`.
8. `:62` — рядок anti-noise-списку «**Don't crystallize user-runnable scripts.**». Це **ЗАБОРОНА, а не обіцянка** (`r4`): заборонна частина лишається в списку, стискається лише повторне історичне пояснення (тепер воно живе в одному місці — правка 3). Цільове:

   > - **Don't crystallize user-runnable scripts.** If you find yourself wanting to propose `scripts/{name}.sh` or `scripts/{name}.py` as a saved artifact, stop — capture the underlying content as a wiki page the agent reads back, or run an inline command at the moment of need.

### Тести (той самий коміт — форма (а))

9. Додати у `tests/skill-contracts.sh` **гард A** — область рівно `references/` + `SKILL.md` (Δ6). Місце вставки: у кластері негативних гардів після `:431` (`never emit a separate РЕФЛЕКСІЯ block`), і **обов'язково ВИЩЕ** блоку `# Wire the executable hooks test suite…` наприкінці файлу.

```bash
# t2: the legacy reflection field name must not return to skill contract text.
# The pattern is assembled from two halves ON PURPOSE — the Done-when grep for the
# old name covers tests/, so this file must not contain the contiguous literal
# (a repo-wide or tests/-wide scope would also make this guard match itself).
legacy_reflection_field="Автомат""изував"
grep -rq "$legacy_reflection_field" "$ROOT/references/" "$ROOT/SKILL.md" &&
  fail "legacy reflection field name must not appear in references/ or SKILL.md (renamed to Кристалізація: in 4.7.0)"
```

   **Область НЕ розширювати** на `$ROOT`, `$ROOT/tests/`, `$ROOT/docs/` (пастки 1 і 3; `docs/` навмисно зберігає слово за `r5`). `$ROOT/tests/scenarios/` додасть T6, коли сценарії стануть чисті.

### Не чіпати

Формат пропозиції `🔁 Помічаю патерн:` з `[y] / [n] / [пізніше]`; приклад із OpenSSH; решту anti-noise-правил (`:58-61`); відсутність `set_skill_link` і `writing-skills` (негативні гарди `:412-413`, `:418-419` — після правок файл і далі не сміє їх містити); рядок `Disabled | nudge_interval: 0` і абзац про `nudge_interval` (`r7`); `references/maintenance-and-mistakes.md:43`.

### Verify

```
cd "/Users/a/AI/claude-wiki-skill/.claude/worktrees/v47-reflection" && \
  grep -rn 'Автоматизував' references/ SKILL.md; [ $? -eq 1 ] || echo "FAIL: legacy name in references/"
grep -n 'Read the room' references/crystallization.md   # абзац :13 на місці
grep -n "Don't crystallize user-runnable scripts" references/crystallization.md  # паркан на місці
grep -n 'harness-side counter' references/crystallization.md  # r7 на місці
```
Далі — повна канонічна сюїта.

### Коміт

`feat(v47-reflection-cleanup): t2-crystallization-cleanup — прибрати риштування tier-моделі і додати гард на старе ім'я поля`

---

## Task 3 — зняти маску з `state` / `archived_at`

**Канонічний id: `t3-state-filter-unmask`**

**Хвиля 3.** Незалежна від T1/T2 за змістом; ставиться третьою через спільний `tests/skill-contracts.sh`. Диф ~12 рядків.

**Розділова лінія, що робить задачу перевіряною:** машиночитані правила фільтра змінюються; **друковані рядки звіту й діалогу лишаються байт-у-байт** (`R8`).

### Що зробити

1. `references/operation-lint.md:30` (гілка «швидко / fast / top-10») — «Sort `report()` by `patch_count desc, last_patched_at asc`, filter `state == "active"` and `protected == false`, take the first 10» → фільтр лишається **лише** `protected == false`. Початок рядка («verify only top-10 most-edited active + unprotected pages») можна лишити або привести до «top-10 most-edited unprotected pages» — обери одне і не чіпай сортування й число 10.
2. `references/operation-lint.md:31` (default full lint) — «Verify ALL **active +** unprotected pages» → «Verify ALL unprotected pages». Решта речення (порядок сортування, «protected pages skipped», аналогія з ESLint/mypy/ruff) без змін.
3. `references/operation-lint.md:35` (розмірний гейт heads-up) — «If `report()` finds fewer than 20 **active +** unprotected pages» → «fewer than 20 unprotected pages». **Поріг 20 і поведінка не змінюються.**
4. `references/operation-wiki-status.md:102` (`[b]` Top-5 longest unverified) — «filtered to `state == "active"` and `protected == false`» → «filtered to `protected == false`». Решта комірки (сортування `last_patched_at asc`, AUTO/DECIDE split) без змін.
5. `references/telemetry.md:34` — замінити речення про forward-compat + обіцянку v5-куратора на точне формулювання за Δ4. Цільове (можна дослівно):

   > All ten fields are present for every record. Timestamps are ISO 8601 UTC. Of the three non-counter fields only `protected` is live: it is written by `wiki protect` / `wiki unprotect` and read by the lint and `wiki status` subset filters. `state` is written only as its default `"active"` — both when a record is created and when a record missing the key is silently backfilled — and after the subset filters dropped it, nothing reads it. `archived_at` is written only as its default `null` and nothing reads it. Both stay in the record shape so the on-disk form needs no migration.

   **Обіцянка «v5+ will use them for curator/auto-transitions» ВИДАЛЯЄТЬСЯ** — вона не має ні власника, ні дати. Формулювання «`state` ніхто не пише» і його м'якша форма «пишеться лише при створенні запису» — **ЗАБОРОНЕНІ** (`r3`, `R4`): дефолт пишеться двома шляхами, і другий (silent backfill) має живий асерт `tests/hooks/run.sh:1483`.
6. `references/telemetry.md:46` (рядок таблиці «Semantic mapping») — розщепити рядок `` `state`, `protected`, `archived_at` | forward-compat | v4.0 does not write these except defaults `` на два, щоб `protected` не стояв в одній комірці з двома мертвими полями:

   | `protected` | live — page is pin-protected | Written by `wiki protect` / `wiki unprotect`; read by the lint and `wiki status` subset filters (`protected == false`) |
   | `state`, `archived_at` | default-only | Written once as defaults (`"active"`, `null`); nothing reads them |

### Тести (той самий коміт — форма (а))

7. Додати у `tests/skill-contracts.sh` **гард C** (поруч із гардом A, вище блоку `# Wire the executable hooks test suite`):

```bash
# t3: the dead subset filter must not come back into the reference text.
# Scope is references/ only — a tests/-wide scope would match this guard itself.
grep -rq 'state == "active"' "$ROOT/references/" &&
  fail "lint / wiki status subsets must filter on protected == false only (dead state filter removed in 4.7.0)"
```

   Розщеплення half-літералами тут **не потрібне** (Пастка 2): Done-when №3 має область `references/ tests/scenarios/`, `skill-contracts.sh` туди не входить. `$ROOT/tests/scenarios/` додасть T6.

### Не чіпати

`references/telemetry.md:76` (silent backfill defaults — жива поведінка); `:36` (field-rename compat `pinned` → `protected`); фразу «All ten fields are present for every record»; `references/discovery-versioning.md:352` (політика silent-backfill forward-compat полів); `references/operation-doctor.md:67-71` (doctor перевіряє наявність десяти ключів); **будь-яку згадку `protected == false`**; друкований блок heads-up `🔍 Готую повний лінт: N активних сторінок. / Pin-protected (skipped): K сторінок.`; `references/operation-lint.md:33` (`Verified subset: full — N active pages`, `top-10 most-edited active`) — це UI, який два сценарії цитують дослівно; `references/operation-lint.md:223`; історичний запис Migration Log 4.2.10 (`references/discovery-versioning.md:451-454`, «fewer than 20 active unprotected pages») — `r5`.

### Verify

```
cd "/Users/a/AI/claude-wiki-skill/.claude/worktrees/v47-reflection" && \
  grep -rn 'state == "active"' references/; [ $? -eq 1 ] || echo "FAIL: dead filter survived"
grep -rn 'protected == false' references/     # влучання лишаються
grep -n 'Verified subset: full' references/operation-lint.md   # друкований рядок недоторканий
grep -n 'Готую повний лінт' references/operation-lint.md       # heads-up недоторканий
grep -n 'Backfill missing keys silently' references/telemetry.md  # :76 живий
git -C "/Users/a/AI/claude-wiki-skill/.claude/worktrees/v47-reflection" diff --stat  # hooks/ відсутні
```
Далі — повна канонічна сюїта.

### Коміт

`feat(v47-reflection-cleanup): t3-state-filter-unmask — зняти мертвий фільтр state і сформулювати telemetry чесно`

---

## Task 4 — три точкові правки у `SKILL.md` / `README.md` + правопис

**Канонічний id: `t4-skill-readme-touchups`**

**Хвиля 4.** Незалежна. Диф ~8 рядків. **`SKILL.md` тут правиться ЛИШЕ на `:158`** — бамп версії на `:3` належить T5 і йде іншою хвилею (`R10`).

### Що зробити

1. `SKILL.md:158` — «mature projects may benefit from lint/status/cleanup and **skill** crystallization» → «…lint/status/cleanup and crystallization». Видаляється рівно слово вирізаної цілі; решта абзацу («Use the wiki as a palette, not a checklist…») дослівно.
2. `README.md:309` (двічі в одному рядку) — «єдиний target **крихталізації**» і «видалено як target **крихталізації**» → «кристалізації» (`r8`).
3. `README.md:311` — «сигнал-кандидат для **крихталізації**» → «кристалізації» (`r8`).
4. `README.md:317` (буліт «Tiered crystallization» у секції «What's new in v4.0») — Δ5. **Факт лишається фактом** («у v4.0 пропонувалась concept-сторінка, helper-скрипт або під-скіл; ніколи silent»), але наявна помітка `*(Перероблено у v4.1 і v4.4 — див. вище.)*` посилюється до недвозначної, напр.:

   > *(Скасовано: tier-модель прибрана у v4.1 і v4.4 — скриптова й skill-ціль більше не пропонуються, єдина ціль кристалізації — wiki-сторінка. Див. вище.)*

5. **Буліт про v4.7.0** (спека: «рекомендовано, одна дія, не механізм»). Вставити **безпосередньо перед** `README.md:34` (`## What's new in v4.6`) новий заголовок і рівно один буліт — README строго newest-first за секціями, і буліт без заголовка був би підшитий під v4.6, тобто стверджував би неправду про реліз:

```markdown
## What's new in v4.7

- **Поле блоку РЕФЛЕКСІЯ зветься `Кристалізація:`.** Перейменування agent-visible
  контракту: блок друкується у хід і ніде не зберігається, тому на диску нічого не
  змінюється — `wiki_version` лишається `"4.0"`, міграцій нуль. Разом із цим
  прибрані залишки вирізаної tier-моделі кристалізації з довідки скіла.
```

   **Слово `Автоматизував` у README не вживати** (Done-when №2 покриває `README.md`).

### Тести

Окремого нового гарда задача не додає: правки 2–3 асертить гард B, який приземляє T6 (він сканує і `README.md`, і `tests/scenarios/`, тому може приземлитись лише коли обидві області чисті). Правку 1 асертить наявний ліміт рядків `SKILL.md` + повна сюїта; правки 4–5 — README-асерти нижче, які МУСЯТЬ лишитись зеленими.

### Не чіпати

Таблицю «Доступні версії» `README.md:370` (рядок `v4.0.0` з «tiered crystallization (4 рівні зі скриптами)») — `r5`; заголовок `## What's new in v4.6` і його асерт (`tests/skill-contracts.sh:711-712`); асерти `Без [y] жодних файлів не пишеться` (`:508`), `~/.qwen/skills` (`:714`), `wiki-session-start.sh` (`:717`); `README.md:565-568` (інсталяційні приклади з `v4.0.0`); `SKILL.md:3` (це T5); Platform Compatibility таблицю (асерт 5 колонок `:23-24`).

### Verify

```
cd "/Users/a/AI/claude-wiki-skill/.claude/worktrees/v47-reflection" && \
  grep -rni 'крихталіз' SKILL.md README.md references/; [ $? -eq 1 ] || echo "FAIL: misspelling survived"
grep -n 'skill crystallization' SKILL.md; [ $? -eq 1 ] || echo "FAIL: skill tier survived"
grep -n "What's new in v4.7" README.md && grep -n "What's new in v4.6" README.md
grep -n 'tiered crystallization (4 рівні зі скриптами)' README.md   # історія недоторкана
wc -l SKILL.md   # <= 450
```
Далі — повна канонічна сюїта.

### Коміт

`feat(v47-reflection-cleanup): t4-skill-readme-touchups — прибрати skill-tier зі SKILL.md, виправити правопис і статус v4.0 у README`

---

## Task 5 — версія 4.7.0, version-пін і запис Migration Log

**Канонічний id: `t5-version-migration-log`**

**Хвиля 5.** Залежить від T4 (спільний `SKILL.md`, `R10`). Диф ~18 рядків. **Три правки — ОДИН коміт** (`R9`: без перенацілення піна сюїта червона одразу після бампу).

### Що зробити

1. `SKILL.md:3` — `version: "4.6.1"` → `version: "4.7.0"`.
2. `tests/skill-contracts.sh:561-562` — `grep -q 'version: "4.6.1"' "$ROOT/SKILL.md" || fail "SKILL.md frontmatter must be bumped to 4.6.1"` → `"4.7.0"` **у патерні І в тексті fail-повідомлення**.
3. `references/discovery-versioning.md` — **дописати** запис `### 4.7.0 (2026-08-14)` безпосередньо **перед** `### 4.6.0 (2026-08-13)` (наразі рядок 456), зберігаючи newest-first порядок блоку. Наявні записи 4.0–4.6.0 **не переписувати** (`r5`) — `git diff` мусить показати рівно вставку.

   **ПАСТКА 3 — критично.** Файл лежить в області гарда A (хвиля 2), гарда C (хвиля 3), Done-when №2 і №3. Текст запису **не сміє містити** ні суцільного `Автоматизував`, ні суцільного `state == "active"`. Готове формулювання, що це поважає:

```markdown
### 4.7.0 (2026-08-14)
- No schema migration (`wiki_version` stays `"4.0"`); zero per-wiki migrations
  required for existing wikis. The РЕФЛЕКСІЯ block's crystallization field is
  renamed to `Кристалізація:` (it previously carried the automation-era name).
  This is an agent-visible contract only: the block is printed into the turn and
  never persisted — `{wiki}/log.md` keeps its own entry format — so nothing on
  disk is rewritten. The crystallization reference is stripped of scaffolding
  left by the tier model removed in 4.1 and 4.4. The dead active-state filter is
  dropped from the lint and `wiki status` subsets: the subset is now filtered by
  `protected == false` only, and the page counts printed in the lint heads-up are
  unchanged because that filter always passed everything. The `.usage.json`
  record shape is unchanged — `state`, `protected` and `archived_at` are still
  present in every record.
```

### Тести (той самий коміт — форма (а))

4. Додати у `tests/skill-contracts.sh` (поруч із наявним історичним асертом `### 4.6.0` на `:603-604`) дзеркальний асерт:

```bash
grep -q '### 4.7.0' "$ROOT/references/discovery-versioning.md" ||
  fail "discovery-versioning.md Migration Log must have a ### 4.7.0 entry"
```

### Не чіпати

Історичний асерт `### 4.6.0` (`:603-604`) — лишається зеленим; асерт узгодження мажора `SKILL.md` ↔ `references/operation-init.md` (`:606+`) — мажор лишається `4`, `wiki_version` в `operation-init.md` лишається `"4.0"`; будь-який наявний запис Migration Log; `SKILL.md:158` (це T4).

### Verify

```
cd "/Users/a/AI/claude-wiki-skill/.claude/worktrees/v47-reflection" && \
  grep -n 'version: "4.7.0"' SKILL.md && grep -n '4.7.0' tests/skill-contracts.sh && \
  grep -n '### 4.7.0' references/discovery-versioning.md && \
  grep -rn 'wiki_version: "4.0"' references/operation-init.md
grep -rn 'Автоматизував' references/; [ $? -eq 1 ] || echo "FAIL: legacy literal in Migration Log"
grep -rn 'state == "active"' references/; [ $? -eq 1 ] || echo "FAIL: dead filter literal in Migration Log"
git -C "/Users/a/AI/claude-wiki-skill/.claude/worktrees/v47-reflection" diff -- references/discovery-versioning.md   # лише вставка
```
Далі — повна канонічна сюїта.

### Коміт

`feat(v47-reflection-cleanup): t5-version-migration-log — бамп 4.7.0, version-пін і запис Migration Log`

---

## Task 6 — тестові сценарії: ім'я поля, фільтр, правопис + гард на правопис

**Канонічний id: `t6-scenarios-cleanup`**

**Хвиля 6.** Залежить від T4 (гард B сканує `README.md`). Диф ~20 рядків, усі — заміни в межах рядка у шести сценаріях.

### Що зробити — перейменування поля (11 рядків)

1. `tests/scenarios/crystallization.md` — `:7`, `:20`, `:69` (заголовок колонки таблиці), `:233`, `:276` → `` `Кристалізація:` `` / `Кристалізація: нічого — патерн не повторюється` (значення без змін).
2. `tests/scenarios/crystallization.md:186` — значення `нічого — юзер попросив скрипт поза tier-моделлю` посилається на неіснуючу модель. → напр. `нічого — юзер попросив скрипт, а скрипти не кристалізуються`. **Хвіст «rather than fabricating a tier name» лишається** — це паркан.
3. `tests/scenarios/reflection-triggers.md` — `:51`, `:97`, `:192` (очікуваний вивід блоку) і `:184` (текст правила «блок закінчується на …») → `Кристалізація:`. У `:51`/`:97`/`:192` значення `нічого — операція разова` без змін.
4. `tests/scenarios/query-discovery.md:133` → `` `Кристалізація:` ``.

### Що зробити — правопис (`r8`)

5. `tests/scenarios/crystallization.md:192` — «Скіл більше не пропонує user-runnable скрипти як **крихталізацію**» → «кристалізацію».

### Що зробити — зняття фільтра (Δ2, 3 рядки)

Правляться **лише речення-правила**; **JSON-фікстури з `"state": "active"` НЕ чіпати** — форма запису на диску не змінюється (`r3`). Це стосується `telemetry-counters.md`, `wiki-status.md`, `staleness-content-verification.md`, `cleanup-flow.md:122` та будь-яких інших фікстур.

6. `tests/scenarios/cleanup-flow.md:65` — «Filter `state == "active"` and `protected == false`» → «Filter `protected == false`». Сортування `patch_count desc, last_patched_at asc` без змін.
7. `tests/scenarios/staleness-content-verification.md:71` — те саме у правилі top-10.
8. `tests/scenarios/wiki-status.md:224` — те саме в описі `[b]`. **Перелік сторінок і хвіст «(`secret-rotation-recipe` skipped because protected)» лишаються** — вони підтверджують, що `protected` живий.

### Тести (той самий коміт — форма (а))

9. Додати у `tests/skill-contracts.sh` **гард B** (поруч із гардами A і C, вище блоку `# Wire the executable hooks test suite`):

```bash
# t6: the inherited misspelling of «кристалізація» must not come back (r8).
# Two-half literal ON PURPOSE — the Done-when grep covers tests/, and a
# tests/-wide scope would make this guard match itself.
legacy_spelling="крихт""аліз"
grep -rqi "$legacy_spelling" "$ROOT/SKILL.md" "$ROOT/README.md" "$ROOT/references/" "$ROOT/tests/scenarios/" &&
  fail "use «кристалізація» — the inherited misspelling must not appear in skill or scenario text (r8)"
```

10. **Розширити області гардів A і C** на `$ROOT/tests/scenarios/` (додавання шляху, не послаблення) — рівно тепер сценарії стали чисті, і це робить Done-when №2 і №3 регресійно захищеними:
    - гард A → `grep -rq "$legacy_reflection_field" "$ROOT/references/" "$ROOT/SKILL.md" "$ROOT/tests/scenarios/"`;
    - гард C → `grep -rq 'state == "active"' "$ROOT/references/" "$ROOT/tests/scenarios/"`.

    **`$ROOT/tests/` цілком або `$ROOT` — заборонено** (Пастка 1: самозбіг).

    ⚠️ Перед розширенням гарда C переконайся, що жодна JSON-фікстура не містить рядка `state == "active"` (фікстури мають форму `"state": "active"` — інший літерал, збігу немає). Перевірка: `grep -rn 'state == "active"' tests/scenarios/` після правок 6–8 має дати нуль.

### Не чіпати

Регресійні суб-сценарії, що забороняють скрипт-/skill-цілі (`r4`) — правиться лише ім'я поля й формулювання `:186`; JSON-фікстури з `"state": "active"`; `tests/README.md` (замір показує, що правок не потребує: рядки про «proposes only the single `wiki` artifact type, never a script or skill tier» — це паркан, а не залишок; файл входить у задачу як **перевірка**, не як правка); `tests/hooks/run.sh` (hooks поза скоупом); сценарії `cross-agent-discovery.md` (їхні заголовки асертить сюїта на `:148-322`, `:499-502`).

### Verify

```
cd "/Users/a/AI/claude-wiki-skill/.claude/worktrees/v47-reflection" && \
  grep -rn 'Автоматизував' tests/scenarios/; [ $? -eq 1 ] || echo "FAIL: legacy name in scenarios"
grep -rn 'state == "active"' tests/scenarios/; [ $? -eq 1 ] || echo "FAIL: dead filter in scenarios"
grep -rni 'крихталіз' SKILL.md README.md references/ tests/scenarios/; [ $? -eq 1 ] || echo "FAIL: misspelling"
grep -rn '"state": "active"' tests/scenarios/   # фікстури НА МІСЦІ (мають бути влучання)
grep -n 'never a script or skill tier' tests/README.md   # паркан на місці
```
Далі — повна канонічна сюїта.

### Коміт

`feat(v47-reflection-cleanup): t6-scenarios-cleanup — перейменувати поле у сценаріях, зняти фільтр і додати гард правопису`

---

## Task 7 — наскрізна верифікація Done-when

**Канонічний id: `t7-final-verify`**

**Хвиля 7.** Залежить від усіх. Правок коду не робить. Якщо якийсь пункт червоний — **не «підганяй» гард під результат**: локалізуй пропущене влучання й правь текст у файлі, якому воно належить, окремим комітом того ж id.

### Що зробити

Прогнати всі десять пунктів Done-when із кореня воркtree і зафіксувати вивід:

```
cd "/Users/a/AI/claude-wiki-skill/.claude/worktrees/v47-reflection"

# 1 — повна канонічна сюїта
bash tests/hooks/run.sh && bash tests/skill-contracts.sh && \
  bash tests/install-cross-agent-links.sh && bash tests/uninstall.sh

# 2 — старе ім'я поля відсутнє (docs/ виключено навмисно, r5)
grep -rn 'Автоматизував' SKILL.md README.md references/ tests/ ; [ $? -eq 1 ] || echo FAIL-2

# 3 — мертвий фільтр відсутній
grep -rn 'state == "active"' references/ tests/scenarios/ ; [ $? -eq 1 ] || echo FAIL-3

# 4 — правопис (r8)
grep -rni 'крихталіз' SKILL.md README.md references/ tests/ ; [ $? -eq 1 ] || echo FAIL-4

# 5 — нове ім'я на місці, обидва рядки блоку живі (r2)
grep -n 'Кристалізація:' references/reflection.md
grep -n 'Зберіг у wiki:' references/reflection.md

# 6 — protected недоторканий
grep -rn 'protected == false' references/
git -C "$PWD" diff --stat 666fb45..HEAD -- references/cleanup-flow.md   # має бути порожньо

# 7 — паркан на місці (r4)
grep -n 'set_skill_link\|writing-skills\|🧹' tests/skill-contracts.sh

# 8 — версія узгоджена, схема лишилась 4.0
grep -n 'version: "4.7.0"' SKILL.md
grep -n '4.7.0' tests/skill-contracts.sh
grep -rn 'wiki_version: "4.0"' references/

# 9 — Migration Log: лише вставка
grep -n '### 4.7.0 (2026-08-14)' references/discovery-versioning.md
git -C "$PWD" diff 666fb45..HEAD -- references/discovery-versioning.md   # лише додані рядки

# 10 — скоуп не поповз
git -C "$PWD" diff --stat 666fb45..HEAD
```

**Пункт 10 — жорсткий:** у `diff --stat` НЕ сміє бути жодного файла з `hooks/`, `install.sh`, `uninstall.sh`, `docs/specs/`, `docs/plans/` (крім самого цього плану, доданого до старту задач), `tests/hooks/`. Очікуваний перелік торкнутих файлів рівно такий: `SKILL.md`, `README.md`, `references/reflection.md`, `references/self-improvement.md`, `references/crystallization.md`, `references/operation-lint.md`, `references/operation-wiki-status.md`, `references/telemetry.md`, `references/discovery-versioning.md`, `tests/skill-contracts.sh`, `tests/scenarios/crystallization.md`, `tests/scenarios/reflection-triggers.md`, `tests/scenarios/query-discovery.md`, `tests/scenarios/cleanup-flow.md`, `tests/scenarios/staleness-content-verification.md`, `tests/scenarios/wiki-status.md`.

Додатково перевірити інваріанти, які Done-when не ловить: `git -C "$PWD" diff 666fb45..HEAD -- references/telemetry.md` не чіпає `:76`; друковані рядки `Готую повний лінт` і `Verified subset: full` присутні дослівно.

### Коміт

Якщо правок не було — комітити нема чого; зафіксуй результат у звіті задачі. Якщо був фікс: `feat(v47-reflection-cleanup): t7-final-verify — фінальна верифікація Done-when`.
