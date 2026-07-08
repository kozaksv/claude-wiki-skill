# Integration Checklist (Phase I dogfood pass)

End-to-end mental review of `SKILL.md` + `references/` after Phase H. Goal: every operation that touches wiki state mentions the right cross-cutting concerns (telemetry mutator, reflection trigger, page protection, Karpathy staleness, anti-noise).

## Method

Read `SKILL.md` as the routing contract, then read each operation reference it points to. For each operation, verify five anchors are reachable from inside the operation body (or its `### After completion`):

1. **Telemetry mutator** — does the operation say *which* `bump_*` / `forget` calls fire and when?
2. **Reflection trigger** — does the `### After completion` section spell out fire-vs-skip and reference the anti-noise rule?
3. **Page protection** — if the operation can read or destroy pages, does it skip `protected: true` (or refuse with the unpin hint)?
4. **Karpathy staleness** — does any staleness logic explicitly defer to content-verification, never timestamps?
5. **Anti-noise** — does the operation correctly classify itself as edit-block (fire reflection) or read-only (skip)?

## Operation-by-operation findings

### Eight operations cross-referenced from intro/frontmatter

- ✅ Frontmatter `description` lists all 8 by name (init, ingest-source, ingest-binary, query, lint, cleanup, split, wiki status).
- ✅ Frontmatter `description` includes the public README/installer init prompt family (`створи вікі`, `ініціалізуй wiki`, `init wiki`, `bootstrap wiki`), so fresh install CTA and model trigger contract match.
- ✅ `SKILL.md` is a thin entrypoint and routes to every operation reference.
- ✅ All 8 `## Operation: <Name>` headers are present under `references/` — no orphan operations described elsewhere.

### Ingest-Source

- ✅ Telemetry: Step 7 — `bump_view`, `bump_patch`, `bump_use` listed explicitly with when-to-fire rules.
- ✅ Reflection: `### After completion` fires reflection (anti-noise rare).
- ✅ Protect auto-suggest: Step 8 catches security/incident/migration/compliance/recovery patterns.
- ✅ Karpathy staleness: not directly relevant (this is write-side); telemetry only feeds into Lint later.
- ✅ Anti-noise: explicitly says "rarely applies" because writes happen.

### Ingest-Binary

- ✅ Telemetry: Step 10 enumerates all `bump_patch` and `bump_use` calls.
- ✅ Reflection: `### After completion` fires reflection with `Перевірив:` section.
- ✅ Protect auto-suggest: Step 11 mirrors Ingest-Source pattern.
- ✅ Karpathy staleness: not directly relevant.
- ✅ Anti-noise: "does not apply".

### Query

- ✅ Telemetry: Step 6 — `bump_view` for each read; `bump_patch` + `bump_use` if Filing Back fires.
- ✅ Reflection: `### After completion` correctly notes read-only default with Filing-Back exception.
- ✅ Page protection: not relevant for Query (no destructive ops; Query reads any page on demand).
- ✅ Karpathy staleness: not relevant.
- ✅ Anti-noise: applies by default.
- ✅ Discovery: `### When to Query` opens with **master rule** ("query before generating project-specific content from memory"), enumerates Ukrainian question shapes, pairs with crystallization (find-nothing = crystallization candidate). Frontmatter `description` mirrors the proactive trigger so the skill activates on natural «як налаштувати/що таке/де лежить» phrasing without requiring "wiki" keyword.

### Wiki Status

- ✅ Telemetry: explicit "meta-operation does NOT bump view_count" note. Downstream picks bump normally.
- ✅ Reflection: `### After completion` correctly skips (read-only) and warns against double-fire from downstream.
- ✅ Page protection: surfaces protected list separately; `[a]` / `[b]` filter out `protected: true`.
- ✅ Karpathy staleness: doesn't flag — only sorts by signal and offers content-verification.
- ✅ Anti-noise: applies.

### Lint

- ✅ Telemetry: check #1 says ".usage.json is read here for prioritization only" — anti-flagging stance is explicit.
- ✅ Reflection: `### After completion` explicitly says Lint/report/revert output is the visible reasoning layer; no extra РЕФЛЕКСІЯ block after lint/status/cleanup-flow.
- ✅ Page protection: dedicated `### Page protection during Lint` subsection. Full, `швидко`, path scope, and topic scope skip `protected: true`; explicit verification requires `wiki unprotect` first.
- ✅ Karpathy staleness: check #1 IS the canonical Karpathy reformulation — long paragraph banning timestamp/heuristic flagging.
- ✅ Anti-noise: lint/status/cleanup reports are terminal; applied fixes are explained in the report rather than followed by reflection.

### Split

