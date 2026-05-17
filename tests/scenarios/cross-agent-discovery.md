# Scenario: Cross-agent discovery and instruction-file sync

These scenarios exercise the agent-neutral discovery contract for Claude,
Codex, and Gemini. They are manual/integration scenarios: the expected behavior
comes from `references/discovery-versioning.md` and
`references/operation-init.md`.

Unless a scenario explicitly says otherwise, the project root contains `.git/`
or a `.git` file. Git is a hard prerequisite: non-git directories cannot
create, query, lint, or cleanup a wiki.

## Scenario 1: AGENTS.md-only project

### Setup

- Project root contains `AGENTS.md` with:
  `Wiki schema and operations -> docs/wiki/schema.md. Skill: wiki.`
- Project root contains `docs/wiki/index.md` and `docs/wiki/schema.md` with
  `wiki_version: "4.0"`.
- No `CLAUDE.md` or `GEMINI.md` exists.

### Expected behavior

- Discovery reads `AGENTS.md`.
- Wiki location resolves to `docs/wiki/`.
- State is `current` because schema major `4` matches skill major `4`.
- No `CLAUDE.md` or `GEMINI.md` is created during read-only operations.

## Scenario 2: Conflicting instruction files

### Setup

- `AGENTS.md` points at `docs/wiki/schema.md`.
- `CLAUDE.md` points at `docs/old-wiki/schema.md`.
- Only `docs/wiki/index.md` exists.

### Expected behavior

- Discovery reads both instruction files.
- The existing wiki directory on disk wins when active agent is unclear.
- The conflict is flagged for the next lint/cleanup pass instead of silently
  creating a second wiki.
- Init does not proceed as `absent`.

## Scenario 2b: Active-agent pointer is stale, another file is valid

### Setup

- Session is clearly running under Codex.
- `AGENTS.md` points at `docs/old-wiki/schema.md`.
- `CLAUDE.md` points at `docs/wiki/schema.md`.
- `docs/old-wiki/index.md` does not exist.
- `docs/wiki/index.md` and `docs/wiki/schema.md` exist.

### Expected behavior

- Discovery reads both instruction files and validates every candidate by
  checking for `index.md`.
- The broken active-agent pointer in `AGENTS.md` does not win.
- Wiki location resolves to the valid `docs/wiki/`.
- The stale `AGENTS.md` pointer is flagged for the next lint/cleanup pass.
- Init does not proceed as `absent` and does not create a second wiki.

## Scenario 2c: Parent workspace pointer outside the repo boundary

### Setup

- Current working directory is `/work/parent/project-a/src`.
- `/work/parent/project-a/.git/` exists.
- `/work/parent/AGENTS.md` points at `/work/parent/docs/wiki/schema.md`.
- `/work/parent/project-a/` has no instruction files and no `docs/wiki/index.md`.

### Expected behavior

- Discovery walks from `src/` up to `/work/parent/project-a/` and stops there
  because it is the nearest `.git/` ancestor.
- `/work/parent/AGENTS.md` is outside the discovery boundary and is ignored.
- Init treats `project-a` as `absent` and asks/proposes bootstrap for this repo,
  instead of attaching the nested project to the parent workspace wiki.

## Scenario 2d: Monorepo with explicit sub-project wiki pointer

### Setup

- Current working directory is `/work/mono/apps/web/src`.
- `/work/mono/.git/` exists; there is no nested `.git/`.
- `/work/mono/apps/web/AGENTS.md` points at `apps/web/docs/wiki/schema.md`.
- `/work/mono/apps/api/AGENTS.md` points at `apps/api/docs/wiki/schema.md`.
- Both wiki directories have `index.md`, but `apps/api/AGENTS.md` is in a
  sibling directory, not on the cwd → parent path.

### Expected behavior

- Discovery walks `src/` → `apps/web/` → `apps/` → `/work/mono/`.
- It reads the `apps/web/AGENTS.md` pointer because it is on the walk path.
- It does not scan sibling `apps/api/` on its own.
- Wiki location resolves to `apps/web/docs/wiki/`.
- If multiple wikis are desired in one git repo, each sub-project must expose
  its own instruction-file pointer; otherwise the default is one canonical wiki
  per git root marker.
- If cross-agent instruction-file sync is explicitly requested for this
  sub-project, the generated `CLAUDE.md` and `GEMINI.md` pointers are written in
  `apps/web/` using the path relative to each instruction file:
  `docs/wiki/schema.md`, not `/work/mono/docs/wiki/schema.md` and not a
  hard-coded repo-root path.
