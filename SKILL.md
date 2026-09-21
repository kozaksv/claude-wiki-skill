---
name: wiki
version: "4.10.0"
description: >
  Read and maintain a project's LLM Wiki: query, init, ingest, edit, lint,
  cleanup, split, protect and status. Use for wiki/вікі requests and
  project-specific architecture, setup, decisions and recipes. Read relevant
  wiki evidence before answering; use the GitHub adapter for remote repos.
---

# LLM Wiki

A persistent knowledge base of project decisions and synthesized understanding.
Use the smallest workflow that covers the request. Shared reading/writing rules
are independent of the filesystem or GitHub transport.

## Choose the Access Mode First

- **Remote repository:** load [skills/wiki-github/SKILL.md](skills/wiki-github/SKILL.md).
  It supports reading and authorized wiki changes through the connected GitHub
  tools. A scratch filesystem alone is not a checkout of the target repository.
  The repository used to install this skill is not automatically the target.
- **Local checkout, question or inventory:** load
  [references/local-reader.md](references/local-reader.md) and
  [references/reader-core.md](references/reader-core.md). Do not load migration
  and telemetry instructions for ordinary reading.
- **Local maintenance:** load [references/writer-core.md](references/writer-core.md),
  [references/discovery-versioning.md](references/discovery-versioning.md), and
  the operation reference below. Existing user authorization covers its scope;
  do not ask again for permission already supplied.
- An explicit request about a GitHub ref selects that snapshot even if a local
  checkout exists. A request for local changes selects the checkout.

Installed skills provide the workflow; GitHub provides repository access.
Merely storing a SKILL.md or AGENTS.md in a repository does not install a skill
in a ChatGPT account. The standalone ChatGPT skill bundles the shared contracts;
maintainers regenerate that bundle with `python3 scripts/build_skill.py`.

## Platform Compatibility (Local Workspace)

| Generic action | Claude Code | Codex | Gemini CLI | Qwen Code |
|---|---|---|---|---|
| Read files | Read | file/shell tools | read_file | read_file |
| Edit files | Edit/Write | apply_patch | file/shell tools | edit/write_file |
| Run commands | Bash | exec_command | shell tool | shell |
| Track tasks | TodoWrite | update_plan | native tasks | native tasks |

Translate reference tool names to available equivalents; do not invent tools.

## Session-Start Contract

1. **READ FIRST:** read the complete wiki index, then relevant topic pages
   before a wiki-backed answer. Follow the shared reader contract for ranges,
   truncation, current rules, historical incidents and correction notices.
2. **CITE:** support project claims with sources actually read. Use wikilinks
   where rendered, clickable file/GitHub links in ChatGPT. Identify inferences
   and sources outside the wiki.
3. **NO MEMORY-FIRST:** memory and an index marker are not source evidence.
   A legacy `WIKI INDEX (hook-injected)` block may have been truncated by the
   host. A new `WIKI DISCOVERY (hook)` block supplies a path only. Neither
   satisfies READ FIRST; explicitly read the index.
4. **GAPS:** an index omission is not proof that no page exists. Check actual
   paths before declaring a gap; distinguish a failed read from absence.

A query has no agent-initiated writes: no manual telemetry bumps, migration,
pointer sync, hooks installation or automatic filing back. A user's request to
save or change knowledge invokes the writing workflow. Independently installed
hooks may continue their optional local telemetry.

## Reference Loading Map

| User intent / operation | Required references |
|---|---|
| Update the installed skill / repair hook registration | `references/updating.md` |
| Read or change a remote GitHub wiki | `skills/wiki-github/SKILL.md`; it routes reading and writing |
| Ask project-specific questions | `references/local-reader.md`, `references/reader-core.md`, `references/operation-query.md` |
| Create / initialize / migrate a local wiki | `references/discovery-versioning.md`, `references/wiki-structure.md`, `references/operation-init.md`, `references/writer-core.md`, `references/telemetry.md`, `references/reflection.md` |
| Add source Markdown/spec/code knowledge | `references/discovery-versioning.md`, `references/wiki-structure.md`, `references/operation-ingest-source.md`, `references/writer-core.md`, `references/telemetry.md`, `references/reflection.md` |
| Add binary artifact from tmp/ | `references/discovery-versioning.md`, `references/wiki-structure.md`, `references/operation-ingest-binary.md`, `references/telemetry.md`, `references/reflection.md` |
| Print local wiki status | `references/local-reader.md`, `references/operation-wiki-status.md`, `references/telemetry.md`, `references/maintenance-and-mistakes.md` |
| Run lint / verify wiki health | `references/discovery-versioning.md`, `references/operation-lint.md`, `references/writer-core.md`, `references/telemetry.md`, `references/maintenance-and-mistakes.md` |
| Diagnose/repair wiki+hooks health | `references/discovery-versioning.md`, `references/operation-doctor.md`, `references/telemetry.md`, `references/maintenance-and-mistakes.md` |
| Split a large page | `references/discovery-versioning.md`, `references/wiki-structure.md`, `references/operation-split.md`, `references/writer-core.md`, `references/telemetry.md`, `references/reflection.md` |
| Cleanup / resolve lint/status actions | `references/discovery-versioning.md`, `references/operation-cleanup.md`, `references/operation-lint.md`, `references/cleanup-flow.md`, `references/writer-core.md`, `references/maintenance-and-mistakes.md` |
| Reflection / crystallization | `references/reflection.md`, `references/crystallization.md`, `references/cleanup-flow.md`, `references/self-improvement.md` |
| Catalog, durable protection, current/history layout | `references/wiki-maintenance.md` |
| Optional telemetry / wiki navigation | `references/telemetry.md`, `references/wiki-structure.md` |

If a required reference is missing, report the missing file rather than
inventing its instructions.

## Local Maintenance Invariants

- One real git clone, one canonical `~/.claude/skills/wiki` entrypoint and
  symlink exports for Codex, Gemini and Qwen. Claude need not be installed.
- Git backs maintenance snapshots and rollback. Discovery walks only to the
  nearest Git boundary and rejects resolved paths escaping the repository.
- `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `QWEN.md` are pointer sources.
  Validate candidates by their index. A broken active-agent pointer cannot
  hide a valid wiki or authorize creation of another wiki.
- Use the canonical `hooks/lib/discover.sh` parser for local discovery.
  It accepts `## Wiki`, `## Вікі`, case variants and heading suffixes.
- Track durable protection in `policy.json`; keep usage counters local.
  Resolve legacy protection before destructive work, and block on corrupt
  protection metadata. Optional telemetry failure must not block a query.
- `doc-extract` is needed only for ingest-binary.
- Content determines staleness. Telemetry only prioritizes verification.
- Keep resident instruction files short; schema and procedures live in wiki
  or skill references. Keep dated history separate from current guidance.
