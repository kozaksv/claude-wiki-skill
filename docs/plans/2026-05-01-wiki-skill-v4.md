# Wiki Skill v4.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade the universal wiki skill from v3.0 to v4.0 by adding versioning, telemetry sidecar, РЕФЛЕКСІЯ block, tiered crystallization, `wiki status` operation, and Karpathy-aligned content-verification staleness — adopting Hermes-Agent architectural patterns where they fit.

**Architecture:** Wiki skill is a purely instructional Markdown file (`SKILL.md`) that tells Claude how to behave during wiki operations. There is no compiled code — implementation = editing SKILL.md sections, plus minimal fixture/scenario files for verification. Each phase modifies SKILL.md in coherent blocks, verified by manual scenario testing against mock wiki fixtures.

**Tech Stack:** Markdown, YAML frontmatter, JSON (for `.usage.json` records). No code in the skill itself; the `.usage.json` mutator API (`bump_view`/`bump_use`/`bump_patch`/`forget`) is described as instructions for Claude to execute via existing Read/Write/Edit/Bash tools.

**Source of truth for design:** `/Users/a/Library/CloudStorage/Dropbox/AI/Health/.claude/worktrees/determined-lederberg-54151a/docs/superpowers/specs/2026-05-01-wiki-skill-v4-self-improvement-design.md` (committed to Health repo as commit `34605ce`).

**Implementation repository (NOT Health):** `/Users/a/Library/CloudStorage/Dropbox/AI/claude-wiki-skill/` (independent git repo, symlinked to `~/.claude/skills/wiki/`).

**Critical:** all `git` operations in this plan are against the wiki-skill repo unless noted. Subagents must `cd` into that repo before any file operation.

---

## Phase 0 — Working Environment Setup

### Task 0.1: Verify wiki-skill repo state and create working branch

**Files:**
- Repo: `/Users/a/Library/CloudStorage/Dropbox/AI/claude-wiki-skill/`

- [ ] **Step 1: Verify repo state**

```bash
cd /Users/a/Library/CloudStorage/Dropbox/AI/claude-wiki-skill/
git status
git log --oneline -5
```

Expected: clean working tree on `main` branch, recent commits visible.

- [ ] **Step 2: Create v4 branch**

```bash
git checkout -b v4-self-improvement
git status
```

Expected: switched to new branch, clean tree.

- [ ] **Step 3: Backup current SKILL.md as reference**

```bash
cp SKILL.md /tmp/SKILL.md.v3-backup
wc -l SKILL.md /tmp/SKILL.md.v3-backup
```

Expected: both files have identical line counts (around 590 lines).

- [ ] **Step 4: Create tests directory for fixtures**

```bash
mkdir -p tests/fixtures tests/scenarios
ls tests/
```

Expected: two empty directories.

- [ ] **Step 5: Commit branch setup**

```bash
git add tests/
git commit --allow-empty -m "chore(v4): scaffold tests/ directory and start v4-self-improvement branch"
git status
```

Expected: clean working tree, one new commit.

---

## Phase A — Versioning Skeleton

### Task A.1: Add `version` field to skill SKILL.md frontmatter

**Files:**
- Modify: `SKILL.md` (frontmatter section, lines 1-11)

- [ ] **Step 1: Read current frontmatter**

```bash
head -15 SKILL.md
```

Expected output: existing frontmatter without `version` field.

- [ ] **Step 2: Add `version: "4.0.0"` to frontmatter**

Edit `SKILL.md` frontmatter to add a `version` field after `name:`. Final frontmatter:

```yaml
---
name: wiki
version: "4.0.0"
description: >
  Manage a project's LLM Wiki (Karpathy pattern) — three layers (concepts,
  entities, transcripts) plus archive/ for binaries. Eight operations:
  init, ingest-source, ingest-binary, query, lint, cleanup, split, wiki-status.
  Triggers: "ingest"/"додай до wiki/вікі", "wiki/вікі lint/query/cleanup/status",
  "оновити/перевір wiki/вікі", "що каже wiki про...", "знайди у вікі",
  any binary in tmp/. "вікі" = "wiki". Also use PROACTIVELY after feat/
  refactor commits and when binaries land in tmp/.
---
```

Note: also update `Seven operations` → `Eight operations` and add `wiki-status` to the trigger list.

- [ ] **Step 3: Verify**

```bash
head -15 SKILL.md | grep -E "version:|operations|wiki-status"
```

Expected: `version: "4.0.0"`, `Eight operations`, and `wiki-status` all present.

- [ ] **Step 4: Commit**

```bash
git add SKILL.md
git commit -m "feat(v4): bump skill version to 4.0.0, declare 8 operations"
```

### Task A.2: Add `## Versioning & Migration` section to SKILL.md

**Files:**
- Modify: `SKILL.md` — add new section after the existing `## Step 0: Discover Wiki Location and Schema` section

- [ ] **Step 1: Locate insertion point**

```bash
grep -n "^## " SKILL.md | head -20
```

Find the line number for `## Step 0: Discover Wiki Location and Schema`. The new section goes right after Step 0 ends (before `## Three Layers` begins).

- [ ] **Step 2: Insert new `## Versioning & Migration` section**

Add a new section with the following content (text adapted from spec section 1):