- The existing `apps/web/AGENTS.md` pointer is left untouched if it resolves to
  the same wiki, even if its text uses a repo-root-style path.

## Scenario 2e: Git worktree or submodule .git file

### Setup

- Current working directory is `/work/mono-submodule/src`.
- `/work/mono-submodule/.git` exists as a file, not a directory, and points to
  real git metadata elsewhere (the usual git worktree/submodule layout).
- `/work/mono-submodule/AGENTS.md` points at `docs/wiki/schema.md`.
- `/work/mono-submodule/docs/wiki/index.md` and
  `/work/mono-submodule/docs/wiki/schema.md` exist.
- `/work/.git/` also exists in a parent workspace.

### Expected behavior

- Discovery treats `/work/mono-submodule/.git` as the git root marker and stops
  the bounded walk at `/work/mono-submodule/`.
- `/work/.git/` and parent workspace instruction files are ignored.
- Wiki location resolves to `/work/mono-submodule/docs/wiki/`.
- The agent does not ask to run `git init`, because normal git commands,
  snapshots, and rollback work from the worktree/submodule directory.

## Scenario 2f: Worktree/submodule with no wiki yet

### Setup

- Current working directory is `/work/mono-submodule/src`.
- `/work/mono-submodule/.git` exists as a file, not a directory, and points to
  real git metadata elsewhere.
- No `docs/wiki/` exists under `/work/mono-submodule/`.
- No `CLAUDE.md`, `AGENTS.md`, or `GEMINI.md` exists under
  `/work/mono-submodule/`.
- User says `wiki init`.

### Expected behavior

- Discovery treats `/work/mono-submodule/.git` as the git root marker; the
  bounded walk stops at `/work/mono-submodule/`.
- The agent does not ask to run `git init`, because the worktree/submodule
  already has a valid git marker.
- State resolves to `absent`.
- The Bootstrap plan template is shown; step 1 reads as `Git repository —
  підтверджено git-маркер` (no fresh-init clause fires, because git was not
  just created by the Init gate).
- After explicit `y`, the wiki is created inside `/work/mono-submodule/` — not
  in any parent directory and not by attaching to a wiki outside the worktree.

## Scenario 3: Gemini-only fresh project

### Setup

- Project has no `CLAUDE.md`, `AGENTS.md`, or `GEMINI.md`.
- Session is clearly running under Gemini CLI.
- No `docs/wiki/` exists.

### Expected behavior

- Init proposes fresh bootstrap.
- After confirmation, wiki files are created under `docs/wiki/`.
- `GEMINI.md` is created with the one-line `## Wiki` pointer.
- `CLAUDE.md` and `AGENTS.md` are also created as minimal cross-agent pointer
  files, so Claude and Codex receive the same resident wiki hint without extra
  user setup.

## Scenario 3b: Codex-only fresh project

### Setup

- Project has no `CLAUDE.md`, `AGENTS.md`, or `GEMINI.md`.
- Session is clearly running under Codex.
- No `docs/wiki/` exists.

### Expected behavior

- Init proposes fresh bootstrap.
- After confirmation, wiki files are created under `docs/wiki/`.
- `AGENTS.md` is created with the one-line `## Wiki` pointer.
- `CLAUDE.md` and `GEMINI.md` are also created as minimal cross-agent pointer
  files, so Claude and Gemini receive the same resident wiki hint without extra
  user setup.

## Scenario 3c: Claude init prepares Codex discovery

### Setup

- Session is clearly running under Claude.
- Project has no wiki.
- The installed `wiki` skill is available through the shared canonical
  `~/.claude/skills/wiki` entrypoint.
- `~/.agents/skills/wiki` is missing or broken.

### Expected behavior

- Init bootstraps the project wiki normally.
- During completion checks, the agent verifies the cross-agent skill exports.
- The agent runs `install.sh --repair-exports` from the canonical wiki skill
  entrypoint to repair `~/.agents/skills/wiki` and other shared exports without
  switching the installed skill ref.
- Init creates or updates the project-local `AGENTS.md` and `GEMINI.md` wiki
  pointers alongside `CLAUDE.md`.
- If the installer is unavailable, init reports the missing export explicitly
  instead of claiming Codex will see the skill.
- After a successful repair, Codex can discover the same `wiki` skill through
  `~/.agents/skills/wiki`.

## Scenario 3d: Fresh non-git project

### Setup

- Current working directory is `/work/money`.
- `/work/money/` has no `.git/` directory or `.git` file ancestor.
- No `docs/wiki/` exists.
- User says `wiki init`.

### Expected behavior

- Discovery stops before looking for wiki files or parent instruction files.
- The agent explains that git is required for snapshots, rollback, cleanup, and
  migration safety.
