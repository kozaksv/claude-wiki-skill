# Scenario: РЕФЛЕКСІЯ block triggers

Four sub-scenarios that exercise the trigger table and anti-noise rule defined in
`SKILL.md` → `## Self-Improvement Loop`. Each runs against a v4-shaped test wiki and
asserts whether a РЕФЛЕКСІЯ block was emitted (and what its `trigger:` line says).

## Common setup

Mock wiki state (shared by all sub-scenarios):

- `docs/wiki/schema.md` with `wiki_version: "4.0"` frontmatter (current state)
- `docs/wiki/index.md`, `docs/wiki/log.md`, `docs/wiki/.usage.json` present
- `docs/wiki/concepts/purchase-flow.md` and `docs/wiki/concepts/intake-stock.md` exist
- `.gitignore` contains `docs/wiki/.usage.json`

The "agent" in these scenarios is the wiki skill instructing Claude. The expected
output is the РЕФЛЕКСІЯ block (or its absence) — verified by inspection of the turn's
final assistant message.

---

## Sub-scenario 1: Pre-commit trigger

### Setup

- A new spec file `specs/2026-05-01-pricing.md` exists.
- Both `purchase-flow.md` and `intake-stock.md` will be edited during ingest.

### Trigger

User says: "ingest specs/2026-05-01-pricing.md and then commit". The agent runs
Ingest-Source, edits both pages, updates `index.md` + `log.md`, then prepares to
run `git commit`.

### Expected skill behavior

1. Step 0 reads schema.md → state = `current`, continue.
2. Ingest-Source executes: reads pages, edits two concept pages, updates `index.md`
   and `log.md`, bumps telemetry.
3. Just before `git commit` (the pre-commit moment), the agent emits a РЕФЛЕКСІЯ
   block.

### Expected output (РЕФЛЕКСІЯ block)

```
📚 РЕФЛЕКСІЯ — 2026-05-01 14:32 — trigger: pre-commit

Дізнався: knowing prices live as a separate variant attribute clarifies why receive-flow doesn't recompute discounts.
Чому це краще: discount logic stays inside the purchase document, variants stay clean — fewer cross-cutting concerns.
Зберіг у wiki: [[purchase-flow]], [[intake-stock]]
Автоматизував: нічого — операція разова

Перевірив:
  ✅ index.md — entries для двох сторінок не змінились (були вже актуальні)
  ✅ log.md — додано "## [2026-05-01] ingest | pricing-spec"
  ✅ .usage.json — bump_patch для двох сторінок, bump_use для нових wikilinks

──────────────────────────────────────────
🧹 Показати список того, що в wiki могло застаріти?
   Я лише покажу — нічого не змінюватиму без твого слова.
   [y] показати  /  [n] продовжуємо
```

### Manual verification

- The block appears immediately before the assistant says "running git commit".
- The `trigger:` line says `pre-commit`.
- The `Перевірив:` section is present (because `index.md` / `log.md` / `.usage.json`
  were structural files touched).

---

## Sub-scenario 2: TodoWrite-completion trigger

### Setup

- TodoWrite has three todos: "read spec", "update purchase-flow", "update index".
- Agent works through them, marking each `completed` in turn.

### Trigger

The agent marks the **last** todo (`update index`) as `completed`. No `git commit`
follows — the user just wants to stop here.

### Expected skill behavior

1. Last todo flips to `completed` → hard event.
2. The agent emits a РЕФЛЕКСІЯ block in the same turn (after the TodoWrite update,
   before the natural-language wrap-up).

### Expected output (РЕФЛЕКСІЯ block)

```
📚 РЕФЛЕКСІЯ — 2026-05-01 14:45 — trigger: todo-completion

Дізнався: нічого нового — стандартна реалізація за патерном [[purchase-flow]].
Зберіг у wiki: [[purchase-flow]]
Автоматизував: нічого — операція разова

Перевірив:
  ✅ index.md — оновлено опис [[purchase-flow]]
  ✅ log.md — додано запис

──────────────────────────────────────────
🧹 Показати список того, що в wiki могло застаріти?
   Я лише покажу — нічого не змінюватиму без твого слова.
   [y] показати  /  [n] продовжуємо
```

