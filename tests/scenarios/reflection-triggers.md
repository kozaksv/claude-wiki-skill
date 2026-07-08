# Scenario: РЕФЛЕКСІЯ block triggers

Four sub-scenarios that exercise the trigger table and anti-noise rule defined in
`references/reflection.md`. Each runs against a v4-shaped test wiki and
asserts whether a РЕФЛЕКСІЯ block was emitted (and what its `trigger:` line says).

## Common setup

Mock wiki state (shared by all sub-scenarios):

- `docs/wiki/schema.md` with `wiki_version: "4.0"` frontmatter (current state)
- `docs/wiki/index.md`, `docs/wiki/log.md`, `docs/wiki/.usage.json` present
- `docs/wiki/concepts/purchase-flow.md` and `docs/wiki/concepts/intake-stock.md` exist
- `.gitignore` contains `docs/wiki/.usage.json`

The "agent" in these scenarios is the active Claude/Codex/Gemini session running
the wiki skill. The expected output is the РЕФЛЕКСІЯ block (or its absence) —
verified by inspection of the turn's final assistant message.

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
```

### Manual verification

- The block appears immediately before the assistant says "running git commit".
- The `trigger:` line says `pre-commit`.
- The `Перевірив:` section is present (because `index.md` / `log.md` / `.usage.json`
  were structural files touched).
- The block ends on `Перевірив:` — no trailing interrogation, no embedded
  confirm-prompt emoji, no `[y]/[n]` menu. Since this session has no passive
  drift signal (see Sub-scenario 4 for the drift-present variant), no `⚠️`
  pointer line follows either.

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
```

### Manual verification

- `trigger:` line says `todo-completion` (not `pre-commit`).
- "Чому це краще" line is **omitted** — because "Дізнався" reported no new insight,
  the field rule says drop the explanation line entirely.
- The `Перевірив:` section appears because `index.md` and `log.md` were touched.
- The block ends on `Перевірив:` — no trailing interrogation, no embedded
  confirm-prompt emoji, no `[y]/[n]` menu. The passive drift notice
  (`⚠️ Вікі: ...`) never appears here either, regardless of drift state — it is
  reserved for `trigger: pre-commit` only (see Sub-scenario 4).

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
**should** fire as an explicit synthesis-write, with `trigger: explicit` unless
the same turn is already covered by a stronger hard event such as
`todo-completion` or `pre-commit`.

---

## Sub-scenario 4: Pre-commit trigger with passive drift notice

### Setup

Same as Sub-scenario 1 (pre-commit trigger fires, РЕФЛЕКСІЯ block emitted),
plus one passive drift signal already present in the mock wiki: the body of
`docs/wiki/concepts/intake-stock.md` contains `[[old-discount-model]]`, and
`docs/wiki/concepts/old-discount-model.md` does not exist on disk (a dead
cross-ref — the same cheap, no-LLM-read signal `wiki status` computes).

### Trigger

The agent is at the end of an Ingest-Source, about to commit, and emits the
РЕФЛЕКСІЯ block. This is a `trigger: pre-commit` turn, and a passive drift
signal exists.

### Expected skill behavior

Because this is `trigger: pre-commit` AND a passive drift signal is present,
the block gets a single non-interactive pointer line appended after
`Автоматизував:` (or `Перевірив:` when present):

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
⚠️ Вікі: 1 пасивних дрифт-сигналів — запусти `wiki status` для деталей
```

### Manual verification

- The `⚠️` line is the **only** possible tail on a reflection block — it is
  non-interactive: no `[y]/[n]`, no menu, nothing awaiting a reply. It names
  `wiki status` as the place to act; it does not itself show a list, apply a
  fix, or mutate anything.
- Search the block for the old interactive confirm-prompt emoji → must return
  zero matches. That interactive `[y]/[n]` tail no longer exists anywhere in
  the skill's output.
- The `⚠️` line fires **only** when both conditions hold: `trigger: pre-commit`
  AND at least one passive drift signal exists. Contrast with:
  - Sub-scenario 1 (`trigger: pre-commit`, no drift signal in that setup) →
    no `⚠️` line, block ends on `Перевірив:`.
  - Sub-scenario 2 (`trigger: todo-completion`) → no `⚠️` line ever, even if
    the same drift signal were present — non-pre-commit triggers never show
    it.
- The `⚠️` line MUST NOT appear at the end of a Lint run, a `wiki status` run,
  or any cleanup-flow run — those already end on their own report (see
  `references/cleanup-flow.md` → "Anti-recursion rule (hard), re-scoped").
