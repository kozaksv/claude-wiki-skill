# Historical wiki release log examples

Superseded behavior is history, not current instruction-file policy.

```markdown
### 4.12.0 (2026-10-05)
- No schema migration. Release B: deterministic consolidation of legacy
  instruction files into AGENTS.md (`scripts/migrate.py` plan/check/apply/commit/rollback),
  automated private CLAUDE.local.md move with two loading checkpoints, update-time proposal.

### 4.11.0 (2026-10-05)
- No schema migration. Release A: AGENTS.md-only writes, agent-neutral discovery,
  agy CLI export (`~/.gemini/config/skills`), Gemini CLI retired.

### 4.0 (2026-05-01)
- Added `.usage.json` telemetry sidecar
- Added `wiki_version` frontmatter to schema.md
- Added РЕФЛЕКСІЯ block as required behavior
- Added Tiered crystallization
- Added `wiki status` operation
- Reformulated Lint as Karpathy content-verification

### 4.1 (2026-05-07)
- No schema migration. Skill behavior changed: removed user-runnable script crystallization tier and added proactive query triggers.

### 4.2 (2026-05-14)
- No schema migration. Installer/discovery behavior changed: shared canonical cross-agent exports and agent-neutral instruction-file discovery.

### 4.2.1 (2026-05-17)
- No schema migration. Init behavior changed: cross-agent skill export self-heal
  during project init and minimal empty-project bootstrap with no invented entity
  categories.

### 4.2.2 (2026-05-17)
- No schema migration. Discovery/init behavior changed: cross-agent
  instruction-file sync keeps `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, and
  `QWEN.md` wiki pointers aligned for existing and newly bootstrapped wikis.

### 4.2.3 (2026-05-17)
- No schema migration. Tightened repair behavior: instruction pointers use paths
  relative to each instruction file, status/lint/query stay read-only, and
  repair-only installer mode reports partial conflicts precisely.

### 4.2.4 (2026-05-17)
- No schema migration. Tightened consent and planning behavior: non-absent Init
  repair actions require explicit approval, user-facing plans hide raw template
  placeholders, and already-valid pointer text is not reformatted.

### 4.2.5 (2026-05-17)
- No schema migration. Tightened non-absent Init again: project-local pointer
  writes and global export repairs share one explicit consent block, and
  migration failure reports use Execute checklist numbering.

### 4.2.6 (2026-05-17)
- No schema migration. Clarified the consent contract across recovery docs,
  scenarios, and migration-plan templates: non-absent Init repairs inspect
  first and write nothing without explicit approval.

### 4.2.7 (2026-05-17)
- No schema migration. Polished non-absent Init wording: consistent
  user-facing repair labels, explicit single-repair migration-plan handling,
  and a stronger recovery diagnostic for exported skills.

### 4.2.8 (2026-05-17)
- No schema migration. Git is now a hard prerequisite for every wiki operation:
  non-git Init must ask before running `git init`, and all other non-git wiki
  operations stop with an explanation instead of creating or using a wiki.

### 4.2.9 (2026-05-17)
- No schema migration. Step 0 now distinguishes orphan-wiki state (wiki
  artifacts exist but no git marker) from truly empty projects: any operation
  in an orphan-wiki project shows an active `git init` repair gate that
  preserves the existing wiki, instead of suggesting `wiki init` for a wiki
  that already exists.

### 4.2.10 (2026-05-17)
- No schema migration. Lint heads-up dialog is now size-gated: wikis with
  fewer than 20 active unprotected pages start full verification immediately
  without asking about `швидко` / topic / path scope.

### 4.9.0 (2026-09-19)

- Shared reader/writer contracts and separate filesystem/GitHub adapters.
- ChatGPT can prepare authorized edits and wiki PRs, not only read.
- Query does not initiate telemetry, migration or pointer writes.
- Deterministic optional catalog/index, tracked policy with legacy-pin
  migration, and a current/history layout; existing v4 Markdown stays readable.
- The hook emits a small discovery notice and never claims READ FIRST.
  This supersedes the historical v4.5 injection description below.
- Wiki/Вікі heading variants and active-agent priorities use the same tested
  parser for local hooks and maintenance. No schema-major migration.

### 4.8.0 (2026-09-19)
- No schema migration (`wiki_version` stays `"4.0"`). Add the self-contained
  `skills/wiki-github/SKILL.md` read adapter and a ChatGPT plugin manifest.
  Remote queries use the selected repository/ref as their boundary, read
  through GitHub, and cite actual files without local telemetry or sync.
  Local installation, hooks, and mutating operation contracts are unchanged.

