# Scenario: `wiki status` operation (manual pull-model)

Single scenario that exercises the `## Operation: Wiki Status` section in
`references/operation-wiki-status.md`. Sets up a v4-shaped mock wiki with mixed activity (hot/cold/protected
pages, one cross-ref drift, one schema drift), triggers `wiki status`, and
verifies the structured display + action menu behave per spec section 6.

This is a meta-operation: the test also verifies that **no telemetry counters
are incremented** for the surveyed pages, and **no РЕФЛЕКСІЯ block** is
emitted (anti-noise rule).

## Setup

Mock wiki state:

- `docs/wiki/schema.md` — frontmatter `wiki_version: "4.0"` (state: `current`).
  `## Document Types` section declares `category` values: `services`,
  `components`, `documents`. (No `legacy` category — that's the schema-drift
  trap.)
- `docs/wiki/index.md` — lists all pages below.
- `docs/wiki/log.md` — empty stub.
- `.gitignore` contains `docs/wiki/.usage.json`.

Pages on disk:

```
docs/wiki/concepts/
  purchase-flow.md          (hot — high view_count)
  intake-stock.md           (hot — high view_count + recent edits)
  dose-dimensions.md        (central — high use_count)
  course-builder.md         (drift-risk — high patch_count)
  secret-rotation-recipe.md (cold but protected)
docs/wiki/entities/
  services/
    auth-service.md         (legitimate)
  legacy/                                 ← schema drift!
    old-service.md          (frontmatter category="legacy" — not in schema.md)
docs/wiki/transcripts/
  2026-04-12-design-call.md (one transcript)
```

Plus `docs/wiki/concepts/old-auth-middleware.md` containing the body line:

```
See [[middleware-rules]] for the routing details.
```

…but `docs/wiki/concepts/middleware-rules.md` does not exist on disk →
**cross-ref drift**.

`archive/` contains 3 binary files (PDFs, all referenced by entity pages —
no orphans).

`docs/wiki/.usage.json` (mocked):

```json
{
  "concepts/purchase-flow.md": {
    "view_count": 15, "use_count": 4, "patch_count": 1,
    "last_viewed_at": "2026-04-30T10:00:00Z",
    "last_used_at":   "2026-04-25T09:00:00Z",
    "last_patched_at":"2026-03-15T14:00:00Z",
    "created_at":     "2026-01-10T08:00:00Z",
    "state": "active", "protected": false, "archived_at": null
  },
  "concepts/intake-stock.md": {
    "view_count": 12, "use_count": 3, "patch_count": 3,
    "last_viewed_at": "2026-04-30T11:00:00Z",
    "last_used_at":   "2026-04-28T09:00:00Z",
    "last_patched_at":"2026-04-29T13:00:00Z",
    "created_at":     "2026-01-12T08:00:00Z",
    "state": "active", "protected": false, "archived_at": null
  },
  "concepts/dose-dimensions.md": {
    "view_count": 6, "use_count": 8, "patch_count": 2,
    "last_viewed_at": "2026-04-29T12:00:00Z",
    "last_used_at":   "2026-04-30T08:00:00Z",
    "last_patched_at":"2026-04-20T10:00:00Z",
    "created_at":     "2026-02-01T08:00:00Z",
    "state": "active", "protected": false, "archived_at": null
  },
  "concepts/course-builder.md": {
    "view_count": 4, "use_count": 1, "patch_count": 5,
    "last_viewed_at": "2026-04-28T10:00:00Z",
    "last_used_at":   "2026-04-15T09:00:00Z",
    "last_patched_at":"2026-04-30T15:00:00Z",
    "created_at":     "2026-03-01T08:00:00Z",
    "state": "active", "protected": false, "archived_at": null
  },
  "concepts/secret-rotation-recipe.md": {
    "view_count": 0, "use_count": 0, "patch_count": 1,
    "last_viewed_at": null,
    "last_used_at":   null,
    "last_patched_at":"2026-02-10T14:00:00Z",
    "created_at":     "2026-02-10T14:00:00Z",
    "state": "active", "protected": true, "archived_at": null
  },
  "concepts/old-auth-middleware.md": {
    "view_count": 1, "use_count": 0, "patch_count": 1,
    "last_viewed_at": "2026-04-01T09:00:00Z",
    "last_used_at":   null,
    "last_patched_at":"2026-04-01T09:00:00Z",
    "created_at":     "2026-04-01T09:00:00Z",
    "state": "active", "protected": false, "archived_at": null
  },
  "entities/services/auth-service.md": {
    "view_count": 2, "use_count": 1, "patch_count": 1,
    "last_viewed_at": "2026-04-20T10:00:00Z",
    "last_used_at":   "2026-04-20T10:00:00Z",
    "last_patched_at":"2026-04-20T10:00:00Z",
    "created_at":     "2026-04-20T10:00:00Z",
    "state": "active", "protected": false, "archived_at": null
  },
  "entities/legacy/old-service.md": {
    "view_count": 0, "use_count": 0, "patch_count": 1,
    "last_viewed_at": null,
    "last_used_at":   null,
    "last_patched_at":"2026-01-05T08:00:00Z",
    "created_at":     "2026-01-05T08:00:00Z",
    "state": "active", "protected": false, "archived_at": null
  },
  "transcripts/2026-04-12-design-call.md": {
    "view_count": 1, "use_count": 0, "patch_count": 1,
    "last_viewed_at": "2026-04-12T15:00:00Z",
    "last_used_at":   null,
    "last_patched_at":"2026-04-12T15:00:00Z",
    "created_at":     "2026-04-12T15:00:00Z",
    "state": "active", "protected": false, "archived_at": null
  }
}
```

