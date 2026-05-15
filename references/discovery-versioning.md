## Step 0: Discover Wiki Location and Schema

**Before any operation**, locate both the wiki directory and its schema. Follow this sequence:

1. **Find agent instruction files** — set the discovery boundary first: start in the current working directory and walk up parent directories until the nearest ancestor containing `.git/` (include that directory). If no `.git/` ancestor exists, continue to the filesystem root. In each visited directory, look for `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md`. If more than one exists, read all of their `## Wiki` sections and validate every referenced wiki path by checking for `{wiki}/index.md`. If their wiki pointers conflict, choose only among valid existing wiki directories: prefer the active agent's valid instruction-file pointer when the active agent is clear; otherwise choose the valid wiki found earliest in the cwd → parent walk (nearest to the current working directory). If the active agent's pointer is broken/stale but another instruction file points at a valid wiki, use the valid wiki and surface the stale pointer as a DECIDE finding during the next lint/cleanup pass. Never prefer a broken active-agent pointer over a valid wiki on disk.
2. **Read the Wiki section** — look for a `## Wiki` section that declares wiki paths (e.g., "Wiki (`docs/wiki/`)")
3. **Verify wiki exists** — check that the discovered directory contains `index.md`
4. **If no Wiki section exists** — search for `docs/wiki/index.md` relative to the nearest agent instruction file location, then relative to the current working directory
5. **Locate schema** — wiki schema (layers, operations, conventions, `Entity Categories`, `Document Types`, `File Naming`) lives in exactly one of:
   - **Preferred (v3+):** `{wiki}/schema.md` — canonical location, keeps wiki metadata out of resident agent-instruction context
   - **Legacy (v1–v2):** sections inside an agent instruction file, usually `CLAUDE.md` (`## Wiki`, `## Entity Categories`, `## Document Types`, `## File Naming`)

   Try `{wiki}/schema.md` first. Fall back to agent instruction file sections. When both exist, prefer `schema.md` and surface the duplication as a DECIDE finding during next lint.
6. **If wiki not found at all** — tell the user: "No wiki found. Would you like me to initialize one?" Then delegate to the **Init (bootstrap-aware)** operation below — it detects project state (5-state model: `absent` / `legacy` / `current` / `older` / `newer`), creates the three-layer structure (`concepts/`, `entities/`, `transcripts/`) with `archive/` outside git, proposes migration for existing artifacts, and writes schema to `{wiki}/schema.md`.
7. **Compare versions** — read `wiki_version` from `{wiki}/schema.md` frontmatter (if absent → state = `legacy`). Read your own `version` from this SKILL.md frontmatter. Determine state per the Versioning & Migration table. If state ≠ `current`, halt the requested operation and follow the migration flow. After the migration completes (or the user declines but keeps the conversation going), resume the originally requested operation. Do not require the user to retype it. The only exception is an explicit user request to stop.

All paths below use `{wiki}` as placeholder for the discovered wiki directory (e.g., `docs/wiki/`). Replace mentally with the actual path.

**CRITICAL: Never create a second wiki.** If you find an existing valid wiki, use it. If an agent instruction file references a wiki path, trust it only after verifying that the directory contains `index.md`; stale pointers are cleanup findings, not permission to bootstrap a second wiki. Only create a new wiki when none exists anywhere in the project.

**Monorepo scope:** the supported default is one canonical wiki per `.git` ancestor. If multiple sub-projects inside the same repo intentionally maintain separate wikis, treat that as an explicit user/project convention: require an instruction-file pointer in or below the sub-project directory and prefer the closest valid pointer found in the cwd → parent walk. Do not infer multiple wikis from sibling directories on your own.

**Why schema.md is preferred over agent instruction file sections:** files like `CLAUDE.md`, `AGENTS.md`, and `GEMINI.md` can load into resident context on every session start, so every byte there is paid on every turn. Wiki schema is operational metadata for the wiki itself — it's needed only during wiki operations, not on every conversation. Moving it to `{wiki}/schema.md` reduces resident-context bloat without losing anything, because wiki operations always discover the wiki first anyway.

