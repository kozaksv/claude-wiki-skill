# Дизайн: нативна підтримка Qwen Code у wiki skill (v4.6.0)

Дата: 2026-08-13. Статус: затверджено користувачем у чаті (брейншторм наживо).
Slug циклу: `v46-qwen`. База: `origin/master`.

**Класифікація:** bounded-розширення наявних потоків — Qwen Code стає
четвертим клієнтом за зразком трьох існуючих (Claude/Codex/Gemini).
Скіл-версія `4.5.0 → 4.6.0` (behavior release; `wiki_version` лишається
`"4.0"`).

## Контекст і мотивація

Скіл декларативно підтримує Claude/Codex/Gemini; Qwen Code зараз підключений
зовнішніми саморобними адаптерами поза репо. Підтверджений баг: PostToolUse у
`~/.qwen/settings.json` спрацьовує (matcher `read_file|write_file|edit|notebook_edit`),
але `hooks/post-tool-use.sh` знає лише Claude-назви (`case "$tool_name" in
Read|Edit|Write|MultiEdit`) — Qwen-виклики виходять через `*) exit 0`,
телеметрія view/patch не пишеться. SessionStart працює лише через зовнішній
wrapper `~/.qwen/hooks/wiki-session-start.sh`, який пакує raw-text вивід
канонічного хука в Qwen JSON envelope.

## Перевірені факти (основа дизайну; звірені з кодом qwen-code 0.21.11 локально)

1. Qwen PostToolUse stdin = Claude-схема: `tool_name`, `tool_input`, `cwd`,
   `hook_event_name`; canonical назви інструментів — lowercase
   (`Read→read_file`, `Edit→edit`, `Write→write_file`,
   `NotebookEdit→notebook_edit`; `replace` — legacy-alias `edit`).
2. Параметри: `read_file`/`write_file`/`edit` → `tool_input.file_path`;
   `notebook_edit` → `tool_input.notebook_path`; fallback `tool_input.path`
   (може бути відносним). Це власний ланцюжок екстракції Qwen
   (file_path → notebook_path → path).
3. SessionStart: не-JSON stdout НЕ інжектиться в контекст (стає
   "info"-повідомленням) — потрібен envelope
   `{"continue":true,"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"…"}}`.
   Matcher `startup|clear|compact` валідний (input має поле `source`).
4. Qwen експортує хукам і `CLAUDE_PROJECT_DIR`, і `QWEN_PROJECT_DIR`
   (обидва = cwd проєкту) — але на compat-експорт не покладаємось.
5. Qwen Code нативно читає `AGENTS.md` і `QWEN.md` як resident-інструкції;
   конфіг — `~/.qwen/settings.json`.
6. Робочий SessionStart-адаптер уже існує зовні
   (`~/.qwen/hooks/wiki-session-start.sh`) — його логіка переноситься в скіл.

## 1. hooks/ — ядро

**`hooks/session-start-qwen.sh` (новий, ~30 рядків)** — логіка зовнішнього
`~/.qwen/hooks/wiki-session-start.sh` переїжджає в скіл: викликає сусідній
канонічний `session-start.sh` (через власний `$HOOK_DIR`, не hardcoded шлях),
пакує stdout у Qwen JSON envelope через `python3 json.dumps`. Порожній
вивід / немає вікі / немає python3 → тихий `exit 0`. Claude-шлях
(`session-start.sh`) не змінюється взагалі. Шлях містить маркер
`/skills/wiki/hooks/` — granularity un/install працює без змін.

**`hooks/post-tool-use.sh`** — точкові редагування:

- case: `Read|read_file) → view`;
  `Edit|Write|MultiEdit|write_file|edit|notebook_edit|replace) → patch`.
- python-екстрактор stdin: union `tool_input.file_path` →
  `tool_input.notebook_path` → `tool_input.path` → `tool_input.edits[].file_path`
  (порядок-стабільний dedup; для Claude нових ключів не існує — нуль впливу).
  Відносний `path` уже резолвиться наявним anchor-механізмом.
