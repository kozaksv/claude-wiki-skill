# Wiki Skill v4.5 — Hook-Backed Contract (дизайн)

**Дата:** 2026-07-08
**Статус:** затверджено користувачем (brainstorm 2026-07-08)
**Базова версія скіла:** 4.4.0 → **4.5.0**
**Схема вікі:** `wiki_version` лишається `"4.0"` (on-disk схема вікі не змінюється)

## Контекст і проблема

Найслабше місце скіла — головні правила тримаються на слухняності моделі, а не на
механіці. Changelog v4.2.21 фіксує: агенти «відповідали з пам'яті і пропускали
читання вікі, м'які формулювання дозволяли раціоналізувати». Телеметрія майже
порожня (максимум ~10 переглядів на сторінку), бо агенти читають сторінки
звичайним `Read` повз query-операцію — пріоритизація lint фактично сліпа.

Текст цю війну не виграє — харнес виграє. Рішення: перевести Session-Start
Contract і телеметрію з текстової дисципліни в хуки Claude Code.

## Мета

1. **SessionStart-хук**: автоматично інжектити `{wiki}/index.md` у контекст на
   старті сесії. «Прочитай index першим» перестає бути правилом, яке можна
   забути — він уже прочитаний.
2. **PostToolUse-хук**: авто-інкремент телеметрії `.usage.json` на читання
   (`view`) та редагування (`patch`) wiki-сторінок — незалежно від того, чи
   згадав агент про скіл.
3. **`wiki doctor`**: одна операція наскрізної діагностики (пойнтери, версія,
   `.usage.json`, симлінк-експорти, стан хуків, git-стан).
4. **Щотижневий lint**: реалізується як нагадування в SessionStart-інжекті
   (перша сесія тижня пропонує `wiki lint швидко`), НЕ як безлюдний cron.
5. **Нуль per-project розкатки**: установка глобальна, discovery сам знаходить
   вікі кожного проєкту. Існуючі проєкти отримують все після одного оновлення
   скіла на машині.

## Не-мета

- Жодних змін on-disk схеми вікі (`wiki_version` = `"4.0"`; major bump не потрібен).
- Жодних headless-запусків lint (lint має DECIDE-гілки — рішення лишаються за людиною).
- Жодних hook-записів у файлах проєктів (`.claude/settings.json` проєкту не чіпаємо):
  проєктні репо лишаються чистими від Claude-специфіки.
- Хуки для Codex/Gemini не будуються: ці агенти лишаються на чинному текстовому
  контракті (він же — fallback для Claude, якщо хуки зламані/не встановлені).
- Автоматизація `bump_use` (нові `[[wikilink]]`) — механічно не детектиться,
  лишається ручною для всіх агентів.

## Затверджені рішення (brainstorm)

| Розвилка | Рішення |
|---|---|
| Топологія хуків | **Глобально, раз на машину**: один запис у `~/.claude/settings.json`, скрипти в репо скіла, self-discovery вікі в кожному проєкті |
| Скоуп | **Весь бриф**: ядро (2 хуки + авто-установка) + повний `wiki doctor` + щотижневий lint |
| Щотижневий lint | **Нагадування в SessionStart-інжекті** (не headless cron): якщо від останнього lint минуло >7 днів — перша сесія тижня отримує рядок-нагадування |

## Архітектура

```
~/claude-wiki-skill (репо скіла, canonical link ~/.claude/skills/wiki)
├── hooks/
│   ├── lib/
│   │   └── discover.sh        # спільний discovery: знайти {wiki} від $CLAUDE_PROJECT_DIR
│   ├── session-start.sh       # інжект index.md + lint-reminder + heartbeat
│   ├── post-tool-use.sh       # bump_view / bump_patch у .usage.json
│   ├── install-hooks.sh       # merge hook-записів у ~/.claude/settings.json (ідемпотентно)
│   └── uninstall-hooks.sh     # дзеркальне видалення наших записів
├── references/
│   └── operation-doctor.md    # НОВИЙ: операція wiki doctor
└── tests/
    ├── hooks/                 # НОВЕ: виконувані тести скриптів (tmp-фікстури)
    │   └── run.sh
    └── scenarios/hooks.md     # НОВИЙ сценарій поведінки агента
```