- ✅ Telemetry: step 4 — `forget(original_path)`; successors auto-create on first patch.
- ✅ Reflection: `### After completion` fires (always writes).
- ✅ Page protection: not directly addressed in Split, but the only entry path that triggers Split on a protected page is via cleanup-flow which already enforces page protection upstream.
- ✅ Karpathy staleness: not relevant.
- ✅ Anti-noise: "does not apply".

### Init

- ✅ Telemetry: step 6a creates `.usage.json` empty dict; step 6b adds to gitignore.
- ✅ Reflection: `### After completion` fires unconditionally with `Перевірив:`.
- ✅ Page protection: not relevant for fresh wiki.
- ✅ Karpathy staleness: not relevant.
- ✅ Anti-noise: "does not apply".

### Cleanup

- ✅ Telemetry: step 4 — `forget(path)` for deleted entity stubs.
- ✅ Reflection: cleanup-flow uses its own action/report output and does not emit a recursive reflection block.
- ✅ Page protection: cleanup-flow's destructive verbs (`видали`, `merge`) honor page protection — refuses with `wiki unprotect` hint.
- ✅ Karpathy staleness: cleanup is non-staleness oriented; staleness lives in Lint.
- ✅ Anti-noise: explicitly applied for proposal-only mode.

### Pin / Unpin micro-operations

- ✅ Defined under `references/cleanup-flow.md` → `wiki protect` / `wiki unprotect`.
- ✅ Telemetry: pure metadata toggle — does not bump `patch_count`.
- ✅ Reflection: explicitly skipped (anti-noise applied — they're not "edits to content").
- ✅ Page protection: this IS the toggle for page protection.
- ✅ Karpathy staleness: orthogonal.
- ✅ Anti-noise: applied.

## Cross-cutting consistency checks

### Page protection consistency

- ✅ Cleanup-flow safety layer 3 (`### Safety layers`) enforces page protection on `видали` and `merge`.
- ✅ Lint `### Page protection during Lint` blocks full / `швидко` / path / topic flows correctly.
- ✅ Wiki Status `[a]` / `[b]` filter protected pages out of proposals (line in Action menu routing table).
- ✅ Protect auto-suggest fires at Ingest-Source step 8 and Ingest-Binary step 11 with identical wording.
- ✅ `wiki protect` / `wiki unprotect` are the only ways to toggle.

### Karpathy staleness consistency

- ✅ `references/telemetry.md` → `### Role: prioritization, not flagging` — the source-of-truth paragraph.
- ✅ `references/operation-lint.md` → `Checklist > 1. Staleness (Karpathy content-verification)` — the operational embodiment.
- ✅ Wiki Status routes content-verification to Lint, never flags itself.
- ✅ Common Mistakes row "Auto-flagging staleness by timestamp" reinforces.

### Anti-noise consistency

- ✅ Master rule: `references/reflection.md` → `### Anti-noise rule` (clear principle: only Read = no reflection).
- ✅ Each `### After completion` correctly cites it or states the stronger lint/status/cleanup no-reflection rule.
- ✅ Pin/unpin micro-ops apply it (metadata only = no reflection).
- ✅ Common Mistakes row "Skipping reflection because 'small change'" closes the loophole — anti-noise is *only* for read-only blocks.

### Crystallization (proposal, not silent write)

- ✅ `references/crystallization.md` — single artifact type (wiki page) and proposal format.
- ✅ Script tier (`scripts/*.sh` / `*.py`) deliberately absent — Division of Labor reasoning in the table's "Why no `scripts/` tier" callout.
- ✅ Common Mistakes rows "Creating crystallization artifact silently" + "Proposing `scripts/*.sh` or `scripts/*.py` as crystallization" reinforce.

### Telemetry as gitignored sidecar

- ✅ `## Telemetry Sidecar > ### Gitignored` — explicit.
- ✅ Init step 6b adds it to `.gitignore`.
- ✅ Common Mistakes row "Treating .usage.json as user-visible".

### Versioning + migration

- ✅ `## Versioning & Migration` — full state model + plan format + explicit-not-silent contract.
- ✅ Init's discovery aligns the 5-state model with Step 0's table.
- ✅ Common Mistakes row "Migrating wiki_version silently" closes loophole (only `.usage.json` field-backfill is silent).

## Gaps fixed inline during this pass

1. **Lint/status/cleanup reflection contract tightened.** The report is now the visible reasoning layer; no extra РЕФЛЕКСІЯ follows these operations, including after AUTO fixes or natural-language revert.

No other gaps required instruction edits — the v4.2 surface area is consistent.

## Conclusion

After this dogfood pass and the Lint fix, all eight operations consistently route through the five cross-cutting concerns. The split entrypoint/reference layout is internally coherent; the single downstream entry point (`wiki status`) converges on the same cleanup-flow mechanics.

Ready for v4.2.0 release tag after the final verification pass.
