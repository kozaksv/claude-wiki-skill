# v4.6.1 — client-aware project anchor (design)

## Проблема

Обидва anchor-ланцюги скіла безумовно віддають перевагу `CLAUDE_PROJECT_DIR`
над `QWEN_PROJECT_DIR`:

- `hooks/post-tool-use.sh:381-385` — `CLAUDE_PROJECT_DIR` → `QWEN_PROJECT_DIR`
  → stdin `cwd` → `pwd`;
- `hooks/lib/discover.sh:154-157` — fallback усередині `discover_wiki`, коли
  `$1` порожній: `CLAUDE_PROJECT_DIR` → `QWEN_PROJECT_DIR` → `pwd`. Саме цим
  шляхом іде `hooks/session-start.sh:237` (викликає `discover_wiki` без
  аргументу).

Це коректно, поки в середовищі є щонайбільше одна з двох змінних. Але коли
**Qwen Code запущено зсередини сесії Claude Code** (вкладений агент — типовий
випадок для оркестрації), у хука присутні ОБИДВІ, і вони вказують на РІЗНІ
проєкти.

**Доказ — емпіричний, не теоретичний.** Прогін 2026-08-14 із хуком-дампером
під ізольованим `HOME` (Qwen Code 0.21.11) показав у середовищі PostToolUse-
хука одночасно:

```
QWEN_PROJECT_DIR=<корінь проєкту, у якому працює Qwen>
CLAUDE_PROJECT_DIR=<корінь проєкту батьківської Claude-сесії>
```

Той самий прогін підтвердив решту контрактів: `tool_name` приходить у
lowercase (`read_file`, `edit`, `write_file`), шлях завжди в
`tool_input.file_path` і завжди абсолютний, `source: "startup"` для
SessionStart.

### Наслідки (різні за тяжкістю)

1. **SessionStart (Qwen) — тиха дезінформація, гірший випадок.**
   `session-start-qwen.sh` → `session-start.sh` → `discover_wiki` без
   аргументу → fallback бере `CLAUDE_PROJECT_DIR` → у Qwen-сесію інжектується
   індекс **чужої** вікі. Агент отримує знання іншого проєкту як довідку про
   поточний, і жодного сигналу про підміну немає.
2. **PostToolUse (Qwen) — мовчазна втрата телеметрії.**
   Anchor вказує на чужий проєкт → `discover_wiki` знаходить чужу вікі →
   boundary-guard відкидає абсолютний шлях Qwen-файлу як «поза межами {wiki}»
   → `.usage.json` не оновлюється. Чужа вікі при цьому НЕ забруднюється —
   guard тримає, — але подія зникає без сліду.

Зворотний випадок (Claude Code зсередини Qwen-сесії) симетричний: у Claude-
хука опиниться `QWEN_PROJECT_DIR`, і його наявність не має впливати на вибір.

## Підхід

**Клієнт визначається за фактом виклику, а не за наявністю env.** Обидві
змінні лишаються в ланцюгу — змінюється лише те, ЯКА з них перша, і рішення
приймається з сигналу, що доведено належить події, яка щойно сталася.

### PostToolUse — сигнал уже в руках

`tool_name` зі stdin уже розібраний для action-gate, і набори не перетинаються
(Qwen — lowercase, Claude — CamelCase). Anchor-ланцюг стає client-aware:

| подія | порядок |
|---|---|
| Qwen-інструмент (`read_file`, `write_file`, `edit`, `replace`, `notebook_edit`) | `QWEN_PROJECT_DIR` → `CLAUDE_PROJECT_DIR` → stdin `cwd` → `pwd` |
| Claude-інструмент (`Read`, `Edit`, `Write`, `MultiEdit`) | `CLAUDE_PROJECT_DIR` → `QWEN_PROJECT_DIR` → stdin `cwd` → `pwd` |

Другий рядок — рівно поточна поведінка. Змінюється лише перший.

### SessionStart — сигнал дає транспорт

У SessionStart немає `tool_name`, але є інший доведений сигнал: сам факт, що
виклик прийшов через Qwen-транспорт. `hooks/session-start-qwen.sh` експортує
`WIKI_HOOK_CLIENT=qwen` перед викликом канонічного хука, і fallback
`discover_wiki` це враховує:

| середовище | порядок |
|---|---|
| `WIKI_HOOK_CLIENT` дорівнює рівно `qwen` | `QWEN_PROJECT_DIR` → `CLAUDE_PROJECT_DIR` → `pwd` |
| будь-що інше (зокрема порожнє чи `Qwen`/`QWEN`) | `CLAUDE_PROJECT_DIR` → `QWEN_PROJECT_DIR` → `pwd` |

`WIKI_HOOK_CLIENT` — приватний канал між wrapper і канонічним хуком: він не
є публічним контрактом, не документується як налаштування користувача і
приймається ЛИШЕ за точної рівності `qwen` (жодних case-insensitive порівнянь
чи префіксів). Впливає рівно на порядок двох env-сходинок, обидві з яких і
так походять із того самого середовища, тож підміна значення нічого не
відкриває — вона лише обирає між двома вже наявними кандидатами.

## Інваріанти (не порушувати)

- **Регрес-нуль для Claude/Codex/Gemini.** Default-гілки обох ланцюгів
  байт-у-байт ті самі. Codex і Gemini власної env не мають — вони йдуть
  default-гілкою, як і раніше.
- **Жодна сходинка не зникає.** «Чужий» env лишається fallback-ом: середовище,
  де задано лише одну змінну, поводиться рівно як зараз.
- Fail-closed discovery (git-boundary), boundary-guard `{wiki}/`, version-gate,
  24 KB cap, `exit 0` на всіх шляхах хуків — не чіпаються.
- On-disk схема не змінюється: `wiki_version` лишається `"4.0"`.
- Мутекс `hooks/lib/settings-lock.sh` і транспортний конверт Qwen — поза
  дотиком.

## Зміни

- `hooks/post-tool-use.sh` — client-aware anchor (порядок залежить від
  `tool_name`); коментар про причину з посиланням на вкладений сценарій.
- `hooks/lib/discover.sh` — `WIKI_HOOK_CLIENT`-гілка у fallback `discover_wiki`.
- `hooks/session-start-qwen.sh` — експорт `WIKI_HOOK_CLIENT=qwen`.
- `SKILL.md` — версія `4.6.0` → `4.6.1`; `tests/skill-contracts.sh` —
  перенацілення version-assert.
- Тести: `tests/hooks/run.sh`.

## Тести

1. Обидві env задані на РІЗНІ git-проєкти, подія `read_file` → `.usage.json`
   оновлюється у вікі **QWEN**-проєкту; вікі Claude-проєкту байт-у-байт
   недоторкана.
2. Дзеркально: подія `Read` за тих самих умов → оновлюється вікі
   **CLAUDE**-проєкту.
3. SessionStart через `session-start-qwen.sh` з обома env → JSON-конверт несе
   індекс QWEN-проєкту.
4. SessionStart канонічний (`WIKI_HOOK_CLIENT` не заданий) з обома env →
   індекс CLAUDE-проєкту (регрес-тест на default-гілку).
5. Задана лише одна env (кожен із двох випадків, обидві події) → поведінка
   незмінна.
6. `WIKI_HOOK_CLIENT` зі значенням `Qwen`, `QWEN `, `qwen2`, порожнім →
   default-порядок (точна рівність, без «майже збігів»).
7. Наявні кейси `tests/hooks/run.sh` лишаються зеленими без правок.

## Поза скоупом

- `hooks/session-start.sh` не читає документоване поле stdin `cwd` (спирається
  лише на env і `pwd`). Дотичний недолік того ж класу — окремий follow-up, у
  цьому циклі НЕ чіпається.
- Будь-яка зміна пріоритетів для Codex/Gemini.
- Нові env-перемикачі понад `WIKI_HOOK_CLIENT`.

## Done-when

`bash tests/hooks/run.sh && bash tests/skill-contracts.sh && bash
tests/install-cross-agent-links.sh && bash tests/uninstall.sh` — зелено;
вкладений сценарій (обидві env на різні проєкти) дає правильну вікі для обох
клієнтів у SessionStart і PostToolUse.
