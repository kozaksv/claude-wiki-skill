# Plan — Wiki Skill v4.6.1: client-aware project anchor

**Date:** 2026-08-14
**Spec:** `docs/superpowers/specs/2026-08-14-v461-anchor-precedence.md`
**Design:** `docs/superpowers/specs/2026-08-14-v461-anchor-precedence-design.md`
**Settled-леджер:** `docs/superpowers/plans/2026-08-14-v461-anchor-precedence-settled.md` — **ОКРЕМИЙ файл, НЕ переносити сюди, НЕ видаляти** (p4).
**Working root (ALL paths absolute under):** `/Users/a/AI/claude-wiki-skill/.claude/worktrees/v46-qwen`
**Slug:** `v461-anchor-precedence`. База: `master` воркtree `v46-qwen` (`3b1ce77`).
**Nature:** behavior patch у трьох хук-файлах + бамп версії скіла + приведення двох doc-артефактів у відповідність. **On-disk схема вікі без змін** (`wiki_version` = `"4.0"`, `_hooks.hook_version` = `"1"`), нуль міграцій, нуль backfill. Skill bump `4.6.0` → `4.6.1`.

**Commit-контракт посадок (обов'язковий):** subject коміта кожної задачі — `feat(v461-anchor-precedence): <канонічний id> — <опис>`. Лончер конвеєра деривує knownDone РІВНО з патерна `feat(v461-anchor-precedence): <id>` на гілці (інші типи/subjects невидимі), тож відхилення від формату означає фантомну переробку задачі наступним раном. Канонічні id перелічені в кожній задачі і в таблиці хвиль.

---

## Worktree discipline (читати ПЕРЕД будь-якою задачею)

- Це **окремий worktree**; твій shell cwd може бути ІНШИМ worktree. НІКОЛИ голий `git`.
- Усі git: `git -C "/Users/a/AI/claude-wiki-skill/.claude/worktrees/v46-qwen" …`.
- Усі Read/Edit/Write і файлові Bash — ЛИШЕ за АБСОЛЮТНИМИ шляхами під коренем вище.
- Будь-який run/тест: `cd "/Users/a/AI/claude-wiki-skill/.claude/worktrees/v46-qwen" && …`.
- Перед КОЖНИМ комітом: `git -C "…root…" status --short` МАЄ показувати САМЕ твої файли. Порожньо / не ті → писав не туди, виправ абсолютний шлях ПЕРШ ніж комітити.
- Коміть лише файли своєї задачі явними абсолютними шляхами.
- **Симлінк-пастка:** `~/.claude/skills/wiki` — симлінк на ОСНОВНИЙ репо, не на цей worktree. Ніколи не тестуй проти реальних `~/.claude/…` чи `~/.qwen/…` — ЛИШЕ проти tmp-фікстур.

## Канонічна повна сюїта (verify-крок КОЖНОЇ задачі — без винятків)

```
cd "/Users/a/AI/claude-wiki-skill/.claude/worktrees/v46-qwen" && \
  bash tests/hooks/run.sh && \
  bash tests/skill-contracts.sh && \
  bash tests/install-cross-agent-links.sh && \
  bash tests/uninstall.sh
```

Сюїта МАЄ бути зеленою після КОЖНОЇ задачі. Тому кожна задача нижче — **форма (а)**: тест і код, що його задовольняє, в ОДНОМУ комміті. Жодна задача не лишає «падаючу перевірку для наступної», жодна задача не додає expected-fail маркерів. Задачі, що додають ЛИШЕ тести (T2), тестують код, який уже приземлився попередньою хвилею, — вони зелені в момент коміту, це та сама форма (а).

**Про номери рядків у цьому плані.** Анкери у продакшн-файлах (`hooks/*.sh`, `SKILL.md`, `README.md`, `tests/scenarios/*.md`) звірені й точні на `3b1ce77`. Анкери в `tests/hooks/run.sh` і `tests/skill-contracts.sh` **дрейфують**: кожна посадка дописує десятки рядків. Тому в тестових файлах орієнтуйся на **текстовий анкер** (заголовок секції `echo "=== … ===" >&2`, ім'я хелпера, коментар над блоком), а номер читай як «приблизно тут». Розбіжність номера з текстом — НЕ підстава вважати задачу невиконуваною: `grep -n` по анкеру і працюй далі.

## Спільні інваріанти (НЕ ослаблювати в жодній задачі)

- **Регрес-нуль для Claude / Codex / Gemini.** Default-гілка обох ланцюгів (`CLAUDE_PROJECT_DIR` → `QWEN_PROJECT_DIR` → хвіст) лишається **текстово тотожною поточній**. Жодна сходинка не зникає: «чужий» env лишається fallback-ом.
- **Хвіст ланцюга — спільний і не дублюється.** `stdin cwd` → `pwd` (PostToolUse) та `pwd` (`discover_wiki`) стоять ПОЗА `if`, в одному екземплярі.
- **Клієнт визначається за фактом виклику, не за наявністю env.** PostToolUse — ЛИШЕ за `tool_name`. SessionStart — ЛИШЕ за `WIKI_HOOK_CLIENT`. `post-tool-use.sh` **не читає** `WIKI_HOOK_CLIENT` взагалі (edge 6).
- **`WIKI_HOOK_CLIENT` — приватний канал транспорт → канонічний хук.** Приймається лише за **точної рівності** `qwen` (`[ "$x" = "qwen" ]`; не `case`-патерн, не `[[ == ]]` з glob, не нормалізація регістру). Не документується як налаштування користувача ні в `SKILL.md`, ні в README.
- **Класифікація клієнта — тотальна за конструкцією.** Клієнт присвоюється в тих самих гілках `case "$tool_name"`, що й `action`. Третього переліку імен інструментів у файлі не з'являється (R1). Інваріант `BATCH_TOOLS ⊂ action-gate` не зачіпається; `BATCH_TOOLS` лишається `{"MultiEdit"}`.
- **Скоуп замкнено (p2, R6):** рівно три правки коду + версія + два doc-артефакти. Жодних sha/dev-ino-звірок, fd-утримань, фонових процесів, нових env понад `WIKI_HOOK_CLIENT`, нових асертів у `skill-contracts.sh` понад перенацілення version-піна. Будь-яка пропозиція «закрити ще одне вікно» тут відхиляється як спіраль рев'ю.
- **`hooks/session-start.sh` НЕ змінюється взагалі** (p3): stdin `cwd` у канонічному SessionStart — окремий follow-up.
- Кожен шлях кожного хука завершується `exit 0` і НІКОЛИ не блокує інструмент чи старт сесії.
- Fail-closed-без-git, boundary-guard `{wiki}/`, version-gate, 24 KB cap, фільтри сторінок, мутекс, інсталери — **без дотику й без послаблень**.
- `set -u`-безпека: скрізь `${VAR:-}`; жодна підстановка команди не живить присвоєння напряму.
- **Наявні асерти не послаблюються й не видаляються.** Планом дозволено рівно **два** точкові дотики до наявних перевірок, обидва без послаблення: (1) перенацілення version-піна `4.6.0` → `4.6.1` у `tests/skill-contracts.sh` разом із текстом fail-повідомлення (T5, той самий коміт, що й бамп `SKILL.md`); (2) коментар + герметизація наявного discover-кейсу 18 через `env -u WIKI_HOOK_CLIENT` (T3) — це посилення, не послаблення. **Історичний** Migration-Log-асерт `### 4.6.0` і Platform-таблиця (5 колонок) НЕ чіпаються; запис `### 4.6.1` у `references/discovery-versioning.md` **не додається** (поза скоупом за спекою).

## Топологія хвиль

Кожна задача = окрема хвиля (шар залежностей). Паралелізації немає свідомо: п'ять із семи задач по черзі торкаються `tests/hooks/run.sh`, і паралельні хвилі дали б merge-конфлікти в тих самих секціях.

| Хвиля | Задача | Головні файли | Залежить від |
|---|---|---|---|
| 1 | T1 `t1-ptu-client-anchor` — client у action-gate + client-aware anchor | `hooks/post-tool-use.sh`, `tests/hooks/run.sh` | — |
| 2 | T2 `t2-ptu-client-matrix` — решта матриці PostToolUse (лише тести) | `tests/hooks/run.sh` | T1 |
| 3 | T3 `t3-discover-hook-client` — `WIKI_HOOK_CLIENT` у fallback `discover_wiki` | `hooks/lib/discover.sh`, `tests/hooks/run.sh` | — |
| 4 | T4 `t4-qwen-transport-signal` — wrapper передає `WIKI_HOOK_CLIENT=qwen` | `hooks/session-start-qwen.sh`, `tests/hooks/run.sh` | T3 |
| 5 | T5 `t5-version-bump` — `SKILL.md` 4.6.1 + перенацілення піна | `SKILL.md`, `tests/skill-contracts.sh` | — |
| 6 | T6 `t6-docs-anchor-precedence` — Scenario 3q3 + README | `tests/scenarios/cross-agent-discovery.md`, `README.md` | T1, T3, T4 |
| 7 | T7 `t7-final-verify` — наскрізна верифікація Done-when | — | усі |

**Чому doc-артефакти (T6) окремою задачею, а не в комміті коду.** Спека (R4) просить правити їх «у тому ж комміті, що й код». Обидва артефакти роблять твердження, які охоплюють **обидва** механізми одночасно (both-set буліт Scenario 3q3 описує і PostToolUse-за-`tool_name`, і SessionStart-за-транспортом; README-речення `:59-60` — так само). Розрізати їх між T1 і T4 означало б двічі переписати ті самі рядки й лишити в дереві проміжну редакцію з наполовину реверснутим твердженням — стан гірший за один коміт пізніше в тому ж циклі. Жоден виконуваний тест ці рядки не асертить (`skill-contracts.sh` перевіряє лише **заголовки** сценаріїв і заголовок «What's new in v4.6» — усі три лишаються на місці), тож порядок не впливає на колір сюїти. Вимога спеки по суті — «не follow-up, а частина цього циклу» — виконана: T6 обов'язкова задача цього плану і передує T7.

---

## Task 1 — `hooks/post-tool-use.sh`: client у action-gate + client-aware anchor

**Канонічний id: `t1-ptu-client-anchor`** — стабільний ідентифікатор задачі у графі (knownDone, stop-loss-лічильники і done-піни деривуються з нього; НЕ перечеканювати).

**Хвиля 1.** Незалежна. Диф ~30 рядків коду/коментарів + ~110 рядків тестів.

### Що зробити

1. **Розщепити наявний `case "$tool_name"` на чотири гілки, кожна присвоює І `action`, І `client`.** Анкер: `hooks/post-tool-use.sh:364-369` (блок `local action` + `case`, що вже стоїть **ПЕРЕД** `[ "${#file_paths[@]}" -gt 0 ] || exit 0` на `:371` — цей порядок із v4.6 **не змінюється**).

   ```bash
   local action client
   case "$tool_name" in
     Read)                          action="view";  client="claude" ;;
     read_file)                     action="view";  client="qwen"  ;;
     Edit|Write|MultiEdit)          action="patch"; client="claude" ;;
     write_file|edit|replace|notebook_edit)
                                    action="patch"; client="qwen"  ;;
     *) exit 0 ;;
   esac
   ```

   Відображення «ім'я → `action`» і гілка `*) exit 0` мають лишитись **байт-у-байт тими самими за результатом** для кожного з дев'яти дозволених імен; змінюється лише групування гілок. `client` присвоюється в КОЖНІЙ не-exit гілці, тож під `set -u` він завжди визначений нижче.

   **Заборонено:** окремий другий `case`/список імен «client-gate» після action-gate (R1 — це створило б третій перелік назв інструментів у файлі й тихий режим відмови для майбутнього Qwen-імені).

2. **Anchor-ланцюг стає впорядкованим за `client`.** Анкер: `hooks/post-tool-use.sh:381-385`.

   ```bash
   local anchor
   if [ "$client" = "qwen" ]; then
     anchor="${QWEN_PROJECT_DIR:-}"
     [ -n "$anchor" ] || anchor="${CLAUDE_PROJECT_DIR:-}"
   else
     anchor="${CLAUDE_PROJECT_DIR:-}"
     [ -n "$anchor" ] || anchor="${QWEN_PROJECT_DIR:-}"
   fi
   [ -n "$anchor" ] || anchor="$stdin_cwd"
   [ -n "$anchor" ] || anchor="$(pwd)"
   ```

   Гілка `else` — поточний код без змін. Хвіст (`stdin_cwd` → `pwd`) — спільний, ПОЗА `if`, в одному екземплярі.

3. **Коментарі.** Переписати header-нотатку `hooks/post-tool-use.sh:22-31` — фраза «strict precedence `$CLAUDE_PROJECT_DIR` -> `$QWEN_PROJECT_DIR`» і «QWEN_PROJECT_DIR … only applies when CLAUDE_PROJECT_DIR is unset» **більше не вірні**. Нове формулювання: порядок двох env-сходинок client-aware за `tool_name`; хвіст спільний. Коментар над anchor-блоком (`:373-380`) пояснює **причину**: вкладена Qwen-сесія всередині Claude-сесії — обидві env присутні й вказують на РІЗНІ проєкти (емпіричний прогін 2026-08-14, Qwen Code 0.21.11), з посиланням на `docs/superpowers/specs/2026-08-14-v461-anchor-precedence.md`.

**НЕ чіпати:** `_wiki_ptu_bump` цілком (`:97-263`), python-екстрактор (`:297-352`) і `BATCH_TOOLS` у ньому (`:343`), version-gate (`:394-405`), boundary-guard (`:418-422`), фільтри `*.md` / `index|schema|log.md` / `log/` (`:424-443`), `discover_wiki "$anchor"` (`:388`), `exit 0` на всіх шляхах.

**Заборонено:** будь-яке читання `WIKI_HOOK_CLIENT` у цьому файлі (edge 6 — гілка `WIKI_HOOK_CLIENT` у `discover_wiki` для PostToolUse структурно недосяжна, бо хук завжди передає непорожній `$anchor`).

### Тести (post-tool-use-секція `tests/hooks/run.sh`, анкер `echo "=== post-tool-use.sh ===" >&2` + хелпери `_ptu_stdin`/`_ptu_field`/`_sha`/`assert_file_unchanged`)

Спільна форма всіх кейсів: дві фікстури `claude_fixture="$(make_fixture)"` і `qwen_fixture="$(make_fixture)"`, у кожній `printf 'body\n' >"$…/docs/wiki/foo.md"`; `_sha` обох `.usage.json` знімається ДО виклику; після виклику один бампається, другий перевіряється `assert_file_unchanged`. `file_path` — **абсолютний** (Qwen завжди шле абсолютний шлях).

- **P1** `read_file`, `CLAUDE_PROJECT_DIR="$claude_fixture" QWEN_PROJECT_DIR="$qwen_fixture"`, шлях у **qwen**-фікстурі → `view_count`=1 у qwen-вікі; claude-`.usage.json` байт-у-байт незмінний.
- **P2** `Read`, обидві env, шлях у **claude**-фікстурі → `view_count`=1 у claude-вікі; qwen-`.usage.json` незмінний.
- **P8** `Read`, обидві env, **`WIKI_HOOK_CLIENT=qwen` у середовищі**, шлях у claude-фікстурі → бампається **claude**-вікі, qwen незмінний. Доказ: PostToolUse не читає `WIKI_HOOK_CLIENT`, env не може перебити `tool_name`.
- **P9** `run_shell_command` і `Grep`, кожен із валідним шляхом усередині відповідної вікі, обидві env → **обидва** `.usage.json` незмінні, stdout порожній, `exit 0` (action-gate не розширився).

Кожен кейс додатково асертить `rc=0`.

**Наявні PostToolUse-кейси мають лишитись зеленими без жодної правки** — зокрема first-match-wins по ключах stdin, `edits[]`-batch-only, не-matched імена, concurrent-bump, relative-`file_path`-через-stdin-`cwd`.

### Verify

1. `cd "/Users/a/AI/claude-wiki-skill/.claude/worktrees/v46-qwen" && bash -n hooks/post-tool-use.sh` — синтаксис ок.
2. Канонічна повна сюїта → зелена.
3. `grep -n 'WIKI_HOOK_CLIENT' hooks/post-tool-use.sh` → **порожньо**.
4. `git -C "…root…" status --short` показує рівно `hooks/post-tool-use.sh` і `tests/hooks/run.sh`.

### Файли

- `hooks/post-tool-use.sh:22-31` (header-нотатка anchor), `:364-369` (action/client `case`), `:373-385` (anchor-ланцюг)
- `tests/hooks/run.sh` (post-tool-use-секція, ~`:1070`+)

### Commit

`feat(v461-anchor-precedence): t1-ptu-client-anchor — client-aware anchor order in post-tool-use`

---

## Task 2 — PostToolUse: решта матриці клієнт × ланцюг (лише тести)

**Канонічний id: `t2-ptu-client-matrix`** — стабільний ідентифікатор задачі у графі (knownDone, stop-loss-лічильники і done-піни деривуються з нього; НЕ перечеканювати).

**Хвиля 2.** Залежить від T1 (тестує вже приземлений код — форма (а), зелено в момент коміту). Диф ~130 рядків тестів, **нуль рядків продакшн-коду**.

### Що зробити

Дописати в post-tool-use-секцію `tests/hooks/run.sh` (одразу після блоку P1/P2/P8/P9 з T1) решту матриці. Та сама спільна форма: дві фікстури, `_sha` до виклику, `assert_file_unchanged` на «чужій».

- **P3** для КОЖНОГО з `write_file`, `edit`, `replace`, `notebook_edit`, обидві env, абсолютний шлях у **qwen**-фікстурі → `patch_count`=1 у qwen-вікі; claude-`.usage.json` незмінний. (Форма stdin — наявний `_ptu_stdin` з `tool_input.file_path`; варіант `notebook_path` уже покритий наявним кейсом і тут не дублюється.)
- **P4** для КОЖНОГО з `Edit`, `Write`, `MultiEdit`, обидві env, абсолютний шлях у **claude**-фікстурі → `patch_count`=1 у claude-вікі; qwen незмінний.
- **P5** `read_file`, задано **лише** `CLAUDE_PROJECT_DIR` (`env -u QWEN_PROJECT_DIR`), шлях у claude-фікстурі → бампається claude-вікі. Доказ: qwen-first гілка не «загубила» fallback-сходинку.
- **P6** `Read`, задано **лише** `QWEN_PROJECT_DIR` (`env -u CLAUDE_PROJECT_DIR`), шлях у qwen-фікстурі → бампається qwen-вікі (дзеркально; наявна поведінка не зламана).
- **P7** `read_file`, **жодної** env (`env -u CLAUDE_PROJECT_DIR -u QWEN_PROJECT_DIR`), stdin `cwd` = фікстура, **відносний** `file_path` = `docs/wiki/foo.md`, хук запущено з підкаталогу фікстури → бампається вікі фікстури. Форма stdin — як у наявному кейсі «relative file_path resolves against stdin cwd» (анкер: `assert_eq "post-tool-use: relative file_path resolves against stdin cwd…"`, ~`tests/hooks/run.sh:1487`). Доказ: спільний хвіст ланцюга не продубльовано й не зламано.

Кожен кейс асертить `rc=0`. Жоден наявний assert не правиться.

### Verify

1. Канонічна повна сюїта → зелена.
2. `git -C "…root…" diff --stat` показує зміни РІВНО в `tests/hooks/run.sh` (нуль продакшн-файлів).
3. Швидкий негативний контроль (не комітити): тимчасово інвертувати `if [ "$client" = "qwen" ]` у `hooks/post-tool-use.sh` → `bash tests/hooks/run.sh` МАЄ почервоніти на P1/P3; повернути файл через `git -C "…root…" checkout -- hooks/post-tool-use.sh` ПЕРЕД комітом.

### Файли

- `tests/hooks/run.sh` (post-tool-use-секція, після блоку T1)

### Commit

`feat(v461-anchor-precedence): t2-ptu-client-matrix — full client × anchor-chain matrix for post-tool-use`

---

## Task 3 — `hooks/lib/discover.sh`: `WIKI_HOOK_CLIENT` у fallback стартової точки

**Канонічний id: `t3-discover-hook-client`** — стабільний ідентифікатор задачі у графі (knownDone, stop-loss-лічильники і done-піни деривуються з нього; НЕ перечеканювати).

**Хвиля 3.** Незалежна від T1/T2 логічно, серіалізована по `tests/hooks/run.sh`. Диф ~15 рядків коду/коментарів + ~120 рядків тестів.

### Що зробити

1. Правиться **лише** блок `if [ -z "$start" ]` усередині `discover_wiki`. Анкер: `hooks/lib/discover.sh:153-158`.

   ```bash
   local start="${1:-}"
   if [ -z "$start" ]; then
     if [ "${WIKI_HOOK_CLIENT:-}" = "qwen" ]; then
       start="${QWEN_PROJECT_DIR:-}"
       [ -n "$start" ] || start="${CLAUDE_PROJECT_DIR:-}"
     else
       start="${CLAUDE_PROJECT_DIR:-}"
       [ -n "$start" ] || start="${QWEN_PROJECT_DIR:-}"
     fi
     [ -n "$start" ] || start="$(pwd)"
   fi
   ```

   - Порівняння — **точна рівність** `[ "$x" = "qwen" ]`. НЕ `case`-патерн, НЕ `[[ == ]]` з glob-семантикою, НЕ нормалізація регістру, НЕ префікс.
   - Явний `$1` як і раніше **виграє над усім**: внутрішній блок виконується тільки при порожньому `start`.
   - Хвіст `pwd` — ПОЗА внутрішнім `if`, в одному екземплярі.
   - Безпека під `set -euo pipefail` зберігається: `${VAR:-}` скрізь, жодна підстановка команди не живить присвоєння напряму.

2. Переписати коментар над блоком (`hooks/lib/discover.sh:148-152`) — формулювання «CLAUDE_PROJECT_DIR always wins when both are set (spec edge 11)» **більше не вірне**. Нове фіксує: `WIKI_HOOK_CLIENT` — **приватний канал транспорту → канонічний хук**, не користувацьке налаштування, приймається лише за точної рівності `qwen`, впливає РІВНО на порядок двох env-сходинок (обидві з того самого середовища), обидві лишаються в ланцюгу.

**НЕ чіпати:** `[ -d "$start" ] || return 0` (`:159`), fail-closed-без-git (`:168-170`), boundary-guard (`:47-60`), `_wiki_disc_dir_pointers` і перелік `CLAUDE.md AGENTS.md GEMINI.md QWEN.md` (`:86-105`), normalize-pointer (`:107-127`), Phase-1 walk-up (`:186-210`), Phase-2 fallback (`:212-226`).

### Тести (discover-секція `tests/hooks/run.sh`, поряд із наявними кейсами 17-19; анкер — коментар `# 17. QWEN_PROJECT_DIR as the start-point anchor…`)

Форма виклику — як у наявних кейсах 17/18: `bash -c "source '$DISCOVER_LIB'; discover_wiki"` із потрібним env-префіксом, без аргументу.

- **D1** `WIKI_HOOK_CLIENT=qwen`, `CLAUDE_PROJECT_DIR="$claude_fixture" QWEN_PROJECT_DIR="$qwen_fixture"` (РІЗНІ фікстури) → повертає `real "$qwen_fixture/docs/wiki"`.
- **D2 (правка наявного кейсу 18, ~`tests/hooks/run.sh:569-578`)** — асерт «CLAUDE_PROJECT_DIR wins over QWEN_PROJECT_DIR when both are set» **лишається** як регрес-гард default-гілки. Дві мінімальні правки, обидві **без послаблення**: (а) коментар «spec edge 11» → «v4.6.1 default-гілка: без транспортного сигналу порядок незмінний»; (б) додати `env -u WIKI_HOOK_CLIENT` у префікс виклику, щоб кейс став герметичним до змінної, успадкованої з середовища запуску сюїти. Текст `desc` можна доуточнити («…when WIKI_HOOK_CLIENT is not set»), але **не послаблювати**.
- **D3** для КОЖНОГО з шести значень `WIKI_HOOK_CLIENT` ∈ {`Qwen`, `QWEN`, `qwen ` (з хвостовим пробілом), `qwen2`, `` (порожнє), unset через `env -u WIKI_HOOK_CLIENT`}, обидві env на різні фікстури → у ВСІХ шести повертається **claude**-фікстура. Доказ точної рівності без «майже збігів».
- **D4** `WIKI_HOOK_CLIENT=qwen`, `env -u QWEN_PROJECT_DIR`, задано лише `CLAUDE_PROJECT_DIR` → claude-фікстура (жодна сходинка не зникла).
- **D5** `WIKI_HOOK_CLIENT=qwen`, `env -u CLAUDE_PROJECT_DIR -u QWEN_PROJECT_DIR`, виклик із `cd` у фікстуру → вікі фікстури через `pwd` (спільний хвіст незмінний).
- **D6** `WIKI_HOOK_CLIENT=qwen`, обидві env, виклик із **явним** `$1` на ТРЕТЮ фікстуру → вікі третьої фікстури (гілка живе виключно у fallback).
- **D7** наявні кейси 17, 19 і решта discover-блоку — зелені **без правок**.

### Verify

1. `cd "…root…" && bash -n hooks/lib/discover.sh` — синтаксис ок.
2. `cd "…root…" && bash -uc "source hooks/lib/discover.sh; discover_wiki >/dev/null; echo ok"` → `ok` (перевірка `set -u`-безпеки нової гілки).
3. Канонічна повна сюїта → зелена.
4. `grep -n 'WIKI_HOOK_CLIENT' hooks/lib/discover.sh` → рівно одне порівняння через `[ … = "qwen" ]`, жодного `case`/`[[ ]]`.

### Файли

- `hooks/lib/discover.sh:147-158` (коментар + fallback-блок `discover_wiki`)
- `tests/hooks/run.sh` (discover-секція, наявний кейс 18 ~`:569-578` + нові кейси поряд)

### Commit

`feat(v461-anchor-precedence): t3-discover-hook-client — WIKI_HOOK_CLIENT orders the discover_wiki fallback`

---

## Task 4 — `hooks/session-start-qwen.sh`: транспорт передає сигнал клієнта

**Канонічний id: `t4-qwen-transport-signal`** — стабільний ідентифікатор задачі у графі (knownDone, stop-loss-лічильники і done-піни деривуються з нього; НЕ перечеканювати).

**Хвиля 4.** Залежить від T3 (без гілки в `discover_wiki` сигнал ні на що не впливає). Диф ~5 рядків коду/коментарів + ~90 рядків тестів.

### Що зробити

1. Єдина правка коду — рядок виклику канонічного хука, `hooks/session-start-qwen.sh:42`:

   ```bash
   out="$(WIKI_HOOK_CLIENT=qwen "$HOOK_DIR/session-start.sh")"
   ```

   - **Command-prefix, а НЕ `export` окремим рядком.** Ефект для дитини той самий, але змінна не потрапляє в середовище самого wrapper-а й не тече в жодного іншого його нащадка (зокрема в `python3`-пакувальник нижче). Мінімальна поверхня — рівно один процес.
   - Значення **хардкоджене**: wrapper не пропускає й не поважає успадковане `WIKI_HOOK_CLIENT` — транспорт авторитетний щодо власної дитини.

2. Дописати 2-3 рядки коментаря над цим рядком: `WIKI_HOOK_CLIENT` — приватний сигнал транспорту канонічному хукові (не публічний контракт, не документується як налаштування), потрібен, бо в SessionStart немає `tool_name`; посилання на спеку.

**НЕ чіпати:** перевірку `command -v python3` (`:37`), контракт «порожній stdout → мовчання» (`:48`), envelope-пакування (`:50-63`), «stderr не тече в stdout», `exit 0` на кожному шляху, `HOOK_DIR`-резолвінг (`:31`).
**`hooks/session-start.sh` НЕ змінюється взагалі** (p3).

### Тести (секція `tests/hooks/run.sh`, анкери `echo "=== session-start.sh ===" >&2` і `echo "=== session-start-qwen.sh ===" >&2`)

Фікстури мають бути **розрізнюваними**: після `make_fixture` перезаписати `docs/wiki/index.md` унікальним маркером, напр. `printf '# Wiki Index\n\nMARKER_CLAUDE_FIXTURE\n' >"$claude_fixture/docs/wiki/index.md"` і `MARKER_QWEN_FIXTURE` — для другої.

- **S1** wrapper `$SESSION_START_QWEN_HOOK`, обидві env на різні фікстури, `env -u WIKI_HOOK_CLIENT` → `rc=0`; stdout парситься `json.load`; `continue == True`; `hookSpecificOutput.additionalContext` **містить** `MARKER_QWEN_FIXTURE` і **не містить** `MARKER_CLAUDE_FIXTURE` (`assert_contains` + `assert_not_contains`).
- **S1b** той самий виклик, але з `WIKI_HOOK_CLIENT=claude` у середовищі wrapper-а → результат ІДЕНТИЧНИЙ S1 (маркер qwen). Доказ спеки: значення хардкоджене, успадковане не поважається.
- **S2** канонічний `$SESSION_START_HOOK` **напряму**, обидві env, `env -u WIKI_HOOK_CLIENT` → інжектиться індекс **claude**-фікстури (`MARKER_CLAUDE_FIXTURE` присутній, `MARKER_QWEN_FIXTURE` відсутній). Регрес-гард default-гілки.
- **S3** канонічний `$SESSION_START_HOOK` напряму з `WIKI_HOOK_CLIENT=qwen`, обидві env → індекс **qwen**-фікстури. Доказ: гілка не залежить від того, хто саме викликав.
- **S4** наявні wrapper-кейси (порожній stdout без вікі, non-git, відсутній `python3`, форма envelope, «рівно один рядок», 24 KB cap, `assert_not_contains` на витік stderr) — зелені **без правок**.

### Verify

1. `cd "…root…" && bash -n hooks/session-start-qwen.sh` — синтаксис ок.
2. Канонічна повна сюїта → зелена.
3. `git -C "…root…" diff --stat hooks/session-start.sh` → **порожньо** (p3: канонічний хук недоторканий).
4. `grep -n 'WIKI_HOOK_CLIENT' hooks/session-start-qwen.sh` → рівно один command-prefix, жодного окремого `export`.

### Файли

- `hooks/session-start-qwen.sh:39-42` (коментар + рядок виклику)
- `tests/hooks/run.sh` (секції `session-start.sh` ~`:821`+ і `session-start-qwen.sh` ~`:974`+)

### Commit

`feat(v461-anchor-precedence): t4-qwen-transport-signal — qwen wrapper hands WIKI_HOOK_CLIENT to the canonical hook`

---

## Task 5 — бамп версії скіла 4.6.0 → 4.6.1

**Канонічний id: `t5-version-bump`** — стабільний ідентифікатор задачі у графі (knownDone, stop-loss-лічильники і done-піни деривуються з нього; НЕ перечеканювати).

**Хвиля 5.** Незалежна від коду; серіалізована для простоти. Диф ~4 рядки. **Обидві правки — ОБОВ'ЯЗКОВО в одному комміті**: це пін поточної версії, і без перенацілення сюїта червона одразу після бампу.

### Що зробити

1. `SKILL.md:3` — `version: "4.6.0"` → `version: "4.6.1"`.
2. `tests/skill-contracts.sh` — version-пін (анкер: `grep -q 'version: "4.6.0"' "$ROOT/SKILL.md"`, ~`:561-562`) → `'version: "4.6.1"'`, разом із текстом fail-повідомлення (`must be bumped to 4.6.0` → `4.6.1`).

**НЕ чіпати:**
- **історичний** Migration-Log-асерт `grep -q '### 4.6.0' "$ROOT/references/discovery-versioning.md"` (~`:601-602`) — це лог, а не пін;
- асерти `### 4.5.0` / `### 4.5.1`, Platform-таблицю (`| Qwen Code |`), `QWEN.md`-асерти, major-version-крос-чек `skill_version` vs `init_schema_major` (major лишається `4` — бамп patch його не зачіпає);
- `references/discovery-versioning.md` взагалі: запис `### 4.6.1` у Migration Log **НЕ додається** (лог документує дельти on-disk-схеми й agent-visible discovery-контракту; цей патч не змінює ні першого, ні другого);
- `SKILL.md` поза рядком версії; `wiki_version` = `"4.0"` у `references/operation-init.md`.

### Verify

1. `cd "…root…" && grep -n 'version: "4.6' SKILL.md` → рівно `4.6.1`.
2. `cd "…root…" && grep -c '### 4.6.0' references/discovery-versioning.md` → ≥1 (лог не зачеплено).
3. Канонічна повна сюїта → зелена.
4. `git -C "…root…" status --short` показує рівно `SKILL.md` і `tests/skill-contracts.sh`.

### Файли

- `SKILL.md:3`
- `tests/skill-contracts.sh` (version-пін ~`:561-562`)

### Commit

`feat(v461-anchor-precedence): t5-version-bump — skill 4.6.1 and version pin retarget`

---

## Task 6 — документація, що зараз стверджує протилежне

**Канонічний id: `t6-docs-anchor-precedence`** — стабільний ідентифікатор задачі у графі (knownDone, stop-loss-лічильники і done-піни деривуються з нього; НЕ перечеканювати).

**Хвиля 6.** Залежить від T1, T3, T4 (описує вже приземлену поведінку). Диф ~35 рядків тексту, **нуль коду**.

### Що зробити

**A. `tests/scenarios/cross-agent-discovery.md`, Scenario 3q3 (`:248-279`).**

- Заголовок сценарію (`:248` — `## Scenario 3q3: \`QWEN_PROJECT_DIR\` as a project-root anchor`) і Setup (`:250-261`, один env заданий) **лишаються без змін**: цей випадок поведінку не змінює, а заголовок може бути запіненим у `skill-contracts.sh`-стилі перевірок сценаріїв.
- Перші два буліти «Expected behavior» (`:265-271`) — про fallback при **unset** `CLAUDE_PROJECT_DIR` — лишаються вірними; хіба що уточнити, що ланцюг у default-гілці має саме такий порядок.
- **Буліт `:272-275` реверсується.** Прибрати «(unusual …)» і «`CLAUDE_PROJECT_DIR` wins — it is checked first in the chain **regardless of which agent is actually running**». Замість цього:
  - both-set — **штатний вкладений сценарій** (Qwen Code запущено зсередини сесії Claude Code), підтверджений емпіричним прогоном 2026-08-14 (Qwen Code 0.21.11);
  - поведінка **client-aware**: PostToolUse обирає порядок за `tool_name` (lowercase Qwen-імена → `QWEN_PROJECT_DIR` першим; CamelCase Claude-імена → `CLAUDE_PROJECT_DIR` першим); SessionStart — за фактом виклику через `hooks/session-start-qwen.sh`; канонічний SessionStart без транспортного сигналу → `CLAUDE_PROJECT_DIR` першим;
  - обидві env лишаються в ланцюгу як взаємний fallback — жодна сходинка не зникла.
- Останній буліт (`:276-279`, stdin `cwd` як нижчий fallback) лишається вірним і **не змінюється**.
- **Заборонено** описувати `WIKI_HOOK_CLIENT` як налаштування користувача. Якщо змінна згадується — тільки як приватний канал транспорт → канонічний хук (R3).

**B. `README.md` (мінімально).**

- `README.md:59-60` — «`QWEN_PROJECT_DIR` is also recognized as a project-root anchor, lowest-priority after `CLAUDE_PROJECT_DIR`» → одне речення про client-aware порядок: обидві змінні визнаються як project-root anchor, а порядок їх перевірки залежить від клієнта події; кожна лишається fallback-ом для іншої.
- Буліт про телеметрію (`README.md:39-45`): фраза «No `if … else` branching per client» була вірною для v4.6 (union імен) і **стає хибною для anchor-у**. Уточнити: union імен інструментів лишається union-ом; окремо від нього порядок двох env-anchor-ів залежить від клієнта — це єдина per-client гілка в хуках.
- Додати **один короткий буліт `v4.6.1`** під тим самим розділом «What's new in v4.6»: що було зламано (вкладена сесія — обидві env на різні проєкти → чужий індекс у SessionStart і мовчазна втрата телеметрії в PostToolUse), для кого (вкладені сесії Qwen усередині Claude і навпаки), і що на диску нічого не змінилось (`wiki_version` = `"4.0"`, нуль міграцій). **Без** опису `WIKI_HOOK_CLIENT` як налаштування.
- **НЕ перейменовувати** заголовок `## What's new in v4.6` — він запінений у `tests/skill-contracts.sh` (~`:711-712`). Так само не чіпати згадки `~/.qwen/skills` і `wiki-session-start.sh` (пін ~`:714-717`).

**Що НЕ чіпається взагалі:** `SKILL.md`, `references/*` (жоден не описує anchor-precedence — перевірено `grep -rn "PROJECT_DIR" SKILL.md references/` → нуль збігів), `tests/scenarios/hooks.md`.

### Verify

1. Канонічна повна сюїта → зелена (зокрема сценарій-піни й README-піни в `skill-contracts.sh`).
2. `cd "…root…" && grep -rn "PROJECT_DIR" README.md tests/scenarios/` — **жодного** твердження про безумовний пріоритет `CLAUDE_PROJECT_DIR` (Done-when 4); зокрема немає рядка «regardless of which agent is actually running».
3. `cd "…root…" && grep -rn "WIKI_HOOK_CLIENT" README.md SKILL.md references/` → **порожньо** або лише як явно позначений приватний канал (R3).
4. `git -C "…root…" status --short` показує рівно `README.md` і `tests/scenarios/cross-agent-discovery.md`.

### Файли

- `tests/scenarios/cross-agent-discovery.md:248-279` (Scenario 3q3, Expected behavior)
- `README.md:39-45`, `:59-60`, + новий буліт під `## What's new in v4.6` (`:34`)

### Commit

`feat(v461-anchor-precedence): t6-docs-anchor-precedence — scenario 3q3 and README state the client-aware order`

---

## Task 7 — фінальна наскрізна верифікація

**Канонічний id: `t7-final-verify`** — стабільний ідентифікатор задачі у графі (knownDone, stop-loss-лічильники і done-піни деривуються з нього; НЕ перечеканювати).

**Хвиля 7.** Залежить від усіх. Продакшн-код **не змінюється**; допускається лише виправлення дефекту, знайденого на цьому кроці (тоді — з тестом, у тому ж комміті, форма (а)).

### Що зробити

Пройти Done-when спеки по пунктах і зафіксувати докази.

1. **Сюїта.** Канонічна повна команда → зелена. Записати підсумкові PASS/FAIL з `tests/hooks/run.sh`.
2. **Вкладений сценарій (Done-when 2)** — ручний прогін на двох tmp-фікстурах із РІЗНИМИ маркерами (обидві git-репо з `docs/wiki/`), обидві env задані одночасно:
   - `read_file` + абсолютний шлях у qwen-фікстурі → бампнулась **qwen**-вікі; `.usage.json` claude-фікстури байт-у-байт незмінний (`shasum -a 256` до/після);
   - `Read` + абсолютний шлях у claude-фікстурі → дзеркально;
   - `bash hooks/session-start-qwen.sh` → `additionalContext` містить маркер **qwen**-фікстури і не містить claude-маркера;
   - `bash hooks/session-start.sh` без `WIKI_HOOK_CLIENT` → маркер **claude**-фікстури.
3. **Одна env (Done-when 3)** — по одному прогону з `env -u QWEN_PROJECT_DIR` і з `env -u CLAUDE_PROJECT_DIR` для обох клієнтів: поведінка тотожна до-зміннєвій.
4. **Done-when 4** — `cd "…root…" && grep -rn "PROJECT_DIR" README.md tests/scenarios/` не містить тверджень про безумовний пріоритет `CLAUDE_PROJECT_DIR`.
5. **Замкнутість скоупу (p2/R6)** — `git -C "…root…" diff --stat 3b1ce77..HEAD` МАЄ показувати РІВНО: `hooks/post-tool-use.sh`, `hooks/lib/discover.sh`, `hooks/session-start-qwen.sh`, `SKILL.md`, `README.md`, `tests/scenarios/cross-agent-discovery.md`, `tests/hooks/run.sh`, `tests/skill-contracts.sh`, `docs/superpowers/…` (спека/дизайн/план/леджер). **Будь-який інший файл — регрес скоупу**, зокрема `hooks/session-start.sh` (p3), `hooks/install-hooks.sh`, `hooks/uninstall-hooks.sh`, `hooks/lib/settings-lock.sh`, `install.sh`, `uninstall.sh`, `references/*`.
6. **Інваріанти на місці** — `grep`-перевірки: `WIKI_HOOK_CLIENT` відсутній у `hooks/post-tool-use.sh`; у `hooks/lib/discover.sh` порівняння лише через `[ … = "qwen" ]`; `BATCH_TOOLS = {"MultiEdit"}` у `hooks/post-tool-use.sh` не змінився; `wiki_version: "4.0"` у `references/operation-init.md` не змінився; `### 4.6.1` у `references/discovery-versioning.md` **відсутній**.
7. **Леджер на місці** — `docs/superpowers/plans/2026-08-14-v461-anchor-precedence-settled.md` існує й не змінений (p4).

### Verify

Канонічна повна сюїта → зелена + усі сім пунктів вище зафіксовані у звіті задачі.

### Файли

- Немає (верифікаційна задача). За потреби — точковий фікс із тестом у тому ж комміті.

### Commit

`feat(v461-anchor-precedence): t7-final-verify — final verification pass`