```markdown
## Versioning & Migration

Every wiki has a version stored in `{wiki}/schema.md` frontmatter:

\`\`\`yaml
---
wiki_version: "4.0"
last_migration: "2026-05-01"
---
\`\`\`

The skill itself has a version in this file's frontmatter (`version: "4.0.0"`).

### State detection on Step 0

After locating the wiki and reading `schema.md`, compare versions:

| State | Condition | Action |
|---|---|---|
| `current` | `wiki_version` == skill major version | Continue with operation |
| `legacy` | Wiki exists but `wiki_version` field absent in frontmatter | Identify version interactively, then propose migration |
| `older` | `wiki_version` < skill version | Generate migration plan, ask user once |
| `newer` | `wiki_version` > skill version | Warn user, ask whether to continue |
| `absent` | No wiki found | Defer to Init operation (bootstrap) |

### Migration plan format

For `older` and `legacy` states, present a single approval block:

\`\`\`
⚠️ Wiki версії 3.0, скіл — 4.0. Потрібна міграція.

План:
  1. {step 1 description}
  2. {step 2 description}
  ...

Зроблю всі N кроків одразу? [y] / [n] / [пропусти крок N]
\`\`\`

Wait for explicit `y`. On `n`, abort the operation. On `пропусти крок N`, exclude that step and re-confirm.

### Migration is explicit, not silent

Wiki migrations involve directory/file creation, gitignore changes, and frontmatter additions — user-visible changes that warrant explicit consent. Backfill of missing fields **inside** `.usage.json` records (forward-compat fields like `state`, `pinned`, `archived_at`) IS silent. Only structural migrations require the plan-then-confirm flow.

### Migration Log

`schema.md` carries a `## Migration Log` section that records what changed between versions. Each entry:

\`\`\`markdown
### 4.0 (2026-05-01)
- Added `.usage.json` telemetry sidecar
- Added `wiki_version` frontmatter to schema.md
- Added РЕФЛЕКСІЯ block as required behavior
- Added Tiered crystallization
- Added `wiki status` operation
- Reformulated Lint as Karpathy content-verification
\`\`\`

When proposing a migration plan, the skill reads its own SKILL.md frontmatter `version` and the wiki's `schema.md` `## Migration Log` to determine what changed.
```

(Note: in the actual SKILL.md, escape the inner triple-backticks correctly. The example above uses `\`\`\`` for clarity in this plan.)

- [ ] **Step 3: Verify section order**

```bash
grep -n "^## " SKILL.md | head -20
```

Expected: `## Versioning & Migration` appears between `## Step 0` and `## Three Layers`.

- [ ] **Step 4: Commit**

```bash
git add SKILL.md
git commit -m "feat(v4): add Versioning & Migration section"
```

### Task A.3: Update Step 0 procedure to include version comparison

**Files:**
- Modify: `SKILL.md` — `## Step 0: Discover Wiki Location and Schema` section

- [ ] **Step 1: Read current Step 0**

```bash
sed -n '/^## Step 0/,/^## /p' SKILL.md | head -30
```

- [ ] **Step 2: Add version comparison sub-step**

Within Step 0, after the existing 6 numbered steps (Find CLAUDE.md, Read CLAUDE.md, Verify wiki exists, etc.), add a 7th step:

```markdown
7. **Compare versions** — read `wiki_version` from `{wiki}/schema.md` frontmatter (if absent → state = `legacy`). Read your own `version` from this SKILL.md frontmatter. Determine state per the Versioning & Migration table. If state ≠ `current`, halt the requested operation and follow the migration flow.
```

- [ ] **Step 3: Verify**

```bash
grep -A2 "Compare versions" SKILL.md
```

Expected: new step 7 visible.

- [ ] **Step 4: Commit**

```bash
git add SKILL.md
git commit -m "feat(v4): Step 0 now compares wiki version against skill version"
```

### Task A.4: Update Init operation to write `wiki_version` frontmatter

**Files:**
- Modify: `SKILL.md` — `## Operation: Init (bootstrap-aware)` → `### Execute` subsection

- [ ] **Step 1: Read current Execute subsection**

```bash
sed -n '/^### Execute/,/^### /p' SKILL.md | head -30
```

- [ ] **Step 2: Update step 6 (schema.md creation)**

Replace the existing step 6 ("Create `{wiki}/schema.md` with layers, operations summary, ...") with:

```markdown
6. Create `{wiki}/schema.md` with `wiki_version: "4.0"` and `last_migration: "{today}"` in frontmatter, layers description, operations summary, `Entity Categories`, `Document Types`, `File Naming`, and `## Migration Log` section seeded with v4.0 entry. Add a single `## Wiki` pointer in CLAUDE.md: _"Wiki schema and operations → `docs/wiki/schema.md`. Skill: `wiki`."_ (for v1/v2 migrations — move existing CLAUDE.md sections into `schema.md` and replace them with the pointer)
```

- [ ] **Step 3: Add reference to versioning behavior**

After the `### Execute` block, add a note:

```markdown
### Versioning during Init

For all migration-from-legacy paths, follow the explicit plan format described in `## Versioning & Migration`. After successful migration, write `## Migration Log` entry documenting the path taken (e.g., "v1 → v4 via init bootstrap").
```

- [ ] **Step 4: Verify**

```bash
grep -A2 "wiki_version: \"4.0\"" SKILL.md
grep "Versioning during Init" SKILL.md
```

Expected: both present.

- [ ] **Step 5: Commit**

```bash
git add SKILL.md
git commit -m "feat(v4): Init writes wiki_version + Migration Log to new schema.md"
```

### Task A.5: Create version migration scenario fixture

**Files:**
- Create: `tests/scenarios/v3-to-v4-migration.md`

- [ ] **Step 1: Write fixture scenario**

Create `tests/scenarios/v3-to-v4-migration.md` with:

```markdown
# Scenario: v3 → v4 migration

## Setup

Mock wiki state:
- `docs/wiki/schema.md` exists, no `wiki_version` frontmatter (legacy v3)
- `docs/wiki/concepts/`, `docs/wiki/entities/`, `docs/wiki/transcripts/` populated
- `docs/wiki/index.md` and `log.md` present
- `docs/wiki/.usage.json` does NOT exist
- `.gitignore` does NOT have `docs/wiki/.usage.json`

## Trigger

User says: "що каже wiki про purchase-flow"

## Expected skill behavior

1. Step 0 reads schema.md frontmatter, finds no `wiki_version` → state = `legacy`
2. Skill halts the query operation
3. Skill outputs migration plan:
   - Identify: "Wiki existing but no version. Latest skill is 4.0. Last documented version was 3.0 (post-schema-canonicalization). Treat as 3.0?"
   - User confirms
   - Plan proposed:
     1. Add wiki_version: "4.0" + last_migration: "{today}" to schema.md frontmatter
     2. Add `## Migration Log` section to schema.md with v4.0 entry
     3. Create docs/wiki/.usage.json (empty dict)
     4. Add "docs/wiki/.usage.json" to .gitignore
     5. Append "## [{today}] migration | 3.0 → 4.0" to log.md
