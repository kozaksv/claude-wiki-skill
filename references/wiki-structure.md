## Tracks (configurable; within Wiki)

The wiki's tracks are **configurable** via `{wiki}/schema.md` — either
`preset: <name>` or an inline `tracks:` list (see SKILL.md → *Tracks*). The
directory a page lives in dictates its `type`, and a track may declare
`requires` (mandatory frontmatter fields) and `path_map` (code globs → that
track). With **no declaration the default is the `karpathy` preset** — three
internal layers:

```
{wiki}/concepts/         → themes, processes, rules (synthesis)
{wiki}/entities/         → specific things (people, contracts, objects, ...)
{wiki}/transcripts/      → full text of binaries (for grep / LLM context)
```

Other built-in preset: `code-project` (`guide`/`workflows`/`modules`, where
`modules` requires a `module:` field). Projects may declare their own presets
(see `presets/README.md`). The descriptions below detail the default `karpathy`
layers.

Plus external layers:

```
Raw Binaries (immutable) → archive/ (gitignored, outside wiki)
Schema (conventions)     → {wiki}/schema.md (preferred, v3+)
                         → agent instruction file sections (legacy, v1–v2)
```

**Concepts** — the existing layer. Themes, gotchas, architectural decisions.

**Entities** — hub pages for specific things. Each entity page has:
- Frontmatter with `type: entity`, `category`, `key`, project-specific fields
- Synthesis (what this is, why it matters)
- Cross-refs (to other entities, concepts, transcripts, binaries)

**Lazy entity creation:** create an entity page only when a document or
operation actually references the entity. Don't pre-populate from inventories.

**Transcripts** — auto-generated MD with full text of a binary. Frontmatter
links back to source binary and corresponding entity page. No synthesis,
no editing — pure raw text for grep and LLM context.

**Naming** — for documents:  `{YYYY-MM-DD}_{type}_{slug}.{ext}`.
For templates: `template_{type}_{slug}.{ext}`.
For abstract entities: `{slug}.md`.
Cyrillic OK. Spaces → `-`. Forbidden: `/\?*<>:|`, quotes, dots (except before ext).

## Navigation Files

| File | Purpose | Format |
|------|---------|--------|
| `{wiki}/index.md` | Catalog of all pages, organized by category | `- [[page-name]] — one-line description` |
| `{wiki}/log.md` | Live chronological log of recent operations (soft cap ~2000 lines, see `## Log Rotation`) | `## [YYYY-MM-DD] operation \| Subject` + optional `touched: [[page-a]], [[page-b]]` line for searchability. Optional `## Archived` section at the top lists rotated shards. |
| `{wiki}/log/{YYYY-MM-DD}_to_{YYYY-MM-DD}.md` | Archived log shards (rotated out of `log.md`) | Same entry format as `log.md`. Created lazily on first rotation; date range derived from peeled entries, not calendar boundaries. |

**Read `index.md` FIRST** for any wiki operation — it's your map.

## Log Rotation

`{wiki}/log.md` is the **live** log with a **soft cap of 2000 lines**. When a
log write would push the file past the cap, rotate: peel the oldest contiguous
entries into a shard until the live log drops to about 1000 lines. This bounds
the cost of reading `log.md` (at ~2000 lines the Read tool starts paginating)
while keeping history grep-able through shards.

Rotation is **activity-driven**, not calendar-driven. Quiet projects never
rotate. Active projects accumulate shards as they actually fill the live log.

### Algorithm (lazy, runs before every log write)

1. Read `{wiki}/log.md`, count lines.
2. If line count `< 2000` → write the new entry as usual, done.
3. Otherwise:
   1. Parse `## [YYYY-MM-DD] ...` headers to find entry boundaries.
   2. Find the cut point that leaves the tail (kept in `log.md`) at about
      1000 lines. **Never split an entry mid-way** — cut between entries.
   3. Derive `{min-date}` and `{max-date}` from the `## [YYYY-MM-DD] ...`
      headers of the peeled entries.
   4. Atomically write peeled content to
      `{wiki}/log/{min-date}_to_{max-date}.md` (temp file in same dir → rename).
      Create `{wiki}/log/` directory if missing.
   5. Rewrite `log.md` with the tail. Update the `## Archived` index at the top
      with a new line: `- [[log/{min-date}_to_{max-date}]] — {min-date} to {max-date}`.
4. Now append the new entry to the freshly-trimmed `log.md`.

### Shard naming

`{wiki}/log/{YYYY-MM-DD}_to_{YYYY-MM-DD}.md` — both dates come from the
peeled entries themselves, **not** from calendar boundaries. Shard ranges
will look jagged (e.g. `2025-11-14_to_2026-02-09.md`) — that is the point.
Each shard represents the project's "epoch" between two rotation events.

### Edge cases

- **All entries in `log.md` share the same date** and the file is still
  over the cap → peeling would produce a single-day shard whose date range
  equals the tail's date range, giving no historical separation. Skip
  rotation, surface a warning (`log.md exceeds rotation cap but contains
  only one calendar date — abnormal write volume?`), and append. The next
  day's writes will allow rotation to peel meaningfully.
- **`log.md` has no `## [YYYY-MM-DD] ...` headers** (hand-edited, corrupt) →
  skip rotation, surface a warning, append. Do not attempt to repair the
  file; that is a manual cleanup concern.
- **First rotation on a wiki without `log/`** → create the directory before
  writing the shard.
- **Shard write fails** (disk full, permission denied) → surface a warning,
  skip rotation for this write, still append the new entry. Telemetry-style
  tolerance: never block a wiki operation because rotation infrastructure
  failed.

### Reading semantics

- **Recent activity** (last few rotation cycles) → read `{wiki}/log.md`.
- **Deep history** → consult the `## Archived` index at the top of `log.md`
  (one-hop list of every shard by date range), then read the matching
  `log/{...}.md` shard(s).
- Agents do not need a filesystem listing of `log/` — the `## Archived`
  index in `log.md` is the authoritative pointer set.

### Out of scope

- Shards are **not** listed in `{wiki}/index.md`. They are navigation
  infrastructure, not knowledge content.
- Shards are **not** tracked in `{wiki}/.usage.json`. Telemetry tracks
  knowledge pages, not the log substrate.
- No automatic compaction, merging, or pruning of shards. Once peeled,
  shards stay as-is. Consolidation, if ever needed, is a manual edit.

---

