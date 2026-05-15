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
