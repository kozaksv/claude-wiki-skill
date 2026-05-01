# Integration Checklist (Phase I dogfood pass)

End-to-end mental review of SKILL.md after Phase H. Goal: every operation that touches wiki state mentions the right cross-cutting concerns (telemetry mutator, reflection trigger, pin protection, Karpathy staleness, anti-noise).

## Method

Read SKILL.md top to bottom. For each operation, verify five anchors are reachable from inside the operation's body (or its `### After completion`):

1. **Telemetry mutator** — does the operation say *which* `bump_*` / `forget` calls fire and when?
2. **Reflection trigger** — does the `### After completion` section spell out fire-vs-skip and reference the anti-noise rule?
3. **Pin protection** — if the operation can read or destroy pages, does it skip `pinned: true` (or refuse with the unpin hint)?
4. **Karpathy staleness** — does any staleness logic explicitly defer to content-verification, never timestamps?
5. **Anti-noise** — does the operation correctly classify itself as edit-block (fire reflection) or read-only (skip)?

## Operation-by-operation findings

### Eight operations cross-referenced from intro/frontmatter

- ✅ Frontmatter `description` lists all 8 by name (init, ingest-source, ingest-binary, query, lint, cleanup, split, wiki-status).
- ✅ `## Modularity` paragraph: "The eight operations are a palette, not a checklist."
- ✅ All 8 `## Operation: <Name>` headers present — no orphan operations described elsewhere.

### Ingest-Source

- ✅ Telemetry: Step 7 — `bump_view`, `bump_patch`, `bump_use` listed explicitly with when-to-fire rules.
- ✅ Reflection: `### After completion` fires reflection (anti-noise rare).
- ✅ Pin auto-suggest: Step 8 catches security/incident/migration/compliance/recovery patterns.
- ✅ Karpathy staleness: not directly relevant (this is write-side); telemetry only feeds into Lint later.
- ✅ Anti-noise: explicitly says "rarely applies" because writes happen.

### Ingest-Binary

- ✅ Telemetry: Step 10 enumerates all `bump_patch` and `bump_use` calls.
- ✅ Reflection: `### After completion` fires reflection with `Перевірив:` section.
- ✅ Pin auto-suggest: Step 11 mirrors Ingest-Source pattern.
- ✅ Karpathy staleness: not directly relevant.
- ✅ Anti-noise: "does not apply".

### Query

- ✅ Telemetry: Step 6 — `bump_view` for each read; `bump_patch` + `bump_use` if Filing Back fires.
- ✅ Reflection: `### After completion` correctly notes read-only default with Filing-Back exception.
- ✅ Pin protection: not relevant for Query (no destructive ops; Query reads any page on demand).
- ✅ Karpathy staleness: not relevant.
- ✅ Anti-noise: applies by default.

### Wiki Status

- ✅ Telemetry: explicit "meta-operation does NOT bump view_count" note. Downstream picks bump normally.
- ✅ Reflection: `### After completion` correctly skips (read-only) and warns against double-fire from downstream.
- ✅ Pin protection: surfaces pinned list separately; `[a]` / `[b]` filter out `pinned: true`.
- ✅ Karpathy staleness: doesn't flag — only sorts by signal and offers content-verification.
- ✅ Anti-noise: applies.

### Lint

- ✅ Telemetry: check #1 says ".usage.json is read here for prioritization only" — anti-flagging stance is explicit.
- ✅ Reflection: **`### After completion` was MISSING — added during this dogfood pass.** Now correctly says read-only default; per-page action verbs from cleanup-flow trigger reflection on their own terms.
- ✅ Pin protection: dedicated `### Pin protection during Lint` subsection. `[a]` / `[b]` / `[c]` skip; `[d]` requires explicit unpin.
- ✅ Karpathy staleness: check #1 IS the canonical Karpathy reformulation — long paragraph banning timestamp/heuristic flagging.
- ✅ Anti-noise: report-only Lint = skip reflection; applied fixes = fire.

### Split

- ✅ Telemetry: step 4 — `forget(original_path)`; successors auto-create on first patch.
- ✅ Reflection: `### After completion` fires (always writes).
- ✅ Pin protection: not directly addressed in Split, but the only entry path that triggers Split on a pinned page is via cleanup-flow which already enforces pin protection upstream.
- ✅ Karpathy staleness: not relevant.
- ✅ Anti-noise: "does not apply".

### Init