4. User confirms `y`, all 5 steps execute
5. After migration, original query operation resumes

## Manual verification

After running the scenario in a test wiki:
- `cat docs/wiki/schema.md` shows new frontmatter
- `cat docs/wiki/.usage.json` returns `{}`
- `grep ".usage.json" .gitignore` finds the line
- `grep "migration" docs/wiki/log.md` finds the entry
```

- [ ] **Step 2: Commit**

```bash
git add tests/scenarios/v3-to-v4-migration.md
git commit -m "test(v4): add v3→v4 migration scenario fixture"
```

---

## Phase B — Telemetry Sidecar

### Task B.1: Add `## Telemetry Sidecar (.usage.json)` section to SKILL.md

**Files:**
- Modify: `SKILL.md` — insert new section after `## Versioning & Migration`

- [ ] **Step 1: Locate insertion point**

```bash
grep -n "^## " SKILL.md
```

New section goes right after `## Versioning & Migration`.

- [ ] **Step 2: Insert section content**

Add a new `## Telemetry Sidecar (.usage.json)` section. Source content from spec section 4 ("Telemetry sidecar"). Include:

- Path: `{wiki}/.usage.json` (dotfile, gitignored)
- Record structure with all fields (`view_count`, `use_count`, `patch_count`, three timestamps, `created_at`, `state`, `pinned`, `archived_at`)
- Semantic mapping table (view = consult / use = synthesis-applied / patch = modified)
- Forward-compat fields explanation
- Mutator API (described as instructions to Claude): `bump_view`, `bump_use`, `bump_patch`, `forget`, `report`
- Tolerance rules: atomic write via temp+rename, corrupt read → `{}`, write fail → log only never raise, missing keys backfilled
- Role: prioritization not flagging
- gitignored rationale (per-clone, no merge noise)

The full text should mirror spec section 4 verbatim, adapted to instructional voice (e.g., "When you read a wiki page, increment view_count" instead of "API: bump_view(path)").

- [ ] **Step 3: Verify**

```bash
grep -n "Telemetry Sidecar" SKILL.md
grep -c "view_count\|use_count\|patch_count" SKILL.md
```

Expected: section present, all three counter fields mentioned multiple times.

- [ ] **Step 4: Commit**

```bash
git add SKILL.md
git commit -m "feat(v4): add Telemetry Sidecar section (.usage.json structure + mutator API)"
```

### Task B.2: Update each existing operation to call telemetry mutators

**Files:**
- Modify: `SKILL.md` — each operation section

- [ ] **Step 1: Update `## Operation: Ingest-Source` step list**

Within Ingest-Source's "Step-by-Step", add a new final step:

```markdown
**Step 8 — Update telemetry.** For each page read during this ingest, call `bump_view(path)`. For each page modified, call `bump_patch(path)`. For new pages, the patch action sets `created_at`. For each new `[[wikilink]]` added, call `bump_use(target_path)`.
```

- [ ] **Step 2: Update `## Operation: Ingest-Binary` step list**

Add similar step at end: telemetry updates for entity page (created), transcripts/index.md (patched), each entity touched (use bumped).

- [ ] **Step 3: Update `## Operation: Query` flow**

Within Query's "Process" step list, add: "After reading pages, call `bump_view(path)` for each."

- [ ] **Step 4: Update `## Operation: Lint`**

Within Lint, in step 1 (Staleness check), add: "Use `.usage.json` to prioritize which pages to read first — sort by highest `patch_count` and oldest `last_patched_at`."

- [ ] **Step 5: Update `## Operation: Split`**

In Split, after "Rewrite or delete original", add: "If original is deleted, call `forget(original_path)`. For each successor created, telemetry will auto-create the record on first patch."

- [ ] **Step 6: Update `## Operation: Cleanup`**

In Cleanup process, add: "When deleting orphan pages, call `forget(path)`."

- [ ] **Step 7: Verify**

```bash
grep -B1 "bump_view\|bump_patch\|bump_use\|forget" SKILL.md | head -40
```

Expected: telemetry calls referenced in 5+ operations.

- [ ] **Step 8: Commit**

```bash
git add SKILL.md
git commit -m "feat(v4): wire telemetry mutators into ingest/query/lint/split/cleanup ops"
```

### Task B.3: Update Init bootstrap to create .usage.json + .gitignore entry

**Files:**
- Modify: `SKILL.md` — `## Operation: Init` Execute subsection

- [ ] **Step 1: Add steps to Execute subsection**

After existing step 6 (schema.md creation), add:

```markdown
6a. Create `{wiki}/.usage.json` with `{}` (empty dict). This is the telemetry sidecar — see `## Telemetry Sidecar`.
6b. Add `{wiki}/.usage.json` to `.gitignore`. Telemetry is per-clone, not shared.
```

- [ ] **Step 2: Update bootstrap plan example in Init section**

If the Init section has an example plan (it does, per spec section 7), update the example to include these steps.

- [ ] **Step 3: Verify**

```bash
grep -A1 ".usage.json" SKILL.md | head -20
```

Expected: gitignore reference and creation step both present.

- [ ] **Step 4: Commit**

```bash
git add SKILL.md
git commit -m "feat(v4): Init bootstraps .usage.json + .gitignore entry"
```

### Task B.4: Create telemetry scenario fixture

**Files:**
- Create: `tests/scenarios/telemetry-counters.md`

- [ ] **Step 1: Write scenario**

Create `tests/scenarios/telemetry-counters.md` with three sub-scenarios:
1. View increment — read a page during query, verify `.usage.json` shows view_count++ and last_viewed_at updated
2. Patch increment — edit a page during ingest-source, verify patch_count++ and last_patched_at updated
3. Use increment — adding `[[page-b]]` to page-a's body, verify page-b's use_count++

Each sub-scenario: setup state, trigger action, expected `.usage.json` diff, manual verification command.

- [ ] **Step 2: Commit**

```bash
git add tests/scenarios/telemetry-counters.md
git commit -m "test(v4): add telemetry counter scenarios"
```

---

## Phase C — РЕФЛЕКСІЯ Block

### Task C.1: Add `## Self-Improvement Loop` section to SKILL.md

