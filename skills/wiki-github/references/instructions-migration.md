# Instruction consolidation — release B

Consolidates legacy `CLAUDE.md`, `.claude/CLAUDE.md`, `GEMINI.md`, `QWEN.md` into
`AGENTS.md` per logical scope, then deletes the approved legacy files. Read
`instructions-audit.md` first; its write boundary still applies to every other
operation. The helper is deterministic and never calls a model:
`python3 <skill>/scripts/migrate.py <command> --project <repo>`.

## When to propose

Propose once per operation (no persistent suppression) after: an explicit skill
update for selected projects, non-absent `wiki init`, or explicit wiki
maintenance. Never on query/status/compact/resume/tool call. One message: which
legacy files exist, what is deterministic, what needs a decision, blockers and
budgets; actions **prepare plan / defer**. Deferring never blocks the originally
authorized wiki edit when wiki selection is unambiguous. Wiki schema stays `4.0`.

## Workflow

1. `plan` — writes a private plan under `<git-dir>/wiki-migration/<id>/plan.json`
   (never in the public tree) and prints a summary: `status` (`ready`,
   `needs-decision`, `blocked`), outputs, deletes, fragment classes, findings,
   inbound references. Classes: `identical`, `generated-pointer-stub`,
   `contained-exact`, `unique`, `conflict-or-unknown`; canonical fragments are
   the destination. Every non-blank line of every source is a fragment.
2. Review. Deterministic entries are pre-approved. For `unique`/`conflict-or-unknown`
   read the source fragment and the draft `AGENTS.md` in the plan, merge
   conflicts, edit `outputs[].content` when needed and set `rewritten: true` for a
   changed fragment. Different headings do not prove absence of conflict.
   Mark decisions with `migrate.py approve --plan <p> --fragment <id>` (or `--all`
   after reviewing everything); use the user's consent already given for this
   migration — do not ask again per fragment unless a new conflict/scope appears.
3. Optional optimization: a separate, skippable plan step using lint check #11
   (`operation-lint.md`) on the drafted `AGENTS.md`. Critical rules and their
   conditions are KEEP; changing/moving/shortening them is DECIDE. Skipping it
   (`approve --skip-optimization`) never bypasses critical-rule or budget checks.
4. `check --plan <p>` — must report `ok: true`. It rejects: stale sources/destinations
   or moved HEAD; a fragment not accounted exactly once; placed text missing from
   its destination (unless reviewed as rewritten); a critical line
   (MUST/NEVER/ЗАБОРОНЕНО/ОБОВ’ЯЗКОВО/…) missing unless explicitly waived in that
   coverage entry; a future-tree discovery result different from the initial
   wiki selection (lost/broken custom pointer, second wiki hazard); an import that
   points at a deleted legacy file; agy `.agents/rules/*.md` without a valid
   `trigger`; files over agy's 24 000-byte budget or a Codex root→cwd chain over
   32 KiB (or the configured `project_doc_max_bytes`). Claude `@path` and agy
   `@[label](path)` includes are not resident for every CLI: inline them or
   approve with `approve --includes`. Coverage proves accounting, not semantic
   equivalence — the agent's review is still required.
5. `apply --plan <p> --write` — re-checks, backs up dirty/untracked/private
   originals under `<git-dir>/wiki-migration/<id>/backup/` (0700/0600), writes
   outputs by replacing the directory entry (a canonical symlink is materialized,
   never written through), deletes only listed legacy paths by literal unlink,
   then re-runs discovery for every planned cwd. Unrelated dirty/staged paths are
   untouched. State: `applied-uncommitted`.
6. `commit --plan <p> [--message]` — one scoped commit of the public manifest
   (`git commit --only -- <paths>`, new files added explicitly, never `git add .`).
   Refuses paths with pre-existing user changes. Push/PR only in the selected
   delivery scope.
7. Recovery: `rollback --plan <p> --write` restores tracked paths from the plan's
   base commit, untracked/dirty ones from backup, and removes new outputs only
   when their hash still matches what the migration wrote. After a commit use
   `rollback --revert` (normal `git revert`). Never `git reset --hard`/`git clean`.

Same-level different valid wiki pointers block the plan; root/nested wikis are
kept per scope. Case variants, unknown symlinks and escapes block. `AGENTS.override.md`,
`.claude/AGENTS.md`, `.qwen/QWEN.local.md` and native settings are reported, not
changed. `GEMINI.md` is also an agy-native rules file: classify agy-specific text
before deleting it; moved agy rules need valid `.agents/rules` frontmatter.

## Private Claude blocker (`CLAUDE.local.md`)

While it exists Claude reads CLAUDE-family files instead of `AGENTS.md`. The
automated flow keeps two human loading checkpoints:

1. `migrate.py private prepare --source <path>/CLAUDE.local.md --write` — exact
   backup, `.claude/rules/<name>.md` in the same scope (relative imports
   recomputed), pattern added to `$GIT_COMMON_DIR/info/exclude`, ignore and index
   verified. The original stays.
2. Checkpoint 1: the user opens a **new** session in that cwd and confirms the
   rules file in `/context`; then `private confirm --checkpoint 1`.
3. `private switch --write` removes the original (backup kept).
4. Checkpoint 2: in another new session the user confirms the private rules in
   `/context` and `AGENTS.md` in `/memory`; then `private confirm --checkpoint 2`.
5. Failure: `private recover --write`. Never flip the global
   `claude-md-and-agents-md` setting automatically; ancestors outside the repo are
   only reported. Private text, maps and backups are never committed or posted.

## Remote (ChatGPT/GitHub)

Materialize the pinned snapshot's instruction files and wiki indexes into a
temporary Git repository, run the bundled `scripts/migrate.py plan` there, review,
then `migrate.py check --plan <p> --snapshot <dir>`. Delete legacy files remotely only
after that check actually passed on the exact proposed outputs; record command,
snapshot SHA and result. If it cannot run, report `coverage not machine-validated`,
keep the legacy files, and delete only after a separate explicit user decision
naming those paths. Direct commit and PR delivery both stay available. Remote mode
cannot see private files, local settings or native loading.
