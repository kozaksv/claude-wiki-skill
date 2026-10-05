## Step 0: Discover Wiki Location and Schema

For ordinary questions, use `local-reader.md` and `reader-core.md` instead.
For local maintenance, execute `hooks/lib/discover.sh` for path discovery.
Use `instructions-audit.md` before any instruction write. Priority is agent-
neutral; `WIKI_DISCOVERY_AGENT` no longer changes selection. A same-level
conflict returns exit 3 without a path; audit reports the read-only selection.
Its tested parser is canonical: ignore fenced code, accept Wiki/Вікі H2
headings with suffixes, stop at H1/H2, and validate within the Git boundary.
The explanation below defines maintenance state handling after discovery.

This reference describes the local-workspace adapter. For a remote repository
read through GitHub, use `skills/wiki-github/SKILL.md` instead; local `.git`,
hook provisioning, instruction-file sync, and migration gates do not apply.

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
   - A `## Wiki` pointer in `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, or
     `QWEN.md` that resolves to an on-disk `index.md` (pointer-based, fully
     formed).
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

2. **Find agent instruction files** — walk cwd to the nearest Git boundary,
   inclusive. At each level validate exact-case `AGENTS.md`, `CLAUDE.md`,
   `GEMINI.md`, `QWEN.md` pointers in that order, independent of active agent.
   Inspect every candidate at the nearest valid level. Same-level different
   valid wikis: warned read-only selection; no unaddressed writes (including
   AUTO-lint and hooks) until an explicit target resolves that operation.
   Root-X/nested-Y: nearest wins, cross-level difference is warning only.
   Stale pointers do not hide valid ones. See reader-core.md/discovery-cases.md.
3. **Read the pointer section** — look for the section that declares wiki paths (e.g., "Wiki (`docs/wiki/`)").

   **What counts as the pointer section.** A level-2 heading whose text starts with `Wiki` or `Вікі`, case-insensitive, optionally followed by more words. `## Wiki`, `## Вікі`, and `## Вікі проєкту` are all the pointer section; `## Wiki notes` is too. Both spellings are recognized on **read**; `## Wiki` remains the canonical form for **writes** (new pointers and stale-pointer repairs).

   Recognizing the Ukrainian spelling is not cosmetic politeness. This skill's user-facing language is Ukrainian, so a project whose instruction files are written in Ukrainian will naturally head that section `## Вікі` — and a discovery that only matches `## Wiki` then reports "no wiki found" for a project that plainly has one. If that project's wiki also lives outside `docs/wiki/`, the canonical-path fallback in step 5 finds nothing either, and Init proceeds to bootstrap a **second** wiki — the exact outcome the never-create-a-second-wiki invariant exists to prevent. A heading written in the user's own language must never be the reason the skill duplicates their wiki.
4. **Verify wiki exists** — check that the discovered directory contains `index.md`
5. **If no pointer section resolved to a valid `index.md`** — this covers two cases: (a) no pointer section (`## Wiki` / `## Вікі`) exists in any discovered instruction file, or (b) a pointer section exists but its pointer is stale/broken (target file does not exist). In either case, fall through to canonical-path search: look for `docs/wiki/index.md` relative to the nearest agent instruction file location, then relative to the current working directory, then relative to the git root. The git-root fallback catches the case where cwd is nested below the project root and no instruction files exist (e.g. `/repo/.git/` + `/repo/docs/wiki/index.md` + cwd `/repo/src/`). A valid on-disk wiki always beats a stale resident pointer — if Step 5 finds `docs/wiki/index.md`, use it and surface the stale pointer as a DECIDE finding during the next lint/cleanup pass.
6. **Locate schema** — wiki schema (layers, operations, conventions, `Entity Categories`, `Document Types`, `File Naming`) lives in exactly one of:
   - **Preferred (v3+):** `{wiki}/schema.md` — canonical location, keeps wiki metadata out of resident agent-instruction context
   - **Legacy (v1–v2):** sections inside an agent instruction file, usually `CLAUDE.md` (`## Wiki`, `## Entity Categories`, `## Document Types`, `## File Naming`)

   Try `{wiki}/schema.md` first. Fall back to agent instruction file sections. When both exist, prefer `schema.md` and surface the duplication as a DECIDE finding during next lint.
7. **If `index.md` is missing but other wiki-owned files exist (partial wiki)** — before declaring "no wiki found", check whether a wiki directory exists with wiki-owned files but lacks a valid `index.md`. The candidate directories to check (in this exact order, all of them, before falling through):

   - any directory referenced by a pointer section (`## Wiki` / `## Вікі`), even if its `index.md` is missing or invalid,
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

### Hook provisioning (Claude Code only)

This is unsolicited first-time provisioning only. An explicit skill update or
hook repair follows `references/updating.md` and is never skipped merely because
one discovery block is present. A discovery block cannot prove current registrations
or absence of a duplicate in another settings scope.

After Step 0 resolves a valid wiki, and only when the active agent is Claude
Code, offer to install the global session hooks that announce
the path to `{wiki}/index.md` at session start and keep `.usage.json` heartbeats warm.
This is a host-side, cross-project install — it never touches project files
or the wiki itself.

