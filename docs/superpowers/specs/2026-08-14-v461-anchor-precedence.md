# Spec — Wiki Skill v4.6.1: client-aware project anchor

**Дата:** 2026-08-14
**Версія скіла:** 4.6.0 → 4.6.1 (behavior patch; `wiki_version` лишається `"4.0"` — нуль міграцій)
**Джерело:** брейншторм `docs/superpowers/specs/2026-08-14-v461-anchor-precedence-design.md` (затверджено)
**Леджер вердиктів:** `docs/superpowers/plans/2026-08-14-v461-anchor-precedence-settled.md` (окремий файл, НЕ дублюється тут — p4)
**Slug циклу:** `v461-anchor-precedence`. База: гілка `master` воркtree `v46-qwen` (`3b1ce77`).

**Дельта проти дизайн-документа (свідома, обґрунтована нижче):** дизайн у розділі
«Зміни» не згадав два вже наявні артефакти, які **стверджують протилежне** до
нової поведінки — `tests/scenarios/cross-agent-discovery.md` (Scenario 3q3) і
`README.md`. Це не розширення скоупу коду (p2 не порушено): жодного нового
механізму, лише приведення тверджень у відповідність із кодом у тому ж комміті.
Залишити їх як є означало б лишити в репо **тестовий сценарій із хибним
очікуванням** — тобто зелений хибний тест.

**Про P1 у «Відкладеному рев'ю» дизайну** («diff only adds design doc, no
implementation») — це артефакт життєвого циклу: рев'ю дивилося на коміт із самим
дизайном. Імплементація приходить планом і тасками з цієї спеки; додаткової дії
специфікація не потребує.

## Проблема

Обидва anchor-ланцюги скіла безумовно ставлять `CLAUDE_PROJECT_DIR` перед
`QWEN_PROJECT_DIR`:

- `hooks/post-tool-use.sh` (anchor-блок після action-gate) —
  `CLAUDE_PROJECT_DIR` → `QWEN_PROJECT_DIR` → stdin `cwd` → `pwd`;
- `hooks/lib/discover.sh`, `discover_wiki()` — fallback стартової точки, коли
  `$1` порожній: `CLAUDE_PROJECT_DIR` → `QWEN_PROJECT_DIR` → `pwd`. Саме цим
  шляхом іде `hooks/session-start.sh` (`main()` викликає `discover_wiki` **без
  аргументу**).

Це коректно рівно доти, доки в середовищі задано щонайбільше одну з двох змінних
— припущення, зафіксоване в v4.6 як edge 11 («стала `CLAUDE_PROJECT_DIR`
всередині Qwen-сесії… теоретично інший anchor»). Емпіричний прогін 2026-08-14
(Qwen Code 0.21.11, ізольований `HOME`, хук-дампер) показав, що припущення хибне
для **штатного** оркестраційного випадку: коли Qwen Code запущено зсередини
сесії Claude Code, у середовищі хука присутні **обидві** змінні й вони вказують
на **різні** проєкти. Той самий прогін підтвердив решту контрактів, на які
спирається рішення: `tool_name` у Qwen приходить lowercase (`read_file`, `edit`,
`write_file`), шлях завжди в `tool_input.file_path` і завжди абсолютний,
SessionStart має `source: "startup"`.

Наслідки різні за тяжкістю:

1. **SessionStart (Qwen) — тиха дезінформація, гірший випадок.**
   `session-start-qwen.sh` → `session-start.sh` → `discover_wiki` без аргументу →
   fallback бере `CLAUDE_PROJECT_DIR` → у Qwen-сесію інжектується індекс **чужої**
   вікі. Агент отримує знання іншого проєкту як довідку про поточний, і сигналу
   про підміну немає ніде: envelope валідний, хук вийшов `exit 0`.
2. **PostToolUse (Qwen) — мовчазна втрата телеметрії.** Anchor вказує на чужий
   проєкт → `discover_wiki` знаходить чужу вікі → boundary-guard відкидає
   абсолютний шлях Qwen-файлу як «поза межами `{wiki}/`» → `.usage.json` не
   оновлюється. Чужа вікі при цьому **не** забруднюється (guard тримає), але
   подія зникає без сліду — пріоритизація lint у вкладених сесіях знову працює
   наосліп, як до v4.5.