### 4.7.0 (2026-08-14)
- No schema migration (`wiki_version` stays `"4.0"`); zero per-wiki migrations
  required for existing wikis. The РЕФЛЕКСІЯ block's crystallization field is
  renamed to `Кристалізація:` (it previously carried the automation-era name).
  This is an agent-visible contract only: the block is printed into the turn and
  never persisted — `{wiki}/log.md` keeps its own entry format — so nothing on
  disk is rewritten. The crystallization reference is stripped of scaffolding
  left by the tier model removed in 4.1 and 4.4. The dead active-state filter is
  dropped from the lint and `wiki status` subsets: the subset is now filtered by
  `protected == false` only, and the page counts printed in the lint heads-up are
  unchanged because that filter always passed everything. The `.usage.json`
  record shape is unchanged — `state`, `protected` and `archived_at` are still
  present in every record.

### 4.6.0 (2026-08-13)
- No schema migration (`wiki_version` stays `"4.0"`); zero per-wiki migrations
  required for existing wikis. Native Qwen Code support added: agent-neutral
  discovery now spans four instruction files instead of three —
  `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `QWEN.md` — as equal pointer
  sources, all validated the same way (`{wiki}/index.md` must exist).
  Discovery's bounded walk, Cross-agent instruction-file sync, and the
  resident-context rationale note all cover `QWEN.md` alongside the other
  three files. Step 0's file-conflict rule gained an explicit deterministic
  tie-breaker for the case where the active agent is unclear and more than
  one instruction file at the same walk depth points at a different valid
  wiki: fall back to file-priority order `CLAUDE.md` → `AGENTS.md` →
  `GEMINI.md` → `QWEN.md`, first valid pointer wins. Operation Init mirrors
  the same four-file coverage (active-agent inference, contract-bound wiki
  location, project pointer sync, migration-plan templates) and gained a
  fourth cross-agent skill export check: `~/.qwen/skills/wiki`.

### 4.5.1 (2026-08-10)
- No schema migration (`wiki_version` stays `"4.0"`); nothing to migrate on
  existing wikis. Three defects found while bootstrapping a fresh wiki in a
  Ukrainian-language project:
  - **The pointer section now also accepts `## Вікі`.** Step 0 matched only
    `## Wiki`, so an instruction file headed `## Вікі проєкту` read as having no
    pointer at all. That is a duplication hazard, not a cosmetic miss: for a
    wiki declared under a Ukrainian heading at a non-canonical path, discovery
    finds nothing and Init bootstraps a **second** wiki beside the real one.
    Recognition accepts both spellings; `## Wiki` stays canonical for writes,
    and a valid pointer under a Ukrainian heading is left unchanged.
  - **Init keeps the layer directories in git.** `concepts/`, `entities/`, and
    `transcripts/` are created empty, and git does not track empty directories
    — so the skeleton the bootstrap plan promises vanished on the first clone.
    Init now writes a `.gitkeep` into each empty layer directory.
  - **The installer reports the hook step.** `install.sh` ran
    `install-hooks.sh` silently and its final summary never mentioned hooks, so
    the only way to find out whether SessionStart/PostToolUse were registered
    was to read `~/.claude/settings.json` by hand. The summary now states the
    outcome and that hooks take effect from the *next* session. The same block
    called them "git hooks", which they are not.

### 4.5.0 (2026-07-08)
- No schema migration (`wiki_version` stays `"4.0"`); zero per-wiki
  migrations required for existing wikis. All new artifacts are host-side:
  optional global Claude Code session hooks
  (`~/.claude/skills/wiki/hooks/…`, registered via canonical symlink path in
  `~/.claude/settings.json`) that auto-inject `{wiki}/index.md` at session
  start and heartbeat `.usage.json` telemetry, plus the `hooks/` directory
  shipped inside this skill's own repo. Session-Start Contract clarified:
  a hook-injected index block satisfies READ FIRST for `index.md` only,
  never a substitute for reading/citing topic pages, and never proof by
  itself that PostToolUse telemetry is alive (see `references/telemetry.md`
  dual-signal rule). New `## Operation: Wiki Doctor`
  (`references/operation-doctor.md`) diagnoses wiki *and* hook health
  read-only. New Hook provisioning subsection (this file) offers one-time
  per-session opt-in installation, gated on Claude Code + a found wiki + no
  existing inject-block + no `~/.claude/wiki-hooks-optout` marker.

### 4.4.0 (2026-07-07)
- No schema migration (`wiki_version` stays `"4.0"`); zero migrations required
  for existing wikis. Crystallization is now wiki-only: the skill tier is
  removed, so the old delegation-vs-direct-create topology no longer exists.
  The embedded cleanup-prompt is removed; the cleanup-flow is now
  single-entry via `wiki status` instead of being offered inline after every
  reflection. Motivation: prompt fatigue from the emoji cleanup-prompt asking
  after every reflection, plus an unused skill tier whose
  installer-safety/export-topology surface never paid off in practice.