_Note: this is a v3 evolution from Karpathy's original pattern, which placed schema in resident instruction files such as CLAUDE.md/AGENTS.md. The rationale is purely operational (resident-context cost); the spirit (schema as co-evolved governance document) is preserved. Projects following the original pattern (v1–v2) continue to work via the instruction-file fallback._

## Versioning & Migration

Every wiki has a schema version stored in `{wiki}/schema.md` frontmatter. This is the wiki schema major line, not every skill release:

```yaml
---
wiki_version: "4.0"
last_migration: "2026-05-01"
---
```

The skill itself has a version in this file's frontmatter (`version: "4.2.0"`). For state detection, compare the schema major (`4` for `4.0`, `4.1`, `4.2`) with the skill major (`4` for `4.2.0`). v4.1/v4.2 changed agent behavior and installer behavior, not the on-disk wiki schema; a fresh v4.2 skill can still create `wiki_version: "4.0"` and be current.

### State detection on Step 0

After locating the wiki and reading `schema.md`, compare versions:

| State | Condition | Action |
|---|---|---|
| `current` | schema major from `wiki_version` == skill major version | Continue with operation |
| `legacy` | Wiki exists but `wiki_version` field absent in frontmatter | Identify version interactively, then propose migration |
| `older` | schema major from `wiki_version` < skill major version | Generate migration plan, ask user once |
| `newer` | schema major from `wiki_version` > skill major version | Warn user, ask whether to continue |
| `absent` | No wiki found | Defer to Init operation (bootstrap) |

### Migration plan format

For `older` and `legacy` states, present a single approval block:

```
⚠️ Wiki версії 3.0, скіл — 4.0. Потрібна міграція.

План:
  1. {step 1 description}
  2. {step 2 description}
  ...

Зроблю всі N кроків одразу? [y] / [n] / [пропусти крок N]
```

Wait for explicit `y`. On `n`, abort the operation. On `пропусти крок N`, exclude that step and re-confirm.

### Migration is explicit, not silent

Wiki migrations involve directory/file creation, gitignore changes, and frontmatter additions — user-visible changes that warrant explicit consent. Backfill of missing fields **inside** `.usage.json` records (forward-compat fields like `state`, `protected`, `archived_at`) IS silent. Only structural migrations require the plan-then-confirm flow.

### Migration failure: partial-state handling

Before executing a migration/init plan in a git repo, record the current HEAD and
list the files/directories the plan expects to create, move, or edit. If any step
fails, stop immediately and report:

- steps completed
- step that failed and stderr/error reason
- files/directories already created or modified
- safest recovery command(s)

Do **not** continue with later migration steps after a failure. If the repo was
clean before the migration and every changed path is migration-owned, offer to
roll back those paths for the user. If the repo was dirty or touched files
overlap user work, do not run destructive rollback commands; leave the partial
state visible and ask how to proceed. On the next invocation, re-run Step 0 and
treat the partial state according to what actually exists (`schema.md`,
`wiki_version`, `index.md`), not according to the failed plan's intent.

### Migration Log

`schema.md` carries a `## Migration Log` section that records what changed between versions. Each entry:

```markdown
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
```

When proposing a migration plan, the skill reads its own SKILL.md frontmatter `version` and the wiki's `schema.md` `## Migration Log` to determine what changed.

### Optional config knobs in `schema.md` frontmatter

Optional `nudge_interval: <N>` in `schema.md` frontmatter overrides the default crystallization periodic nudge frequency (default ~15 tool-calling iterations). Set to `0` to disable the periodic nudge while keeping hard triggers (pre-commit, TodoWrite-completion, explicit user) active. See `references/crystallization.md` for the trigger model.
