## Operation: Cleanup

Post-migration / periodic housekeeping AND structural reorganization of existing content.

### When to Cleanup

- After init/bootstrap completes
- User says "wiki cleanup", "почисть wiki/вікі"
- Periodically (every ~10 sessions or after major changes)
- **When migrating content between agent instruction files and wiki** (e.g. extracting implementation details, consolidating duplicates). This is the canonical home for "wiki refactor" — not `ingest-source` (no new material entering) and not `lint` (not read-only report). Use the log tag `cleanup` with a descriptive subject.

### Process

1. Remove empty directories under `docs/wiki/` and `archive/`
2. Verify `archive/` is in `.gitignore`; add if missing
3. Verify schema exists at `{wiki}/schema.md` (preferred). If schema lives in instruction-file sections instead, propose migration: move to `{wiki}/schema.md`, leave a 1-line pointer in the instruction file. If both exist — propose collapsing into schema.md only.
4. Find unused entity stubs (entity pages with no cross-refs from anywhere) — propose deletion. For each page deleted, call `forget(path)` against `.usage.json` (see `## Telemetry Sidecar`).
5. Find concept pages not in `index.md` and vice versa — propose fixes
6. Append cleanup actions to `log.md`

### After completion

If this operation was triggered by a TodoWrite-completion or is part of a pre-commit moment, emit a РЕФЛЕКСІЯ block per `references/reflection.md`. Cleanup that only **proposed** fixes (no user consent yet, no edits applied) is a read-only survey — apply the **anti-noise rule** and skip reflection. Cleanup that actually applied fixes (deletions, schema migration, index/log updates) is a structural change — fire reflection and include the `Перевірив:` section.

---
