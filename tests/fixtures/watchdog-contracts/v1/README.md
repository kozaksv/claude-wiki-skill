# Watchdog W1: контрактні сценарії v1

Статус: **чернетка для рев’ю**. [Основна спека W1](../../../../docs/specs/2026-10-25-wiki-watchdog-w1-contracts.md) · [RFC v5 #21](https://github.com/kozaksv/claude-wiki-skill/issues/21) · [GO-рев’ю #23](https://github.com/kozaksv/claude-wiki-skill/issues/23#issuecomment-6393600114).

`contract-cases.json` містить 70 синтетичних сценаріїв спільних контрактів. Це design vectors із заданими вхідними умовами та очікуваними результатами. Вони не є знятими hook payload, готовим Rust test runner або доказом роботи адаптера. Номери AC посилаються на незмінну матрицю RFC v5; один сценарій не закриває весь AC.

## Формат

Кожний case має унікальний `id`, `contract` (C01–C12 у спеці), `owners`, `acceptance`, назву `scenario`, умови `input` та постумови `expected`. Ключі `input` описують fixture setup; це не копія wire envelope `NormalizedEventV1`. Майбутні component tests мають побудувати справжні нормалізовані об’єкти за цими умовами й виконати компонент. Не можна перевірити лише відповідність очікуваного результату самому собі та назвати це runtime acceptance.

Git OIDs, scopes, event IDs, матеріали A/B, B/A/S у rotation та назви станів тут символічні. Тестовий стенд створює відповідні Git commits/files та події. `given` і `steps` у ANCHOR cases задають початковий стан і послідовність дій; capabilities на вході задаються явно. У неперевіреного реального адаптера такі capabilities не вважаються доступними.

Довгі однорідні рядки записані компактно як `text_recipe` / `prefix_text_recipe`: об’єкти `{"repeat": "😀", "count": 5000}` та `{"literal": " USE_WAL"}` розгортаються в заданому порядку і конкатенуються. `count` — число повторів цілого `repeat`; це лише формат синтетичних даних. Розгортання не застосовує Unicode normalization. Поле `raw_json_string_escape` у malformed-case є буквальним фрагментом тестового JSON, не валідним Unicode-текстом джерела.

## Групи

| IDs | Контракт / основний виконавець |
|---|---|
| ED-01–ED-08 | Два instruction profiles, незалежна wiki schema, генерація — W1/W6 |
| EV-01–EV-06 | Події, scope, replay, read coverage, discovery/protection — W2/W3/W4 |
| ST-01–ST-09 | Потреби, Stop, caps, compact/aging, generation — W2/W3 |
| EX-01–EX-03 | Classic import/export та overlap — W4 |
| LOG-01–LOG-03 | Log receipt, ротація, невідомий результат — W5 |
| ACT-01–ACT-02 | Lifecycle/health — W6 |
| API-01 | Резерви, retries та unknown cost — W10 через W2 |
| ANCHOR-01–ANCHOR-19 | До-змінна Git-база та per-path receipts — W2/W5 |
| CF01–CF14 | Спільний bounded fragment, Unicode/джерела — W2 та споживачі |
| CB01–CB05 | AGY compaction/tool-loop delivery boundary — W3/W9 |

## Межі перевірки

Під час підготовки цього PR перевіряються лише JSON, цілісність IDs/посилань та арифметика явних Unicode прикладів. Поведінку Rust/SQLite/адаптерів треба реалізувати й перевірити у відповідних сабепіках. W1 ще потребує погодження контрактів і мінімального build/CI scaffold для двох instruction profiles.

Справжні AGY captures лишаються окремими: [PR #22, snapshot 53dbd68](https://github.com/kozaksv/claude-wiki-skill/tree/53dbd68cf67108bf4546e45f972f310b75bf66c7/tests/fixtures/agy-1.4.7). Вони не доводять full long-final tail, успішний edit, ранню видимість parent result або всі compact/branch/share сценарії. Синтетичний prefix-case CF09 лише демонструє очікувану обробку неповноти та не домальовує відсутній хвіст.