- anchor precedence: `CLAUDE_PROJECT_DIR → QWEN_PROJECT_DIR → stdin cwd → pwd`.

**`hooks/lib/discover.sh`**:

- `discover_wiki` fallback: `CLAUDE_PROJECT_DIR → QWEN_PROJECT_DIR → pwd`.
- `_wiki_disc_dir_pointers`: `CLAUDE.md AGENTS.md GEMINI.md QWEN.md`
  (append у кінець; перший валідний pointer виграє, як зараз).

`version-gate.sh`, boundary-guard, інваріант «кожен хук-шлях exit 0 і ніколи
не блокує інструмент» — без змін.

## 2. install-hooks.sh / uninstall-hooks.sh — мультиклієнт

Рефакторинг у параметризовану функцію «register into settings-file»: той
самий mkdir-lockdir мутекс (окремий lock на кожен файл:
`~/.qwen/settings.json.lockdir`), read-under-lock, timestamped backup,
python3-merge по маркеру, atomic tmp+`os.replace`. Викликається двічі:

- **claude**: як зараз, байт-у-байт ті самі entries (регрес-нуль).
- **qwen**: gate `command -v qwen || -f ~/.qwen/settings.json`, інакше skip
  з підказкою. Entries: SessionStart matcher `startup|clear|compact` →
  канонічний `$HOME/.claude/skills/wiki/hooks/session-start-qwen.sh`;
  PostToolUse matcher `read_file|write_file|edit|notebook_edit` → канонічний
  `post-tool-use.sh`. Обидва в обгортці `test -x … && … || exit 0`, без
  `timeout`/`name`. Чужі ключі (`env` із секретами, `mcpServers`,
  `modelProviders`) недоторкані.
- **Міграція legacy**: Qwen-merge додатково strip'ає entries з маркером
  `/.qwen/hooks/wiki-session-start.sh` (старий зовнішній wrapper) — інакше
  подвійна інжекція. Сам файл wrapper-а видаляє rollout-крок, не інсталер.

`uninstall-hooks.sh` — дзеркально: strip обох маркерів з обох файлів
(кожен під своїм lock); відсутній `~/.qwen/settings.json` → нічого робити.

## 3. install.sh / uninstall.sh / --repair-exports

`QWEN_SKILLS_ROOT="$HOME/.qwen/skills"`: export `wiki` (+ `doc-extract`,
якщо є) → symlink на canonical, безумовно й симетрично до
`~/.agents`/`~/.gemini` — у повній інсталяції, у `--repair-exports`, у
summary-звітах. `uninstall.sh` видаляє qwen-exports так само, як
gemini-exports.

## 4. Документація (мапа згадок знята grep-ом по репо)

- **SKILL.md**: «Claude, Codex, or Gemini» → + Qwen Code; Platform
  Compatibility — 5-та колонка Qwen Code (`read_file` / `edit`+`write_file` /
  `shell` / `todo_write`); Agent-neutral discovery bullet + `QWEN.md`;
  version bump `4.6.0`.
- **references/discovery-versioning.md**: чотири файли в Step 0 (рядки ~27,
  ~107) і в Cross-agent instruction-file sync (~232, ~403, ~513, ~541,
  ~296-виноска).
- **references/operation-init.md**: активний агент Qwen → `QWEN.md`;
  Cross-agent skill availability — 4-й export `~/.qwen/skills/wiki`;
  шаблони планів (кроки 10/12, N-1/N) — + QWEN.md і qwen-export.
- **references/operation-lint.md**: checks **#2a** і **#11** — + `QWEN.md`.
- **references/operation-doctor.md** (~рядок 46) та
  **references/operation-ingest-source.md** (~рядок 121): переліки
  клієнт-файлів + QWEN.md; doctor-перевірки exports/hooks — + qwen-шляхи.
- **README**: layout-схема, «Після встановлення: Qwen Code читає
  ~/.qwen/skills/wiki», recovery cookbook, розділ What's new v4.6,
  migration-note про видалення зовнішнього wrapper-а.
