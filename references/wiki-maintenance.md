# Deterministic Maintenance Tools

Run with Python 3.9+; no packages or network are required. Commands accept an
explicit wiki path. The caller establishes the Git boundary, authorization
and reviewable snapshot using the selected adapter. Helpers do not commit,
push, install hooks or request credentials. Inspect exit status before claiming
success. Query can read old Markdown without running any helper.

## Generated navigation

```bash
python3 <skill>/scripts/wiki.py catalog --wiki docs/wiki
python3 <skill>/scripts/wiki.py catalog --wiki docs/wiki --write
python3 <skill>/scripts/wiki.py catalog --wiki docs/wiki --check
```

Default prints a fresh inventory without writes. `--write` generates
`catalog.json` and a managed block in the existing `index.md`; it preserves
curated prose and categories outside `<!-- wiki:catalog:start -->` and
`<!-- wiki:catalog:end -->`. `--check` fails for missing/stale metadata, omitted
pages, additions, deletions or changed content. Malformed markers are errors.
Catalog hashes cover the actual file bytes; output has no clock timestamps,
so regeneration is deterministic and idempotent. A catalog is a generated
inventory, not a hand-maintained synthesis table; lint must not remove it as
the derivable-inventory anti-pattern.

Membership: all Markdown below the wiki, including custom paths, transcripts
and `history/`, except root index/schema/log, `log/` shards and hidden paths.
Symlinks and special files fail inventory rather than silently producing a
partial catalog. Section ranges cover H2 headings outside fenced code and
frontmatter; readers must verify blob IDs before trusting stored ranges.

Catalog format version 1 contains `pages` sorted by path. Each row has `path`,
`title`, `bytes`, `sha256`, `git_blob_sha1`, `kind` (`page` or `history`) and
`sections` (heading, level, 1-based start/end line). No commit ID is embedded:
the enclosing Git snapshot already provides it without self-reference.

Opt existing wikis in during authorized maintenance; do not modify them on
read. After opting in, regenerate after every content/path change and run
`--check` in the repository's CI. `action.yml` exposes the same checker as a
reusable action; pin its release commit. A wiki owner only needs to enable
that repository workflow once, independently of installing the ChatGPT skill.

## Durable protection

```bash
python3 <skill>/scripts/wiki.py migrate-policy --wiki docs/wiki
python3 <skill>/scripts/wiki.py migrate-policy --wiki docs/wiki --write
python3 <skill>/scripts/wiki.py protect --wiki docs/wiki --page concepts/recovery.md
python3 <skill>/scripts/wiki.py unprotect --wiki docs/wiki --page concepts/recovery.md
python3 <skill>/scripts/wiki.py policy-report --wiki docs/wiki
```

Migration previews by default; writing creates tracked `policy.json` and
preserves every legacy true pin that has no explicit policy record. Counters
are never changed. Explicit policy false overrides a legacy true, permitting
an authorized unprotect to persist across clones. Unknown/corrupt policy
versions and invalid legacy flags are errors, not an unprotected default.
Commit the policy; never put it in `.gitignore`. See `writer-core.md` for
remote legacy-policy limitations and enforcement.

## Current guidance and history

Keep a stable topic path with current rules, status/correction notices,
sources and links to history. Put dated incident narratives under `history/`;
history files link back to the current topic. Do not append an unbounded
incident journal to the current runbook. Do not classify a section by age
alone: read it and determine what is still normative.

For an already isolated H2 history section, the helper can move its body
without rewriting the rest of the page:

```bash
python3 <skill>/scripts/wiki.py split-history --wiki docs/wiki \
  --page concepts/topic.md --heading History \
  --destination history/topic-2026.md
```

Default previews both files. `--write` also refreshes catalog/index, refuses
protected pages or existing destinations, and rolls back ordinary write
failures. The command retains the source H2 anchor and adds reciprocal links.
The automatic helper is deliberately limited to simple, link-free ATX sections.
Possible Setext underlines (`===` / `---`, including ambiguous thematic breaks)
outside YAML frontmatter and fenced code require the reviewed Split workflow;
they are refused before preview or write rather than guessing section boundaries.
Link/HTML markers in the selected heading or body also require review, including
full, collapsed and shortcut references, images and wikilinks. This conservative
guard also refuses literal markers in code; it is not a complete Markdown parser.
The reviewed workflow relocates relative URLs, heading links and reference
definitions using the whole source document. Catalog reading remains available.
The helper does not synthesize new rules, select a section by size, or rewrite
inbound links automatically. For mixed current/history text, use `operation-split.md`.

Writes use atomic replacement per file, with preflight and rollback of ordinary
errors. A process/power interruption across multiple files still needs Git
recovery; re-run validation before committing. Concurrent maintenance writers
must use isolated worktrees/branches or external serialization.
