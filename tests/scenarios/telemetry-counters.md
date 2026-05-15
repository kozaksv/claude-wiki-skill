# Scenario: Telemetry counters (.usage.json)

Three sub-scenarios that exercise the `bump_view` / `bump_patch` / `bump_use` mutators
described in `references/telemetry.md`. Each runs against a v4-shaped
test wiki and asserts the diff in `docs/wiki/.usage.json` after the trigger.

## Common setup

Mock wiki state (shared by all three sub-scenarios):

- `docs/wiki/schema.md` with `wiki_version: "4.0"` frontmatter (current state)
- `docs/wiki/concepts/purchase-flow.md` exists with body referencing files in code
- `docs/wiki/concepts/intake-stock.md` exists, body does NOT contain `[[purchase-flow]]`
- `docs/wiki/index.md` lists both pages
- `docs/wiki/.usage.json` exists with `{}` (empty dict)
- `.gitignore` contains `docs/wiki/.usage.json`

Treat "now" in expectations as ISO 8601 UTC at the moment of the trigger.

---

## Sub-scenario 1: View increment (Query reads a page)

### Trigger

User says: "що каже wiki про purchase-flow"

### Expected skill behavior

1. Step 0 reads schema.md → state = `current`, continue.
2. Operation: Query.
3. Skill reads `docs/wiki/index.md` (NOT a wiki page — index is navigation, not counted).
4. Skill reads `docs/wiki/concepts/purchase-flow.md` via the `Read` tool → page consulted.
5. Skill synthesizes answer, no edit performed.
6. Skill calls `bump_view("concepts/purchase-flow.md")` against `.usage.json`.

### Expected `.usage.json` diff

Before: `{}`

After:

```json
{
  "concepts/purchase-flow.md": {
    "view_count": 1,
    "use_count": 0,
    "patch_count": 0,
    "last_viewed_at": "<now>",
    "last_used_at": null,
    "last_patched_at": null,
    "created_at": "<now>",
    "state": "active",
    "protected": false,
    "archived_at": null
  }
}
```

Note: record didn't exist before, so `bump_view` created it with all ten fields.
`created_at` is set on first record creation (not on first patch only — any first
mutator creates the record).

### Manual verification

```bash
jq '."concepts/purchase-flow.md".view_count' docs/wiki/.usage.json
# expected: 1
jq '."concepts/purchase-flow.md".last_viewed_at' docs/wiki/.usage.json
# expected: ISO timestamp roughly equal to trigger time
jq '."concepts/purchase-flow.md".patch_count' docs/wiki/.usage.json
# expected: 0
```

---

## Sub-scenario 2: Patch increment (Ingest-Source edits a page)

### Trigger

User says: "ingest this gotcha into purchase-flow: discount stacking now allows per-item override"

### Expected skill behavior

1. Step 0 → state = `current`, continue.
2. Operation: Ingest-Source.
3. Skill reads `docs/wiki/index.md`, then reads `docs/wiki/concepts/purchase-flow.md` (Step 2 + Step 3 of the operation) → that's a `bump_view`.
4. Skill edits `docs/wiki/concepts/purchase-flow.md` to add the new gotcha → `Edit` tool fires.
5. Skill appends entry to `docs/wiki/log.md`.
6. Step 7 of Ingest-Source: telemetry update.
   - `bump_view("concepts/purchase-flow.md")` (read in step 3)
   - `bump_patch("concepts/purchase-flow.md")` (edited in step 4)
   - No new `[[wikilinks]]` added in this scenario, so no `bump_use`.

### Expected `.usage.json` diff

Before: `{}` (or any state — this sub-scenario is independent; assume fresh)

After:

```json
{
  "concepts/purchase-flow.md": {
    "view_count": 1,
    "use_count": 0,
    "patch_count": 1,
    "last_viewed_at": "<now>",
    "last_used_at": null,
    "last_patched_at": "<now>",
    "created_at": "<now>",
    "state": "active",
    "protected": false,
    "archived_at": null
  }
}
```