- **tests/README.md**, `tests/scenarios/cross-agent-discovery.md`,
  `tests/scenarios/hooks.md`: Qwen-сценарії.

## 5. Тести (tests/hooks/run.sh + суміжні)

- **discover**: pointer лише у `QWEN.md`; пріоритет при кількох файлах;
  `QWEN_PROJECT_DIR` fallback (без `CLAUDE_PROJECT_DIR`).
- **post-tool-use**: `read_file` → `view_count`+1; `edit`/`write_file`/
  `notebook_edit` (через `notebook_path`) → `patch_count`+1; відносний
  `path` + `QWEN_PROJECT_DIR` anchor; `_hooks.post_tool_use_at`
  оновлюється; наявні Claude-кейси зелені без змін.
- **session-start-qwen**: stdout парситься `json.load`; `continue==true`,
  `hookEventName=="SessionStart"`, `additionalContext` містить
  `=== WIKI INDEX (hook-injected) ===`; проєкт без вікі → порожньо, exit 0.
- **install/uninstall-hooks**: qwen-запис під фейковим HOME + PATH-стаб
  `qwen` (gate); idempotent повтор; legacy wrapper-entry зникає;
  секрети/чужі ключі байт-у-байт збережені; corrupt JSON → fail без
  запису; strip з обох файлів.
- **install-cross-agent-links.sh / uninstall.sh**: qwen-export
  створюється/чиниться/видаляється.
- **skill-contracts.sh**: сепаратор Platform Compatibility таблиці →
  5 колонок.

Повна тест-команда репо (канон):
`bash tests/hooks/run.sh && bash tests/skill-contracts.sh && bash tests/install-cross-agent-links.sh && bash tests/uninstall.sh`.

## 6. Rollout на машині користувача (= Done-when; після посадки, поза движком)

1. `bash hooks/install-hooks.sh` → `~/.qwen/settings.json` перепідключено на
   канонічні хуки, legacy-entries зникли.
2. `rm ~/.qwen/hooks/wiki-session-start.sh` (+ порожня `~/.qwen/hooks/`).
3. Live-перевірка в Qwen-сесії на тест-проєкті: індекс інжектнуто;
   read/edit wiki-сторінки → `.usage.json` bump, свіжий
   `_hooks.post_tool_use_at`.
4. `install.sh --repair-exports` → `~/.qwen/skills/wiki` існує; всі
   тест-сюїти зелені; Claude/Codex/Gemini поведінка незмінна.

## Не-цілі

HTTP-hooks, `timeout`-поля в entries, PreToolUse, глобальний `~/.qwen/QWEN.md`,
авто-видалення wrapper-файла інсталером.

## Обмеження (інваріанти, НЕ ослаблювати)

- DRY — канонічна логіка лишається в `hooks/lib`; qwen-специфіка — лише
  тонкий транспорт-шар.
- Всі шляхи хуків `exit 0` і ніколи не блокують інструмент.
- Boundary-guard і version-gate інваріанти збережені.
- Claude/Codex/Gemini поведінка байт-у-байт без змін (регрес-нуль).

## Відкладене рев'ю

- [P1] (codex-кор) Task 2 add() vs regres-test path count conflict [file: docs/superpowers/plans/2026-08-13-v46-qwen.md]: Task 2 одночасно вимагає обробляти всі file_path/notebook_path/path через add() і в регрес-тесті бампати лише file_path; за наявності кількох валідних шляхів реалізація неминуче оновить кілька записів.
- [P1] (agy-атк) uninstall.sh orphaned-hook guard omits ~/.qwen/settings.json [file: uninstall.sh]: SETTINGS_JSON is hardcoded to $HOME/.claude/settings.json; grep confirms zero references to qwen anywhere in uninstall.sh. If a user has active Qwen hook entries only in ~/.qwen/settings.json (no Claude hooks), HOOKS_FAILED stays 0 and --remove-clones deletes $SKILL_DIR, stranding the Qwen hook references with no recovery script left.