Глобальний `~/.claude/settings.json` (після установки):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|clear|compact",
        "hooks": [{ "type": "command", "command": "\"$HOME/.claude/skills/wiki/hooks/session-start.sh\"" }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Read|Edit|Write|MultiEdit",
        "hooks": [{ "type": "command", "command": "\"$HOME/.claude/skills/wiki/hooks/post-tool-use.sh\"" }]
      }
    ]
  }
}
```

Шлях іде через canonical link `~/.claude/skills/wiki` (не через realpath) — та
сама логіка, що й у cross-agent exports: перемикання версії скіла автоматично
підхоплюється хуками. `$HOME` розгортає shell, який виконує hook-команду.

**Примітка (верифікувати при імплементації проти актуальної доки Claude Code
hooks):** точні назви matcher-значень SessionStart (`startup`/`clear`/`compact`)
і поля stdin-JSON (`tool_name`, `tool_input.file_path`, `cwd`,
`hook_event_name`). Якщо реальні назви відрізняються — підлаштувати скрипти,
дизайн-рішення не змінюються.

## Компонент 1: `hooks/lib/discover.sh`

Bash-функція `discover_wiki <start_dir>` → друкує абсолютний шлях `{wiki}` або
нічого. Це **спрощене дзеркало Step 0** (кроки 2–5 discovery-versioning.md),
достатнє для хуків:

1. Визначити git-межу: walk-up від `<start_dir>` до першого каталогу з `.git`
   (директорія або файл), включно. Нема git-маркера → нічого не друкувати,
   `exit 0` (вікі без git не буває — інваріант).
2. На кожному рівні walk-up (від `<start_dir>` до git-кореня включно) перевірити
   `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`. У кожному існуючому — знайти секцію
   `## Wiki` і перший \`backtick-шлях\` у ній; resolve відносно директорії
   instruction-файла; кандидат валідний, якщо існує `{кандидат}/index.md`.
   Перший валідний по порядку walk-up перемагає.
3. Fallback (жоден pointer не резолвиться): `docs/wiki/index.md` відносно
   (а) директорії найближчого instruction-файла, (б) `<start_dir>`,
   (в) git-кореня — перший існуючий.
4. Нічого не знайдено → нічого не друкувати, `exit 0`.

Стартова точка для обох хуків: `$CLAUDE_PROJECT_DIR`, fallback — `pwd`
(хук-команди запускаються з поточної директорії сесії). stdin для discovery не
парситься — це тримає скрипт чистим bash без залежностей.

Розбіжності зі Step 0 — свідомі й допустимі: хук не робить конфлікт-résolution
між кількома валідними вікі (бере першу по walk-up) і не детектить legacy/partial
стани. Хук — best-effort спостерігач; складні стани обробляє агент у Step 0.

**Вартість у проєктах без вікі:** кілька stat/grep, ~10 мс, мовчазний вихід.

## Компонент 2: `hooks/session-start.sh`

Тригер: `SessionStart` з matcher `startup|clear|compact` (без `resume`:
відновлена сесія вже має інжект у стенограмі). stdout цього хука Claude Code
додає в контекст сесії.

Логіка:

1. `discover_wiki` → нема вікі → `exit 0` (порожній stdout, жодного шуму).
2. Друкує блок (розмітка стабільна — вона є маркером для агента й тестів):

   ```
   === WIKI INDEX (hook-injected) ===
   Джерело: {wiki}/index.md
   Session-Start Contract: READ FIRST для index.md виконано цим інжектом.
   Перед кожною project-specific відповіддю прочитай тематичні сторінки з
   index і цитуй [[page-name]]. Ручні bump_view/bump_patch НЕ потрібні —
   телеметрію веде хук; bump_use (нові [[wikilink]]) — вручну.
   ---
   {вміст index.md}
   === END WIKI INDEX ===
   ```

3. **Ліміт розміру:** якщо `index.md` > 24 KB — друкуються перші 24 KB +
   рядок `[!] Індекс обрізано на 24KB ({повний розмір}) — кандидат на split/дієту.`
4. **Lint-reminder:** прочитати `_hooks.last_lint_at` з `.usage.json`. Якщо поле
   відсутнє АБО старше 7 діб — додати рядок після блоку індексу:
   `⏰ Тижневий wiki lint: останній запуск {дата|невідомо}, минуло >7 днів — запропонуй користувачу «wiki lint швидко».`
   («швидко» — існуючий lint-скоуп top-10 most-edited; агент лише пропонує,
   рішення і DECIDE-меню лишаються за користувачем.)
