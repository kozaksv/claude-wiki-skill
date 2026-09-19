## Operation: Query

Read the wiki to answer a project-specific question: architecture, setup,
recipes, decisions, paths, prior findings. Ordinary filesystem inspection such
as pwd or git status needs no wiki query.

1. Select the adapter in SKILL.md: local-reader.md for a checkout, or the
   standalone wiki-github skill for a remote repository.
2. Follow reader-core.md: read the index, resolve actual paths, retrieve the
   relevant evidence and corrections, then answer with source citations.
3. Check the tree before declaring a topic missing from the wiki. Report
   incomplete access or partial reads honestly.
4. Keep querying read-only. Do not manually bump counters, sync pointers,
   install hooks, migrate or create pages. Optional local hooks may record
   their own telemetry; absence of hooks requires no fallback writes.

A useful synthesis may be proposed for crystallization. Write it only when
the user's current or prior request authorizes saving knowledge; then route
to writer-core.md and the appropriate ingest/edit operation. No extra
confirmation is needed for an already authorized write.

Query alone skips the РЕФЛЕКСІЯ block under reflection.md's anti-noise rule.
An authorized synthesis-write follows the writing workflow's reflection rules.
