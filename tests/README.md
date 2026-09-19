# Test strategy

This repo has several complementary kinds of tests:

- `install-cross-agent-links.sh` is an automated shell regression test for installer behavior: canonical link shape, symlink exports, repair-only exports, conflict preservation, bad refs, optional `doc-extract` failure, and truthful summaries.
- `uninstall.sh` is an automated shell regression test for safe uninstall behavior: idempotent symlink removal, conflict preservation, and optional clean-clone removal.
- `skill-contracts.sh` is a static contract test for the split skill layout: `SKILL.md` must stay a thin entrypoint, required `references/` files must exist, and critical LLM-behavior invariants must remain textually present.
- `scenarios/*.md` are executable review scenarios for LLM-driven behavior. They define the expected model contract for discovery, migration, cleanup, crystallization, reflection, and wiki operations across Claude, Codex, Gemini, and Qwen Code.

The Markdown scenarios are intentional, not placeholders. The behavior they cover depends on an agent reading project files, resolving ambiguous user intent, and applying the skill instructions in context, so plain shell assertions would either miss the actual contract or overfit to a fake parser.

`scenarios/chatgpt-github.md` covers the remote read/write adapter: snapshot-scoped
retrieval, missing index entries, empty/partial/inaccessible wikis, duplicate
basenames, truncation, and capability boundaries. Validate the new entrypoint
with Skill Creator's `quick_validate.py skills/wiki-github` and the package with
Plugin Creator's `validate_plugin.py .` where those development helpers are
available. Scenario review is separate from manifest/static validation.

In scenarios, fixed section headers, action verbs, telemetry field names, and safety prompts are contract. Concrete counts, timestamps, example page orderings, and sample entity names are examples unless the scenario explicitly says otherwise.

Manual pre-release pass order for the current prose scenarios:

1. `cross-agent-discovery.md` — run in Claude, Codex, Gemini, and Qwen Code if
   available; at minimum run Codex-only and Gemini-only fresh-init paths, plus
   the Qwen-specific `QWEN.md`-pointer and `QWEN_PROJECT_DIR`-anchor
   sub-scenarios.
2. `v3-to-v4-migration.md` — include the partial-failure sub-scenario before any mass release.
3. `cleanup-flow.md` — verify destructive double-confirmation and protected-page behavior.
4. `reflection-triggers.md` — verify reflection fires after mutating operations and does not fire after read-only/report-only operations.
5. `crystallization.md` — verify the skill proposes only the single `wiki` artifact type and never a script or skill tier.
6. `wiki-status.md` and `staleness-content-verification.md` — verify anti-recursion after status/lint-style reports.

If an automated eval harness is added later, start with the highest-risk scenarios:

- Step 0 discovery across `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, and `QWEN.md`
- destructive cleanup double-confirmation
- anti-recursion after lint/status/cleanup
- crystallization proposing only the single `wiki` artifact type (never a script or skill tier)

## Deterministic maintenance coverage

Run `python3 -m unittest discover -s tests -p 'test_*.py' -v`.
These tests execute real discovery in Git fixtures and exercise catalog
coverage/drift, Git blob identity, large-page section ranges, Unicode paths,
symlink/FIFO boundaries, durable/legacy protection, corruption handling,
history extraction and rollback. They do not claim model or GitHub E2E coverage.

Run `python3 scripts/build_skill.py --check` for canonical/bundled parity.
The Wiki contracts workflow runs these plus the existing hook/installer suites.
The root `action.yml` makes catalog check/write available to consuming repos.