## Trigger

User says: `wiki status`.

(Equivalent triggers: `вікі статус`, `як справи у вікі`, `огляд wiki`.)

## Expected skill behavior

1. Step 0 reads `schema.md` → `wiki_version: "4.0"` → state = `current`.
2. Read `.usage.json` (full dict — no individual `Read` of any wiki page yet).
3. Count files per layer:
   - concepts: 6 pages
   - entities: 2 pages (1 in `services/`, 1 in `legacy/`)
   - transcripts: 1 page
   - total: 9
4. Count binaries in `archive/`: 3.
5. Compute rankings:
   - **Top by view_count**: `[[purchase-flow]]` (15), `[[intake-stock]]` (12)
   - **Top by use_count**: `[[dose-dimensions]]` (8), `[[purchase-flow]]` (4)
   - **Top by patch_count**: `[[course-builder]]` (5), `[[intake-stock]]` (3)
6. List protected: `[[secret-rotation-recipe]]` (only one).
7. Detect passive issues:
   - **Cross-ref drift**: `[[old-auth-middleware]]` body links to
     `[[middleware-rules]]` — target file does not exist.
   - **Schema drift**: `[[old-service]]` frontmatter `category: legacy` —
     `legacy` is not declared in `schema.md` `## Document Types`.
8. Print structured display (see expected output below).
9. Wait for user choice from action menu.

## Expected output

```
📊 Wiki Status — docs/wiki/

Версія: 4.0 (актуальна)
Сторінок: 9 (concepts: 6, entities: 2, transcripts: 1)
Прив'язаних бінарних файлів у archive/: 3

Активність (з .usage.json):
  Найчастіше консультуються:  [[purchase-flow]] (15 view), [[intake-stock]] (12)
  Найбільш цитуються:         [[dose-dimensions]] (8 use), [[purchase-flow]] (4)
  Найбільш редагуються:       [[course-builder]] (5 patch), [[intake-stock]] (3)

Захищені:
  • [[secret-rotation-recipe]]

⚠️ Знайдено пасивно:
  • Cross-ref drift: [[old-auth-middleware]] → [[middleware-rules]] (видалено)
  • Schema drift: [[old-service]] використовує category="legacy" (нема в schema.md)

──────────────────────────────────────────
🔍 Хочеш зробити content-check (LLM читає сторінки, верифікує claims)?

  [a] Топ-5 найбільш редагованих (drift risk найвищий)
  [b] Топ-5 найдовше unverified (нема recent edit'у — claims могли застаріти)
  [c] Конкретні сторінки — вкажи [[page-names]]
  [пасивні fix'и]:
    [1] cross-ref у [[old-auth-middleware]]
    [2] schema-drift у [[old-service]]
  [n] нічого
```

