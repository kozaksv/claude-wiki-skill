# Test strategy

This repo has two kinds of tests:

- `install-cross-agent-links.sh` is an automated shell regression test for installer behavior: canonical link shape, symlink exports, conflict preservation, bad refs, optional `doc-extract` failure, and truthful summaries.
- `uninstall.sh` is an automated shell regression test for safe uninstall behavior: idempotent symlink removal, conflict preservation, and optional clean-clone removal.
- `skill-contracts.sh` is a static contract test for the split skill layout: `SKILL.md` must stay a thin entrypoint, required `references/` files must exist, and critical LLM-behavior invariants must remain textually present.
- `scenarios/*.md` are executable review scenarios for LLM-driven behavior. They define the expected model contract for discovery, migration, cleanup, crystallization, reflection, and wiki operations across Claude, Codex, and Gemini.

The Markdown scenarios are intentional, not placeholders. The behavior they cover depends on an agent reading project files, resolving ambiguous user intent, and applying the skill instructions in context, so plain shell assertions would either miss the actual contract or overfit to a fake parser.

If an automated eval harness is added later, start with the highest-risk scenarios:

- Step 0 discovery across `CLAUDE.md`, `AGENTS.md`, and `GEMINI.md`
- destructive cleanup double-confirmation
- anti-recursion after lint/status/cleanup
- Codex/Gemini-only skill crystallization into the shared canonical topology