### Manual verification

```bash
jq '."concepts/purchase-flow.md".patch_count' docs/wiki/.usage.json
# expected: 1
jq '."concepts/purchase-flow.md".last_patched_at' docs/wiki/.usage.json
# expected: ISO timestamp roughly equal to trigger time
jq '."concepts/purchase-flow.md".view_count' docs/wiki/.usage.json
# expected: 1 (the read that preceded the edit)
```

---

## Sub-scenario 3: Use increment (new wikilink added)

### Setup adjustment

Same as Common setup, but additionally pre-populate `.usage.json` with an existing
record for `intake-stock.md` (so we can verify increment vs. create-from-zero):

```json
{
  "concepts/intake-stock.md": {
    "view_count": 3,
    "use_count": 5,
    "patch_count": 2,
    "last_viewed_at": "2026-04-30T10:00:00Z",
    "last_used_at": "2026-04-25T09:00:00Z",
    "last_patched_at": "2026-04-28T12:00:00Z",
    "created_at": "2026-04-01T08:00:00Z",
    "state": "active",
    "protected": false,
    "archived_at": null
  }
}
```

### Trigger

User says: "додай у purchase-flow посилання на intake-stock — там описаний наступний крок"

### Expected skill behavior

1. Step 0 → state = `current`, continue.
2. Operation: Ingest-Source (or direct edit, same telemetry rules apply).
3. Skill reads `docs/wiki/concepts/purchase-flow.md` → `bump_view("concepts/purchase-flow.md")`.
4. Skill edits `docs/wiki/concepts/purchase-flow.md` to add `[[intake-stock]]` somewhere in the body → `bump_patch("concepts/purchase-flow.md")`.
5. Telemetry rule for `bump_use`: a new `[[wikilink]]` to `concepts/intake-stock.md` was added → `bump_use("concepts/intake-stock.md")`.

### Expected `.usage.json` diff

For `concepts/intake-stock.md` only the use fields change (other fields preserved):

```json
{
  "concepts/intake-stock.md": {
    "view_count": 3,
    "use_count": 6,
    "patch_count": 2,
    "last_viewed_at": "2026-04-30T10:00:00Z",
    "last_used_at": "<now>",
    "last_patched_at": "2026-04-28T12:00:00Z",
    "created_at": "2026-04-01T08:00:00Z",
    "state": "active",
    "protected": false,
    "archived_at": null
  }
}
```

A new record for `concepts/purchase-flow.md` is also added with `view_count: 1`,
`patch_count: 1`, `use_count: 0` (it was the page we edited, not the page we cited).

### Manual verification

```bash
jq '."concepts/intake-stock.md".use_count' docs/wiki/.usage.json
# expected: 6 (was 5)
jq '."concepts/intake-stock.md".last_used_at' docs/wiki/.usage.json
# expected: ISO timestamp roughly equal to trigger time
jq '."concepts/intake-stock.md".view_count' docs/wiki/.usage.json
# expected: 3 (unchanged)
jq '."concepts/intake-stock.md".created_at' docs/wiki/.usage.json
# expected: "2026-04-01T08:00:00Z" (unchanged)
```

---

## Tolerance assertions (cross-cutting)

The following tolerance behaviors apply across all three sub-scenarios — verify
once when wiring telemetry into the skill:

- **Corrupt `.usage.json`** — replace file body with `not-json` before the trigger.
  Skill must read it as `{}`, perform the operation, and write a fresh dict
  containing only the new record. The wiki operation MUST succeed.
- **Read-only `.usage.json`** — `chmod 444` before the trigger. Skill must complete
  the wiki operation, log a warning, and NOT raise. Counters stay at their
  pre-trigger values.
- **Missing field on existing record** — pre-populate `.usage.json` with a record
  missing `protected` (legacy v4.0 record). On read, skill backfills `protected: false`
  silently and proceeds.