Зворотний випадок (Claude Code зсередини Qwen-сесії) симетричний: у Claude-хука
опиниться `QWEN_PROJECT_DIR`, і сама його наявність не повинна впливати на вибір.

## Підхід

**Клієнт визначається за фактом виклику, а не за наявністю env.** Обидві змінні
лишаються в ланцюгу; змінюється рівно те, ЯКА з двох перевіряється першою, і
рішення приймається з сигналу, що доведено належить події, яка щойно сталася.
Жодна сходинка не зникає, жоден новий механізм не з'являється.

### PostToolUse — сигнал уже в руках

`tool_name` зі stdin уже розібраний для action-gate, і множини імен не
перетинаються (Qwen — lowercase, Claude — CamelCase). Anchor-ланцюг стає
client-aware:

| подія | порядок |
|---|---|
| Qwen-ім'я (`read_file`, `write_file`, `edit`, `replace`, `notebook_edit`) | `QWEN_PROJECT_DIR` → `CLAUDE_PROJECT_DIR` → stdin `cwd` → `pwd` |
| Claude-ім'я (`Read`, `Edit`, `Write`, `MultiEdit`) | `CLAUDE_PROJECT_DIR` → `QWEN_PROJECT_DIR` → stdin `cwd` → `pwd` |

Другий рядок — байт-у-байт поточна поведінка. Хвіст ланцюга (stdin `cwd` → `pwd`)
спільний і не змінюється; впорядковуються рівно дві env-сходинки.

### SessionStart — сигнал дає транспорт

У SessionStart немає `tool_name`, але є інший доведений сигнал: сам факт, що
виклик прийшов через Qwen-транспорт. `hooks/session-start-qwen.sh` передає
канонічному хукові `WIKI_HOOK_CLIENT=qwen`, і fallback `discover_wiki` це
враховує:

| середовище | порядок |
|---|---|
| `WIKI_HOOK_CLIENT` дорівнює **рівно** `qwen` | `QWEN_PROJECT_DIR` → `CLAUDE_PROJECT_DIR` → `pwd` |
| будь-що інше (порожнє, unset, `Qwen`, `QWEN`, `qwen `, `qwen2`) | `CLAUDE_PROJECT_DIR` → `QWEN_PROJECT_DIR` → `pwd` |

`WIKI_HOOK_CLIENT` — **приватний канал** між wrapper-ом і канонічним хуком: не
публічний контракт, не документується як налаштування користувача, приймається
лише за точної рівності (жодних case-insensitive порівнянь, префіксів, glob-ів).
Він впливає рівно на порядок двох env-сходинок, обидві з яких і так походять із
того самого середовища, тож підміна значення нічого не відкриває — вона лише
обирає між двома вже наявними кандидатами.

### Два механізми не перетинаються — і це властивість коду, не дисципліни

`hooks/post-tool-use.sh` завжди викликає `discover_wiki "$anchor"` з
**непорожнім** аргументом (хвіст ланцюга гарантує щонайменше `pwd`), тож гілка
`WIKI_HOOK_CLIENT` у `discover_wiki` для PostToolUse **структурно недосяжна**.
І навпаки: `session-start.sh` не читає `tool_name` (його там немає). Отже:

- PostToolUse вирішує **лише** за `tool_name`;
- SessionStart вирішує **лише** за `WIKI_HOOK_CLIENT`;
- `WIKI_HOOK_CLIENT` у середовищі не може перебити `tool_name` (окремий тест).

## Зміни

Проєкція, як у попередніх спеках циклу: **дані = схема вікі на диску +
`.usage.json`**, **API = hook-скрипти + контрактні файли скіла**, **UI = діалоги
агента та README/сценарії**.

### Дані

**Без змін.** `wiki_version` = `"4.0"`. `.usage.json` — та сама схема, ті самі
поля запису, той самий `_hooks` мета-ключ (`hook_version` лишається `"1"`).
Нуль міграцій, нуль backfill, нуль нових полів.

### API — `hooks/post-tool-use.sh` (client-aware anchor)

**1. Action-gate додатково класифікує клієнта — в тому самому `case`, не в
другому.** Наявний `case "$tool_name"` (той, що вже стоїть ПЕРЕД перевіркою
`[ "${#file_paths[@]}" -gt 0 ]` — порядок із v4.6 не змінюється) розщеплює свої
дві гілки на чотири, кожна з яких присвоює **і** `action`, **і** `client`:

```
case "$tool_name" in
  Read)                          action="view";  client="claude" ;;
  read_file)                     action="view";  client="qwen"  ;;
  Edit|Write|MultiEdit)          action="patch"; client="claude" ;;
  write_file|edit|replace|notebook_edit)
                                 action="patch"; client="qwen"  ;;
  *) exit 0 ;;
esac
```

- Відображення «ім'я → `action`» і гілка `*) exit 0` — **байт-у-байт ті самі**
  за результатом для кожного з дев'яти дозволених імен; змінюється лише
  групування гілок.
- **Чому не окремий `case` після action-gate.** Другий перелік імен створив би
  **третій** список назв інструментів у файлі (поряд з action-gate і
  `BATCH_TOOLS`) і разом з ним — тихий режим відмови: майбутнє Qwen-ім'я,
  додане до action-gate, але забуте в client-gate, мовчки отримало б
  Claude-first порядок, тобто рівно той баг, який цей цикл закриває. У
  злитому вигляді класифікація **тотальна за конструкцією**: додати дозволене
  ім'я, не вирішивши його клієнта, синтаксично неможливо.
- Інваріант `BATCH_TOOLS ⊂ action-gate` не змінюється; `BATCH_TOOLS` лишається
  `{"MultiEdit"}` у python-екстракторі й не зачіпається.

**2. Anchor-ланцюг стає впорядкованим за `client`:**

```
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

- Гілка `else` (Claude/усе інше) — поточний код без змін.
- Хвіст (`stdin_cwd` → `pwd`) — спільний, поза `if`, не дублюється.
- `${VAR:-}` скрізь: безпечно під `set -u`; жодна підстановка команди не
  живить присвоєння напряму (лишається safe під `set -e`).
- Коментар над блоком пояснює **причину** (вкладена Qwen-сесія всередині
  Claude-сесії: обидві env присутні й вказують на різні проєкти) з посиланням
  на цю спеку; стара примітка «QWEN_PROJECT_DIR applies only when
  CLAUDE_PROJECT_DIR is unset» переписується — вона більше не вірна.

Решта хука (`discover_wiki "$anchor"`, `realpath`, version-gate, boundary-guard
`{wiki}/`, фільтри `*.md` / не-`index|schema|log`, r-m-w `.usage.json`, `exit 0`
на всіх шляхах) — **без дотику**.

### API — `hooks/lib/discover.sh` (`WIKI_HOOK_CLIENT` у fallback)

Правиться **лише** блок `if [ -z "$start" ]` усередині `discover_wiki`:

```
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

- Порівняння — `[ "$x" = "qwen" ]` (точна рівність, не `case`-патерн, не
  `[[ == ]]` з glob-семантикою, не нормалізація регістру).
- Явний `$1` як і раніше **виграє над усім**: блок виконується тільки при
  порожньому `start`.
- Хвіст `pwd`, git-boundary fail-closed, `_wiki_disc_dir_pointers` (перелік
  `CLAUDE.md AGENTS.md GEMINI.md QWEN.md`), pointer-валідація, Phase-2 fallback
  — **без змін**.
- Коментар над блоком фіксує: `WIKI_HOOK_CLIENT` — приватний канал транспорту,
  не користувацьке налаштування; діє лише на порядок двох env-сходинок.

### API — `hooks/session-start-qwen.sh` (сигнал клієнта)

Єдина правка — рядок виклику канонічного хука:

```
out="$(WIKI_HOOK_CLIENT=qwen "$HOOK_DIR/session-start.sh")"
```

- **Command-prefix, а не `export` окремим рядком.** Ефект для дитини той самий
  (це і є «експорт у середовище дочірнього процесу» з дизайну), але змінна не
  потрапляє в середовище самого wrapper-а й, отже, не тече в жодного іншого
  його нащадка (зокрема в `python3`-пакувальник). Мінімальна поверхня —
  рівно один процес, який має право на цей сигнал.
- Значення хардкоджене: wrapper **не** пропускає й не поважає успадковане
  `WIKI_HOOK_CLIENT` — транспорт авторитетний щодо власної дитини.
- Усе решта wrapper-а (перевірка `python3`, порожній stdout → мовчання,
  envelope, stderr не тече в stdout, `exit 0` на кожному шляху) — без змін.