## Manual verification

### Telemetry — counters NOT incremented

Diff `.usage.json` before vs after the `wiki status` invocation:

- `view_count` on every record is unchanged. The agent did `Read(.usage.json)`,
  which is sidecar bookkeeping, not a wiki-page consultation.
- `use_count`, `patch_count`, `last_*_at` — unchanged for all records.
- No new keys appear, no keys are removed.

This is the meta-operation contract from `SKILL.md`:

> `wiki status` itself does NOT bump `view_count` for surveyed pages. Reading
> `.usage.json` and counting page files is bookkeeping, not consultation.

### Reflection — no РЕФЛЕКСІЯ block emitted

Search the assistant turn for the string `📚 РЕФЛЕКСІЯ` → must return zero
matches. `wiki status` is read-only at the meta-level (no `Edit`, no `Write`,
no side-effecting `Bash`); the anti-noise rule applies.

### Action menu — items reachable

For each menu choice, the next user reply routes to the documented operation:

| Reply | Expected next-turn behavior |
|---|---|
| `a` | Delegate to `## Operation: Lint` content-verification with `[[course-builder]], [[intake-stock]], [[dose-dimensions]], [[purchase-flow]], [[old-auth-middleware]]` (top 5 by patch_count desc) |
| `b` | Delegate to `## Operation: Lint` content-verification with the 5 pages whose `last_patched_at` is oldest among `state == "active"` and `protected == false` — i.e. `[[old-service]]` (Jan 5), `[[purchase-flow]]` (Mar 15), `[[auth-service]]` (Apr 20)... (`secret-rotation-recipe` skipped because protected) |
| `c [[purchase-flow]]` | Delegate to Lint content-verification with that exact page set |
| `1` | Apply passive fix: edit `concepts/old-auth-middleware.md`, remove or replace the broken `[[middleware-rules]]` link. Bumps `patch_count` for `old-auth-middleware.md` (this is a real edit, not a meta-op). |
| `2` | Apply passive fix: either move `entities/legacy/old-service.md` into a valid category, or propose adding `legacy` to `schema.md` `## Document Types`. Bumps `patch_count` for whichever file ends up modified. |
| `n` | Print "OK, нічого не зроблено" and end the operation. No further state change. |

### Page protection

`[[secret-rotation-recipe]]` appears under `Захищені:` and is **excluded** from
the `[b]` "Top-5 longest unverified" candidate list, even though its
`last_patched_at` is 2026-02-10 (one of the oldest). Pin acts as a hard fence
against content-verification proposals.

### Output structure stays predictable

If `Захищені:` were empty, the section header would still print with the
fallback `«жодних — ще нічого не захищено»`. Same shape applies to the
passive-issues section. The structural skeleton of the output is invariant
across runs — only content varies.

## Edge cases (out of scope but documented)

- **Corrupt `.usage.json`** → tolerance rule: treat as `{}`. The activity
  rankings section then prints `«нічого — телеметрія порожня»` as the
  fallback. Page counts still come from filesystem scan.
- **No wiki yet** (`docs/wiki/` doesn't exist) → Step 0 catches this; skill
  redirects to `## Operation: Init` instead of running status.
- **Wiki version mismatch** (e.g. `wiki_version: "3.0"`) → Step 0 catches this;
  skill prompts for migration before any status logic runs.