### Manual verification

- `trigger:` line says `todo-completion` (not `pre-commit`).
- "Чому це краще" line is **omitted** — because "Дізнався" reported no new insight,
  the field rule says drop the explanation line entirely.
- The `Перевірив:` section appears because `index.md` and `log.md` were touched.

### Deduplication note

If the user immediately follows with `git commit` (within ~60 seconds), the agent
must **not** emit a second block for the pre-commit trigger. One block, deduplicated.

---

## Sub-scenario 3: Anti-noise (read-only block, no reflection)

### Setup

- User asks a question. Agent runs Query operation only — reads `index.md`,
  reads `purchase-flow.md`, synthesizes answer, does NOT file back.
- No `Edit`, no `Write`, no side-effecting `Bash`.

### Trigger

User says: "що каже wiki про purchase flow?"

### Expected skill behavior

1. Step 0 reads schema.md → state = `current`.
2. Query reads `index.md`, reads `purchase-flow.md`, calls `bump_view` on both
   (telemetry update is read-bookkeeping, NOT a wiki page edit).
3. Agent synthesizes the answer, returns it to user.
4. **No РЕФЛЕКСІЯ block is emitted** — anti-noise rule applies.

### Expected output

A regular synthesis answer with `[[purchase-flow]]` citation. **No** `📚 РЕФЛЕКСІЯ`
header anywhere in the turn.

### Manual verification

- Search the assistant turn for the string `📚 РЕФЛЕКСІЯ` → must return zero matches.
- The `bump_view` mutation against `.usage.json` did happen (verifiable in the
  sidecar diff), but mutating telemetry alone does not count as a "wiki page edit"
  for reflection purposes — telemetry is bookkeeping under the anti-noise rule.

### Edge case: Query that files back

If during Query the agent decides the synthesis is reusable and creates a new wiki
page (Filing Back), that turns the operation into a synthesis-write. Reflection
**should** fire, with `trigger:` matching whatever event ends the turn (typically
`todo-completion` if the question was tracked as a todo, otherwise the agent waits
for a hard event and only fires at that point — Filing Back alone does not fire
reflection without a paired hard trigger).

---

## Sub-scenario 4: Cleanup-prompt embedded

### Setup

Same as Sub-scenario 1 (pre-commit trigger fires, РЕФЛЕКСІЯ block emitted).

### Trigger

The agent is at the end of an Ingest-Source, about to commit, and emits the
РЕФЛЕКСІЯ block.

### Expected skill behavior

The block ends with the embedded cleanup-prompt:

```
──────────────────────────────────────────
🧹 Показати список того, що в wiki могло застаріти?
   Я лише покажу — нічого не змінюватиму без твого слова.
   [y] показати  /  [n] продовжуємо
```

### Expected agent behavior on each user response

| User reply | Agent action |
|---|---|
| `y` | Show a list of candidates (top-N by drift signal from `.usage.json`, plus passive findings like cross-ref drift). **No** edits, deletions, or modifications applied. Each candidate is informational; user must explicitly request action on any of them in a follow-up message. |
| `n` | Continue the conversation normally; reflection block is closed. |
| (no reply within the turn) | Treat as `n`. Do not block waiting; do not re-prompt. |

### Manual verification

- The horizontal-rule line (`──────────────────────────────────────────`) appears
  immediately above the cleanup-prompt — the prompt is part of the same block, not
  a separate utterance.
- On `y`, the next turn shows ONLY a list — no `Edit` / `Write` tool calls fire.
- On `n` or silence, the conversation moves on; no further reflection-related
  output appears until the next trigger event.

### Safety contract

The cleanup-prompt is the wiki skill's only place where a single keypress (`y`)
might lead toward destructive action — and even then, it stops at "show a list".
Actual `видали` / `merge` / `розбий` actions still require explicit, separate
instructions from the user. This is the safety boundary: reflection observes,
the user directs.
