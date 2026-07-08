## Telemetry Sidecar (.usage.json)

Each wiki carries a small sidecar file `{wiki}/.usage.json` that tracks per-page activity. It is gitignored, per-clone, and never blocks an operation if it goes wrong. The sidecar exists to **prioritize** what to read or verify next — never to flag pages as stale on its own. Staleness is judged by reading content (see `## Operation: Lint`).

### Path

`{wiki}/.usage.json` — dotfile, sibling to `schema.md`, `index.md`, `log.md`. Created during Init and on legacy → v4 migration.

### Gitignored

Telemetry is per-clone, not shared. In team contexts, sharing would create constant merge noise (every read by every dev/CI generates a diff). The skill bootstrap (init / migration) adds `{wiki}/.usage.json` to `.gitignore` automatically.

### Record structure

The file is a JSON dict — keys are page paths relative to `{wiki}/` (e.g. `concepts/purchase-flow.md`), values are records with this shape:

```json
{
  "concepts/purchase-flow.md": {
    "view_count": 0,
    "use_count": 0,
    "patch_count": 0,
    "last_viewed_at": null,
    "last_used_at": null,
    "last_patched_at": null,
    "created_at": "2026-05-01T14:32:00Z",
    "state": "active",
    "protected": false,
    "archived_at": null
  }
}
```

All ten fields are present for every record. Timestamps are ISO 8601 UTC. `state`, `protected`, `archived_at` are forward-compat fields (v5+ will use them for curator/auto-transitions); v4.0 reads them as defaults but does not act on them.

**Field-rename compat (v4.0.0 → v4.0.x): `pinned` → `protected`.** The earliest v4.0.0 release used `pinned` as the field name; subsequent commits renamed it to `protected` for clearer English semantics matching the user-facing «захищена» term. **On read, accept either name as truthy** — old records with `pinned: true` are treated as `protected: true`. **On the first write to a record carrying the legacy `pinned` field**, silently migrate: copy the value to `protected`, drop the old `pinned` key. No version-bump prompt for this — it's a field-level backfill (per Versioning & Migration silent-backfill rule).

### Semantic mapping

| Field | Meaning in wiki | When to increment |
|---|---|---|
| `view_count` / `last_viewed_at` | view = consult | You read the page file (Claude `Read`, Codex/Gemini equivalent file-read; level-1 disclosure during Query, Lint, Ingest) |
| `use_count` / `last_used_at` | use = synthesis-applied | The page is cited as `[[wikilink]]` in a new or updated page body |
| `patch_count` / `last_patched_at` | patch = modified | You modify the page file (Claude `Edit`/`Write`, Codex `apply_patch`, Gemini equivalent edit/write) |
| `created_at` | birth timestamp | Set once on first record creation; never changes |
| `state`, `protected`, `archived_at` | forward-compat | v4.0 does not write these except defaults (`"active"`, `false`, `null`) |

### Mutator API (instructional)

These are the actions you must perform on `.usage.json` during operations. Read the file, mutate the in-memory dict, write atomically (see Tolerance below). If a path key is missing on a `bump_*`, create the record with all ten default fields, then increment.

| Action | When to call | Effect |
|---|---|---|
| `bump_view(path)` | After reading a wiki page file | `view_count += 1`; `last_viewed_at = now`; create record if absent |
| `bump_use(path)` | After adding a new `[[wikilink]]` to `path` from another page's body | `use_count += 1`; `last_used_at = now`; create record if absent |
| `bump_patch(path)` | After modifying the page (including new file creation) | `patch_count += 1`; `last_patched_at = now`; create record with `created_at = now` if absent |
| `forget(path)` | After `Cleanup` deletes an orphan, after `Split` deletes the original | Remove the key from the dict |
| `report()` | During `Lint` and `wiki status` | Return the full sortable list (path + all fields) for prioritization |

Translate these into concrete file mutations: read JSON, modify dict, write back atomically. Do not maintain counters in memory across turns — re-read the file each operation.

**On `bump_view`/`bump_patch` (rows above):** when Claude Code hooks are
installed, these calls **may** be pattern-suppressed — but the suppression
applies only when confirmed live PostToolUse telemetry (fresh
`_hooks.post_tool_use_at`), never merely because an index-inject block was
observed this session. See `### Dual-signal rule` and `### Manual-bump
suppression rule` below for the full contract.

### Tolerance rules

The wiki operation must never fail because of telemetry. Apply these rules:

- **Atomic write** — write to a temp file in the same directory, then rename over the target. Never partial-write `.usage.json` directly.
- **Corrupt read → `{}`** — if the file is unparseable JSON, treat it as an empty dict and continue. Do not restore from a template; subsequent writes will rebuild it.
- **Write fail → log only, do not raise** — if you cannot write the sidecar (disk full, permission denied, etc.), surface a warning to the user but let the wiki operation succeed. Telemetry is best-effort.
- **Backfill missing keys silently** — if a record exists but lacks newer fields (e.g. an old record without `protected`), fill the missing fields with defaults (`"active"`, `false`, `null`) on read. This is the only silent-migration path; structural migrations require explicit consent (see `## Versioning & Migration`).

### Role: prioritization, not flagging

Telemetry never marks a page as "stale". It surfaces signals that help you choose where to look first:

| Field | Used for |
|---|---|
| `view_count`, `last_viewed_at` | "Hot" pages — high-view = consulted often, prioritize for content-verification |
| `use_count`, `last_used_at` | "Central" pages — high cite-count = nodes whose drift cascades through the wiki |
| `patch_count`, `last_patched_at` | "Drift risk" — sort by largest `patch_count` and oldest `last_patched_at` for `Lint` candidates |
| `created_at` | Display in `wiki status` output, used for "longest unverified" sorting |

Lint and `wiki status` use these to propose a small subset of pages to read in full. The actual judgment ("is this stale?") still requires a content read.

### `_hooks` — reserved metadata key

Any key in `.usage.json` starting with `_` is **reserved metadata, not a page
record**. `report()` and every page-iteration (Lint's candidate scan, `wiki
status`'s activity rankings, phantom-record detection) must skip `_`-prefixed
keys entirely — they are never counted as pages, never flagged as
missing-fields, never proposed for `forget()`.

The one metadata key v4.5 defines is `_hooks`, written by the optional Claude
Code session hooks (`hooks/session-start.sh`, `hooks/post-tool-use.sh`) and
by the agent at points noted in the relevant operation references. Its shape:

```json
{
  "_hooks": {
    "session_start_at": "2026-07-08T09:00:00Z",
    "post_tool_use_at": "2026-07-08T09:04:12Z",
    "last_lint_at": "2026-07-08T09:10:00Z",
    "hook_version": "4.5.0"
  }
}
```

All four fields are optional — a fresh `.usage.json` may have no `_hooks` key
at all, or a partial one. This is covered by the existing silent-backfill
rule above (`## Tolerance rules`): missing fields are filled with defaults
(here: absent) on read, no schema bump, no migration prompt. `_hooks` is
metadata about the telemetry system itself, not a versioned record shape.

### Dual-signal rule — two independent heartbeats

Two separate things can each be true or false, and neither implies the
other:

1. **`index injected`** — a `WIKI INDEX (hook-injected)` block appeared in
   the current session's context. This proves only that `session-start.sh`
   fired for this session (fresh `_hooks.session_start_at`). It says nothing
   about whether the per-tool-call telemetry hook is running.
2. **`telemetry active`** — `post-tool-use.sh` is actually firing on
   `Read`/`Edit`/`Write` calls. This can be proven **only** by a fresh
   `_hooks.post_tool_use_at` (i.e. updated during the current session, after
   the agent's own `Read` of a wiki page) — never by the presence of the
   inject block. A session can have a live inject block and a completely
   dead PostToolUse hook (missing `python3`, a stdin field mismatch, a write
   failure) — this is the "injected-but-dead" state, and it is
   indistinguishable from full telemetry health unless the two signals are
   checked separately.

### Manual-bump suppression rule

`bump_view(path)` / `bump_patch(path)` calls that the agent would otherwise
make manually (per the Mutator API above) are suppressed **only** when
telemetry is confirmed active — i.e. `_hooks.post_tool_use_at` is fresh for
the current session. If the index was injected (`session_start_at` fresh)
but `post_tool_use_at` is stale or absent, the agent continues making manual
`bump_view`/`bump_patch` calls as a fallback. Reasoning: a double-count is
caught by Lint (a implausibly high `view_count`/`patch_count` is a visible,
correctable artifact); a silently suppressed bump that should have fired
manually produces a permanently zeroed telemetry record, which is invisible
and non-recoverable. When in doubt, bump.

`bump_use(path)` is **always** manual, regardless of hook state — no hook
observes `[[wikilink]]` additions inside a page body, so there is no signal
that could suppress it.

Notes on `bump_view`/`bump_patch` above (`## Mutator API`): suppression
applies **only** when PostToolUse telemetry is confirmed live via a fresh
`_hooks.post_tool_use_at`, never merely because an index-inject block was
observed this session.