- ✅ Telemetry: step 6a creates `.usage.json` empty dict; step 6b adds to gitignore.
- ✅ Reflection: `### After completion` fires unconditionally with `Перевірив:`.
- ✅ Pin protection: not relevant for fresh wiki.
- ✅ Karpathy staleness: not relevant.
- ✅ Anti-noise: "does not apply".

### Cleanup

- ✅ Telemetry: step 4 — `forget(path)` for deleted entity stubs.
- ✅ Reflection: `### After completion` distinguishes proposal-only (skip) vs. applied-fixes (fire).
- ✅ Pin protection: cleanup-flow's destructive verbs (`видали`, `merge`) honor pin protection — refuses with `wiki unpin` hint.
- ✅ Karpathy staleness: cleanup is non-staleness oriented; staleness lives in Lint.
- ✅ Anti-noise: explicitly applied for proposal-only mode.

### Pin / Unpin micro-operations

- ✅ Defined under `## Self-Improvement Loop > wiki pin / wiki unpin`.
- ✅ Telemetry: pure metadata toggle — does not bump `patch_count`.
- ✅ Reflection: explicitly skipped (anti-noise applied — they're not "edits to content").
- ✅ Pin protection: this IS the toggle for pin protection.
- ✅ Karpathy staleness: orthogonal.
- ✅ Anti-noise: applied.

## Cross-cutting consistency checks

### Pin protection consistency

- ✅ Cleanup-flow safety layer 3 (`### Safety layers`) enforces pin protection on `видали` and `merge`.
- ✅ Lint `### Pin protection during Lint` blocks `[a]` / `[b]` / `[c]` / `[d]` flows correctly.
- ✅ Wiki Status `[a]` / `[b]` filter pinned pages out of proposals (line in Action menu routing table).
- ✅ Pin auto-suggest fires at Ingest-Source step 8 and Ingest-Binary step 11 with identical wording.
- ✅ `wiki pin` / `wiki unpin` are the only ways to toggle.

### Karpathy staleness consistency

- ✅ `## Telemetry Sidecar > ### Role: prioritization, not flagging` — the source-of-truth paragraph.
- ✅ `## Operation: Lint > Checklist > 1. Staleness (Karpathy content-verification)` — the operational embodiment.
- ✅ Wiki Status routes content-verification to Lint, never flags itself.
- ✅ Common Mistakes row "Auto-flagging staleness by timestamp" reinforces.

### Anti-noise consistency

- ✅ Master rule: `## Self-Improvement Loop > ### Anti-noise rule` (clear principle: only Read = no reflection).
- ✅ Each `### After completion` correctly cites it.
- ✅ Pin/unpin micro-ops apply it (metadata only = no reflection).
- ✅ Common Mistakes row "Skipping reflection because 'small change'" closes the loophole — anti-noise is *only* for read-only blocks.

### Crystallization (proposal, not silent write)

- ✅ `## Self-Improvement Loop > ### Tiered Crystallization` — full hierarchy and proposal format.
- ✅ Tier 4 explicitly delegates to `superpowers:writing-skills` — no SKILL.md created from this skill.
- ✅ Common Mistakes row "Creating crystallization artifact silently" reinforces.

### Telemetry as gitignored sidecar

- ✅ `## Telemetry Sidecar > ### Gitignored` — explicit.
- ✅ Init step 6b adds it to `.gitignore`.
- ✅ Common Mistakes row "Treating .usage.json as user-visible".

### Versioning + migration

- ✅ `## Versioning & Migration` — full state model + plan format + explicit-not-silent contract.
- ✅ Init's discovery aligns the 5-state model with Step 0's table.
- ✅ Common Mistakes row "Migrating wiki_version silently" closes loophole (only `.usage.json` field-backfill is silent).

## Gaps fixed inline during this pass

1. **Lint had no `### After completion` section.** Added one that:
   - Marks Lint as read-only by default (skip reflection).
   - Notes that per-page action verbs from the cleanup-flow trigger reflection on their own terms.
   - Warns against double-fire.

No other gaps required SKILL.md edits — the v4 surface area is consistent.

## Conclusion

After this dogfood pass and the Lint fix, all eight operations consistently route through the five cross-cutting concerns. The skill is internally coherent; downstream entry points (РЕФЛЕКСІЯ embedded prompt, `wiki status`) converge on the same cleanup-flow mechanics.

Ready for v4.0.0 release.
