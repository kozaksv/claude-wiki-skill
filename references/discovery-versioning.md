## Step 0: Discover Wiki Location and Schema

**Before any operation**, locate both the wiki directory and its schema. Follow this sequence:

1. **Require a git root first** — start in the current working directory and walk up parent directories until the nearest ancestor containing `.git/` or a `.git` file (include that directory).

   Git is the foundation of the wiki: snapshots, rollback, lint auto-fixes,
   cleanup, and migration safety rely on commits.

   A `.git` file (used by git worktree and submodules) counts as the git root
   marker for this purpose: it points at real git metadata elsewhere, while
   normal git commands, snapshots, and rollback still work from that working
   tree.

   If a `.git` file points at missing or unreachable metadata (for example, the
   parent worktree was removed), wiki operations may fail at runtime when git
   commands run. Treat that as a user-recoverable state: tell the user to run
   `git worktree repair` or re-create the repo before resuming wiki work; do
   not silently fall back to `git init` in that directory.

   If no `.git/` directory or `.git` file ancestor exists, stop the boundary
   walk. Before refusing, scan for wiki artifacts in the current working
   directory and its ancestors (without a git boundary, because there is none).
   Wiki artifacts include both fully-formed and partial wikis:

   - A `docs/wiki/index.md` file (canonical, fully formed).
   - A `## Wiki` pointer in `CLAUDE.md`, `AGENTS.md`, or `GEMINI.md` that
     resolves to an on-disk `index.md` (pointer-based, fully formed).
   - A `docs/wiki/` directory (or pointer-resolved directory) containing
     any wiki-owned files even when `index.md` is missing: `schema.md`,
     `log.md`, `.usage.json`, `concepts/`, `entities/`, `transcripts/`,
     `archive/`. This catches damaged/partial wikis whose `index.md` was
     removed.

   Pick the nearest such artifact to cwd. This produces two cases:

   - **Orphan wiki detected** (wiki artifacts exist but no git marker):
     the skill **never runs `git init` for an orphan-wiki state**, no
     matter what the user types. The skill cannot reliably know where
     the user's project root is, and any auto-`git init` carries blast
     radius (a wrong location creates a repo that boxes unrelated files
     or sibling projects). The honest, safe behavior is: explain what's
     wrong, tell the user how to fix it, and close the operation
     without writing anything.

     **The gate** is shown regardless of which operation the user asked
     for. It is informational — no consent reply is expected, because
     there's nothing for the user to consent to:

     ```
     У `{absolute_wiki_artifact_directory}` знайдено wiki, але `.git/` немає.
     Wiki не працює без git: snapshots, rollback і cleanup потребують commits.

     Я не запускаю `git init` для orphan-wiki сам, бо тільки ви знаєте,
     де project root вашого проєкту, і помилка в цьому виборі
     створила б `.git/` у неправильному місці (наприклад, охопивши
     несумісні sibling-проєкти або весь `$HOME`).

     Що зробити вручну:
       1. `cd` у директорію вашого project root. Project root — це
          директорія, яка містить wiki (`{absolute_wiki_artifact_directory}`)
          як sub-tree і яку ви вважаєте коренем проєкту (зазвичай
          там лежать `package.json` / `pyproject.toml` / `Cargo.toml` /
          `README.md` / `.gitignore`, etc.).
       2. Виконайте `git init` у цій директорії.
       3. Повторіть оригінальну операцію — Step 0 знайде новий
          `.git/` і продовжить як зазвичай.

     Скіл закриває операцію без змін. Wiki не чіпається.
     ```

     Substitute the wiki-artifact-directory placeholder with the real
     absolute path before showing the prompt. After showing the gate,
     end the operation. Do not parse a reply, do not loop, do not write
     anything (no `git init`, no wiki files, no instruction-file edits,
     no `.gitignore`, no telemetry, no second wiki, no deletion of the
     existing wiki).

   - **No wiki artifacts found** (truly empty for wiki purposes):

     - If the user's requested operation is Init/bootstrap, ask:

       ```
       Wiki потребує git для snapshots, rollback і cleanup safety.
       Git-метадані (`.git/` або файл `.git`) не знайдено для цього проєкту.

       Створити `.git/` у `{absolute_current_working_directory}` і продовжити wiki init? [y/N]
       ```

       Substitute `{absolute_current_working_directory}` with the real absolute
       cwd before showing the prompt. On explicit `y`, run `git init` in that
       displayed current working directory, then restart Step 0 from that
       directory. On anything else, stop and say: `Вікі не буде працювати без git: git є основою wiki для snapshots, rollback і cleanup. Нічого не створено.`

     - If the requested operation is not Init/bootstrap, stop and say: `Вікі не буде працювати без git: git є основою wiki для snapshots, rollback і cleanup. Спершу ініціалізуй git або запусти wiki init і підтвердь git init.`

   The skill runs `git init` from exactly one place — the **absent-state
   Init gate** — and only after explicit `y` from the user. The
   **orphan-wiki repair gate** never runs `git init` itself; it only
   explains the situation and asks the user to handle it manually.
   This split is deliberate: absent-state means cwd is unambiguous (no
   wiki exists yet, the user clearly chose where they're running from),
   while orphan-wiki means a wiki already exists in the user's
   directory structure and the skill has no reliable way to identify
   the matching project root from path strings alone.

2. **Find agent instruction files** — with the git root as the discovery boundary, walk from cwd upward to that root, inclusive. In each visited directory, look for `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md`. If more than one exists, read all of their `## Wiki` sections and validate every referenced wiki path by checking for `{wiki}/index.md`. If their wiki pointers conflict, choose only among valid existing wiki directories: prefer the active agent's valid instruction-file pointer when the active agent is clear; otherwise choose the valid wiki found earliest in the cwd → parent walk (nearest to the current working directory). If the active agent's pointer is broken/stale but another instruction file points at a valid wiki, use the valid wiki and surface the stale pointer as a DECIDE finding during the next lint/cleanup pass. Never prefer a broken active-agent pointer over a valid wiki on disk.
3. **Read the Wiki section** — look for a `## Wiki` section that declares wiki paths (e.g., "Wiki (`docs/wiki/`)")
4. **Verify wiki exists** — check that the discovered directory contains `index.md`
5. **If no `## Wiki` pointer resolved to a valid `index.md`** — this covers two cases: (a) no `## Wiki` section exists in any discovered instruction file, or (b) a `## Wiki` section exists but its pointer is stale/broken (target file does not exist). In either case, fall through to canonical-path search: look for `docs/wiki/index.md` relative to the nearest agent instruction file location, then relative to the current working directory, then relative to the git root. The git-root fallback catches the case where cwd is nested below the project root and no instruction files exist (e.g. `/repo/.git/` + `/repo/docs/wiki/index.md` + cwd `/repo/src/`). A valid on-disk wiki always beats a stale resident pointer — if Step 5 finds `docs/wiki/index.md`, use it and surface the stale pointer as a DECIDE finding during the next lint/cleanup pass.
6. **Locate schema** — wiki schema (layers, operations, conventions, `Entity Categories`, `Document Types`, `File Naming`) lives in exactly one of:
   - **Preferred (v3+):** `{wiki}/schema.md` — canonical location, keeps wiki metadata out of resident agent-instruction context
   - **Legacy (v1–v2):** sections inside an agent instruction file, usually `CLAUDE.md` (`## Wiki`, `## Entity Categories`, `## Document Types`, `## File Naming`)

   Try `{wiki}/schema.md` first. Fall back to agent instruction file sections. When both exist, prefer `schema.md` and surface the duplication as a DECIDE finding during next lint.
7. **If `index.md` is missing but other wiki-owned files exist (partial wiki)** — before declaring "no wiki found", check whether a wiki directory exists with wiki-owned files but lacks a valid `index.md`. The candidate directories to check (in this exact order, all of them, before falling through):

   - any directory referenced by a `## Wiki` pointer (even if its `index.md` is missing or invalid),
   - `docs/wiki/` relative to each instruction file's directory,
   - `docs/wiki/` relative to cwd,
   - `docs/wiki/` relative to the git root (so a partial wiki at the project root is caught even when cwd is nested and no instruction files exist).

   The wiki-owned files that count as evidence: `schema.md`, `log.md`, `.usage.json`, `concepts/`, `entities/`, `transcripts/`, `archive/`. If any such file exists in a candidate wiki directory but `index.md` does not, this is **partial wiki state** — a prior Init/migration may have stopped mid-flow, or `index.md` was accidentally removed. Show this informational gate and end the operation:

   ```
   У `{absolute_wiki_directory}` знайдено артефакти wiki, але `index.md` відсутній.
   Це partial/damaged state — попередня операція Init/migration могла не завершитися,
   або файл випадково видалено.

   Знайдено wiki-owned files:
     - {list_of_found_files}

   Що зробити вручну:
     1. Відновити `index.md` з git history. Git tree paths мають бути
        repo-relative, тому використовуйте `git -C {absolute_git_root}`
        або запустіть з project root:
          `git -C {absolute_git_root} log -- {wiki_path_relative_to_git_root}/index.md`
          `git -C {absolute_git_root} show <hash>:{wiki_path_relative_to_git_root}/index.md > {absolute_wiki_directory}/index.md`
     2. Або move/rename wiki-директорію повністю (наприклад
        `mv {absolute_wiki_directory} {absolute_wiki_directory}.bak`),
        щоб скіл міг створити fresh wiki через `wiki init`.
     3. Повторити оригінальну операцію.

   Скіл закриває операцію без змін. Існуючі файли не чіпаються.
   ```

   Substitute placeholders with real values:
   `{absolute_wiki_directory}` is the absolute path of the wiki dir
   (e.g. `/work/app/docs/wiki/`); `{absolute_git_root}` is the
   absolute path of the git root (e.g. `/work/app/`);
   `{wiki_path_relative_to_git_root}` is the wiki path relative to the
   git root (e.g. `docs/wiki`). Also substitute the actual list of
   found files. After showing the gate, end the operation. Do not
   create wiki files, do not write instruction-file pointers, do not
   touch `.gitignore`/`archive/`/telemetry, do not delete or rewrite
   the existing wiki-owned files. Partial-state recovery is purely
   user-driven, for the same reason orphan-wiki repair is: the skill
   cannot reliably tell which files are the user's real wiki vs.
   stale leftovers.

8. **If wiki not found at all (no `index.md` AND no other wiki-owned files anywhere)** — tell the user: "No wiki found. Would you like me to initialize one?" Then delegate to the **Init (bootstrap-aware)** operation below — it detects project state (5-state model: `absent` / `legacy` / `current` / `older` / `newer`), creates the three-layer structure (`concepts/`, `entities/`, `transcripts/`) with `archive/` outside git, proposes migration for existing artifacts, and writes schema to `{wiki}/schema.md`.
9. **Compare versions** — read `wiki_version` from `{wiki}/schema.md` frontmatter (if absent → state = `legacy`). Read your own `version` from this SKILL.md frontmatter. Determine state per the Versioning & Migration table. If state ≠ `current`, halt the requested operation and follow the migration flow. After the migration completes (or the user declines but keeps the conversation going), resume the originally requested operation. Do not require the user to retype it. The only exception is an explicit user request to stop.

All paths below use `{wiki}` as placeholder for the discovered wiki directory (e.g., `docs/wiki/`). Replace mentally with the actual path.

### Cross-agent instruction-file sync

After Step 0 resolves a valid wiki, keep the project-local resident hints in
sync so every supported agent can rediscover it without user setup. The sync
target is the directory containing the valid instruction-file pointer. If the
wiki was found by fallback (`docs/wiki/index.md`) rather than a pointer, use the
project root under the discovery boundary.

For each of `CLAUDE.md`, `AGENTS.md`, and `GEMINI.md` in that target directory:

- Compute `{schema_path_relative_to_instruction_file}` as the POSIX relative
  path from that instruction file's directory to the resolved `{wiki}/schema.md`.
  Compute `{index_path_relative_to_instruction_file}` analogously for `{wiki}/index.md`.
  Compute `{wiki_dir_relative_to_instruction_file}` as the relative path to the
  wiki directory itself (no trailing `schema.md` / `index.md`). Do not hard-code
  `docs/wiki/...` unless that is the actual relative path from the file being written.
- The canonical `## Wiki` block to write is the **Session-Start Contract pointer**:

  ```
  ## Wiki

  Wiki at `{wiki_dir_relative_to_instruction_file}`. Schema → `{schema_path_relative_to_instruction_file}`. Skill: `wiki`.

  **ОБОВ'ЯЗКОВО на старті сесії:** прочитай `{index_path_relative_to_instruction_file}` ДО
  будь-якої project-specific відповіді (як налаштувати X / де лежить Y / як працює Z /
  «пам'ятаєш як ми...»). Кожна така відповідь МАЄ містити `[[page-name]]` цитати на
  сторінки вікі. Без цитат — баг, переробити. Memory-first заборонено: якщо вікі
  суперечить пам'яті — вікі виграє.

  Для пошуку викликай скіл `wiki` (operation: query).
  ```

  Substitute the three placeholders with real relative paths before writing.
- If the file is missing, create missing minimal instruction files containing
  only a short title and the full Session-Start Contract pointer block above.
- If the file exists and has no `## Wiki` section, append the full pointer block.
- If the file already has a `## Wiki` section that points at the resolved wiki
  (any pointer line that resolves to a valid on-disk wiki — old one-line form,
  Session-Start Contract block, absolute path, or repo-root-style path), leave
  it unchanged. The Session-Start Contract block is the canonical form for
  **new** pointers and **stale-pointer repairs**, not a formatting migration
  for already-valid pointers. If the user wants to upgrade an existing valid
  pointer to the new block, that is an explicit `wiki init` / pointer-repair
  request, not an automatic rewrite.
- If the file points at a different valid wiki, do not overwrite it silently;
  surface the conflict as a DECIDE finding during lint/cleanup.
- If the file points at a stale path and the resolved wiki is valid, repair the
  stale pointer by replacing the `## Wiki` section with the full Session-Start
  Contract block above (since a stale-pointer repair rewrites that section
  anyway). Mention the repair in the response. Surface extra legacy
  schema/details that lived in the old `## Wiki` section as a DECIDE finding.

Run this sync during Init and explicit pointer-repair requests. For non-absent
Init states (`current`, `legacy`, `older`, `newer`), gate writes through the
Non-absent Init consent block in `references/operation-init.md`; inspect and
report first, then write only after explicit approval.

Do not run this sync during status, lint, or query; report missing/stale
pointers as findings and tell the user to run `wiki init` or an explicit
pointer repair if they want the files written. For ordinary read-only project
questions, never interrupt the answer solely to create pointer files.

**CRITICAL: Never create a second wiki.** If you find an existing valid wiki, use it. If an agent instruction file references a wiki path, trust it only after verifying that the directory contains `index.md`; stale pointers are cleanup findings, not permission to bootstrap a second wiki. Only create a new wiki when none exists anywhere in the project.

**Monorepo scope:** the supported default is one canonical wiki per git root marker (`.git/` directory or `.git` file). If multiple sub-projects inside the same repo intentionally maintain separate wikis, treat that as an explicit user/project convention: require an instruction-file pointer in or below the sub-project directory and prefer the closest valid pointer found in the cwd → parent walk. Do not infer multiple wikis from sibling directories on your own.

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

Before executing a migration/init plan, verify that the project is inside a git
repo. If the repo has no commits yet (fresh `git init`), note the unborn HEAD;
otherwise record the current HEAD and list the files/directories the plan
expects to create, move, or edit. If any step fails, stop immediately and
report:

- steps completed
- step that failed and stderr/error reason
- files/directories already created or modified
- safest recovery command(s)

Use Execute checklist numbering when reporting which step failed; if helpful,
also name the related user-facing plan item (for example, "Execute step 6
(`schema.md`, Plan item 1)").

Do **not** continue with later migration steps after a failure. If the repo was
clean before the migration and every changed path is migration-owned, offer to
roll back those paths for the user. For fresh `git init` repos with unborn HEAD,
there is no commit to reset to; the safest recovery is to remove only the
migration-owned paths listed in the failure report. For example, if the failure
report says `docs/wiki/` and `archive/` were the only created paths, then
`rm -rf docs/wiki/ archive/` would be safe; always derive the path list from the
report, not from this example. Do not suggest `git reset --hard HEAD` on an
unborn branch. If the repo was dirty or touched files
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

### 4.2.1 (2026-05-17)
- No schema migration. Init behavior changed: cross-agent skill export self-heal
  during project init and minimal empty-project bootstrap with no invented entity
  categories.

### 4.2.2 (2026-05-17)
- No schema migration. Discovery/init behavior changed: cross-agent
  instruction-file sync keeps `CLAUDE.md`, `AGENTS.md`, and `GEMINI.md` wiki
  pointers aligned for existing and newly bootstrapped wikis.

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
  `GEMINI.md` for new pointers and stale-pointer repairs; already-valid
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
    `AGENTS.md` / `GEMINI.md` resolves to. If Step 0 finds neither,
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

When proposing a migration plan, the skill reads its own SKILL.md frontmatter `version` and the wiki's `schema.md` `## Migration Log` to determine what changed.

### Optional config knobs in `schema.md` frontmatter

Optional `nudge_interval: <N>` in `schema.md` frontmatter overrides the default crystallization periodic nudge frequency (default ~15 tool-calling iterations). Set to `0` to disable the periodic nudge while keeping hard triggers (pre-commit, TodoWrite-completion, explicit user) active. See `references/crystallization.md` for the trigger model.