Propose installation only when **all** of these hold, checked in order:

1. The active agent is Claude Code (not Codex, not Gemini CLI).
2. Step 0 found a valid wiki for this project.
3. The current session context contains **no** `WIKI DISCOVERY (hook)`
   block — if the block is already present, hooks are already active; do not
   ask again.
4. `~/.claude/wiki-hooks-optout` does not exist.
5. The proposal has not already been shown once this session.
6. `hooks/install-hooks.sh` exists (resolved relative to this skill's own
   directory) and is executable. This installer ships in a later increment;
   until that file lands, this whole branch has no target to run — silently
   skip the proposal (do not ask, do not mention hooks, do not error). Once
   the script ships, condition 6 becomes true automatically and no other
   change is needed here.

When all six hold, show a DECIDE prompt (once per session, never repeated
after the first decline/accept in the same session):

```
Хочеш поставити глобальні session-хуки для wiki (Claude Code)? Вони
повідомляють шлях до {wiki}/index.md на старті сесії і оновлюють телеметрію
використання сторінок. Хости — глобальні, per-machine, не per-project.

[y] встановити   [n] не зараз   [не питай більше] більше не пропонувати
```

- **`y`** — if no canonical hook marker exists yet in
  `~/.claude/settings.json`, run `install-hooks.sh`. Tell the user hooks
  registration is updated; a new session is a clean smoke test. Existing
  context is not proof of current hook output; do not assert a host-wide reload limitation.
- **`y`, but a canonical marker already exists** — this is the "marker
  present but no inject" branch: a hook entry is registered yet no
  `WIKI DISCOVERY (hook)` block appeared this session, meaning hooks
  are broken (stale script path, lost executable bit, missing `python3`,
  etc.), not simply un-installed. Do **not** blindly reinstall/overwrite —
  route to `references/operation-doctor.md` (`wiki doctor`) to diagnose the
  actual cause first.
- **`n`** — continue the originally requested operation; do not ask again
  this session (condition 5 already prevents that), but a future session may
  ask again.
- **`не питай більше`** — create (touch) `~/.claude/wiki-hooks-optout` as an
  empty marker file. Its mere existence is the opt-out signal (condition 4);
  no content is read from it. Future sessions skip the proposal entirely
  until the user deletes that file themselves.

This proposal is provisioning only — it never runs without the conditions
above, never fires more than once per session, and never overrides an
explicit prior opt-out.

### Canonical instruction-file maintenance (release A)

Load `instructions-audit.md`. No four-file sync remains. Fresh empty-scope Init
creates only `AGENTS.md`; maintenance/ingest writes shared rules or pointers
only to an existing regular canonical file after preflight and consent.
Legacy scope without it: `consolidation required`, no instruction writes.
Stale legacy pointers are report-only; no placeholder, redirect or symlink is
created. Scope-aware consolidation and deletion belong to release B.

For canonical-pointer repairs compute `{schema_path_relative_to_instruction_file}`
and the index/wiki paths from the canonical file's directory. Keep any pointer
line that resolves to a valid on-disk wiki unchanged. Before replacing the
pointer section with the full Session-Start block, preserve custom details;
never silently discard existing rules. Do not run pointer maintenance during
status, lint, or query. For non-absent Init states, use the Non-absent Init
consent block and write only after explicit approval.

**CRITICAL: Never create a second wiki.** Existing valid pointers and canonical
fallback select the current wiki; missing instruction files are not permission
for another knowledge store. The default is one canonical wiki per git root marker,
with explicitly declared nested subproject wikis allowed by nearest-scope rules.
Schema/procedures stay in schema.md or skill references, not resident context.

## Versioning & Migration

Every wiki has a schema version stored in `{wiki}/schema.md` frontmatter. This is the wiki schema major line, not every skill release:

```yaml
---
wiki_version: "4.0"
last_migration: "2026-05-01"
---
```

The skill release version is in the root `SKILL.md` frontmatter. For state detection, compare the schema major with the skill major (`4` for any v4.x release). v4.x releases change agent behavior and installer behavior, not the on-disk wiki schema; a fresh v4.x skill can still create `wiki_version: "4.0"` and be current.

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

Use a dated entry naming the actual schema/content change. Historical release
examples moved to `docs/history/instruction-schema-release-log.md`; do not load
them as current behavior or copy their four-file sync into a new project.
Instruction layout changes in 4.11–4.12 (AGENTS.md-only, consolidation) do not require a schema-major migration.


When proposing a migration plan, the skill reads its own SKILL.md frontmatter `version` and the wiki's `schema.md` `## Migration Log` to determine what changed.

### Optional config knobs in `schema.md` frontmatter

Optional `nudge_interval: <N>` in `schema.md` frontmatter overrides the default crystallization periodic nudge frequency (default ~15 tool-calling iterations). Set to `0` to disable the periodic nudge while keeping hard triggers (pre-commit, TodoWrite-completion, explicit user) active. See `references/crystallization.md` for the trigger model.