- The agent asks: ``Створити `.git/` у `/work/money` і продовжити wiki init? [y/N]``.
- On explicit `y`, the agent runs `git init` in `/work/money`, restarts Step 0,
  and then presents the normal fresh-bootstrap plan.
- On any other answer, the agent creates nothing and says the wiki will not work
  without git.
- For non-init operations in the same setup, the agent does not offer a wiki
  action menu; it refuses and points the user to initialize git first or run
  `wiki init`.

## Scenario 3e: Orphan wiki — skill explains and refuses; user fixes manually

### Setup

- Current working directory is anywhere inside (or at) a project that
  contains a wiki on disk but no git marker. Examples that all
  exercise the same gate:
  - `/work/money` with wiki at `/work/money/docs/wiki/`.
  - `/work/money/src` with wiki at `/work/money/docs/wiki/`.
  - `/work/docs` with wiki at `/work/docs/wiki/` (project root itself
    named `docs/`).
- None of those directories or their ancestors contains `.git/` or a
  `.git` file.
- (Step 0 detects orphan-wiki only when discovery actually resolves a
  wiki — i.e., `docs/wiki/index.md` exists or a `## Wiki` pointer in
  `CLAUDE.md`/`AGENTS.md`/`GEMINI.md` resolves to one. By contract,
  these are the only places a wiki can live. Files at non-canonical
  paths without a pointer are not considered wikis at all — Init in
  such a project will bootstrap a fresh wiki at `docs/wiki/`, and
  users who want their wiki somewhere else must add a `## Wiki`
  pointer first.)
- User says `wiki lint` (or any wiki operation; the gate is the same
  for `query`, `status`, `cleanup`, `split`, `ingest`, and `init`).

### Expected behavior

- Step 0 detects the orphan-wiki state and resolves the wiki.
- The agent shows the informational gate. There is no consent reply to
  parse — the gate explains, the operation ends:

  ```
  У `/work/money/docs/wiki/` знайдено wiki, але `.git/` немає.
  Wiki не працює без git: snapshots, rollback і cleanup потребують commits.

  Я не запускаю `git init` для orphan-wiki сам, бо тільки ви знаєте,
  де project root вашого проєкту, і помилка в цьому виборі
  створила б `.git/` у неправильному місці (наприклад, охопивши
  несумісні sibling-проєкти або весь `$HOME`).

  Що зробити вручну:
    1. `cd` у директорію вашого project root. Project root — це
       директорія, яка містить wiki (`/work/money/docs/wiki/`) як
       sub-tree і яку ви вважаєте коренем проєкту (зазвичай там
       лежать `package.json` / `pyproject.toml` / `Cargo.toml` /
       `README.md` / `.gitignore`, etc.).
    2. Виконайте `git init` у цій директорії.
    3. Повторіть оригінальну операцію — Step 0 знайде новий
       `.git/` і продовжить як зазвичай.

  Скіл закриває операцію без змін. Wiki не чіпається.
  ```

- The agent does not call `git init`, does not edit instruction files,
  does not modify `.gitignore`, does not touch wiki contents, and does
  not create a second wiki. The original operation ends.
- After the user manually runs `git init` in their project root and
  re-runs the operation, Step 0 finds the new git marker and the
  operation completes normally against the existing wiki.

## Scenario 3f: Non-canonical wiki resolved via `## Wiki` pointer is not treated as absent

### Setup

- Project root is `/work/app/` with `/work/app/.git/` present (git is
  fine).
- `/work/app/` has no `docs/wiki/` directory.
- `/work/app/knowledge/index.md` and `/work/app/knowledge/schema.md`
  exist (wiki lives at a non-canonical path).
- `/work/app/AGENTS.md` contains a `## Wiki` pointer:
  `Wiki schema and operations → knowledge/schema.md. Skill: \`wiki\`.`
- `schema.md` declares `wiki_version: "4.0"`, matching the skill major.
- User says `wiki init`.

### Expected behavior

- Step 0 reads `AGENTS.md`, follows the pointer, and resolves the wiki
  at `/work/app/knowledge/`. The wiki is considered to exist.
- Init's state table classifies this as `current` (schema major matches
  skill major), **not** `absent`. The "absent" state requires no wiki
  found at all — not merely the absence of `docs/wiki/`.
- Init does not bootstrap a fresh wiki at `/work/app/docs/wiki/`. It
  proceeds with the normal `current`-state Init flow (cross-agent
  instruction-file sync, export checks, etc.) against the existing
  wiki at `/work/app/knowledge/`.