- Hardened alongside the simplification: destructive cleanup ops
  (`видали`/`merge`/`розбий`) now commit the destructive change itself —
  snapshot fires only when uncommitted wiki edits exist, no empty marker
  commits — so `git revert HEAD` genuinely undoes the destruction; lint
  snapshot staging targets the resolved `{wiki}` path instead of a hard-coded
  `docs/wiki/`; stale-pointer repair quotes captured legacy `## Wiki` content
  in the repair response and defers its DECIDE finding to the next lint pass
  (no interactive dead-end during Init/repair).

### 4.3.0 (2026-06-02)
- No schema migration (`wiki_version` stays `"4.0"`). New on-disk artifact:
  `{wiki}/log/{YYYY-MM-DD}_to_{YYYY-MM-DD}.md` shards, created lazily by
  **log rotation**. `{wiki}/log.md` now has a soft cap of 2000 lines; on
  each log write, if the file is over cap, the oldest contiguous entries
  are peeled into a date-range-named shard until the live log drops to
  ~1000 lines. See `references/wiki-structure.md` → `## Log Rotation` for
  the algorithm, shard naming, edge cases (single-date overflow, corrupt
  log, missing `log/` dir, shard write failure), and reading semantics.
  Existing wikis pick this up organically: an oversized `log.md` rotates
  on its next log write, no migration prompt. An older skill (≤ 4.2.x)
  reading a wiki that has rotated still sees a valid `log.md` (it just
  won't see archived history in `log/`); this is the reason the schema
  bump was deferred — change is additive, not breaking. Motivation:
  `log.md` previously grew unbounded; very active wikis would eventually
  hit the Read-tool pagination cliff at ~2000 lines. Activity-driven
  rotation (not calendar-driven) bounds live-log size without producing
  empty/tiny shards for quiet projects.

### 4.2.21 (2026-05-27)
- No schema migration. Agent-behavior hardening: introduced
  **Session-Start Contract** in SKILL.md as a NON-NEGOTIABLE block
  contract — agent must read `{wiki}/index.md` before any
  project-specific answer in a wiki-backed project, and every such
  answer must carry `[[page-name]]` citations. Added Red-Flags
  rationalization table and Session-Start Checklist. Operation Query
  «Master rule» rephrased as **BLOCKING RULE (NON-NEGOTIABLE)** with
  explicit «no citations = bug, retry» clause. Cross-agent
  instruction-file sync now writes a full Session-Start Contract
  pointer block (not a one-line pointer) to `CLAUDE.md` / `AGENTS.md` /
  `GEMINI.md` / `QWEN.md` for new pointers and stale-pointer repairs; already-valid
  pointers are left unchanged (no formatting migration). Empty-Wiki
  Exception preserved: agent says «у вікі нема, відповідаю з training»
  and marks topic for crystallization. Motivation: agents were
  default-answering from memory and skipping wiki reads despite the
  «proactive query» description; soft language let them rationalize.

### 4.2.20 (2026-05-17)
- No schema migration. Three contract clarifications close iterations
  4.2.11–4.2.19, which tried successively to derive a safe
  project-root guess from the wiki path (walk-up to instruction files,
  canonical-suffix strip, ambiguity tie-breakers, single/two-candidate
  menus, absolute-path override with validation, pre-bootstrap stray
  scan). Each closed one edge case (nested cwd, pointer escaping
  upward, canonical-vs-legacy ambiguity, non-standard layouts, broad
  `/` or `$HOME` overrides, false positives on ordinary `docs/index.md`,
  partial-wiki misclassification as absent) and surfaced another:

  - **Orphan-wiki repair is fully manual.** When a wiki exists on
    disk but no git marker does, the gate is informational only —
    explains the situation, lists the manual fix (`cd` to project
    root → `git init` → retry), and ends the operation. The skill
    never runs `git init` for an orphan-wiki state under any
    condition. `[y]` is reserved exclusively for the absent-state
    Init gate.

  - **Wiki location is contract-bound.** A project's wiki lives at
    `docs/wiki/` or wherever a `## Wiki` pointer in `CLAUDE.md` /
    `AGENTS.md` / `GEMINI.md` / `QWEN.md` resolves to. If Step 0 finds neither,
    the project is considered to have no wiki — period. Init does
    not scan for stray `index.md` or wiki-like content in
    non-canonical locations. Users who want a wiki outside
    `docs/wiki/` must declare it via a `## Wiki` pointer before
    running any wiki operation; otherwise Init bootstraps a fresh
    wiki at the canonical path.

  - **Partial wiki state is detected and protected.** A wiki
    directory with wiki-owned files (`schema.md`, `log.md`,
    `.usage.json`, `concepts/`, `entities/`, `transcripts/`,
    `archive/`) but missing `index.md` is partial state, not
    absent. Step 0 halts with an informational gate listing the
    found files and the manual recovery options (restore
    `index.md` from git history, or move the directory aside and
    re-init). Init's absent-state bootstrap does not run on
    partial wikis, so existing `schema.md`, `log.md`, telemetry,
    and concept pages are never overwritten.
```
