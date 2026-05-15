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