- No second wiki is created, and the existing `AGENTS.md` pointer
  continues to resolve correctly after Init completes.

## Scenario 3g: Partial wiki (wiki-owned files exist, `index.md` missing)

### Setup

- Project root is `/work/app/` with `/work/app/.git/` present.
- `/work/app/docs/wiki/` exists and contains `schema.md` (with
  `wiki_version: "4.0"`), `log.md`, `.usage.json`, and a `concepts/`
  subdirectory with two pages.
- `/work/app/docs/wiki/index.md` is missing (deleted by mistake, or
  a previous Init/migration stopped mid-flow).
- No `## Wiki` pointer in `CLAUDE.md`/`AGENTS.md`/`GEMINI.md` (or the
  pointer resolves to the same partially populated directory).
- User says `wiki lint` (or any wiki operation — the gate is the
  same).

### Expected behavior

- Step 0 walks instruction files, then verifies `docs/wiki/index.md`
  exists. It does not. Step 0 then checks for partial-wiki signals
  in the candidate wiki directory (`docs/wiki/`): `schema.md` ✓,
  `log.md` ✓, `concepts/` ✓ — wiki-owned files are present.
- Step 0 classifies this as **partial wiki state**, not `absent`.
  Init's absent-state bootstrap is not invoked, so the existing
  `schema.md`, `log.md`, `.usage.json`, and `concepts/` files are
  **not overwritten**.
- The agent shows the partial-wiki gate:

  ```
  У `/work/app/docs/wiki/` знайдено артефакти wiki, але `index.md` відсутній.
  Це partial/damaged state — попередня операція Init/migration могла не
  завершитися, або файл випадково видалено.

  Знайдено wiki-owned files:
    - schema.md
    - log.md
    - .usage.json
    - concepts/

  Що зробити вручну:
    1. Відновити `index.md` з git history (`git log -- docs/wiki/index.md`,
       потім `git show <hash>:docs/wiki/index.md > docs/wiki/index.md`).
    2. Або move/rename wiki-директорію повністю (наприклад
       `mv docs/wiki docs/wiki.bak`), щоб скіл міг створити fresh wiki
       через `wiki init`.
    3. Повторити оригінальну операцію.

  Скіл закриває операцію без змін. Існуючі файли не чіпаються.
  ```

- No `index.md`, `archive/`, telemetry, or instruction-file pointers
  are written. The operation ends.
- After the user restores `index.md` (or moves the partial wiki
  aside), the next operation completes normally — partial-state
  detection no longer triggers because either `index.md` is back
  (resolves as `current`) or the directory is empty (state is
  truly `absent` and bootstrap proceeds).

## Scenario 3h: Partial wiki without git (orphan + partial combined)

### Setup

- Current working directory is `/work/app/` (or `/work/app/src/`;
  cwd doesn't change the gate).
- `/work/app/` has no `.git/` directory and no `.git` file ancestor.
- `/work/app/docs/wiki/schema.md`, `log.md`, `.usage.json`, and a
  `concepts/` subdirectory exist.
- `/work/app/docs/wiki/index.md` is missing.
- User says any wiki operation (`wiki lint`, `wiki init`, etc.).

### Expected behavior

- Step 0's no-git artifact scan includes partial signals (`schema.md`,
  `log.md`, `.usage.json`, `concepts/`, etc.), not just `index.md`.
  The scan finds wiki-owned files at `/work/app/docs/wiki/`, so the
  state is **orphan-wiki**, not absent.
- The agent shows the orphan-wiki informational gate (same as
  Scenario 3e) — explains that wiki exists but `.git/` is missing,
  lists the manual fix (`cd` to project root → `git init` → retry),
  and ends the operation without writing anything.
- The absent-state Init gate does **not** fire. No `git init` is
  proposed and no fresh wiki is bootstrapped — the existing
  `schema.md`, `log.md`, `.usage.json`, and `concepts/` are never
  overwritten.
- After the user runs `git init` manually in the project root, the
  next operation detects partial-wiki state (Scenario 3g flow) and
  asks the user to restore `index.md` or move the wiki directory
  aside. Recovery is two manual steps because the project sat in a
  doubly-damaged state.

## Scenario 3c1: Codex cannot activate wiki skill yet

### Setup

- A project has a valid wiki and a `CLAUDE.md` pointer.
- `AGENTS.md` is missing.
- `~/.agents/skills/wiki` is also missing, so Codex cannot activate the wiki
  skill from a natural-language request.

### Expected behavior

- Recovery documentation tells the user to run
  `bash ~/.claude/skills/wiki/install.sh --repair-exports` first.
