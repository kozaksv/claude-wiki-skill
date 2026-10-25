# W1 / C01 — профілі Classic і Watchdog

[Спільні контракти W1](../../2026-10-25-wiki-watchdog-w1-contracts.md) · [Синтетичні сценарії](../../../../tests/fixtures/watchdog-contracts/v1/contract-cases.json)

Статус: матеріал до W1 spec r1 для рев’ю. Код build/CI і runtime не реалізовано. Джерела прочитані на `a8e1faf53c18aa4da5d21e141c115be3d2ce89e8`. Базові вимоги: RFC v5 #21 §10 та GO-рев’ю декомпозиції #23.

## 1. Підтвердження за кодом

- [scripts/build_skill.py L30–56](https://github.com/kozaksv/claude-wiki-skill/blob/a8e1faf53c18aa4da5d21e141c115be3d2ce89e8/scripts/build_skill.py#L30-L56) має лише `--check`, генерує discovery/export tables і копіює root reader/writer та інші ресурси в `skills/wiki-github`. Немає вибору edition або другого дерева інструкцій.
- [tests/skill-contracts.sh L533–557](https://github.com/kozaksv/claude-wiki-skill/blob/a8e1faf53c18aa4da5d21e141c115be3d2ce89e8/tests/skill-contracts.sh#L533-L557) вимагає `skill major == init schema major` і такого самого пояснення doctor. [L488–525](https://github.com/kozaksv/claude-wiki-skill/blob/a8e1faf53c18aa4da5d21e141c115be3d2ce89e8/tests/skill-contracts.sh#L488-L525) також містять Classic-specific Qwen assertions.
- [reflection.md L43–62](https://github.com/kozaksv/claude-wiki-skill/blob/a8e1faf53c18aa4da5d21e141c115be3d2ce89e8/references/reflection.md#L43-L62) наказує агенту самому рахувати приблизно 15 tool calls. [telemetry.md L155–174](https://github.com/kozaksv/claude-wiki-skill/blob/a8e1faf53c18aa4da5d21e141c115be3d2ce89e8/references/telemetry.md#L155-L174) визначає manual bump fallback та завжди manual `bump_use`. Це не нейтральні файли для автоматичного наслідування Watchdog.
- [install.sh L19–48](https://github.com/kozaksv/claude-wiki-skill/blob/a8e1faf53c18aa4da5d21e141c115be3d2ce89e8/install.sh#L19-L48) встановлює root checkout і не має edition routing. W1 не повинен підміняти цей root entrypoint на 5.x; production routing залишається W6.
- [discovery-versioning.md L279–299](https://github.com/kozaksv/claude-wiki-skill/blob/a8e1faf53c18aa4da5d21e141c115be3d2ce89e8/references/discovery-versioning.md#L279-L299) та [operation-doctor.md L36–39](https://github.com/kozaksv/claude-wiki-skill/blob/a8e1faf53c18aa4da5d21e141c115be3d2ce89e8/references/operation-doctor.md#L36-L39) також потребують явної schema compatibility семантики. Самої зміни одного assert у tests недостатньо.

## 2. Конкретний файловий контракт

Classic лишається у чинних root source paths; Watchdog отримує окремі source-файли. Це дозволяє W3/W4/W5 змінювати власні інструкції без заміни Classic та без перемикання існуючого installer.

| Джерело | Призначення / власник |
|---|---|
| `SKILL.md`, чинні `references/*`, `hooks/*`, `lib/*` | Classic 4.x source; W3/W4/W5 не переписують їх Watchdog-семантикою |
| `profiles/classic.json` | Явний manifest Classic instruction profile, source paths і підтримка schema |
| `profiles/watchdog.json` | Явний manifest Watchdog instruction profile; кожний destination має конкретне source path |
| `profiles/shared/wiki-compatibility.json` | `supported_wiki_schema_majors: [4]`, `init_schema_version: "4.0"`; незалежно від program release |
| `profiles/watchdog/SKILL.md` | Watchdog 5.x entrypoint і routing; W1 skeleton, далі компонентні PR |
| `profiles/watchdog/references/reflection.md` | W3: підказки сторожа, без agent self-counter |
| `profiles/watchdog/references/telemetry.md` та `operation-wiki-status.md` | W4: mechanical SQL accounting/report contract |
| `profiles/watchdog/references/writer-core.md` | W5: authorized writer та explicit log helper |
| `profiles/watchdog/references/discovery-versioning.md`, `operation-init.md` | W1 compatibility routing; W2/W4 доповнюють власні discovery/accounting деталі |
| `profiles/watchdog/references/operation-doctor.md`, `updating.md` | W6: health/lifecycle, пізніше за узгодженим API |
| `build/skill-profiles/classic/`, `build/skill-profiles/watchdog/` | Згенеровані окремі instruction bundles, gitignored; не source і не production-ready release |
| `skills/wiki-github/` | Чинний remote GitHub skill; збирається за існуючим explicit copy list з Classic/shared sources |

Manifest — **explicit destination → source map**. Немає `copy everything + fallback to root`: відсутній обов’язковий Watchdog override для reflection/telemetry/writer/status/init/doctor — build error. Development profile має повне дерево для свого явно заявленого набору інструкцій; його позначка development не дозволяє dangling references або мовчазну підстановку Classic.

Shared джерела дозволені лише через явні записи manifest: наприклад `references/reader-core.md` та discovery fixtures. Зміна такого shared source має прогнати перевірки всіх його споживачів. Власники можуть додавати нові Watchdog sources по компонентах; entrypoint не посилається на неіснуючі файли.

Приклад фрагмента manifest (версія 5.0.0 і paths — специфікація майбутнього артефакту, не оголошення релізу):

```json
{
  "profile_format": 1,
  "edition": "watchdog",
  "skill_version": "5.0.0",
  "compatibility_source": "profiles/shared/wiki-compatibility.json",
  "files": {
    "SKILL.md": "profiles/watchdog/SKILL.md",
    "references/reader-core.md": "references/reader-core.md",
    "references/reflection.md": "profiles/watchdog/references/reflection.md",
    "references/telemetry.md": "profiles/watchdog/references/telemetry.md",
    "references/writer-core.md": "profiles/watchdog/references/writer-core.md",
    "references/operation-wiki-status.md": "profiles/watchdog/references/operation-wiki-status.md"
  }
}
```

Manifest має бути повним для заявленого bundle. Приклад вище показує лише ключові записи, а не готовий повний список. Ідентифікатор/версія profile format — версія формату manifest, не SQLite schema.

### Qwen і GitHub

Watchdog runtime/export capability manifest містить лише Claude Code, Codex CLI та Antigravity. Новий manager не створює Qwen entries навіть при switch Classic; W6 одноразово від’єднує лише однозначно власні legacy entries перед Watchdog activation. Історичні Classic artifacts не переписуються. Текст `QWEN.md` у спільній discovery grammar залишається дозволеним як legacy pointer source — це не Qwen runtime support.

Remote `skills/wiki-github` не отримує локальних Watchdog hooks, binary, SQLite або вимоги викликати `wiki-watchdog`. У W5 новий Watchdog writer має власне source path; root shared/Classic writer і його remote copy зберігають дозволений remote GitHub write flow.

## 3. Команди генерації і межа scaffold

Майбутній CLI builder:

```bash
# Існуюча генерація shared tables та remote GitHub bundle.
python3 scripts/build_skill.py
python3 scripts/build_skill.py --check

# Нове явне збирання instruction profiles.
python3 scripts/build_skill.py --edition classic --out build/skill-profiles
python3 scripts/build_skill.py --edition watchdog --out build/skill-profiles
python3 scripts/build_skill.py --edition all --out build/skill-profiles
python3 scripts/build_skill.py --edition all --out build/skill-profiles --check
```

- Без `--edition` зберігається чинний режим builder; додавання Watchdog sources не робить їх remote bundle sources.
- `--edition` вибирає окремий profile build mode. `--out` обов’язковий у цьому режимі; builder пише лише `<out>/<edition>/` і не перезаписує root `SKILL.md`/`references`.
- Після build `--check` порівнює наявний output з deterministic очікуваним деревом, включно з переліком файлів; помилки source mapping/незамкнених relative references зупиняють збірку. Output не містить timestamp або machine-specific absolute paths.
- На fresh CI output спочатку збирається, потім перевіряється focused profile-contract tests. Існуючий no-args `--check` і Classic tests теж виконуються.
- Це **instruction bundle**, не повний release bundle. W6 пізніше пакує binary/hooks/resources, підписує/перевіряє узгоджений artifact manifest і керує activation/profile generation.
- Поточний spec PR не реалізує ці команди. W1 закривається лише після окремо перевіреного мінімального scaffold; компонентні PR можуть готуватися паралельно, але їхні edition-specific instruction зміни merge-яться після цього gate.

W1 володіє manifest format, source layout, build/CI foundation і compatibility contract. W6 споживає готові profile artifacts та володіє installer/update/switch/health/system distribution. W6 не є прихованим prerequisite для W3/W4/W5.

## 4. Версії та CI

Три незалежні осі:

| Вісь | Джерело істини / перевірка |
|---|---|
| Program/skill edition release | Classic 4.x або Watchdog 5.x; frontmatter відповідає manifest обраного profile |
| Wiki schema | Явний `SUPPORTED_WIKI_SCHEMA_MAJORS=[4]`; init створює 4.0, 4.x приймається обома лінійками |
| SQLite schema | W2 migrations і DB metadata; Classic не потребує SQLite; W6 перевіряє сумісність конкретного binary |

У `tests/skill-contracts.sh` прибирається саме неправильний зв’язок program-major↔schema-major, а не schema gate. Нові assertions перевіряють membership у manifest support set та init schema. Doctor/discovery prose узгоджується з цією семантикою. Наявні Classic-specific інваріанти залишаються Classic tests, зокрема historical Qwen tests; вони не застосовуються до Watchdog output. Окремі profile-contract checks перевіряють Watchdog.

Пропоновані W1 acceptance scenarios:

| ID | Вхід / очікування |
|---|---|
| ED-01 | Program Classic 4.x + schema 4.0/4.9 → supported; Watchdog 5.x + ті самі schema → supported без migration notice |
| ED-02 | Schema 5.x або corrupt/absent version → explicit unsupported/unknown policy; 5.x program не дає права запису у wiki schema 5 |
| ED-03 | Watchdog-only reflection/telemetry/writer source change → Classic і GitHub output не змінюються; shared reader change перевіряється для всіх явних споживачів |
| ED-04 | Manifest пропустив Watchdog override або relative link веде на відсутній reference → build не маскує помилку Classic fallback |
| ED-05 | Classic build/test environment без Rust, watchdog binary, OpenRouter key і мережі → Classic instruction bundle і наявні тести доступні |
| ED-06 | Watchdog output не вимагає self-counting приблизно 15 кроків або manual SQL/counter arithmetic; перевірка scope-specific, не заборона будь-якої згадки Classic |
| ED-07 | Regeneration reproducible; наявний remote GitHub bundle не отримав локальних Watchdog runtime requirements |
| ED-08 | Watchdog capability/export registry не містить Qwen; legacy `QWEN.md` pointer parsing не вважається runtime support; історичні Classic artifacts не переписані |

ED-06 застосовується до відповідних completed component sources: W1 scaffold фіксує цей контракт і negative fixtures; завершені reflection/telemetry semantics приймаються у W3/W4. W1 не може видати неповний profile за user-ready Watchdog.