5. **Heartbeat:** через python3 атомарно (tmp + rename) оновити в `.usage.json`:
   `_hooks.session_start_at = <now ISO 8601 UTC>`, `_hooks.hook_version = "1"`.
   Нема python3 / битий JSON / write-фейл → пропустити мовчки (stderr-warning
   допустимий), інжект однаково відбувається.
6. Завжди `exit 0`.

## Компонент 3: `hooks/post-tool-use.sh`

Тригер: `PostToolUse`, matcher `Read|Edit|Write|MultiEdit` (фаєриться після
успішного виклику інструмента; non-blocking за визначенням події).

Логіка:

1. Прочитати stdin-JSON (python3; нема python3 → `exit 0` мовчки — телеметрія
   best-effort). Дістати `tool_name` і `tool_input.file_path`. Нема
   `file_path` → `exit 0`.
2. `discover_wiki` від `$CLAUDE_PROJECT_DIR`/`pwd` → нема вікі → `exit 0`.
3. Guard: realpath(`file_path`) починається з realpath(`{wiki}`)/ → інакше `exit 0`.
4. Фільтри: тільки `*.md`; **виключити** `index.md`, `schema.md`, `log.md`
   (службова навігація — не «consult сторінки», відповідає чинній семантиці
   view=consult із telemetry.md). `.usage.json` виключений розширенням.
5. Ключ запису = шлях відносно `{wiki}/`.
   - `tool_name == Read` → `bump_view`: `view_count += 1`, `last_viewed_at = now`;
     запис відсутній → створити з усіма 10 полями-дефолтами.
   - `tool_name ∈ {Edit, Write, MultiEdit}` → `bump_patch`: `patch_count += 1`,
     `last_patched_at = now`; запис відсутній → створити (`created_at = now`).
6. `_hooks.post_tool_use_at = now` (heartbeat лічильника — для doctor/status).
7. Tolerance-правила telemetry.md успадковуються повністю: atomic write
   (tmp + rename в тій самій директорії), corrupt read → `{}`, write-фейл →
   мовчазний пропуск. Завжди `exit 0` — хук ніколи нічого не блокує.

Поведінкові наслідки (зафіксувати в текстах):

- **Субагенти теж рахуються**: PostToolUse фаєриться і на tool calls
  субагентів — читання вікі субагентами вперше потрапляє в телеметрію. Це
  бажано (телеметрія стає правдивішою).
- Read сторінки чужої вікі (сесія в проєкті A читає вікі проєкту B) — не
  залічується: discovery йде від проєкту сесії. Рідкісний кейс, толеруємо.
- Гонка паралельних сесій на `.usage.json`: last-writer-wins на цілому файлі,
  можлива втрата одиничного інкремента — прийнятно для пріоритизатора.

## Компонент 4: установка — `hooks/install-hooks.sh` + інтеграція в `install.sh`

`install-hooks.sh` — єдине місце merge-логіки (DRY: його кличуть і
`install.sh`, і агент при skill-provision):

1. Читає `~/.claude/settings.json` (нема → `{}`; битий JSON → **СТОП з
   помилкою**, нічого не писати — на відміну від телеметрії, тут зіпсувати
   користувацький конфіг неприпустимо).
2. Бекап: `~/.claude/settings.json.bak-wiki-hooks-{YYYYMMDD-HHMMSS}` (лише якщо
   файл існував).
3. **Ідемпотентний merge** (python3): з масивів `hooks.SessionStart[]` і
   `hooks.PostToolUse[]` видалити всі entries, чия будь-яка `hooks[].command`
   містить маркер `/skills/wiki/hooks/`; потім додати наші свіжі два записи
   (структура — див. Архітектура). Чужі хуки, інші події, решта ключів
   settings.json — байт-у-байт неторкані. Повторний запуск → той самий результат.
4. Друк: `Хуки wiki встановлено глобально. Активні з наступної сесії Claude Code.`

`uninstall-hooks.sh`: кроки 1–3 без додавання (тільки видалення по маркеру) +
прибрати порожні масиви подій, якщо після видалення вони спорожніли.

Інтеграція:

- `install.sh`: після кроку симлінк-експортів викликає
  `bash "$SKILL_LINK/hooks/install-hooks.sh"`. Фейл (нема python3 тощо) — НЕ
  валить інсталяцію: warning «хуки не встановлено, постав вручну:
  bash ~/.claude/skills/wiki/hooks/install-hooks.sh», решта інсталяції
  завершується (той самий патерн, що з doc-extract).
