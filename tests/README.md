# Test strategy

This repo has two kinds of tests:

- `install-cross-agent-links.sh` is an automated shell regression test for installer behavior: canonical link shape, symlink exports, repair-only exports, conflict preservation, bad refs, optional `doc-extract` failure, and truthful summaries.
- `uninstall.sh` is an automated shell regression test for safe uninstall behavior: idempotent symlink removal, conflict preservation, and optional clean-clone removal.
- `skill-contracts.sh` is a static contract test for the split skill layout: `SKILL.md` must stay a thin entrypoint, required `references/` files must exist, and critical LLM-behavior invariants must remain textually present.
- `scenarios/*.md` are executable review scenarios for LLM-driven behavior. They define the expected model contract for discovery, migration, cleanup, crystallization, reflection, and wiki operations across Claude, Codex, and Gemini.

The Markdown scenarios are intentional, not placeholders. The behavior they cover depends on an agent reading project files, resolving ambiguous user intent, and applying the skill instructions in context, so plain shell assertions would either miss the actual contract or overfit to a fake parser.

In scenarios, fixed section headers, action verbs, telemetry field names, and safety prompts are contract. Concrete counts, timestamps, example page orderings, and sample entity names are examples unless the scenario explicitly says otherwise.

Manual pre-release pass order for the current prose scenarios:

1. `cross-agent-discovery.md` — run in Claude, Codex, and Gemini if available; at minimum run Codex-only and Gemini-only fresh-init paths.
2. `v3-to-v4-migration.md` — include the partial-failure sub-scenario before any mass release.
3. `cleanup-flow.md` — verify destructive double-confirmation and protected-page behavior.
4. `reflection-triggers.md` — verify reflection fires after mutating operations and does not fire after read-only/report-only operations.
5. `crystallization-tiers.md` — verify Codex/Gemini-only direct-create uses the shared canonical topology.
6. `wiki-status.md` and `staleness-content-verification.md` — verify anti-recursion after status/lint-style reports.

If an automated eval harness is added later, start with the highest-risk scenarios:

- Step 0 discovery across `CLAUDE.md`, `AGENTS.md`, and `GEMINI.md`
- destructive cleanup double-confirmation
- anti-recursion after lint/status/cleanup
- Codex/Gemini-only skill crystallization into the shared canonical topology