- `hooks/session-start.sh` **не змінюється взагалі** (p3: stdin `cwd` у
  канонічному SessionStart — окремий follow-up).

### API — версія скіла

- `SKILL.md:3` — `version: "4.6.0"` → `version: "4.6.1"`.
- `tests/skill-contracts.sh:561-562` — version-пін `grep -q 'version: "4.6.0"'`
  → `"4.6.1"` разом із текстом fail-повідомлення, **у тому ж комміті** (це пін
  поточної версії; без перенацілення сюїта червона одразу після бампу).
- **Історичні** асерти Migration Log (`### 4.6.0` у
  `references/discovery-versioning.md`, `tests/skill-contracts.sh:603-604`) —
  **не чіпати**: це лог, а не пін.

### UI — документація, що зараз стверджує протилежне

Обидва артефакти правляться **в тому ж комміті**, що й відповідний код.

**`tests/scenarios/cross-agent-discovery.md`, Scenario 3q3 (обов'язково).**
Секція «Expected behavior» містить твердження, яке ця зміна прямо реверсує:
«If BOTH `CLAUDE_PROJECT_DIR` and `QWEN_PROJECT_DIR` happen to be set …
`CLAUDE_PROJECT_DIR` wins — it is checked first in the chain **regardless of
which agent is actually running**». Правки:

- «unusual» → штатний вкладений сценарій (Qwen усередині Claude-сесії),
  з посиланням на емпіричний прогін;
- both-set поведінка розписується як client-aware: PostToolUse — за
  `tool_name`; SessionStart — за фактом виклику через `session-start-qwen.sh`;
  канонічний SessionStart без транспортного сигналу — `CLAUDE_PROJECT_DIR`;
- рядок про stdin `cwd` як нижчий fallback лишається вірним і не змінюється;
- заголовок сценарію й Setup (один env заданий) лишаються — цей випадок
  поведінку не змінює.

**`README.md` (обов'язково, мінімально).**

- `README.md:59-60` — «`QWEN_PROJECT_DIR` is also recognized as a project-root
  anchor, lowest-priority after `CLAUDE_PROJECT_DIR`» → формулювання
  client-aware порядку в одному реченні.
- Розділ «What's new in v4.6», буліт про телеметрію: фраза «No `if … else`
  branching per client» була вірною для v4.6 (union імен) і стає хибною для
  anchor-у. Уточнюється до «union імен інструментів лишається union-ом; окремо
  від нього порядок двох env-anchor-ів залежить від клієнта — це єдина
  per-client гілка в хуках».
- Один короткий буліт `v4.6.1` під тим самим розділом: що саме зламано, для
  кого (вкладені сесії) і що на диску нічого не змінилось. Без опису
  `WIKI_HOOK_CLIENT` як налаштування — це приватний канал.

**Що НЕ чіпається:** `SKILL.md` поза рядком версії, `references/*` (жоден із них
не описує anchor-precedence — перевірено `grep -rn "PROJECT_DIR" SKILL.md
references/`), `tests/scenarios/hooks.md`.

## Тести

Усі нові кейси — у `tests/hooks/run.sh`, наявними хелперами (`make_fixture`,
`real`, `assert_eq`, `assert_file_unchanged`, `_sha`, `_ptu_stdin`, `_ptu_field`,
`_ptu_keys`). Нових залежностей немає.

### `discover_wiki` (fallback стартової точки)

| # | Умови | Очікування |
|---|---|---|
| D1 | `WIKI_HOOK_CLIENT=qwen`, обидві env на РІЗНІ фікстури | повертає вікі **qwen**-фікстури |
| D2 | `WIKI_HOOK_CLIENT` не заданий, обидві env | вікі **claude**-фікстури — це наявний кейс 18 (`tests/hooks/run.sh:569-578`), лишається як регрес-гард default-гілки; правиться лише його коментар («spec edge 11» → v4.6.1 default-branch) |
| D3 | `WIKI_HOOK_CLIENT` ∈ {`Qwen`, `QWEN`, `qwen ` (з пробілом), `qwen2`, `` (порожнє), unset через `env -u`}, обидві env | у ВСІХ шести — вікі **claude**-фікстури (точна рівність, без «майже збігів») |
| D4 | `WIKI_HOOK_CLIENT=qwen`, задано лише `CLAUDE_PROJECT_DIR` | вікі claude-фікстури (жодна сходинка не зникла) |
| D5 | `WIKI_HOOK_CLIENT=qwen`, жодної env, `cd` у фікстуру | вікі фікстури через `pwd` (хвіст незмінний) |
| D6 | `WIKI_HOOK_CLIENT=qwen`, обидві env, виклик з **явним** `$1` на третю фікстуру | вікі третьої фікстури (гілка живе лише у fallback) |
| D7 | наявні кейси 17, 19 і решта discover-блоку | зелені без правок |

### `post-tool-use.sh`

Спільна форма: дві фікстури (`claude_fixture`, `qwen_fixture`), у кожній —
`docs/wiki/foo.md`; `_sha` обох `.usage.json` знімається до виклику; після
виклику один бампається, другий перевіряється `assert_file_unchanged`.

| # | Умови | Очікування |
|---|---|---|
| P1 | `read_file`, обидві env | `view_count`=1 у **qwen**-вікі; claude-`.usage.json` байт-у-байт незмінний |
| P2 | `Read`, обидві env | `view_count`=1 у **claude**-вікі; qwen-`.usage.json` незмінний |
| P3 | кожне з `write_file`, `edit`, `replace`, `notebook_edit`, обидві env | `patch_count`=1 у **qwen**-вікі; claude незмінний |
| P4 | кожне з `Edit`, `Write`, `MultiEdit`, обидві env | `patch_count`=1 у **claude**-вікі; qwen незмінний |
| P5 | `read_file`, задано лише `CLAUDE_PROJECT_DIR` | бампається claude-вікі (fallback-сходинка ціла) |
| P6 | `Read`, задано лише `QWEN_PROJECT_DIR` | бампається qwen-вікі (дзеркально) |
| P7 | `read_file`, жодної env, stdin `cwd` = фікстура, відносний `file_path` | бампається вікі фікстури (хвіст ланцюга незмінний; форма stdin — як у наявному кейсі `tests/hooks/run.sh:1487`) |
| P8 | `Read`, обидві env, **у середовищі `WIKI_HOOK_CLIENT=qwen`** | бампається **claude**-вікі: PostToolUse не читає `WIKI_HOOK_CLIENT`, env не може перебити `tool_name` |
| P9 | `run_shell_command` і `Grep` з валідним шляхом у вікі, обидві env | обидва `.usage.json` незмінні, stdout порожній, `exit 0` (action-gate не розширився) |
| P10 | наявні Claude- і Qwen-кейси PostToolUse, зокрема гарди first-match-wins, `edits[]`-batch-only і не-matched імен | зелені без правок |

### `session-start-qwen.sh` / `session-start.sh`

Індекси фікстур роблять розрізнюваними (унікальний маркер у кожному
`docs/wiki/index.md`).

| # | Умови | Очікування |
|---|---|---|
| S1 | wrapper, обидві env на різні фікстури | stdout парситься `json.load`; `continue == true`; `hookSpecificOutput.additionalContext` містить маркер **qwen**-фікстури і **не** містить маркер claude-фікстури |
| S2 | канонічний `session-start.sh` напряму, обидві env, `WIKI_HOOK_CLIENT` не заданий | інжектиться індекс **claude**-фікстури (регрес default-гілки) |
| S3 | канонічний `session-start.sh` напряму з `WIKI_HOOK_CLIENT=qwen`, обидві env | індекс **qwen**-фікстури (гілка не залежить від того, хто саме викликав) |
| S4 | наявні wrapper-кейси (порожній stdout без вікі, відсутній `python3`, форма envelope, 24 KB cap) | зелені без правок |

### Контрактні сюїти

- `tests/skill-contracts.sh` — після перенацілення піна зелений; асерт
  Platform-таблиці (5 колонок) і Migration-Log-асерт `### 4.6.0` не чіпаються.
- `tests/install-cross-agent-links.sh`, `tests/uninstall.sh` — не зачіпаються
  зміною (інсталери й локи поза скоупом), мають лишитись зеленими як є.

Канонічна повна команда без змін:
`bash tests/hooks/run.sh && bash tests/skill-contracts.sh && bash tests/install-cross-agent-links.sh && bash tests/uninstall.sh`.

## Edge-cases

1. **Обидві env, вкладена Qwen-сесія** (головний сценарій) → PostToolUse анкориться
   на `QWEN_PROJECT_DIR` за lowercase-іменем; SessionStart — за транспортом.
   Телеметрія пишеться у власну вікі, індекс інжектиться власний.
2. **Обидві env, вкладена Claude-сесія всередині Qwen** → CamelCase-ім'я й
   відсутній `WIKI_HOOK_CLIENT` дають `CLAUDE_PROJECT_DIR`. Наявність
   `QWEN_PROJECT_DIR` у середовищі ні на що не впливає.
3. **`WIKI_HOOK_CLIENT=qwen`, але `QWEN_PROJECT_DIR` не заданий** (Qwen не
   експортував змінну) → падаємо на `CLAUDE_PROJECT_DIR`, тобто **сьогоднішня**
   поведінка з усіма її наслідками. Це свідомий residual: без стартового
   сигналу з payload (p3 — поза скоупом) кращого сигналу немає. Шкоду й далі
   обмежують fail-closed-без-git, boundary-guard і version-gate.
4. **`WIKI_HOOK_CLIENT` заданий користувачем у профілі оболонки** → впливає лише
   на канонічний SessionStart і лише на порядок двох сходинок, обидві з того
   самого середовища. За заданої тільки `CLAUDE_PROJECT_DIR` поведінка
   тотожна поточній. Публічним контрактом змінна не стає.
5. **Майже-збіги значення** (`Qwen`, `QWEN`, `qwen `, `qwen2`, порожнє) →
   default-порядок. Точна рівність, покрита тестом D3.
6. **`WIKI_HOOK_CLIENT` у середовищі PostToolUse** → ігнорується повністю:
   хук завжди передає явний anchor у `discover_wiki`, гілка недосяжна (P8).
7. **Qwen-wrapper зареєстровано в `~/.claude/settings.json`** (помилка
   конфігурації) → `WIKI_HOOK_CLIENT=qwen` + порожній `QWEN_PROJECT_DIR` →
   `CLAUDE_PROJECT_DIR`. Безпечна деградація, не крах.
8. **Жодної env** (Codex, Gemini, ручний запуск хука) → обидві гілки сходяться
   на тому самому хвості: stdin `cwd` → `pwd` для PostToolUse, `pwd` для
   `discover_wiki`. Регрес-нуль для Codex/Gemini — за конструкцією, а не за
   тестом.
9. **Нове Qwen-ім'я інструмента в майбутньому** (не в action-gate) → `*) exit 0`
   до будь-якої anchor-резолюції; anchor-порядок узагалі не досягається.
10. **Qwen пише файл через `run_shell_command`** → PostToolUse із файловим
    matcher-ом не спрацьовує; той самий відомий розрив, що й із Claude `Bash`
    (поза скоупом, як у v4.6).
11. **Anchor указує на не-git дерево** (будь-яка з двох env) → fail-closed
    `discover_wiki` повертає порожньо, хук `exit 0` без запису. Порядок сходинок
    цього не послаблює.
12. **Обидві env на один і той самий проєкт** (звичайна не-вкладена Qwen-сесія)
    → порядок нерелевантний, результат ідентичний до і після зміни.
13. **`realpath`/symlink-різниця між значеннями env** → нормалізація й
    boundary-guard відпрацьовують як зараз; anchor-вибір їх не оминає.

## Ризики

| # | Ризик | Мітигація |
|---|---|---|
| R1 | **Третій перелік імен інструментів** (client-gate окремо від action-gate) розійшовся б з ним при додаванні наступного Qwen-імені — і тихо повернув би саме цей баг | Клієнт присвоюється в тих самих гілках, що й `action`: класифікація тотальна за конструкцією, забути ім'я синтаксично неможливо. Інваріант `BATCH_TOOLS ⊂ action-gate` не зачіпається |
| R2 | **Регрес Claude/Codex/Gemini** через правку спільного anchor-коду | Default-гілка обох ланцюгів текстово тотожна поточній; хвіст спільний і не дублюється; кейси D2/D4/P2/P4/P5/S2 фіксують її; наявні сюїти лишаються без правок |
| R3 | `WIKI_HOOK_CLIENT` починає жити як публічний перемикач (документація, підказки, чужий код) | Не документується як налаштування ні в `SKILL.md`, ні в README; коментар у коді називає його приватним каналом транспорту; впливає лише на порядок двох уже наявних кандидатів — підміна нічого не відкриває |
| R4 | **Стала документація** — Scenario 3q3 і README стверджують безумовний пріоритет `CLAUDE_PROJECT_DIR`; після зміни це хибний «зелений» сценарій | Обидва артефакти правляться в тому ж комміті, що й код; це явна частина скоупу цієї спеки, а не follow-up |
| R5 | **Residual для Qwen без `QWEN_PROJECT_DIR`** (edge 3) читається як «фікс не працює» | Задокументовано як відомий залишок з причиною (p3); закривається лише stdin-`cwd`-ом у канонічному SessionStart — окремий follow-up |
| R6 | Розростання патча в новий механізм (спіраль рев'ю попереднього циклу) | p1/p2: три правки коду + версія + два doc-артефакти; жодних sha/dev-ino-звірок, fd-утримань, фонових процесів, нових env понад `WIKI_HOOK_CLIENT`. Будь-яка пропозиція «закрити ще одне вікно» тут — сигнал тієї ж спіралі й відхиляється |
| R7 | `set -u`/`set -e` у викликачів `discover.sh` спіткнеться на новій гілці | Скрізь `${VAR:-}`; порівняння через `[ = ]`; жодна підстановка команди не живить присвоєння напряму — той самий патерн, що вже стоїть у цьому блоці |

## Поза скоупом

- **`hooks/session-start.sh` не вчиться читати stdin `cwd`** (p3) — дотичний
  недолік того ж класу, окремий follow-up.
- Будь-яка зміна пріоритетів чи поведінки для Codex/Gemini.
- Нові env-перемикачі понад `WIKI_HOOK_CLIENT`; читання `WIKI_HOOK_CLIENT` у
  PostToolUse.
- Інсталери, `hooks/lib/settings-lock.sh`, orphan-guard `uninstall.sh`,
  експорти скіла, транспортний конверт Qwen — жодного дотику.
- Discovery-boundary, boundary-guard `{wiki}/`, version-gate, 24 KB cap,
  фільтри сторінок, контракт `exit 0` — не послаблюються й не переписуються.
- Запис `### 4.6.1` у Migration Log `references/discovery-versioning.md` **не
  додається**: лог документує дельти on-disk-схеми й agent-visible
  discovery-контракту, а цей патч не змінює ні першого, ні другого
  (`WIKI_HOOK_CLIENT` — приватний канал між двома хуками). Асерт
  `### 4.6.0` — історичний, лишається зеленим.
- Телеметрія для файлів, записаних через shell; зміни on-disk схеми,
  `wiki_version`, міграції.

## Done-when

1. `bash tests/hooks/run.sh && bash tests/skill-contracts.sh && bash tests/install-cross-agent-links.sh && bash tests/uninstall.sh` — зелено.
2. Вкладений сценарій (обидві env на різні git-проєкти) дає **правильну** вікі
   для обох клієнтів і в SessionStart, і в PostToolUse; вікі другого проєкту
   байт-у-байт недоторкана.
3. Середовище з однією env (кожен із двох випадків) поводиться як до зміни.
4. `grep -rn "PROJECT_DIR" README.md tests/scenarios/` не містить тверджень про
   безумовний пріоритет `CLAUDE_PROJECT_DIR`.

## Інваріанти (НЕ ослаблювати)

- **Регрес-нуль для Claude/Codex/Gemini:** default-гілка обох ланцюгів тотожна
  поточній; жодна сходинка не зникає — «чужий» env лишається fallback-ом.
- Один tool call однофайлового інструмента → рівно один бамп у `.usage.json`
  (`BATCH_TOOLS ⊂ action-gate` без змін).
- Кожен шлях кожного хука завершується `exit 0` і ніколи не блокує інструмент
  чи старт сесії.
- Fail-closed-без-git, boundary-guard `{wiki}/`, version-gate, 24 KB cap — без
  послаблень.
- On-disk схема незмінна: `wiki_version` = `"4.0"`, `_hooks.hook_version` = `"1"`.
- `WIKI_HOOK_CLIENT` приймається лише за точної рівності `qwen` і лишається
  приватним каналом транспорт → канонічний хук.