- `uninstall.sh`: викликає `uninstall-hooks.sh` (best-effort) перед зняттям
  симлінків.

## Компонент 5: skill-provision (пропозиція установки самим скілом)

Новий підрозділ у `references/discovery-versioning.md` (після Step 0):
**Hook provisioning (Claude Code only)**.

Умови пропозиції — ВСІ одночасно:

1. Активний агент — Claude Code (Codex/Gemini: пропуск, хуків для них не існує).
2. Step 0 знайшов валідну вікі.
3. У контексті сесії **немає** блоку `=== WIKI INDEX (hook-injected) ===`
   (сам інжект — маркер справної провізії; є блок → нічого не робити).
4. Не існує `~/.claude/wiki-hooks-optout` (opt-out маркер).
5. Пропозиція ще не звучала в цій сесії.

Тоді — DECIDE, один раз за сесію:

```
Вікі знайдено, але глобальні хуки Claude Code не активні в цій сесії.
Поставити? (інжект index.md на старті сесії + авто-телеметрія)
[y] так / [n] не зараз / [не питай більше]
```

- `y` → перевірити `~/.claude/settings.json`: якщо запис із маркером
  `/skills/wiki/hooks/` УЖЕ є, але інжекту не було — **хуки зламані**
  (битий шлях, помилка скрипта): не переставляти наосліп, а запустити
  `wiki doctor` (гілка діагностики). Якщо запису нема — виконати
  `bash ~/.claude/skills/wiki/hooks/install-hooks.sh` і повідомити:
  «активні з наступної сесії».
- `n` → нічого; наступна сесія спитає знову.
- `не питай більше` → `touch ~/.claude/wiki-hooks-optout`. (Пізніша явна
  установка — `install.sh` або пряме прохання — знімає маркер.)

Явні тригери «онови вікі», «wiki update» → той самий флоу + перевірка версії
схеми (existing state table) → це відповідь на «витягую свіжий скіл і прошу
вікі оновити і вона все налаштовує сама». Після `git pull` скіла навіть
просити не треба: перша ж вікі-операція в будь-якому старому проєкті сама
запропонує установку.

## Компонент 6: `references/operation-doctor.md` (нова операція)

**Тригери:** «wiki doctor», «полікуй вікі», «перевір здоров'я вікі»,
«онови вікі» (upgrade-флоу = doctor з фокусом на провізію + міграцію).

**Природа:** read-only збір → звіт-таблиця ✅/⚠️ → DECIDE-меню ремонтів.
Doctor сам НІЧОГО не змінює; кожен ремонт — існуючий механізм.

| # | Перевірка | Як | Ремонт (пропозиція) |
|---|---|---|---|
| 1 | Пойнтери | Кожен `CLAUDE.md`/`AGENTS.md`/`GEMINI.md` з `## Wiki` ↔ вікі на диску; відсутні пойнтери в існуючих instruction-файлах | існуючий stale-pointer repair / дописати pointer-блок (init-механізм) |
| 2 | Версія схеми | `wiki_version` vs версія скіла (existing state table) | migration flow (existing) |
| 3 | `.usage.json` | Парситься? Записи мають 10 полів? Фантомні ключі (сторінка є в telemetry, нема на диску)? `_`-ключі валідні? | corrupt → перестворити `{}` (tolerance rule); фантоми → `forget(path)` |
| 4 | Симлінк-експорти | `~/.claude/skills/wiki`, `~/.agents/skills/wiki`, `~/.gemini/skills/wiki` існують і ведуть на canonical | `bash install.sh --repair-exports` |
| 5 | Хуки | Запис-маркер у `~/.claude/settings.json`? Скрипти існують і виконувані? python3 у PATH? Heartbeats: `session_start_at` свіжий (ця сесія — якщо інжект-блок є в контексті, мусить бути свіжим), `post_tool_use_at` | `install-hooks.sh` / підказка причини (нема python3 → інжект працює, телеметрія ні) |
| 6 | Git-стан вікі | Проєкт у git? Незакомічені зміни під `{wiki}`? Orphan-стан (existing detection) | існуючі механізми (orphan repair, commit-нагадування) |

Doctor у Reference Loading Map: `discovery-versioning.md`, `operation-doctor.md`,
`telemetry.md`, `maintenance-and-mistakes.md`. Також додати в Operation Index.

