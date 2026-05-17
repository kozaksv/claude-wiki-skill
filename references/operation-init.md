## Operation: Init (bootstrap-aware)

Set up wiki, OR detect existing structure and propose migration.

### When to Init

- User asks to create/initialize a wiki
- Wiki discovery (Step 0) found no existing wiki
- User asks to "bootstrap" / "migrate" / "reorganize" project around wiki

### Discovery

1. **Find agent instruction files** by running `## Step 0: Discover Wiki Location and Schema` first. Use the same bounded walk (`cwd` → nearest `.git/` ancestor, inclusive; filesystem root only when no `.git/` ancestor exists), the same pointer validation (`{wiki}/index.md` must exist), and the same conflict rule (never let a stale active-agent pointer override another file's valid wiki). Use existing files when present and keep their wiki pointers in sync. Infer the active agent from the runtime context when it is explicit (Claude → `CLAUDE.md`, Codex → `AGENTS.md`, Gemini → `GEMINI.md`). If none exists during fresh bootstrap, create the pointer file that matches the active agent. If the active agent is unclear, ask which agent file to create; only default to `CLAUDE.md` when the user wants the legacy convention or does not care.
2. **Determine wiki state** (5-state model, aligned with `## Versioning & Migration > State detection on Step 0`):

   | State | Condition | Action |
   |---|---|---|
   | `absent` | No `docs/wiki/` exists | Bootstrap from scratch (proceed to project-type detection + Plan below) |
   | `legacy` | Wiki exists but no `wiki_version` field in `schema.md` frontmatter | Identify version interactively, then propose migration |
   | `current` | schema major from `wiki_version` matches skill major | Do not change wiki structure. Inspect cross-agent readiness; if repairs are needed, use the Non-absent Init consent block below |
   | `older` | schema major from `wiki_version` < skill major | Generate migration plan, ask user once |
   | `newer` | schema major from `wiki_version` > skill major | Warn user, ask whether to continue |

3. **Scan project for migration candidates** (only if state is `legacy` or `older`):
   - Raw binaries (PDF, DOCX, images, spreadsheets) in non-hidden, non-wiki dirs
   - Analytical MDs (README, analysis, notes) outside `docs/wiki/`
   - Existing concept-like MDs that should move to `concepts/`
   - Duplicate MDs (raw README that overlap wiki content)

### Cross-agent instruction-file sync

For fresh `absent` bootstrap, Init runs the `Cross-agent instruction-file sync`
contract from `references/discovery-versioning.md` after creating the wiki. This
means `CLAUDE.md`, `AGENTS.md`, and `GEMINI.md` in the project pointer directory
all get the same short `## Wiki` pointer after the user approves the bootstrap
plan. The pointer path must be computed as
`{schema_path_relative_to_instruction_file}` for each file, not copied as a
literal `docs/wiki/schema.md` unless that is the correct relative path.

Do not treat a `CLAUDE.md`-only current wiki as fully initialized for cross-agent
use. If Codex opens that project later, `AGENTS.md` needs its own resident hint;
if Gemini opens it, `GEMINI.md` needs one too. For non-absent states, inspect
these files first and use the Non-absent Init consent block before writing any
missing or stale project-local pointers.

### Cross-agent skill availability

Init must leave the wiki usable from the next agent the user opens. During Init
(including `current`, `absent`, `older`, and `legacy` outcomes), inspect the
global `wiki` skill exports before the final response:

1. Check the shared canonical entrypoint: `~/.claude/skills/wiki`.
2. Check the Codex export: `~/.agents/skills/wiki`.
3. Check the Gemini export: `~/.gemini/skills/wiki`.
4. If any export is missing, broken, or points somewhere other than the shared
   canonical entrypoint, disclose the repair in the Init plan. After consent,
   locate the installed skill repository from `~/.claude/skills/wiki` and run
   `install.sh --repair-exports` once to repair exports without cloning,
   fetching, or switching refs. The repair mode is idempotent and preserves
   conflicting non-owned paths. If every export is already valid, this step is a
   no-op and should be reported as such.
5. If `install.sh` is unavailable, report the exact missing/broken export and
   tell the user that Codex/Gemini may not discover `wiki` until that symlink is
   repaired. Do not claim cross-agent readiness unless `~/.agents/skills/wiki`
   reaches the same `SKILL.md` as `~/.claude/skills/wiki`.

For `absent`, this repair appears in the Bootstrap plan template (step 11). For
non-absent states, it appears in the Non-absent Init consent block or, for
`legacy` / `older`, in the Combined migration plan.

This check is intentionally part of project Init, not only first-time global
install: many users create a wiki in Claude first and then open Codex. The
project wiki may be valid while the Codex skill alias is missing.

### Non-absent Init consent block

For `current`, `legacy`, `older`, and `newer` states, do not run cross-agent
repairs silently. Inspect project-local instruction files and global skill
exports first. If no writes are needed, report:

- `Проєктні instruction-файли: OK (no-op)`
- `Cross-agent skill exports: OK (no-op)`

If any item needs repair (Project-local instruction files need repair and/or
global exports need repair), show a short approval block before writing files or
running `install.sh --repair-exports`:

```
Wiki вже існує: {state}, schema {wiki_version}.
Проєктні instruction-файли потребують ремонту:
  - {missing-or-stale-instruction-file}
Cross-agent skill exports потребують ремонту:
  - {missing-or-broken-export}

Полагодити ці cross-agent налаштування зараз? [y/N]
```

Only run the listed repairs after explicit `y`. Without explicit y, do not
write instruction files and do not run `install.sh --repair-exports`; complete
the Init report with version/status findings and note that Codex/Gemini may
need manual repair later.

For `newer`, ask whether to continue with the newer schema first. If the user
declines, stop after the read-only report; do not sync instruction files or
repair exports. If the user continues and repairs are needed, show the
Non-absent Init consent block.

For `legacy` / `older`, include the repair as normal skippable steps in the
migration plan so there is one consent flow.

#### Combined migration plan with export repair

```
⚠️ Wiki версії {wiki_version}, скіл — {skill_version}. Потрібна міграція.

План:
  1. {schema/content migration step}
  2. {additional schema/content migration step, if any}
  ...
  N-1. Проєктні instruction-файли — синхронізувати `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, якщо відсутні або stale
  N. Cross-agent skill exports — полагодити `~/.agents/skills/wiki` / `~/.gemini/skills/wiki`, якщо відсутні або broken

Зроблю всі N кроків одразу? [y] / [n] / [пропусти крок N]
```

Substitute the schema/content migration entries with the actual ordered steps
needed for that wiki, then append project-local pointer repair and export repair
as the last two skippable steps when they are needed. `N` is the total visible
step count.

If the user skips the export step, continue with approved wiki migration steps
and report that global exports still need manual repair. If the user skips the
instruction-file step, do not create or edit `CLAUDE.md`, `AGENTS.md`, or
`GEMINI.md`.

### Project-type detection (only for `absent` state)

When bootstrapping a fresh wiki, scan project root for type signals to propose
initial `entities/` categories. This is a SUGGESTION — user can override or pick
custom categories.

| Signal (file present in project root) | Suggested `entities/` categories |
|---|---|
| `package.json` / `tsconfig.json` | `components/`, `services/` |
| `Cargo.toml` | `modules/`, `traits/` |
| `requirements.txt` / `pyproject.toml` | `modules/`, `classes/` |
| `go.mod` | `packages/`, `interfaces/` |
| `*.csproj` | `classes/`, `services/` |
| `pom.xml` / `build.gradle` | `packages/`, `services/` |
| no project signals | no categories; keep `entities/` empty |

If multiple signals match (polyglot repo), union the suggested categories and let
the user prune. After detection, surface the proposed list inside the Bootstrap
plan template (step 5: `entities/`) so the user sees what they're approving.

For an empty project, do not ask the user for more project information and do
not invent starter pages or categories. Create `entities/` as an empty directory;
the wiki will grow through later `ingest-source`, `ingest-binary`, and query
reflection.

**Scope warning.** Project-type detection ONLY influences proposed initial categories at bootstrap time. It does NOT affect any other behavior — in particular, it does NOT feed into staleness scoring or content-verification (see `## Operation: Lint`), and it does NOT lock future categories (any category can be added later via `ingest-binary` lazy-creation).

### Plan (interactive)

For `legacy` / `older` migrations, before any move, present:
- Concept candidates → list of MDs to move into `concepts/`
- Entity candidates → suggest stubs from mentions in existing wiki
- Binary candidates → list of binaries to move to `archive/` + create transcript
- Dupes → list of MDs to delete (with justification)
- Stale folders → list to remove after content migrated

Ask per group: "Migrate these? [y/N/per-file]". User retains veto on each.

### Bootstrap plan template (for `absent` state)

For a fresh wiki (state = `absent`), present this single-block plan after
project-type detection finishes. Substitute `{detected_type}` with the matched
signal (e.g., `package.json`) or `порожній проєкт`; substitute `{entities-step}`
with either `пропонована структура для {detected_type}: {category-list}` or
`порожня папка (проєкт без сигналів; категорії з'являться пізніше)`; substitute
`{today}` with the current date in `YYYY-MM-DD` form. The plan is a user-facing
outcome checklist, not an execution-order trace; the Execute section below may
order steps differently for safe creation, migration, and failure reporting.

```
📂 Створюю нову wiki у docs/wiki/

План:
  1. docs/wiki/schema.md — frontmatter (wiki_version: "4.0", last_migration: "{today}", nudge_interval: 15) + три розділи (Layers / Operations / Conventions) + Migration Log
  2. docs/wiki/index.md — порожній з трьома секціями (Concepts | Entities | Transcripts)
  3. docs/wiki/log.md — порожній з заголовком
  4. docs/wiki/concepts/ — порожня папка
  5. docs/wiki/entities/ — {entities-step}
  6. docs/wiki/transcripts/ — порожня папка
  7. docs/wiki/.usage.json — порожній dict {}
  8. archive/ — поза wiki (gitignored)
  9. Agent instruction file(s) — синхронізувати `CLAUDE.md`, `AGENTS.md`, `GEMINI.md` через Cross-agent instruction-file sync; create missing minimal instruction files with a relative "Wiki schema → ..." path computed per file (usually `docs/wiki/schema.md`)
  10. .gitignore — додати "archive/" і "docs/wiki/.usage.json"
  11. Cross-agent skill exports — перевірити `~/.agents/skills/wiki` і `~/.gemini/skills/wiki`; якщо exports валідні, no-op; якщо ні, запустити `install.sh --repair-exports`

[y] так, створи все  /  [n] скасувати
```

After confirmation (`y`), implement the approved outcome checklist using the Execute checklist below. After execution, append `## [{today}] init | bootstrap fresh wiki schema v4` to `log.md`. On `n`, abort and leave the project untouched.

### Execute

After consent:

1. Create missing dirs: `concepts/`, `entities/`, `transcripts/`, `archive/`; create `entities/{categories}/` and `archive/{categories}/` only when the approved category list is non-empty
2. Add `archive/` to `.gitignore`
3. Move concept MDs → `concepts/`
4. For each binary:
   - Move to `archive/{category}/{naming-convention}.{ext}`
   - Generate transcript → `transcripts/{slug}.md`
   - Create entity page stub → `entities/{category}/{slug}.md`
5. Create entity stubs for entities mentioned in concepts (lazy: only key/recurring ones)
6. Create `{wiki}/schema.md` with frontmatter, layers description, operations summary, `Entity Categories`, `Document Types`, `File Naming`, and `## Migration Log` section seeded with v4.0 entry. Frontmatter template:

   ```yaml
   ---
   wiki_version: "4.0"
   last_migration: "{today}"
   nudge_interval: 15      # tool-calling iterations between crystallization nudges; 0 disables periodic nudge
   ---
   ```

   Add a single `## Wiki` pointer through Cross-agent instruction-file sync: ensure `CLAUDE.md`, `AGENTS.md`, and `GEMINI.md` each point to _"Wiki schema and operations → `{schema_path_relative_to_instruction_file}`. Skill: `wiki`."_ Create missing minimal instruction files as needed. For v1/v2 migrations, move existing instruction-file schema sections into `schema.md` and replace only the pointer with the relative schema path.
6a. Create `{wiki}/.usage.json` with `{}` (empty dict). This is the telemetry sidecar — see `## Telemetry Sidecar`.
6b. Add `{wiki}/.usage.json` to `.gitignore`. Telemetry is per-clone, not shared.
7. Delete approved duplicates
8. Update `index.md` (three sections: Concepts | Entities | Transcripts)
9. Append `log.md` with migration record
10. Run `Cross-agent instruction-file sync` and `Cross-agent skill availability`; include both results in the final `Перевірив:` list

### Versioning during Init

For all migration-from-legacy paths, follow the explicit plan format described in `## Versioning & Migration`. After successful migration, write `## Migration Log` entry documenting the path taken (e.g., "v1 → v4 via init bootstrap").

### After completion

Init is the most structurally heavy operation in the skill — it creates `schema.md`, `index.md`, `log.md`, `.usage.json`, edits `.gitignore`, writes an agent-instruction pointer, and may move binaries into `archive/`. Always emit a РЕФЛЕКСІЯ block per `references/reflection.md` after Init completes (regardless of trigger), and always include the `Перевірив:` section listing every structural file created or modified. Anti-noise does not apply — Init by definition writes.

---
