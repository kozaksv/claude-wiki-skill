# Scenario: doc-extract optional dependency and fallback paths

These scenarios exercise the `ingest-binary` dependency contract from
`references/operation-ingest-binary.md`. `doc-extract` is optional for the
wiki stack as a whole: text/source wiki operations must keep working if
`doc-extract` is missing, broken, or missing system dependencies.

## Scenario 1: Gemini direct export is used when `.agents` export is missing

### Setup

- `~/.agents/skills/doc-extract` does not exist or is a broken symlink.
- `~/.gemini/skills/doc-extract/bin/extract.sh` exists and is executable.
- `~/.claude/skills/doc-extract/bin/extract.sh` also exists.
- User runs `ingest-binary` on a PDF.

### Expected behavior

- The fallback chain checks `.agents` first, then `.gemini`, then `.claude`.
- The agent invokes `~/.gemini/skills/doc-extract/bin/extract.sh`.
- It does not send the user to the standalone `doc-extract` installer.

## Scenario 2: Missing dependency does not block normal wiki usage

### Setup

- Installer previously failed to clone/install `doc-extract`.
- `~/.agents/skills/wiki` and `~/.gemini/skills/wiki` still point at the shared
  canonical wiki skill.
- No `doc-extract/bin/extract.sh` exists in `.agents`, `.gemini`, or `.claude`.

### Expected behavior

- `query`, `ingest-source`, `lint`, `cleanup`, `split`, `wiki status`, and `init`
  remain available.
- `ingest-binary` stops before creating entity/transcript/archive files and says:
  `doc-extract не знайдено. Повторіть інсталяцію wiki stack:`
- The shown command is the wiki stack installer:
  `curl -fsSL https://raw.githubusercontent.com/kozaksv/claude-wiki-skill/master/install.sh | bash`

## Scenario 3: Extractor exit codes produce user-visible choices

### Setup

- `doc-extract/bin/extract.sh` exists and is executable.
- `ingest-binary` is run against three fixtures that force exit codes:
  `10` (`extraction_failed`), `20` (`missing_dependency`), and `30`
  (`unsupported_format`).

### Expected behavior

- Exit `10`: stop, summarize the method chain from stderr, and offer only
  explicit user choices: manual summary, vision-capable file read if supported,
  or skip. No silent LLM fallback.
- Exit `20`: run `bash "$DOC_EXTRACT_ROOT/bin/doctor.sh"`, show its output, ask
  the user to install missing system dependencies, then retry only after the
  user confirms.
- Exit `30`: ask the user to skip or convert the file first.

## Scenario 4: Broken export with healthy canonical recovery path

### Setup

- `~/.agents/skills/doc-extract` exists but points at a missing target.
- `~/.gemini/skills/doc-extract` does not exist.
- `~/.claude/skills/doc-extract/bin/extract.sh` exists and is executable.

### Expected behavior

- `ingest-binary` falls through to `~/.claude/skills/doc-extract`.
- The binary ingest can proceed.
- A later installer run replaces the broken `.agents` export, but the current
  ingest does not require that repair first.