`wiki status` (operation-wiki-status.md) отримує один рядок:
`Хуки: ✅ активні (session-start {ts}, телеметрія {ts})` /
`⚠️ не встановлені — «wiki doctor» для установки` /
`⚠️ встановлені, але heartbeat застарілий — запусти «wiki doctor»`.

## Телеметрія: `_hooks` metadata і подвійний облік

Зміни `references/telemetry.md`:

1. **Underscore-префікс зарезервовано:** ключі `.usage.json`, що починаються з
   `_`, — метадані, не сторінки. `report()` та всі page-ітерації їх ігнорують.
   Єдиний визначений ключ: `_hooks` з полями `session_start_at`,
   `post_tool_use_at`, `last_lint_at`, `hook_version` (усі опційні; відсутність
   — не помилка). Це покривається чинним silent-backfill правилом — schema bump
   не потрібен.
2. **Правило подвійного обліку:** маркер активності хуків = блок
   `=== WIKI INDEX (hook-injected) ===` у контексті поточної сесії.
   - Блок Є → ручні `bump_view` і `bump_patch` НЕ виконуються (їх веде хук);
     `bump_use` — завжди вручну.
   - Блоку НЕМА (Codex, Gemini, Claude без хуків) → чинна ручна механіка без змін.
3. `bump_view`/`bump_patch` описи доповнюються приміткою «у hook-injected
   сесіях виконується хуком».

Зміни `references/operation-lint.md`: наприкінці lint-прогону (будь-який скоуп)
агент записує `_hooks.last_lint_at = now` у `.usage.json` (та сама механіка, що
інші мутації телеметрії). Зміни `references/operation-init.md`: bootstrap
`.usage.json` включає `_hooks.last_lint_at = now` (свіжа вікі не потребує lint
у день народження — без цього перша ж сесія отримає хибне нагадування).

## Зміни текстів (повний перелік файлів)

| Файл | Зміна |
|---|---|
| `SKILL.md` | frontmatter `version: "4.5.0"`; Session-Start Contract: hook-injected блок = виконаний READ FIRST для index.md (тематичні сторінки все одно читати; нова red-flag «хук інжектнув індекс — значить все прочитано» → «ні, інжект = лише index»); Loading Map: рядок doctor; Operation Index: `operation-doctor.md` |
| `references/discovery-versioning.md` | підрозділ Hook provisioning (умови, DECIDE-блок, optout, гілка «зламані хуки → doctor»); Migration Log: entry 4.5.0 |
| `references/telemetry.md` | `_`-префікс/`_hooks`; правило подвійного обліку; примітки до bump_view/bump_patch |
| `references/operation-doctor.md` | НОВИЙ (див. Компонент 6) |
| `references/operation-query.md` | крок 6 телеметрії — умовний: hook-injected сесія → лише `bump_use` вручну |
| `references/operation-lint.md` | запис `_hooks.last_lint_at` наприкінці прогону |
| `references/operation-init.md` | bootstrap телеметрії включає `_hooks.last_lint_at = now` |
| `references/operation-wiki-status.md` | рядок «Хуки: …» |
| `references/maintenance-and-mistakes.md` | типова помилка: подвійний bump при активних хуках |
| `install.sh` / `uninstall.sh` | виклик `install-hooks.sh`/`uninstall-hooks.sh` (best-effort, не валить інсталяцію) |
| `README.md` | секція «What's new in v4.5» + рядок таблиці версій + rollout-нотатка для існуючих машин |

## Тестування

**НОВЕ: виконувані тести** (скрипти — справжній код) — `tests/hooks/run.sh`,
викликається останнім кроком із `tests/skill-contracts.sh` (один вхід для всіх
тестів зберігається). Фікстури — tmp-каталог: `git init` + `CLAUDE.md` з
pointer-блоком + `docs/wiki/{index.md,schema.md}` + `.usage.json`;
`CLAUDE_PROJECT_DIR` виставляється на фікстуру; stdin-JSON годується heredoc'ом.

Мінімальний набір кейсів:

1. **discover.sh**: знаходить вікі за pointer; walk-up із підкаталогу; boundary
   (не лізе вище git-кореня); нема pointer + нема `docs/wiki/` → тиша; pointer
   на неіснуючий шлях + існуючий `docs/wiki/` → fallback спрацьовує.
