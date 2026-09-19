# Shared Wiki Writing Contract

Use for an authorized create, update, ingest, protect, split, merge, or delete
request. Read the shared reader contract first. An ordinary question does not
authorize filing the answer back. A request to change the wiki does authorize
preparing and delivering the requested changes; do not repeatedly ask for
permission already given. Support both a direct commit and a branch/PR.
Honor an explicitly requested mode ("закоміть у master", "без PR", "зроби PR")
or the user's established project preference. PR is not a mandatory gate.
Absent a preference, use a PR for review; do not ask merely to choose a mode.
An optional project convention in schema.md can record `write_mode: direct`
or `write_mode: pull_request` and `write_branch: master`; it routes already
authorized writes and does not authorize writes in response to a question.
An explicit branch overrides that convention; otherwise verify the default
branch from repository metadata instead of guessing master/main.

## Prepare changes

1. Establish the target wiki and base snapshot. Read `schema.md`, `index.md`,
   the full files to change, relevant sources, and `policy.json` if present.
   Check inbound links before a rename, merge, split, or deletion. Do not
   replace a whole file from a truncated read. Follow the repository's scoped
   conventions; do not copy private wiki examples into the skill source repo.
2. Preserve project frontmatter, sources and useful synthesis. Record a current
   rule with evidence and qualification; keep dated incidents and measurements
   explicitly historical. Put growing history in `history/<topic>-<period>.md`
   and retain a concise current topic page at its stable path. Link both ways.
   Rebase relative Markdown links when moving text, preserve code blocks and
   source attribution, and inspect callers of changed headings.
3. Resolve durable protection from `policy.json` (format below). Before a
   destructive action, merge-source removal, split, or automated lint fix,
   check every affected page. A protected page requires explicit unprotect
   authorization first; a request to delete alone does not unprotect it.
   Preserve/inherit protection when an explicitly authorized restructure moves
   protected content. Missing telemetry cannot erase durable protection.
4. Update curated navigation and cross-links as needed. If catalog generation
   is enabled, regenerate `catalog.json` and the managed block in `index.md`
   from the proposed final tree. The managed block lists every knowledge page
   at an exact path; preserve manual prose/categories outside its markers.
   Do not hand-invent hashes, sizes or section ranges. The bundled
   `scripts/wiki.py catalog --wiki <path> --write` performs regeneration when
   an execution environment is available. Never claim that a stale catalog
   was validated. If deterministic generation cannot run, prepare the edits
   and identify that outstanding check in the PR; do not remove a CI gate.
5. Append a concise entry to `log.md` following its existing convention. Keep
   one entry for the logical change, not each tool call. Handle existing log
   rotation conventions; do not create telemetry or install hooks remotely.

## Validate and deliver

Review the complete diff: intended files only, no source-text loss, valid
frontmatter/JSON, real link targets, protection respected, current/history
distinction preserved. Run repository checks and catalog `--check` when
available. Distinguish checks run from checks still pending.

The adapter publishes the changes against the base snapshot and verifies the
result. Report what changed, the PR/commit or local diff, checks performed,
and material limitations. In direct mode, report the verified commit and
branch. In PR mode, do not equate creating a PR with merging it or publishing
changes to the default branch.

## Durable policy and compatibility

Track `{wiki}/policy.json` in Git; never add it to `.gitignore`:

```json
{
  "version": 1,
  "pages": {
    "concepts/recovery.md": {"protected": true}
  }
}
```

Paths are exact wiki-relative paths. Each record has a boolean `protected`.
An explicit policy record wins, including `false` from an authorized
unprotect. Locally, absent records fall back to the union of legacy
`.usage.json` `protected`/`pinned`; absence of both means unprotected. Preserve
legacy true flags during migration; keep counters untouched. Invalid policy
or unreadable/corrupt legacy protection blocks destructive operations rather
than silently defaulting to unprotected. Ordinary reading remains available.

Remote Git cannot see gitignored pins in another clone. Without a committed
policy, non-destructive edits may proceed, but destructive operations require
the user to confirm protection status or migrate the relevant clone first.
Report this actual limitation only when it affects the requested operation.

`scripts/wiki.py migrate-policy --wiki <path>` previews the migration;
`--write` saves it. `protect` / `unprotect` update policy, preserving legacy
pins for other pages. These commands change policy, not page view counters.
Old hooks may keep legacy fields for backward compatibility; new operations
must resolve effective protection from the versioned policy first.
