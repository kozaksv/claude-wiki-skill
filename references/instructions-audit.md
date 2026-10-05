# AGENTS.md-only instructions — release A

Applies to Init, ingest, pointer repair and every instruction-file write.
Release A does **not** consolidate or delete project instruction files. Legacy
`CLAUDE.md`, `GEMINI.md`, `QWEN.md` remain readable, never writable targets.

## Preflight before writes

Run `python3 <skill>/scripts/instructions.py audit --project <instruction-directory> --json`.
Use the directory in which a new/changed `AGENTS.md` would live; for multiple
selected checkouts, repeat `--project`. This reads metadata and the available
default Codex fallback names, not full effective profiles. It runs no agent,
version check, settings repair, migration or telemetry mutation.

Schema `1` reports `projects[]` (`cwd`, `root`, `inventory`, `discovery`,
`claude_blockers`, `preflight`, `warnings`), `exports[]`, and the separate
`runtime_verification: not_run`. Inventory records contain `path`, `scope`,
`kind`, `tracked`, `exact_case`, `private`, and `link_target` for aliases.
The inventory is the shared read-only input to future release-B consolidation;
A's acceptance does not require an implementation of B.

| Preflight state | Allowed instruction action after consent |
|---|---|
| `instruction_empty` | Fresh Init can create `AGENTS.md`. Unknown Codex profiles are a warning, not a gate in an otherwise empty scope. |
| `canonical_present` | Preserve all existing rules. Append a missing Wiki block or repair a stale block only after target selection and consent. |
| `consolidation_required` | No instruction writes. Report the existing legacy/fallback/case-collision/alias. Do not create a short canonical stub that shadows it. |

`wiki absent` does not mean `instructions absent`. An existing canonical
symlink is not a regular writable instruction file in A: never write through it
into a legacy target. Aliases and content consolidation belong to release B.

If Python is unavailable, perform the same bounded presence/default-fallback
preflight with available file tools. Report the missing machine audit, do not
invent its output or call an agent. Unknown effective configuration alone does
not block empty-scope Init. A known existing legacy/fallback file does.

The original no-Git/orphan/partial-wiki gates still apply. In a legacy scope A
may initialize an explicitly approved canonical `docs/wiki/` without a new
pointer. Existing valid custom pointers keep working. A **new** custom location
that would need a pointer in legacy scope waits for B; do not create a second
wiki or promise that new custom location is rediscoverable without a pointer.

## Canonical pointer maintenance

Use the selected target from discovery, never the active harness name. Write
only a regular, exact-case `AGENTS.md`, or create it after empty-scope Init
preflight. Compute paths relative to its directory, including schema/index.
The canonical new block is:

```markdown
## Wiki

Wiki at `{wiki_dir_relative_to_instruction_file}`. Schema → `{schema_path_relative_to_instruction_file}`. Skill: `wiki`.

Read the complete `{index_path_relative_to_instruction_file}` and relevant wiki
pages before a project-specific answer. Cite the pages actually read. Memory
and injected markers do not replace source reads. Use the `wiki` skill to query.
```

Substitute real paths; never embed the index itself. Keep a valid existing Wiki
or Вікі block unchanged (no formatting-only migration). For a stale canonical
block, show and preserve its custom rules before replacing the pointer section
with the full Session-Start contract. Never silently discard extra content.
A stale **legacy** pointer is report-only (`consolidation required`), even on
an explicit pointer-repair request in A. Report this limit; do not repair the
legacy file, create a duplicate, or silently pretend it was repaired.

Ingest may record a newly learned convention only in an existing regular
`AGENTS.md`, after the same preflight and consent rules. Without canonical,
leave all instruction files untouched and report `consolidation required`.
The separately authorized knowledge edit to an unambiguous wiki can still
proceed; preserve the learned convention in that wiki, not in a legacy file.
Lint must not rewrite/condense/delete legacy instruction files in A either:
report its instruction findings. Canonical optimization uses the existing lint
workflow; critical rules and their conditions remain KEEP unless explicitly
reviewed as DECIDE. A dead link is not permission to delete the surrounding rule.

## Selection and write gate

The shared reader contract and `discovery-cases.md` are normative. Same-level
different **valid** wiki pointers block unaddressed writes, including AUTO-lint,
logs, policy/catalog changes and hook metadata. The hook interface returns `3`
with no wiki path for this case. For read-only analysis, the audit reports the
canonical-order selected wiki plus the conflict. An explicit validated target
can resolve the selection for the requested operation, not for unrelated hooks.

Nearest scope still wins. Root-X/nested-Y is not a same-level conflict: report
an observed cross-level difference without blocking valid monorepo workflows.
The hook does not model native loading across four runtimes. Boundary,
protection and consent gates remain independent of this selection rule.

## Doctor and availability

`bash <skill>/hooks/doctor.sh --project <repo> [--json]` combines the existing
hook audit with this instruction/export report. The old top-level hook keys
and hook exit-status meaning are preserved; instruction findings are separate.
A `wiki hooks: verified` line does not verify instruction loading or exports.

For Claude, report only presence/path of `CLAUDE.md`, `.claude/CLAUDE.md`, and
`CLAUDE.local.md` in the selected cwd and ancestors. Do not read their contents
for the presence probe. User `~/.claude/CLAUDE.md`, separately managed files and
`.claude/rules/` are not these blockers. No `claude --version`, version floor,
plugin-mode probe or global settings change. The ancestor check does not extend
the repository boundary or permit reading an external wiki. Private fixes and
native loading/budget analysis belong to B; A merely reports them.

Global exports come from `lib/harnesses.sh --list`. Repair only after consent
with the installed **new** `install.sh --repair-exports`; it never fetches or
switches refs. It verifies agy's replacement before removing an exact-owned
retired Gemini export. Unknown/dangling foreign links and unsafe parent paths
are preserved. Uninstall is separate: no replacement is installed there.