- After Codex can see the skill, `init wiki` discovers the existing wiki from
  `CLAUDE.md`, follows the Non-absent Init consent block before writing
  `AGENTS.md`, and does not create a second wiki.

## Scenario 3c2: CLAUDE-only current wiki repairs active-agent pointer

### Setup

- Session is clearly running under Codex.
- `CLAUDE.md` points at `docs/wiki/schema.md`.
- `docs/wiki/index.md` and `docs/wiki/schema.md` exist and are current.
- `AGENTS.md` does not exist.
- Global skill exports are already valid.
- User asks: `init wiki`.

### Expected behavior

- Discovery resolves the existing wiki from `CLAUDE.md`; it does not create a
  second wiki.
- State is `current`.
- Because the user explicitly asked to initialize, the agent inspects both
  project-local instruction files and global skill exports.
- Since `AGENTS.md` is missing but global exports are OK, the agent shows the
  Non-absent Init consent block listing only the project-local repair.
- Without explicit `y`, no `AGENTS.md` is written.
- After explicit `y`, `AGENTS.md` is created as a minimal project-local pointer
  file with the same `## Wiki` pointer, and the response mentions the pointer
  repair.

## Scenario 3c3: Read-only status does not write pointers

### Setup

- Session is clearly running under Codex.
- `CLAUDE.md` points at `docs/wiki/schema.md`.
- `docs/wiki/index.md` and `docs/wiki/schema.md` exist and are current.
- `AGENTS.md` does not exist.
- User asks: `wiki status`.

### Expected behavior

- Discovery resolves the existing wiki from `CLAUDE.md`.
- The status report includes a finding that `AGENTS.md` is missing and can be
  repaired by running wiki init or an explicit pointer-repair request.
- No `AGENTS.md` file is created during status.

## Scenario 3c4: Current wiki repair requires consent

### Setup

- Session is clearly running under Codex.
- `CLAUDE.md` points at `docs/wiki/schema.md`.
- `docs/wiki/index.md` and `docs/wiki/schema.md` exist and are current.
- `AGENTS.md` does not exist.
- `~/.agents/skills/wiki` is missing.
- User asks: `init wiki`.

### Expected behavior

- Discovery resolves the existing wiki from `CLAUDE.md`; it does not create a
  second wiki.
- State is `current`.
- The agent shows the Non-absent Init consent block listing both project-local
  instruction-file repair (`AGENTS.md`) and global skill export repair
  (`~/.agents/skills/wiki`).
- Without explicit `y`, the agent does not create `AGENTS.md` and does not run
  `install.sh --repair-exports`; it reports the needed repairs instead.
- After explicit `y`, the agent creates/updates the approved pointer files, runs
  `install.sh --repair-exports`, and reports both results.

## Scenario 3c5: Current wiki export-only repair requires consent

### Setup

- Session is clearly running under Codex.
- `CLAUDE.md` and `AGENTS.md` both point at `docs/wiki/schema.md`.
- `docs/wiki/index.md` and `docs/wiki/schema.md` exist and are current.
- `~/.agents/skills/wiki` is missing or broken.
- User asks: `init wiki`.

### Expected behavior

- Discovery resolves the existing wiki; it does not create a second wiki.
- State is `current`.
- The agent inspects both project-local instruction files and global skill
  exports.
- Since project-local pointers are OK but the Codex export is broken, the agent
  shows the Non-absent Init consent block listing only the global export repair.
- Without explicit `y`, the agent does not run `install.sh --repair-exports`.
- After explicit `y`, the agent runs `install.sh --repair-exports` and reports
  the export repair result.

## Scenario 3d: Truly empty project stays empty

### Setup

- Project has no wiki.
- Project has no code or docs signals such as `package.json`, `pyproject.toml`,
  `README.md`, docs files, source files, or binaries to ingest.
- Session is clearly running under Codex.

### Expected behavior

- Init does not ask the user for more project information.
- Init does not invent starter entity categories such as `people/` or
  `documents/`.
- The bootstrap creates the minimal wiki skeleton with empty `concepts/`,
  empty `entities/`, empty `transcripts/`, empty `.usage.json`, and the
  cross-agent pointer files.

## Scenario 4: Unclear active agent in a fresh project

### Setup

- Project has no `CLAUDE.md`, `AGENTS.md`, or `GEMINI.md`.
- The active agent cannot be inferred from runtime context.
- No `docs/wiki/` exists.

### Expected behavior

- Init asks which instruction file to create.
- It only defaults to `CLAUDE.md` if the user chooses the legacy convention or
  explicitly says they do not care.
- The prompt happens before files are written, so aborting leaves the project
  untouched.
