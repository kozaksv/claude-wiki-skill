# Scenario: Cross-agent discovery and instruction-file sync

These scenarios exercise the agent-neutral discovery contract for Claude,
Codex, and Gemini. They are manual/integration scenarios: the expected behavior
comes from `SKILL.md` → `## Step 0: Discover Wiki Location and Schema` and
`## Operation: Init (bootstrap-aware)`.

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
