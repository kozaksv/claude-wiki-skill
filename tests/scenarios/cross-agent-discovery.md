# Scenario: Cross-agent discovery and instruction-file sync

These scenarios exercise the agent-neutral discovery contract for Claude,
Codex, and Gemini. They are manual/integration scenarios: the expected behavior
comes from `references/discovery-versioning.md` and
`references/operation-init.md`.

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
  per `.git` ancestor.

## Scenario 3: Gemini-only fresh project

### Setup

- Project has no `CLAUDE.md`, `AGENTS.md`, or `GEMINI.md`.
- Session is clearly running under Gemini CLI.
- No `docs/wiki/` exists.

### Expected behavior

- Init proposes fresh bootstrap.
- After confirmation, wiki files are created under `docs/wiki/`.
- `GEMINI.md` is created with the one-line `## Wiki` pointer.
- `CLAUDE.md` and `AGENTS.md` are not created unless the user asks for
  cross-file pointer sync.

## Scenario 3b: Codex-only fresh project

### Setup

- Project has no `CLAUDE.md`, `AGENTS.md`, or `GEMINI.md`.
- Session is clearly running under Codex.
- No `docs/wiki/` exists.

### Expected behavior

- Init proposes fresh bootstrap.
- After confirmation, wiki files are created under `docs/wiki/`.
- `AGENTS.md` is created with the one-line `## Wiki` pointer.
- `CLAUDE.md` and `GEMINI.md` are not created unless the user asks for
  cross-file pointer sync.

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
- If the local skill repo exposes `install.sh`, the agent runs
  `install.sh --repair-exports` to repair `~/.agents/skills/wiki` and other
  shared exports without switching the installed skill ref.
- If the installer is unavailable, init reports the missing export explicitly
  instead of claiming Codex will see the skill.
- After a successful repair, Codex can discover the same `wiki` skill through
  `~/.agents/skills/wiki`.

## Scenario 3d: Truly empty project stays empty

### Setup

- Project has no wiki.
- Project has no code or docs signals such as `package.json`, `pyproject.toml`,
  `README.md`, or source files.
- Session is clearly running under Codex.

### Expected behavior

- Init does not ask the user for more project information.
- Init does not invent starter entity categories such as `people/` or
  `documents/`.
- The bootstrap creates the minimal wiki skeleton with empty `concepts/`,
  empty `entities/`, empty `transcripts/`, empty `.usage.json`, and the
  active-agent pointer.

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