2. **session-start.sh**: друкує преамбулу + повний index; index 30KB → обрізка
   з міткою; heartbeat записано (atomic); `last_lint_at` 8 днів тому → reminder
   є; 2 дні → reminder нема; поля нема → reminder є; вікі нема → порожній stdout,
   exit 0.
3. **post-tool-use.sh**: Read сторінки → `view_count` +1 і `last_viewed_at`
   оновлено; Edit → `patch_count` +1; Write нового файлу → запис створено з
   10 полями; Read `index.md` → НЕ рахується; Read поза вікі → без змін;
   corrupt `.usage.json` → відновлення з `{}` + один свіжий запис; python3
   відсутній у PATH → exit 0, файл неторканий.
4. **install-hooks.sh**: порожній/відсутній settings → записи додано; settings
   із чужими хуками → чужі байт-у-байт збережені; повторний запуск → без
   дублів (ідемпотентність); битий settings JSON → відмова, файл неторканий;
   uninstall → наші зникли, чужі лишились.

**Contract guards** (`tests/skill-contracts.sh`, за існуючим патерном): SKILL.md
містить `4.5.0`; `operation-doctor.md` існує і згаданий у SKILL.md;
`telemetry.md` містить `_hooks`; `discovery-versioning.md` містить
`wiki-hooks-optout`; `session-start.sh` містить маркер `WIKI INDEX (hook-injected)`.

**Сценарій** `tests/scenarios/hooks.md`: (а) hook-injected сесія — агент
відповідає з цитатами, НЕ кличе ручні bump_view/bump_patch, бачить reminder →
пропонує lint; (б) Codex-сесія — блоку нема → чинна ручна телеметрія; (в) блоку
нема, але запис у settings є → агент радить doctor, не переустановку.

## Версіонування

- Скіл: `4.4.0` → `4.5.0`.
- `wiki_version` лишається `"4.0"`: on-disk схема вікі незмінна; `_hooks` —
  tolerated metadata за silent-backfill правилом.
- Migration Log (`discovery-versioning.md`): entry «4.5.0 (2026-07-08)» —
  behavior + host-side artifacts (глобальні хуки Claude Code, hooks/ у репо
  скіла); per-wiki міграцій нуль.

## Ризики й компроміси (прийняті)

1. **Гонка паралельних сесій** на `.usage.json` → last-writer-wins, втрата
   одиничного інкремента — прийнятно для пріоритизатора.
2. **Тиха смерть хука** (сесія живе на текстовому fallback) → heartbeat +
   рядок у `wiki status` + doctor. Свідомо без гучних фейлів.
3. **Хуки активуються з наступної сесії** після установки — обмеження Claude
   Code; повідомляється користувачу при установці.
4. **~10 мс bash-spawn на кожен Read** у проєктах без вікі — ціна глобальної
   топології; discovery-guard мінімізує роботу.
5. **python3 як залежність телеметрії/установки** — інжект працює без нього;
   телеметрія мовчки вимикається; doctor показує причину.
6. **Інжект з'їдає ~5–7 KB контексту** щосесії у wiki-проєктах (за брифом —
   дешево; ліміт 24 KB захищає від патологій).

## Acceptance criteria

1. Свіжа машина: `install.sh` → наступна сесія в wiki-проєкті стартує з
   `=== WIKI INDEX (hook-injected) ===` у контексті.
2. Існуюча машина: `git pull` скіла → перша вікі-операція в старому проєкті
   пропонує установку → `y` → наступна сесія має інжект. Жодних дій у самому
   проєкті.
3. Read wiki-сторінки в hook-сесії інкрементить `view_count` без участі агента;
   Edit/Write — `patch_count`.
4. Сесія в проєкті без вікі: жодного інжекту, жодних записів, жодного видимого
   ефекту хуків.
5. `wiki doctor` показує 6 груп перевірок зі станами і пропонує ремонти;
   `wiki status` показує рядок хуків.
6. Через 7+ днів без lint перша сесія тижня містить lint-reminder; після
   виконаного lint reminder зникає на 7 днів.
7. `tests/skill-contracts.sh` зелений (включно з новими hooks-тестами);
   `uninstall-hooks.sh` повертає settings.json до стану «без наших записів»,
   чужі хуки неторкані.
8. Codex/Gemini сесії працюють за чинним контрактом без регресій.

## Rollout

1. Реліз v4.5.0 у master скіла (цей репозиторій).
2. Ця машина: хуки ставляться в ході імплементації (install-hooks.sh) —
   верифікація acceptance №1/№3 наживо.
