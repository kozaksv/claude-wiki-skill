# Release B validation receipts (4.12.0)

Scope: epic #6 r3 §5, sub-issues #10–#14. Wiki schema stays `4.0`.

## Automated checks (macOS stand; CI repeats on Ubuntu and macOS)

```bash
python3 scripts/build_skill.py --check
python3 -m unittest discover -s tests -p 'test_*.py' -v
bash tests/skill-contracts.sh < /dev/null
bash tests/install-cross-agent-links.sh
bash tests/uninstall.sh
bash tests/hooks/run.sh
```

`tests/test_release_b.py` (36 cases) covers: identical copies, title-only H1
differences, rules-in-CLAUDE with generated stubs, same-heading conflicts, same
bytes in different scopes, stub with extra text, full line coverage with
frontmatter/fences/repeated headings, canonical-only no-op, same-level wiki
conflict, custom and absolute pointers rewritten relative, both symlink alias
directions, import redirects and dangling imports, private/override files left
alone, missing coverage, stale hashes, dropped critical rule, placed text
missing, agy/Codex budgets, includes, agy `trigger` validation, snapshot mode,
apply+commit with unrelated staged changes, rollback of tracked/untracked/new
files, untracked canonical backup, concurrent edit, custom wiki rediscovery, and
the private state machine with exclude/recover/tracked refusal.

## Independent review

A fresh reviewer agent reproduced 8 defects (commit verification on renames/unicode/spaces,
`rollback --revert` preview and untracked restore, partial-write recovery, custom H1 in stubs,
relocated/inline imports, committing a pre-existing untracked `AGENTS.md`, lost headings/titles,
private name validation/CRLF). All were fixed with regression tests
(`ReviewRegressionTests`) and re-verified by the same reviewer. Known safe limitation:
`GEMINI.md → CLAUDE.md` without `AGENTS.md` is blocked as an unknown alias.

## Real-layout dry runs (owner's 10 wiki projects, scratch mirrors only)

Mirrors contained only instruction files and wiki `index.md`/`schema.md`; the
real projects were not written. Results after `approve --all`:

| Class of project | Count | plan → check → apply → commit |
|---|---|---|
| Already canonical | 1 | no-op |
| Identical copies / title-only / generated stubs | 3 | `ready` without decisions; legacy deleted |
| Rules in one file + stubs, or near-identical | 3 | 1–2 decisions; consolidated |
| Divergent multi-file | 3 | real merge decisions; consolidated |

All 10: wiki selection identical before/after, no legacy left, clean tree.
odoo-enterprise and Health additionally passed apply → rollback with a
byte-identical tree. The dry run found and fixed: import-redirect handling
(`@CLAUDE.md` in `QWEN.md`) and the no-op commit case.

## Native receipts (synthetic repositories, real HOME unchanged)

| Surface | Scenario | Result |
|---|---|---|
| Codex 0.160.0 | Rule only in legacy `CLAUDE.md` + stub `AGENTS.md`: before migration 14 commands to find it; after migration | ✅ 0 commands, token answered |
| Claude Code 2.1.289 | Same fixture after migration, all tools disabled | ✅ |
| agy CLI 1.2.16 | Same fixture after migration, `--sandbox` | ✅ token answered |
| Claude Code | Private flow: before — `CLAUDE.local.md` blocks `AGENTS.md`; checkpoint 1 with `--setting-sources project` (only `.claude/rules` can answer); switch; checkpoint 2 in new sessions — both AGENTS and private rule loaded; `.claude/` ignored, nothing public | ✅ (behavioral evidence in fresh sessions; `/context`/`/memory` are interactive-only) |
| Qwen Code | — | Excluded from acceptance by owner decision; not a pass |
| ChatGPT/GitHub | Bundled `scripts/migrate.py check --snapshot` executed standalone on a materialized snapshot | ✅ helper runs from the bundle; connector session itself not run in this receipt |
