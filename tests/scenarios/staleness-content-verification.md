# Scenario: Lint staleness as Karpathy content-verification

Three sub-scenarios that exercise the reformulated `## Operation: Lint`
staleness check (#1) in `SKILL.md`. The check is no longer timestamp-based;
it proposes a subset for verification, reads selected pages in full, verifies
claims, and reports findings without auto-flagging. Захищені pages are
**always** skipped by content-verification proposals. Cross-ref drift and
other passive issues need NO LLM read — pure grep.

The three sub-scenarios cover:

1. **Content-verification flags a deleted source** (active LLM read, claim
   fails)
2. **Захищені page is never proposed for verification** (protect fence holds)
3. **Cross-ref drift is detected passively** (no LLM read, pure grep)

---

## Sub-scenario 1: Source-existing claim fails on read

A page lists a source under `## Sources` that no longer exists on disk.
Content-verification reads the page, verifies the source path, finds it
deleted, and proposes an action.

### Setup

Mock wiki state:

- `docs/wiki/schema.md` — `wiki_version: "4.0"`.
- `docs/wiki/index.md` — lists `[[purchase-flow]]`.
- `docs/wiki/concepts/purchase-flow.md`:

  ```markdown
  # Purchase Flow

  Multi-step purchase → receive → inventory creation flow.

  ## Sources
  - `docs/superpowers/specs/2025-12-01-purchase-receive.md`
  - `apps/api/src/routes/purchases.ts`
  ```

- `apps/api/src/routes/purchases.ts` exists.
- `docs/superpowers/specs/2025-12-01-purchase-receive.md` **does not exist**
  (the spec file was deleted/renamed).

`docs/wiki/.usage.json`:

```json
{
  "concepts/purchase-flow.md": {
    "view_count": 3, "use_count": 2, "patch_count": 4,
    "last_viewed_at": "2026-04-30T10:00:00Z",
    "last_used_at":   "2026-04-25T09:00:00Z",
    "last_patched_at":"2026-04-30T15:00:00Z",
    "created_at":     "2026-01-10T08:00:00Z",
    "state": "active", "protected": false, "archived_at": null
  }
}
```

### Trigger

User: `wiki lint` → picks `[a] Top-5 most edited` from the verification menu.

### Expected skill behavior

1. Sort `report()` by `patch_count desc, last_patched_at asc`. Filter to
   `state == "active"` and `protected == false`. Top entry: `purchase-flow.md`
   (only candidate here).
2. **Read** `concepts/purchase-flow.md` in full → bumps `view_count` to 4
   (this is a real consultation, not a meta-op).
3. Verify each claim:
   - `## Sources` line 1: `docs/superpowers/specs/2025-12-01-purchase-receive.md`
     → file does NOT exist on disk. **Claim fails.**
   - `## Sources` line 2: `apps/api/src/routes/purchases.ts` → file exists.
     **Claim holds.**
4. Report:

   ```
   ### Verified (content-verification subset: [a])
   - [[purchase-flow]] — `## Sources` references deleted file
     `docs/superpowers/specs/2025-12-01-purchase-receive.md` → propose DELETE
     this source line. Other claims hold.
   ```

5. **Do not silently rewrite the page.** Wait for user to choose
   `глянь і онови`, `видали`, `залиш як є`, or `захисти`.

### Manual verification

- The skill did **not** flag the page based on `last_patched_at` value alone;
  it sorted by patch_count first, then read content.
- `view_count` on `purchase-flow.md` is `4` after the lint run (was `3`).
- Telemetry was used for **prioritization** (`[a]` sort), not **flagging**.

---

## Sub-scenario 2: Захищені page is never proposed for verification

A protected page sits with `view_count: 0` and `last_patched_at` of two months
ago. Both algorithmic-staleness signals would normally rank it as a top
candidate. Page protection skips it.

### Setup

Mock wiki state:

- `docs/wiki/schema.md` — `wiki_version: "4.0"`.
- `docs/wiki/index.md` — lists `[[secret-rotation-recipe]]` and
  `[[purchase-flow]]`.
- `docs/wiki/concepts/secret-rotation-recipe.md`:

  ```markdown
  # Cloudflare Tunnel Token Rotation

  Step-by-step recipe for rotating the cloudflared service token when it
  leaks or expires.

  ## Steps
  1. Generate new token in Cloudflare dashboard
  2. Update `/opt/health/.env` with new value
  3. `docker compose up -d cloudflared`

  ## Sources
  - `docs/wiki/concepts/infrastructure.md`
  ```

- `docs/wiki/concepts/infrastructure.md` exists.
- `docs/wiki/concepts/purchase-flow.md` exists with one valid source.

`docs/wiki/.usage.json`:

```json
{
  "concepts/secret-rotation-recipe.md": {
    "view_count": 0, "use_count": 0, "patch_count": 1,
    "last_viewed_at": null,
    "last_used_at":   null,
    "last_patched_at":"2026-02-10T14:00:00Z",
    "created_at":     "2026-02-10T14:00:00Z",
    "state": "active", "protected": true, "archived_at": null
  },
  "concepts/purchase-flow.md": {
    "view_count": 5, "use_count": 1, "patch_count": 2,
    "last_viewed_at": "2026-04-30T10:00:00Z",
    "last_used_at":   "2026-04-25T09:00:00Z",
    "last_patched_at":"2026-04-29T15:00:00Z",
    "created_at":     "2026-01-10T08:00:00Z",
    "state": "active", "protected": false, "archived_at": null
  }
}
```

### Trigger

Two equivalent triggers must both honor the protection:

- (a) User: `wiki lint` → picks `[b] Top-5 longest unpatched among active`.
- (b) User: `wiki status` → picks `[b]` from action menu (delegates to Lint).

### Expected skill behavior

1. Sort `report()` by `last_patched_at asc`. Without protect filter, the result
   would be: `secret-rotation-recipe` (Feb 10), `purchase-flow` (Apr 29).
2. **Apply protect filter**: drop `secret-rotation-recipe` because
   `protected == true`. Result set: `purchase-flow` only.
3. Lint report includes a separate `### Захищені` header listing the protected
   pages (so the user remembers they exist):

   ```
   ### Verified (content-verification subset: [b])
   - [[purchase-flow]] — claims hold, no action needed.

   ### Захищені (skipped by content-verification — `wiki unprotect <path>` to verify)
   - [[secret-rotation-recipe]]
   ```

4. **Do not** read `secret-rotation-recipe.md` content. **Do not** bump its
   `view_count`. **Do not** propose any action against it.

### Manual verification

- After the lint run, `secret-rotation-recipe.md` record in `.usage.json`:
  `view_count` is still `0`, `last_viewed_at` is still `null`.
- `purchase-flow.md` `view_count` is `6` (was `5`).
- Захищені page appears in report under its own header — **never** under
  `### Verified` with a `глянь і онови` / `видали` action.
- Same behavior whether triggered via `wiki lint` directly or via
  `wiki status` → `[b]` delegation.

### `wiki status` rendering of the same state

When the user runs `wiki status` (without picking `[b]`), the structured
display lists `[[secret-rotation-recipe]]` under the `Захищені:` section
verbatim — never under "candidates for verification".

### Unpin path

If the user really wants to verify the protected page, they run:

```
wiki unprotect concepts/secret-rotation-recipe.md
```

The skill mutates `.usage.json` (sets `protected: false`, no `patch_count`
bump). On the next `wiki lint`, the page becomes a normal candidate. After
verification, the user can re-protect via `wiki protect <path>`.

---

## Sub-scenario 3: Cross-ref drift detected passively (no LLM read)

A wikilink in one page points to a deleted target. This is **passive
detection** — no page is read for content; pure grep over `[[wikilinks]]`
vs. file existence.

### Setup

Mock wiki state:

- `docs/wiki/schema.md` — `wiki_version: "4.0"`.
- `docs/wiki/index.md` — lists `[[page-a]]`.
- `docs/wiki/concepts/page-a.md`:

  ```markdown
  # Page A

  See [[page-b]] for the routing details.

  ## Sources
  - `apps/api/src/routes/index.ts`
  ```

- `docs/wiki/concepts/page-b.md` **does not exist** (was deleted in a prior
  cleanup).
- `apps/api/src/routes/index.ts` exists.

`docs/wiki/.usage.json`:

```json
{
  "concepts/page-a.md": {
    "view_count": 2, "use_count": 0, "patch_count": 1,
    "last_viewed_at": "2026-04-20T10:00:00Z",
    "last_used_at":   null,
    "last_patched_at":"2026-04-20T10:00:00Z",
    "created_at":     "2026-04-20T10:00:00Z",
    "state": "active", "protected": false, "archived_at": null
  }
}
```

### Trigger

User: `wiki lint`.

### Expected skill behavior

1. Run **passive checks** (cross-ref drift, schema drift, orphans, etc.) —
   these need NO LLM read of page content. Implementation: grep
   `[[wikilink]]` patterns in every `.md` under `docs/wiki/`, then check each
   target file existence.
2. Find: `concepts/page-a.md` body links to `[[page-b]]` → target file does
   not exist on disk. **Cross-ref drift detected passively.**
3. Report includes:

   ```
   ### Missing Cross-References (passive detection)
   - [[page-a]] → [[page-b]] (target file does not exist)
   ```

4. The user can apply the passive fix without any further LLM page-read:
   either remove the broken `[[page-b]]` link from `page-a.md` body, or
   re-create `page-b.md` if the link is intentional.

### Manual verification

- Before the lint run, `page-a.md` `view_count` was `2`. **After the lint
  run, `view_count` is still `2`** — passive detection did not consult the
  page as content, only grepped it for wikilink patterns.
- No `Read` tool call against `page-a.md` is required for passive cross-ref
  drift. (If the user separately picks `[a]/[b]/[c]/[d]` content
  verification on `page-a`, that **does** bump `view_count`.)
- The reformulated Lint preserves checks #2-13 (cross-ref drift, schema
  drift, orphans, etc.) as passive — only check #1 (staleness) is the
  Karpathy content-verification flow.

---

## Cross-cutting verification

Across all three sub-scenarios:

1. **No timestamp threshold ever flags a page.** Phrases like "page hasn't
   been touched in N days" appear nowhere in skill output. Staleness is
   judged by reading content (or, for passive checks, by file-existence
   grep) — never by clock arithmetic.
2. **`.usage.json` is read for prioritization, not flagging.** The skill may
   say "I'll start with the top-5 most-edited candidates" — that's
   prioritization. The skill never says "this page is stale because it has
   `last_patched_at` 2026-01-05" — that would be flagging.
3. **Pin acts as a hard fence.** `protected == true` excludes the page from
   `[a]/[b]/[c]/[d]` content-verification proposals. Even an explicit user
   list (`[d]`) requires `wiki unprotect` first.
4. **Reflection fires only when edits happen.** Sub-scenario 1 (no edit yet,
   waiting on user choice) — no РЕФЛЕКСІЯ block. Sub-scenario 3, if the
   user later applies the passive fix and `Edit`s `page-a.md`, reflection
   fires from that edit per `## Self-Improvement Loop`.