3. Інші машини: `bash install.sh` (або `git pull` + перша вікі-операція
   запропонує). Інші проєкти цієї машини — нічого: глобальний запис + self-discovery.

## Постскриптум (2026-07-08, аудит doc-гейтів конвеєра)

Конвеєр зупинявся після doc-фаз для аудиту фікс-комітів (движок на той момент
застосовував ПЕРШИЙ автофікс без тріажу; після цього випадку движок виправлено:
тріаж тепер стоїть перед кожним фіксом, а перегляд затверджених рішень
класифікується NEEDS_HUMAN). Вердикт аудиту: катастроф нема, артефакти прийняті
з такими відхиленнями/доповненнями відносно цього дизайну:

1. **Правило супресії ручних bump змінено (єдине справжнє відхилення від
   затвердженого):** дизайн казав «маркер активності хуків = інжект-блок у
   контексті». Рев'ю слушно показало діру: інжект доводить лише живий
   SessionStart; PostToolUse може бути мертвий (нема python3, розбіжність
   stdin-полів) — і супресія за інжектом дала б тиху нульову телеметрію, той
   самий провал, який фіча лагодить. Прийнято двосигнальне правило: пригнічувати
   `bump_view`/`bump_patch` лише за свіжим `_hooks.post_tool_use_at`; інжект без
   свіжого timestamp → ручні bump як fallback (подвійний облік — менше зло).
2. **Version gate** (`hooks/lib/version-gate.sh`): хуки не пишуть у
   legacy/часткові вікі (frontmatter-only парсинг `wiki_version`) — захист від
   тихої host-side міграції повз Step 0. Узгоджено з інваріантом «Migration is
   explicit».
3. **Security-посилення discovery:** boundary-guard на розв'язаному `index.md`
   (ловить симлінк-escape самого файла і fallback-каталогу; walk-up межа поза
   git — `$CLAUDE_PROJECT_DIR`, ніколи `/`) + untrusted-data мітка в преамбулі
   інжекту (in-repo prompt-injection: вміст вікі — дані, не інструкції).
4. **Робастність установки:** канонічний шлях `~/.claude/skills/wiki/hooks/…`
   (літеральний `$HOME`) як стабільний маркер; fail-open обгортка
   `test -x … || exit 0` (зниклий клон не блокує CLI); серіалізація
   read-modify-write на `settings.json` (flock / mkdir-lock із trap-cleanup і
   stale-детекцією без крадіжки живого lock); merge гранулярно по вкладених
   `hooks[]`-командах (не зносити чужі команди у спільному matcher-entry —
   виправляє реальний баг цього дизайну).
5. **Real-shape acceptance gate:** перед «done» — крос-чек matcher-імен і
   stdin-полів проти офіційної документації Claude Code hooks (фікстури тестів
   мусять дзеркалити живу поведінку, не припущення).

## Постскриптум №2 (2026-07-08, whole-feature рев'ю — фінал)

Два повних кола whole-feature рев'ю (8 + 6 знахідок), усі закриті. Відхилення
від цього дизайну, прийняті при ручній інтеграції:

1. **Version gate по major, не по exact "4.0"** (спека вимагала точний збіг):
   узгоджено з рештою системи — state detection і doctor порівнюють major;
   вікі 4.x залишається hook-writable.
2. **Пропозицію «замінити mkdir-lock на python-flock» відкинуто** (вона ж
   породила б Windows-регресію): натомість reclaim stale-лока зроблено
   атомарним mv-claim (rename(2)) — закриває той самий TOCTOU без зміни
   протоколу; uninstall вирівняно з install (LOCK_MAX_AGE pid-recycle guard).
3. **Windows-деградації**: fcntl — try/except (unlocked RMW замість мертвої
   телеметрії); O_NOFOLLOW/O_NONBLOCK — через getattr(os, …, 0); інсталяційні
   гейти -x → -f (втрачений exec-bit не вимикає хуки тихо).
4. **Нове понад дизайн**: MultiEdit-телеметрія збирає union file_path +
   edits[].file_path; {wiki}/log/ шарди виключені з телеметрії; session-start
   bootstrap'ить відсутній .usage.json (свіжий чекаут отримує heartbeat);
   uninstall-hooks повертає non-zero, коли маркер лишився, а python3 нема
   (--remove-clones не зносить клон з recovery-скриптом).