**Files:**
- Modify: `SKILL.md` — insert after `## Telemetry Sidecar`

- [ ] **Step 1: Insert section**

Add new `## Self-Improvement Loop` section. Subsections in order:

1. **Overview** — purpose: visible reflection of agent's reasoning + crystallization triggers
2. **РЕФЛЕКСІЯ block format** — verbatim template from spec section 2
3. **Triggers** — table from spec section 2 (TodoWrite-completion, pre-commit, periodic-nudge, memory-flush, explicit, anti-noise)
4. **Field rules** — from spec section 2 (mandatory fields, what counts as content)
5. **Anti-noise rule** — explicit definition from spec
6. **Cleanup-prompt** — embedded `🧹` prompt at end of reflection, including the safety layer (y = show only)

- [ ] **Step 2: Verify**

```bash
grep -n "Self-Improvement Loop\|РЕФЛЕКСІЯ" SKILL.md
```

Expected: section header + multiple РЕФЛЕКСІЯ references.

- [ ] **Step 3: Commit**

```bash
git add SKILL.md
git commit -m "feat(v4): add Self-Improvement Loop section with РЕФЛЕКСІЯ block spec"
```

### Task C.2: Wire reflection triggers into existing operations

**Files:**
- Modify: `SKILL.md` — each operation that involves edits/writes

- [ ] **Step 1: Add trigger reminders**

Within each of these operations (Ingest-Source, Ingest-Binary, Init, Cleanup, Split), add at the end:

```markdown
**After completion:** if this operation was triggered by a TodoWrite-completion or is part of a pre-commit moment, emit a РЕФЛЕКСІЯ block per `## Self-Improvement Loop`. If it was a read-only operation (no Write/Edit), apply the anti-noise rule and skip reflection.
```

For Query (read-only by default), add: "Query is read-only — apply anti-noise rule (no reflection unless query produced a filing-back wiki page edit)."

- [ ] **Step 2: Verify**

```bash
grep -c "РЕФЛЕКСІЯ block per" SKILL.md
```

Expected: 5+ matches.

- [ ] **Step 3: Commit**

```bash
git add SKILL.md
git commit -m "feat(v4): wire РЕФЛЕКСІЯ triggers into ingest/init/cleanup/split/query"
```

### Task C.3: Create reflection scenario fixture

**Files:**
- Create: `tests/scenarios/reflection-triggers.md`

- [ ] **Step 1: Write scenario**

Create `tests/scenarios/reflection-triggers.md` with sub-scenarios:
1. Pre-commit trigger — user runs ingest-source then `git commit`, reflection block fires before commit
2. TodoWrite-completion trigger — last todo marked done after a multi-edit ingest, reflection block fires
3. Anti-noise — query-only session with no edits, NO reflection block
4. Cleanup-prompt embedded — verify `🧹 Показати список` appears at end of reflection block

For each: setup, trigger, expected output.

- [ ] **Step 2: Commit**

```bash
git add tests/scenarios/reflection-triggers.md
git commit -m "test(v4): add reflection trigger scenarios"
```

---

## Phase D — Tiered Crystallization

### Task D.1: Add `## Tiered Crystallization` subsection to Self-Improvement Loop

**Files:**
- Modify: `SKILL.md` — within `## Self-Improvement Loop`

- [ ] **Step 1: Insert subsection**

Add subsection after the РЕФЛЕКСІЯ format/triggers content, before the cleanup-prompt subsection:

```markdown
### Tiered Crystallization

When the model judges that a recurring pattern is worth crystallizing into a reusable artifact, it proposes (never silently creates) one of four tiers:

| Tier | Artifact | Storage | Model judges (during nudge) |
|---|---|---|---|
| 1. Bash one-liner | shell script ≤20 lines | `scripts/{name}.sh` in project | "Same simple command repeated this session — would a one-liner save tokens?" |
| 2. Python script | Python with args, error handling | `scripts/{name}.py` | "Multi-step flow with conditions/parsing repeated — Python script worth it?" |
| 3. Wiki concept page | new `concepts/{name}.md` | `{wiki}/concepts/` | "Same concept explained across sessions, no existing page covers it" |
| 4. Full skill | new `~/.claude/skills/{name}/SKILL.md` | user-level skills | "Multi-step flow + trigger conditions + reusable across projects — warrants a full skill" |

These are heuristics for the model's holistic judgment during a periodic nudge — NOT counters this skill maintains algorithmically.

### Crystallization triggers

| Trigger | Default | Behavior |
|---|---|---|
| Periodic nudge | Every 15 tool-calling iterations | Skill instructs: "🔍 Зробив 15 операцій з останньої кристалізації — є щось варте автоматизації?" — agent judges holistically |
| Pre-commit | Before `git commit` | Hard trigger (paired with reflection) |
| TodoWrite-completion | Last todo → completed | Hard trigger (paired with reflection) |
| Pre-compression flush | Detect imminent context compression | Guaranteed turn for writing to wiki/scripts |
| Explicit user | "save this as bash/python/skill" | Manual override |

To disable periodic nudge, set `nudge_interval: 0` in `{wiki}/schema.md` frontmatter.

### Proposal format

Skill never creates an artifact silently. Always proposes:

\`\`\`
🔁 Помічаю патерн: {description of recurring pattern}
   Tier {N} ({type}): {proposed-path}

   Створити? [y] / [n] / [пізніше]
\`\`\`

- `y` → create file, show content, stage for commit; reflection records `Автоматизував: tier {N} — {path}`.
- `n` → don't create; record refusal for this normalized pattern in this session (don't re-propose).
- `пізніше` → don't create; may re-propose at next nudge.

### Tier-4 delegation

For tier 4 (full skill), delegate to `superpowers:writing-skills` instead of creating SKILL.md directly. That skill knows skill conventions; this skill knows wiki conventions.

### Anti-noise rules

- Don't propose if user already refused this normalized pattern in this session
- Don't propose for ambient commands (`ls`, `cd`, `git status`)
- Don't propose if arguments are radically different each time (looks like ad-hoc exploration)
- Don't propose tier 1/2 for one-shot operations (deploy, migration), even if recurring
```

