# v4.7.0 — прибрати залишки вирізаної tier-моделі крихталізації (design)

## Проблема

Блок РЕФЛЕКСІЯ щоразу друкує рядок `Автоматизував: нічого — …`. Це не
випадковість формулювання й не лінь моделі — поле структурно не може
відповісти інакше.

### Історія механізму (замір, не спогад)

У v4.0 крихталізація мала **чотири цілі**: bash-скрипт → python-скрипт →
wiki-сторінка → під-скіл. Три з чотирьох були виконуваними артефактами, тож
слово «Автоматизував» описувало реальність.

| Версія | Що прибрали | Джерело |
|---|---|---|
| 4.1 (2026-05-07) | обидві скриптові цілі (`scripts/*.sh`, `scripts/*.py`) — Division of Labor | `references/discovery-versioning.md:398-399` |
| 4.4.0 (2026-07-07) | skill-ціль разом із топологією delegation-vs-direct-create | `references/discovery-versioning.md:512-519` |

Лишилась **одна** ціль — wiki-сторінка (`references/crystallization.md:5-7`,
таблиця на один рядок). Сторінка — це нотатка, а не автоматизація. Тому поле
питає «що ти автоматизував?», а єдина дозволена ненульова відповідь —
«створив сторінку», і та майже дублює рядок `Зберіг у wiki:`, який стоїть
прямо над ним (`references/reflection.md:23-24`).

### Чому це не косметика

`references/reflection.md:69` робить поле **обов'язковим** і перелічує чотири
канонічні «нічого»-відповіді. Тобто скіл контрактно зобов'язаний друкувати
неправдиву назву в кожному блоці рефлексії — це рівно те, що бачить
користувач, і рівно те, на що він поскаржився.

### Замір: блок ніде не зберігається

`{wiki}/log.md` має власний формат записів
(`## [YYYY-MM-DD] operation | Subject`, `references/wiki-structure.md:43`).
Блок РЕФЛЕКСІЯ друкується у хід і на диск не потрапляє. **Наслідок: зміна
складу полів не потребує міграції жодної існуючої вікі**, і `wiki_version`
лишається `"4.0"`.

## Інвентар залишків

| # | Залишок | Файл:рядок | Стан |
|---|---|---|---|
| З1 | поле `Автоматизував:` у строгому шаблоні + правило обов'язковості | `references/reflection.md:24,69`; гард `tests/skill-contracts.sh:427` | видно користувачу щоразу |
| З2 | таблиця крихталізації на ОДИН рядок + три окремі пояснення «чому це не рівень» | `references/crystallization.md:5-7,9,11,62` | риштування від знесеної будівлі |
| З3 | фільтр `state == "active"` + обіцянка «v5+ curator/auto-transitions» | `references/operation-lint.md:30`, `references/operation-wiki-status.md:102`, `references/telemetry.md:34,46` | виглядає живим, є мертвим |
| З4 | «lint/status/cleanup and **skill** crystallization» | `SKILL.md:158` | слово з вирізаної цілі |
| З5 | «Tiered crystallization — … helper-скрипт або під-скіл» у списку фіч | `README.md:317` | читається як актуальна фіча |
| З6 | зразкова відповідь `нічого — юзер попросив скрипт поза tier-моделлю` | `tests/scenarios/crystallization.md:187` | посилання на неіснуючу модель |

Про З3 окремо: жодна операція ніколи не пише `state` інакше ніж `"active"`
(`hooks/post-tool-use.sh:209` — єдине місце запису, і це дефолт). Тому фільтр
завжди пропускає все. `archived_at` не читається ніде. Обидва — сліди
Hermes-куратора, якого свідомо відклали ще у v4.0
(`docs/specs/2026-05-01-…-design.md:21`) і ніколи не збудували.
`protected` при цьому ЖИВЕ — `wiki protect` / `wiki unprotect`
(`references/cleanup-flow.md:125-132`).

## Рішення

### 1. Перейменувати поле

`Автоматизував:` → **`Крихталізація:`**

Питання лишається (воно живе), змінюється лише назва, яка брехала про тип
відповіді. `Крихталізація: нічого — операція разова` читається як осмислене
твердження. Обидва рядки — `Зберіг у wiki:` і `Крихталізація:` — лишаються,
бо відповідають на різні питання (вердикт `r2`).

### 2. Почистити `references/crystallization.md`

Таблицю на один рядок → звичайний абзац. Три окремі пояснення «чому це не
рівень» (рядки 9, 11, 62) → **одне** коротке речення. Скрипт-гілку в тригері
«явний користувач» (рядок 23) стиснути до однієї фрази.

### 3. Зняти маску з `state` / `archived_at`

Прибрати фільтр `state == "active"` з lint і `wiki status`; у `telemetry.md`
замінити обіцянку v5-куратора на пряме «зарезервовані, зараз ніхто не пише і
не читає». Поля з `.usage.json` НЕ видаляти (вердикт `r3`).

### 4. Три точкові текстові правки

`SKILL.md:158`, `README.md:317`, `tests/scenarios/crystallization.md:187`.

### 5. Версія і журнал

`SKILL.md` frontmatter `4.6.1` → `4.7.0`; перенацілити version-assert у
`tests/skill-contracts.sh`; **дописати** запис `4.7.0` у Migration Log
(`references/discovery-versioning.md`) — наявні записи не переписувати.

## Інваріанти (не порушувати)

- **On-disk нуль.** `wiki_version` лишається `"4.0"`; форма запису
  `.usage.json` не змінюється; міграції не потрібні для жодної вікі.
- **Паркан лишається.** Негативні гарди `set_skill_link` / `writing-skills` /
  `🧹` у `tests/skill-contracts.sh` і регресійні суб-сценарії у
  `tests/scenarios/crystallization.md` — це запобіжники, не залишки.
- **`protected` недоторканий** — фільтрація `protected == false` і операції
  `wiki protect` / `wiki unprotect` лишаються як є.
- **Історія недоторкана** — `docs/specs/`, `docs/plans/`, наявні записи
  Migration Log, історична таблиця релізів у README.
- **Хуки не змінюються.** `hooks/` не входить у скоуп зовсім.

## Розкладка задач по файлах (не по шарах)

Кожна задача володіє своїм набором файлів; жодна не редагує файл іншої.

| Задача | Файли |
|---|---|
| T1 перейменування поля | `references/reflection.md`, `references/self-improvement.md` |
| T2 чистка crystallization | `references/crystallization.md` |
| T3 демаскування state | `references/telemetry.md`, `references/operation-lint.md`, `references/operation-wiki-status.md` |
| T4 точкові правки | `SKILL.md`, `README.md` |
| T5 версія + Migration Log | `SKILL.md` frontmatter, `references/discovery-versioning.md` |
| T6 тести | `tests/skill-contracts.sh`, `tests/scenarios/crystallization.md`, `tests/scenarios/reflection-triggers.md`, `tests/scenarios/query-discovery.md`, `tests/README.md` |

T4 і T5 обидва торкаються `SKILL.md` — їх ставити в РІЗНІ хвилі або злити в
одну задачу.

## Тести

1. `tests/skill-contracts.sh` вимагає поле `Крихталізація:` у строгому шаблоні
   і **не** знаходить `Автоматизував:` ніде в `references/`.
2. Негативні гарди (`set_skill_link`, `writing-skills`, `🧹`) лишаються
   зеленими — тобто не видалені.
3. `grep -rn 'state == "active"' references/` → нуль влучань.
4. `grep -rn 'protected' references/` → влучання лишаються (живе поле не
   зачепили).
5. version-assert бачить `4.7.0`; `wiki_version` у
   `references/operation-init.md` і далі `"4.0"`.
6. Наявні кейси всіх чотирьох сюїт лишаються зеленими.

## Поза скоупом

- Автоматизація періодичного нуджа через PostToolUse-лічильник (вердикт `r7`).
- Видалення `state` / `archived_at` із записів `.usage.json` (вердикт `r3`).
- Будь-яка зміна `hooks/`, інсталяторів, discovery, boundary-guard.
- Редагування історичних `docs/specs/` і `docs/plans/` (вердикт `r5`).
- Об'єднання `Зберіг у wiki:` і `Крихталізація:` (вердикт `r2`).

## Done-when

`bash tests/hooks/run.sh && bash tests/skill-contracts.sh && bash
tests/install-cross-agent-links.sh && bash tests/uninstall.sh` — зелено;
`grep -rn 'Автоматизував' references/ SKILL.md` → нуль влучань;
`grep -rn 'state == "active"' references/` → нуль влучань.