- [ ] **Step 2: Verify**

```bash
grep -n "Tiered Crystallization\|Tier 1\|Tier 4\|writing-skills" SKILL.md
```

Expected: subsection present, all four tiers mentioned, writing-skills delegation noted.

- [ ] **Step 3: Commit**

```bash
git add SKILL.md
git commit -m "feat(v4): add Tiered Crystallization subsection (4 tiers + nudge triggers)"
```

### Task D.2: Add nudge_interval config knob to schema.md template

**Files:**
- Modify: `SKILL.md` — `## Operation: Init` Execute step 6 (schema.md creation)

- [ ] **Step 1: Update the schema.md template description**

Where step 6 describes what schema.md should contain, add `nudge_interval: 15` to the frontmatter example:

```yaml
---
wiki_version: "4.0"
last_migration: "2026-05-01"
nudge_interval: 15      # tool-calling iterations between crystallization nudges; 0 disables
---
```

- [ ] **Step 2: Add a brief note in `## Versioning & Migration` documenting the knob**

Add a small subsection or sentence: "Optional `nudge_interval: <N>` in `schema.md` frontmatter overrides the default crystallization periodic nudge frequency. Set to 0 to disable."

- [ ] **Step 3: Verify**

```bash
grep -n "nudge_interval" SKILL.md
```

Expected: 2-3 occurrences (frontmatter example + documentation note).

- [ ] **Step 4: Commit**

```bash
git add SKILL.md
git commit -m "feat(v4): document nudge_interval config knob in schema.md frontmatter"
```

### Task D.3: Create crystallization scenario fixture

**Files:**
- Create: `tests/scenarios/crystallization-tiers.md`

- [ ] **Step 1: Write scenario**

Cover tier-1 through tier-4 proposal scenarios. For each: trigger description, expected proposal output, expected user response handling (y/n/пізніше).

Plus: anti-noise scenarios (refused pattern not re-proposed, ambient commands ignored).

- [ ] **Step 2: Commit**

```bash
git add tests/scenarios/crystallization-tiers.md
git commit -m "test(v4): add tiered crystallization scenarios"
```

---

## Phase E — `wiki status` Operation

### Task E.1: Add `## Operation: Wiki Status` section

**Files:**
- Modify: `SKILL.md` — insert new operation between `## Operation: Query` and `## Operation: Lint`

- [ ] **Step 1: Insert section**

Add `## Operation: Wiki Status` with content from spec section 6:

- Description: manual pull-model, never auto-fired
- When invoked: triggers ("wiki status", "вікі статус", "як справи у wiki", etc.)
- Process: read `.usage.json`, count pages in concepts/entities/transcripts, count binaries in archive/, list pinned pages, detect passive issues (cross-ref drift, schema drift)
- Output format: full template from spec
- Action menu: a/b/c choices for content-verification + numbered passive fixes
- Telemetry update: `wiki status` itself does NOT bump view_count for surveyed pages (it's a meta-operation, not a read)

- [ ] **Step 2: Verify**

```bash
grep -n "^## Operation: " SKILL.md
```

Expected: 8 operations now visible (Init, Ingest-Source, Ingest-Binary, Query, **Wiki Status**, Lint, Split, Cleanup).

- [ ] **Step 3: Commit**

```bash
git add SKILL.md
git commit -m "feat(v4): add Wiki Status operation (manual pull-model)"
```

### Task E.2: Create wiki status scenario fixture

**Files:**
- Create: `tests/scenarios/wiki-status.md`

- [ ] **Step 1: Write scenario**

Setup: mock wiki with mixed activity (some hot pages, some cold, some pinned, one cross-ref drift, one schema drift). Trigger: "wiki status". Expected output: structured display matching spec section 6 format, with action menu.

- [ ] **Step 2: Commit**

```bash
git add tests/scenarios/wiki-status.md
git commit -m "test(v4): add wiki status scenario"
```

---

## Phase F — Karpathy Lint Reformulation

### Task F.1: Reformulate Lint operation around content-verification

**Files:**
- Modify: `SKILL.md` — `## Operation: Lint` section

- [ ] **Step 1: Read current Lint section**

```bash
sed -n '/^## Operation: Lint/,/^## /p' SKILL.md > /tmp/lint-current.txt
wc -l /tmp/lint-current.txt
```

- [ ] **Step 2: Replace Lint section content**

Rewrite the section per spec section 5. Key changes:

- **Reframe Lint as Karpathy content-verification** — staleness is verified by reading and judging, not by timestamps
- **Add subset-selection step** — propose `[a] Top-5 most edited` / `[b] Top-5 longest unverified` / `[c] By category` / `[d] Specific pages`
- **Keep checks 2-13** but remove explicit "30 days" thresholds — pure content-based
- **Telemetry as prioritization** — explain that `.usage.json` is used to sort which pages to read first, not to flag staleness
- **Passive vs content-verification distinction** — cross-ref drift, schema drift are passive (detected without LLM read); claims-against-code-state needs content read

Preserve the existing 13-point checklist structure but reformulate point #1 (Staleness):

```markdown
**1. Staleness — content verification (Karpathy pattern).** Don't infer staleness from timestamps. Instead:
- Propose a subset to verify (full-wiki check is expensive in tokens):
  - [a] Top-5 most edited (from `.usage.json` — high drift risk)
  - [b] Top-5 longest unpatched among active pages
  - [c] All pages in a specific category
  - [d] User-specified `[[page-names]]`
- For each selected page, read in full and verify claims:
  - Files/functions/classes in `## Sources` — do they exist? (file existence check, not mtime)
  - Described flows — match current code? (read code, compare to text)
  - Entity relationships in frontmatter — accurate?
  - Internal `[[wikilinks]]` — resolve?
  - Stated counts/inventories — drift signal; flag for deletion (per no-derivable-counts rule)
- Report findings; don't auto-flag. User chooses action per page.
```

- [ ] **Step 3: Add Pin protection note**

After the checklist, add:

```markdown
### Pin protection during Lint

Pages with `pinned: true` in `.usage.json` are skipped by content-verification proposals (a, b, c). They are listed in the report under a separate "Pinned" header but never auto-flagged for "глянь і онови" or "видали". User can `wiki unpin <path>` if they need to verify a pinned page.
```

- [ ] **Step 4: Verify**

```bash
grep -B1 "content-verification\|Pin protection" SKILL.md | head -20
```

Expected: both concepts present.

- [ ] **Step 5: Commit**

```bash
git add SKILL.md
git commit -m "feat(v4): reformulate Lint as Karpathy content-verification with telemetry prioritization"
```

### Task F.2: Add pin auto-suggest during Ingest-Binary and Ingest-Source

**Files:**
- Modify: `SKILL.md` — `## Operation: Ingest-Binary` and `## Operation: Ingest-Source`

- [ ] **Step 1: Add to Ingest-Binary**

In the entity page creation step, add:

```markdown
**Auto-suggest pin for critical-rare pages.** If the new entity page has frontmatter tag matching `security`, `incident`, `migration`, `compliance`, `recovery`, OR if filename contains any of these prefixes, ask:

\`\`\`
Сторінка [[{slug}]] виглядає як критично-рідкісна. Запропонувати pin? [y/n]
\`\`\`

On `y`, set `pinned: true` in `.usage.json` for this page.
```

- [ ] **Step 2: Add to Ingest-Source**

Within the page creation step, add the same pin-auto-suggest logic.

- [ ] **Step 3: Verify**

```bash
grep -c "pinned: true\|Auto-suggest pin" SKILL.md
```

Expected: 2+ matches.

- [ ] **Step 4: Commit**

```bash
git add SKILL.md
git commit -m "feat(v4): auto-suggest pin for security/incident/migration/compliance/recovery pages"
```

### Task F.3: Create staleness scenario fixture

**Files:**
- Create: `tests/scenarios/staleness-content-verification.md`

- [ ] **Step 1: Write scenario**

Cover three sub-scenarios:
1. Mock wiki with one page whose `## Sources` references a deleted file → content-verification flags it
2. Mock wiki with one pinned security page that's never read → wiki status shows it under Pinned, never as stale
3. Mock wiki with cross-ref drift (`[[page-a]]` → page-b deleted) → passive detection, no LLM read needed

- [ ] **Step 2: Commit**

```bash
git add tests/scenarios/staleness-content-verification.md
git commit -m "test(v4): add staleness content-verification scenarios"
```

---

## Phase G — Init Bootstrap Extension

### Task G.1: Add state detection table to Init operation

**Files:**
- Modify: `SKILL.md` — `## Operation: Init (bootstrap-aware)` → `### Discovery` subsection

- [ ] **Step 1: Update Discovery subsection**

Replace the current "Determine wiki state" table with the expanded 5-state version from spec section 7:

```markdown
2. **Determine wiki state:**

| State | Condition | Action |
|---|---|---|
| `absent` | No `docs/wiki/` exists | Bootstrap from scratch |
| `legacy` | Wiki exists but no `wiki_version` in `schema.md` frontmatter | Identify version interactively, then propose migration |
| `current` | `wiki_version` matches skill's version | Continue |
| `older` | `wiki_version` < skill's version | Generate migration plan, ask user once |
| `newer` | `wiki_version` > skill's version | Warn, ask whether to continue |
```

- [ ] **Step 2: Verify**

```bash
grep -n "absent\|legacy\|current\|older\|newer" SKILL.md | head
```

Expected: all 5 states mentioned.

- [ ] **Step 3: Commit**

```bash
git add SKILL.md
git commit -m "feat(v4): expand Init state detection to 5 states (legacy/older/newer added)"
```

### Task G.2: Add project-type auto-suggest to Init

**Files:**
- Modify: `SKILL.md` — `## Operation: Init` → between Discovery and Plan

- [ ] **Step 1: Insert subsection**

After Discovery, before Plan:

```markdown
### Project-type detection (only for `absent` state)

When bootstrapping a fresh wiki, scan project root for type signals to propose initial `entities/` categories. This is a SUGGESTION — user can override or pick custom categories.

| Signal | Suggested entities/ categories |
|---|---|
| `package.json` / `tsconfig.json` | `components/`, `services/` |
| `Cargo.toml` | `modules/`, `traits/` |
| `requirements.txt` / `pyproject.toml` | `modules/`, `classes/` |
| `go.mod` | `packages/`, `interfaces/` |
| `*.csproj` | `classes/`, `services/` |
| `pom.xml` / `build.gradle` | `packages/`, `services/` |
| no code signals (research / personal / docs project) | `people/`, `documents/` |

Project-type detection ONLY influences proposed initial categories. It does NOT affect any other behavior (especially not staleness — see `## Operation: Lint`).
```

- [ ] **Step 2: Verify**

```bash
grep -n "Project-type detection" SKILL.md
```

Expected: subsection present.

- [ ] **Step 3: Commit**

```bash
git add SKILL.md
git commit -m "feat(v4): Init suggests entities/ categories from project type signals"
```

### Task G.3: Update bootstrap plan format

**Files:**
- Modify: `SKILL.md` — `## Operation: Init` → `### Plan` subsection

- [ ] **Step 1: Add bootstrap plan template**

After existing Plan content, add the explicit bootstrap plan template from spec section 7:

```markdown
### Bootstrap plan template (for `absent` state)

\`\`\`
📂 Створюю нову wiki у docs/wiki/

План:
  1. docs/wiki/schema.md — frontmatter (wiki_version: "4.0", last_migration: "{today}", nudge_interval: 15) + три розділи + Migration Log
  2. docs/wiki/index.md — порожній з трьома секціями (Concepts | Entities | Transcripts)
  3. docs/wiki/log.md — порожній з заголовком
  4. docs/wiki/concepts/ — порожня папка
  5. docs/wiki/entities/ — пропонована структура для {detected_type}: {category-list}
  6. docs/wiki/transcripts/ — порожня папка
  7. docs/wiki/.usage.json — порожній dict
  8. archive/ — поза wiki (gitignored)
  9. CLAUDE.md — додати 1-line pointer "Wiki schema → docs/wiki/schema.md"
  10. .gitignore — додати "archive/" і "docs/wiki/.usage.json"

[y] так, створи все  /  [n] скасувати
\`\`\`

After confirmation, execute all 10 steps. After execution, write `## [{today}] init | bootstrap fresh wiki v4.0` to log.md.
```

- [ ] **Step 2: Verify**

```bash
grep "Bootstrap plan template" SKILL.md
```

Expected: subsection present.

- [ ] **Step 3: Commit**

```bash
git add SKILL.md
git commit -m "feat(v4): add explicit bootstrap plan template for absent state"
```

---

## Phase H — Cleanup-Flow Consolidation

### Task H.1: Add unified cleanup-flow section

**Files:**
- Modify: `SKILL.md` — within `## Self-Improvement Loop`, after Tiered Crystallization

- [ ] **Step 1: Insert subsection**

Add `### Cleanup-flow` subsection containing the unified flow that both РЕФЛЕКСІЯ embedded prompt and `wiki status` action menu trigger:

- Two entry points (РЕФЛЕКСІЯ `[y]` / `wiki status` `[a/b/c]`)
- Same downstream flow: subset selection → content-verification → action menu
- Action menu table (глянь і онови / видали / pin / merge / розбий / глянь обидві)
- Telemetry effects per action
- Safety layers:
  - Double confirmation for `видали` (must say `yes`, not `y`)
  - Snapshot before destructive ops via `git commit -m "chore(wiki): snapshot before {operation}"` (rollback = `git revert`)
  - Pin protection for `видали` (refuse, instruct user to `wiki unpin` first)

- [ ] **Step 2: Verify**

```bash
grep -n "Cleanup-flow\|глянь і онови\|snapshot before" SKILL.md
```

Expected: subsection + action menu items + safety layers all present.

- [ ] **Step 3: Commit**

```bash
git add SKILL.md
git commit -m "feat(v4): unified cleanup-flow with action menu + safety layers"
```

### Task H.2: Add `wiki unpin <path>` micro-operation

**Files:**
- Modify: `SKILL.md` — `## Self-Improvement Loop` → `### Cleanup-flow` (or as separate small operation)

- [ ] **Step 1: Insert text**

Within Cleanup-flow's "Pin protection" subsection, add:

```markdown
### `wiki unpin <path>` and `wiki pin <path>`

Toggle the `pinned` field in `.usage.json` for a specific page. These are micro-operations available as user commands:

- `wiki pin <path>` — set `pinned: true`. Page is now protected from cleanup.
- `wiki unpin <path>` — set `pinned: false`. Page rejoins normal cleanup-flow.

After toggle, the skill confirms the new state and notes which protections (de)apply.
```

- [ ] **Step 2: Verify**

```bash
grep "wiki pin\|wiki unpin" SKILL.md
```

Expected: both commands documented.

- [ ] **Step 3: Commit**

```bash
git add SKILL.md
git commit -m "feat(v4): add wiki pin/unpin micro-operations"
```

### Task H.3: Create cleanup-flow scenario fixture

**Files:**
- Create: `tests/scenarios/cleanup-flow.md`

- [ ] **Step 1: Write scenario**

Cover end-to-end:
1. РЕФЛЕКСІЯ `[y]` → subset selection → content-verification → user picks "1 — глянь і онови" for one finding
2. `wiki status` → user picks "[a]" → top-5 most edited verified → user picks "видали" → double-confirm flow
3. Pin protection — user attempts `видали` on pinned page, skill refuses with helpful message
4. Snapshot rollback — user does destructive op, regrets, runs `git revert HEAD`, wiki restored

- [ ] **Step 2: Commit**

```bash
git add tests/scenarios/cleanup-flow.md
git commit -m "test(v4): add end-to-end cleanup-flow scenarios"
```

---

## Phase I — Final Integration

### Task I.1: Update `## Common Mistakes` table

**Files:**
- Modify: `SKILL.md` — `## Common Mistakes` table at the bottom

- [ ] **Step 1: Add new rows**

Append to the existing table:

```markdown
| Auto-flagging staleness by timestamp | Use Karpathy content-verification — read pages and judge claims. Telemetry is for prioritization, not flagging. |
| Creating crystallization artifact silently | Skill ALWAYS proposes (y/n/пізніше). Never `Write` a script/page/skill without explicit user approval. |
| Treating `.usage.json` as user-visible | It's metadata, gitignored, per-clone. Don't mention specific counter values to user unless `wiki status` is invoked. |
| Migrating `wiki_version` silently | Migration is explicit plan-then-confirm for structural changes. Only field-level backfill in `.usage.json` is silent. |
| Skipping reflection because "small change" | Anti-noise rule applies only to read-only blocks. Any edit/write block produces reflection. |
```

- [ ] **Step 2: Verify**

```bash
grep -c "^| " SKILL.md  # rough count of table rows
```

Expected: row count increased by 5.

- [ ] **Step 3: Commit**

```bash
git add SKILL.md
git commit -m "feat(v4): add v4-specific entries to Common Mistakes table"
```

### Task I.2: Update README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Read current README**

```bash
cat README.md
```

- [ ] **Step 2: Update version + features**

Add/update:
- Version badge or text mentioning v4.0
- Feature list to include: РЕФЛЕКСІЯ block, telemetry, tiered crystallization, wiki status, Karpathy lint
- Hermes-Agent attribution and link

Keep it concise — README is short, not a re-spec.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs(v4): update README with v4.0 features and Hermes attribution"
```

### Task I.3: Wiki self-test against this skill's own SKILL.md

**Files:**
- (none — manual exercise)

- [ ] **Step 1: Mental dogfood test**

Read through the entire updated SKILL.md from top to bottom. Ask:
- Are all 8 operations cross-referenced from the table of contents/intro?
- Does every operation that touches a page mention telemetry mutator?
- Does every operation that produces edits mention reflection trigger?
- Are pin protections consistently mentioned in cleanup-related sections?
- Is the Karpathy-staleness principle reinforced wherever staleness is discussed?
- Are anti-noise rules referenced where they should fire (read-only, ambient commands, refused patterns)?

Note any inconsistencies in `tests/scenarios/integration-checklist.md`.

- [ ] **Step 2: Run integration scenarios**

For each `tests/scenarios/*.md`, mentally walk through against the updated SKILL.md. If any scenario reveals a gap, file an issue in the same scenario file under "Issues Found".

- [ ] **Step 3: Fix any gaps found**

If gaps surface, edit SKILL.md inline. Commit with message `fix(v4): address gap found during integration test — {description}`.

- [ ] **Step 4: Final commit (if no fixes needed)**

```bash
git status
```

Expected: clean working tree. If clean, no new commit needed for this task.

### Task I.4: Merge to main + tag

**Files:**
- (none — git operations only)

- [ ] **Step 1: Final review of branch**

```bash
git log --oneline main..v4-self-improvement
git diff --stat main..v4-self-improvement
```

Expected: ~20-30 commits, modifications to SKILL.md and additions in `tests/scenarios/`.

- [ ] **Step 2: Switch to main and merge**

```bash
git checkout main
git merge --ff-only v4-self-improvement
```

Expected: fast-forward merge succeeds. If it doesn't (main moved during work), abort and ask user how to proceed.

- [ ] **Step 3: Tag the release**

```bash
git tag -a v4.0.0 -m "Wiki Skill v4.0 — Self-Improvement Loop (Hermes-aligned)"
git tag --list | tail -5
```

Expected: `v4.0.0` tag visible.

- [ ] **Step 4: Delete branch**

```bash
git branch -d v4-self-improvement
git branch
```

Expected: branch removed, only `main` listed.

- [ ] **Step 5: Push (only if user explicitly approves)**

Wait for user approval before pushing. If approved:

```bash
git push origin main
git push origin v4.0.0
```

If not approved, leave local-only.

---

## Self-Review

After completing all phases, run through this checklist:

**Spec coverage:**
- [ ] Section 1 (Architecture overview) — all 6 new artifacts implemented (versioning, reflection, crystallization, telemetry, wiki status, Karpathy staleness)
- [ ] Section 2 (Versioning + Migration) — Phase A complete
- [ ] Section 3 (РЕФЛЕКСІЯ block) — Phase C complete
- [ ] Section 4 (Tiered Crystallization) — Phase D complete
- [ ] Section 5 (Telemetry sidecar) — Phase B complete
- [ ] Section 6 (`wiki status`) — Phase E complete
- [ ] Section 7 (Karpathy lint reformulation) — Phase F complete
- [ ] Section 8 (Bootstrap + cleanup-flow) — Phases G + H complete
- [ ] Phasing/integration — Phase I complete

**Placeholder scan:**
- [ ] Search SKILL.md for `TBD`, `TODO`, `XXX`, `???` — should be zero
- [ ] Search for empty section headers (e.g., `## Section\n\n##`) — should be zero
- [ ] Check that every reference to another operation/section uses an existing target

**Type consistency:**
- [ ] `view_count` / `use_count` / `patch_count` — used consistently throughout (no aliases)
- [ ] `bump_view` / `bump_use` / `bump_patch` / `forget` — same naming everywhere
- [ ] `wiki_version` (field name) — same everywhere; not `version` in some places
- [ ] State names (`absent`/`legacy`/`current`/`older`/`newer`) — consistent across Versioning section and Init Discovery

**Operation count:**
- [ ] Frontmatter description says "Eight operations"
- [ ] Section bodies present 8 operation headers (Init, Ingest-Source, Ingest-Binary, Query, Wiki Status, Lint, Split, Cleanup)
- [ ] Migration Log entry mentions 8 operations

If any item fails, fix inline before declaring the plan executed.

---

## Open questions to resolve during implementation

These were flagged in the spec as deferred to plan-writing. The implementer should investigate and document the chosen approach in commit messages or in the SKILL.md text itself:

1. **Periodic nudge mechanism** — the wiki skill is purely instructional Markdown; it cannot directly emit nudges every N tool-iterations because the harness doesn't expose iteration counters to skills. Options:
   - (a) Rely on instruction-based discipline plus hard event triggers (commit, TodoWrite-completion). Periodic becomes a "self-checked" reminder that the model reads in SKILL.md context.
   - (b) Document that periodic nudge is a "future enhancement requiring harness support".
   - **Recommended:** option (a). Model will read the instruction "every 15 ops, judge whether to crystallize" each time it consults SKILL.md, which is at every operation. This is approximate but workable.

2. **Memory flush detection** — Claude Code doesn't expose imminent-compression signals to skills. Options:
   - (a) User-explicit only ("save before /compress" — user must trigger).
   - (b) Document as future enhancement.
   - **Recommended:** option (a). Add to РЕФЛЕКСІЯ trigger list: "explicit user command 'save before compress'".

3. **`nudge_interval` config knob location** — must live somewhere readable on every Step 0. Options:
   - (a) `schema.md` frontmatter (already a Step-0 read target).
   - (b) Separate config file.
   - **Recommended:** option (a) — already in plan.

4. **Pin auto-suggest tag set** — initial tags: `security`, `incident`, `migration`, `compliance`, `recovery`. Plan author may add more. Validate via fixture scenario in Phase F.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-01-wiki-skill-v4.md`. Two execution options:

1. **Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration. **REQUIRED SUB-SKILL:** `superpowers:subagent-driven-development`. Each subagent does one task, returns, I review, dispatch next.

2. **Inline Execution** — Execute tasks in this session using `superpowers:executing-plans`, batch execution with checkpoints for review.

User has already chosen subagent-driven (per latest message: "пиши план і працюй потім сабагентами"). Proceeding with that.
