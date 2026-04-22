---
name: wiki
description: >
  Manage a project's LLM Wiki (Karpathy pattern) — three layers (concepts,
  entities, transcripts) plus archive/ for binaries. Seven operations:
  init, ingest-source, ingest-binary, query, lint, cleanup, split.
  Triggers: "ingest"/"додай до wiki/вікі", "wiki/вікі lint/query/cleanup",
  "оновити/перевір wiki/вікі", "що каже wiki про...", "знайди у вікі",
  any binary in tmp/. "вікі" = "wiki". Also use PROACTIVELY after feat/
  refactor commits and when binaries land in tmp/.
---

# LLM Wiki (Karpathy Pattern)

A persistent, compounding knowledge base maintained by Claude. Instead of re-discovering knowledge each session, the wiki accumulates synthesized understanding across conversations.

This skill is **project-agnostic** — it discovers the wiki location automatically.

## Philosophy

From Karpathy's original pattern (https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f):

> _"the LLM is rediscovering knowledge from scratch on every question. There's no accumulation."_

> _"The tedious part of maintaining a knowledge base is not the reading or the thinking — it's the bookkeeping. Humans abandon wikis because the maintenance burden grows faster than the value. LLMs don't get bored, don't forget to update a cross-reference, and can touch 15 files in one pass."_

> _"connections between documents are as valuable as the documents themselves"_ (Vannevar Bush's Memex)

The wiki is not documentation. It is synthesized understanding that compounds across sessions. Cross-references are first-class — a page with no `[[wikilinks]]` is suspect.

## Division of Labor

Karpathy draws a sharp line: the human curates and directs; the LLM does everything mechanical.

| Human | LLM |
|---|---|
| Curate sources (decide what's worth ingesting) | Read and synthesize those sources |
| Direct the analysis (ask good questions) | Summarize, cross-reference, update pages |
| Think about what it all means | All bookkeeping: index, log, `[[wikilinks]]`, `## See also` |
| Veto LLM proposals on init / cleanup / schema changes | Propose, never execute destructive ops without consent |

> _"You never (or rarely) write the wiki yourself — the LLM writes and maintains all of it."_

If you catch yourself hand-editing wiki pages page-by-page, it's a skill failure — prefer running the relevant operation.

## Modularity

> _"Everything mentioned above is optional and modular — pick what's useful, ignore what isn't."_

Not every project needs every layer or operation:

- **No binary documents (PDFs, contracts, images)?** → skip `entities/` and `transcripts/`. Run only `concepts/`. Skip `ingest-binary` and `doc-extract` dependency.
- **Small wiki (< 20 pages)?** → lint once per quarter, not every 10 sessions. Skip `split` entirely.
- **No raw sources dir?** → `ingest-source` still works from code diffs and conversation context; don't force a `specs/` folder.
- **Schema minimal?** → `schema.md` can be 10 lines. No need for populated Entity Categories or Document Types until the project actually has categories.

The seven operations are a **palette**, not a checklist. A code project might use only `ingest-source` + `query` + `lint`. A research project might lean heavily on `ingest-binary`. Adapt.

## Step 0: Discover Wiki Location and Schema

**Before any operation**, locate both the wiki directory and its schema. Follow this sequence:

1. **Find CLAUDE.md** — look in the current working directory, then walk up parent directories until found
2. **Read CLAUDE.md's Wiki section** — look for a `## Wiki` section that declares wiki paths (e.g., "Wiki (`docs/wiki/`)")
3. **Verify wiki exists** — check that the discovered directory contains `index.md`
4. **If no Wiki section in CLAUDE.md** — search for `docs/wiki/index.md` relative to CLAUDE.md location
5. **Locate schema** — wiki schema (layers, operations, conventions, `Entity Categories`, `Document Types`, `File Naming`) lives in exactly one of:
   - **Preferred (v3+):** `{wiki}/schema.md` — canonical location, keeps wiki metadata out of CLAUDE.md resident context
   - **Legacy (v1–v2):** sections inside `CLAUDE.md` itself (`## Wiki`, `## Entity Categories`, `## Document Types`, `## File Naming`)

   Try `{wiki}/schema.md` first. Fall back to CLAUDE.md sections. When both exist, prefer `schema.md` and flag the duplication during next lint.
6. **If wiki not found at all** — tell the user: "No wiki found. Would you like me to initialize one?" Then delegate to the **Init (bootstrap-aware)** operation below — it detects project state (absent / v1 / current), creates the three-layer structure (`concepts/`, `entities/`, `transcripts/`) with `archive/` outside git, proposes migration for existing artifacts, and writes schema to `{wiki}/schema.md`.

All paths below use `{wiki}` as placeholder for the discovered wiki directory (e.g., `docs/wiki/`). Replace mentally with the actual path.

**CRITICAL: Never create a second wiki.** If you find an existing wiki, use it. If CLAUDE.md references a wiki path, trust it. Only create a new wiki when none exists anywhere in the project.

**Why schema.md is preferred over CLAUDE.md sections:** CLAUDE.md loads into resident context on every session start, so every byte there is paid on every turn. Wiki schema is operational metadata for the wiki itself — it's needed only during wiki operations, not on every conversation. Moving it to `{wiki}/schema.md` reduces resident-context bloat without losing anything, because wiki operations always discover the wiki first anyway.

_Note: this is a v3 evolution from Karpathy's original pattern, which placed schema in CLAUDE.md/AGENTS.md. The rationale is purely operational (resident-context cost); the spirit (schema as co-evolved governance document) is preserved. Projects following the original pattern (v1–v2) continue to work via the CLAUDE.md fallback._

## Three Layers (within Wiki)

The wiki itself has three internal layers:

```
{wiki}/concepts/         → themes, processes, rules (synthesis)
{wiki}/entities/         → specific things (people, contracts, objects, ...)
{wiki}/transcripts/      → full text of binaries (for grep / LLM context)
```

Plus external layers:

```
Raw Binaries (immutable) → archive/ (gitignored, outside wiki)
Schema (conventions)     → {wiki}/schema.md (preferred, v3+)
                         → CLAUDE.md sections (legacy, v1–v2)
```

**Concepts** — the existing layer. Themes, gotchas, architectural decisions.

**Entities** — hub pages for specific things. Each entity page has:
- Frontmatter with `type: entity`, `category`, `key`, project-specific fields
- Synthesis (what this is, why it matters)
- Cross-refs (to other entities, concepts, transcripts, binaries)

**Lazy entity creation:** create an entity page only when a document or
operation actually references the entity. Don't pre-populate from inventories.

**Transcripts** — auto-generated MD with full text of a binary. Frontmatter
links back to source binary and corresponding entity page. No synthesis,
no editing — pure raw text for grep and LLM context.

**Naming** — for documents:  `{YYYY-MM-DD}_{type}_{slug}.{ext}`.
For templates: `template_{type}_{slug}.{ext}`.
For abstract entities: `{slug}.md`.
Cyrillic OK. Spaces → `-`. Forbidden: `/\?*<>:|`, quotes, dots (except before ext).

## Navigation Files

| File | Purpose | Format |
|------|---------|--------|
| `{wiki}/index.md` | Catalog of all pages, organized by category | `- [[page-name]] — one-line description` |
| `{wiki}/log.md` | Chronological record of all operations | `## [YYYY-MM-DD] operation \| Subject` + optional `touched: [[page-a]], [[page-b]]` line for searchability |

**Read `index.md` FIRST** for any wiki operation — it's your map.

---

## Operation: Ingest-Source

Process a new source (spec, feature, code change) into the wiki.

### When to Ingest

- After implementing a significant feature or spec
- When a new design doc lands in raw sources
- When gotchas or non-obvious behaviors are discovered during development
- When the user explicitly asks ("ingest this", "додай до wiki")
- After a major refactor that changes architecture or patterns

### Process

```
0. DISCOVER wiki location (Step 0 above)
1. READ the source (spec, code diff, conversation context)
2. READ {wiki}/index.md to find existing relevant pages
3. READ those relevant wiki pages
4. UPDATE existing pages OR CREATE new pages
5. UPDATE cross-references on other pages that should link here
6. UPDATE {wiki}/index.md (add new pages, update descriptions)
7. APPEND to {wiki}/log.md
```

### Step-by-Step

**Step 1 — Understand the source.** Read the spec or examine the code changes. Identify: what entities are involved? What flows changed? What gotchas emerged? What's the "why" behind the change?

**Step 1.5 — Discuss with the user.** Present key takeaways before writing anything. Summarize what you plan to add/update and to which pages. Let the user guide emphasis — they know what matters most. This is especially important for large sources that touch many topics. Skip this step only if the user explicitly asked for a quick/silent ingest.

**Step 2 — Find relevant wiki pages.** Read `index.md`. Determine which existing pages need updates. A single source typically touches 3-5 wiki pages.

**Step 3 — Update existing pages.** For each affected page:
- Add new information in the appropriate section
- Update facts that changed (don't leave stale info)
- Add `[[wikilinks]]` to new pages if created
- Update the `## See also` section
- Add source reference to `## Sources`

**Step 4 — Create new pages (if needed).** Only when a topic is substantial enough to warrant its own page. Use the Page Template below.

**Step 5 — Update index.md.** Add any new pages. Update descriptions if page scope changed.

**Step 6 — Append to log.md:**
```markdown
## [YYYY-MM-DD] ingest | Brief description of what was ingested
- Source: what was processed (spec name, feature description, code area)
- Updated: list of pages touched
- Created: list of new pages (if any)
- Key changes: 1-2 sentences on what's new
- touched: [[page-a]], [[page-b]], [[page-c]]
```

The `touched:` line enables `grep -l 'page-name' log.md` searches like
"when did we last update purchase-flow?" — purely operational metadata,
no synthesis. Optional but recommended for non-trivial ingests.

### Page Template

```markdown
# Page Title

One-paragraph description of what this page covers.

## [Content sections — structure varies by topic]

## See also
- [[related-page]] — why it's related
- [[another-page]] — why it's related

## Sources
- `path/to/relevant-spec.md`
- `path/to/relevant/code.ts`
```

### Page Conventions

- Start with `# Title` and a short description
- Use `[[wikilinks]]` for cross-references (Obsidian-compatible)
- End with `## See also` (links to related pages) and `## Sources` (raw source references)
- **Describe WHAT and WHY** — code shows HOW. Don't duplicate code in wiki.
- Tables for structured comparisons. Code blocks for schemas/examples.
- Keep pages focused — one topic per page. Split when a page exceeds ~200 lines.

### What Belongs in Wiki vs. NOT

| Wiki (YES) | NOT Wiki |
|------------|----------|
| Synthesized understanding of how systems work | Raw API docs (that's code) |
| Flow descriptions (purchase → receive → inventory) | Git history (use `git log`) |
| Non-obvious relationships between entities | File paths (use `grep`) |
| Gotchas that have bitten us | Ephemeral task details |
| Architectural decisions and their rationale | Debugging session logs |
| Cross-cutting concerns spanning multiple files | One-off fix recipes |

### IMPORTANT: Wiki vs. CLAUDE.md

When updating documentation after implementing a feature:
- **CLAUDE.md** gets ONLY: new conventions, rules, data model summary changes (1-2 lines max)
- **Wiki** gets: implementation details, how things work, component behavior, API specifics
- If in doubt whether something is a "convention" or "implementation detail" — it's wiki
- Reference wiki from CLAUDE.md when needed: "Details → see [[page-name]] in wiki"

---

## Operation: Ingest-Binary

Process a binary artifact (PDF, DOCX, image) into the wiki and archive.

### When to Ingest-Binary

- User drops a file into `tmp/`
- User says "ingest this PDF/DOCX/file", "додай цей документ"
- A new signed contract / certificate / letter arrives

### Process

1. **Detect / ask category** — suggest from `Entity Categories` in schema
   (`{wiki}/schema.md`, fallback to CLAUDE.md). If user wants a new category,
   add a row to schema.md (or CLAUDE.md for legacy v1–v2 layout)
2. **Detect / ask type** — suggest from `Document Types` in schema
   (same fallback order). If new type, add a row to schema.md (or CLAUDE.md legacy)
3. **Propose slug** — from filename + date + parties;
   ask user to confirm or edit
4. **Extract text → transcript (via `doc-extract` skill):**

   Call:
   ```bash
   bash ~/.claude/skills/doc-extract/bin/extract.sh <source_file> \
     --out <wiki>/transcripts/<slug>.md \
     --format md
   ```

   Handle exit code:
   - `0` — transcript created, proceed.
   - `10` (extraction_failed) — STOP. Read stderr method_chain;
     tell user: "doc-extract пройшов каскад [методи], вийшло N символів.
     Варіанти: (1) вручну → summary, (2) Read tool (LLM, дорого),
     (3) пропустити". Wait for user decision.
   - `20` (missing_dependency) — STOP. Run
     `bash ~/.claude/skills/doc-extract/bin/doctor.sh`, show output,
     ask user to install missing deps, then retry.
   - `30` (unsupported_format) — ask user to skip or convert first.
   - `40/50` — caller bug, show stderr.

   **Важливо:** wiki більше НЕ падає на Read tool (LLM vision) сам.
   Єдиний шлях до LLM — явне рішення юзера у відповідь на exit 10.
   Це уникає дорогих silent fallback'ів.

   Если `doc-extract` скіл відсутній — повідом юзера, покажи
   install-команду: `curl -fsSL https://raw.githubusercontent.com/kozaksv/claude-doc-extract-skill/main/install.sh | bash`
5. **Move binary → `archive/{path}/{slug}.{ext}`** (per File Naming convention)
6. **Create entity page → `entities/{category}/{slug}.md`:**
   - Frontmatter (type=entity, category, key, binary, transcript, project-specific fields)
   - Synthesis (LLM proposes — user edits)
   - Cross-refs: scan transcript for mentions of other entities;
     if entity exists → link; if not → lazy-create stub and link
7. **Update related entity pages** — for each entity touched, append to its
   "Documents" section a link to this new entity page
8. **Update concepts** — if new info changes a concept (e.g., new exception
   for `discrepancies`), propose update; ask user to confirm
9. **Update navigation:**
   - `entities/index.md` (or wiki/index.md Entities section): append row
   - `transcripts/index.md`: append row
   - `log.md`: append `## [YYYY-MM-DD] ingest-binary | <description>`

---

## Operation: Query

Search the wiki to answer a question about the project.

### When to Query

- When the user asks about architecture, flows, or design decisions
- When Claude needs context about how a system works before making changes
- When searching for gotchas before touching a specific area
- When the user says "що каже wiki про...", "wiki query", "знайди у wiki"

### Process

```
0. DISCOVER wiki location (Step 0 above)
1. READ {wiki}/index.md
2. IDENTIFY relevant pages from index (usually 1-3)
3. READ those pages
4. SYNTHESIZE answer with citations: [[page-name]]
5. If answer is valuable and reusable → FILE BACK as new wiki page
```

### Filing Back

When a query produces a valuable synthesis (comparison, analysis, connection between topics), consider saving it as a new wiki page. This is a key Karpathy insight: **good answers compound into the knowledge base** rather than disappearing into chat history.

Ask yourself: "Would this answer be useful in a future session?" If yes → create a page.

---

## Operation: Lint

Periodic health-check of the wiki.

### When to Lint

- User explicitly asks ("wiki lint", "перевір wiki")
- Periodically (every ~10 sessions or after major changes)
- When something feels off or inconsistent during other operations

### Checklist

Run through each check and report findings:

**1. Staleness** — Read each wiki page and verify key claims against current code:
- Do referenced files/functions still exist?
- Do described flows match current implementation?
- Are entity relationships accurate?
- Has the data model changed since last update?

**2. Contradictions** — Cross-check between pages:
- Does page A say X while page B says Y?
- Are numbers consistent (test counts, migration numbers, route counts)?

**3. Orphan Pages** — Check index.md:
- Any pages in `{wiki}/` not listed in index.md?
- Any pages listed in index.md that don't exist?

**4. Missing Cross-References** — For each page:
- Does `## See also` include all relevant links?
- Are there `[[wikilinks]]` to related content in the body?

**5. Coverage Gaps** — Think about what's missing:
- Important concepts that lack their own page
- Significant features not reflected in any page
- Recent changes not ingested

**6. Page Health** — For each page:
- Is the `## Sources` section up to date?
- Is the page too long (>200 lines → consider splitting)?
- Is the description in index.md still accurate?

**7. Trinity Integrity** — for each agreement/document entity:
- Does the binary referenced in frontmatter actually exist in `archive/`?
- Does the transcript exist?
- Does the transcript's `entity_page` field point back to this entity?

**8. Orphans:**
- Binaries in `archive/` not referenced by any entity page
- Transcripts without a matching entity page
- Entities with `binary:` set but file missing

**9. Frontmatter Validity:**
- Every entity page has `type: entity`, `category`, `key`
- Every transcript has `type: transcript`, `key`, `source_binary`
- Entity `key` matches filename (without `.md`)

**10. Schema Drift:**
- Are all categories used in `entities/` declared in schema (`{wiki}/schema.md` preferred, CLAUDE.md legacy)?
- Are all types in slugs declared in schema `## Document Types`?
- Is schema split between `{wiki}/schema.md` AND CLAUDE.md sections (duplication)? → propose collapsing to schema.md only
- Does CLAUDE.md still carry full schema instead of a 1-line pointer? → propose migration
- If drift found — propose updating schema

**11. CLAUDE.md Drift** — CLAUDE.md is resident context; wiki is lazy. Detect migration candidates:
- CLAUDE.md > ~150 lines total → flag for review (each line is paid on every session)
- Individual lines > 400 chars describing component names, file paths, API specifics, or implementation behavior (e.g. "URL state syncs via `useUrlState()` hook at `hooks/useUrlState.ts`, converted pages: ...") → propose moving to the targeted wiki page (`[[ui-components]]`, `[[navigation]]`, etc.)
- For each `[[wikilink]]` in CLAUDE.md: verify the target page actually covers the cross-linked topic (otherwise CLAUDE.md carries content that's "linked but duplicated")
- "X removed" / "Y migrated" history notes in CLAUDE.md → belong in git log / wiki log.md, not resident context
- Conversely: wiki pages that contradict CLAUDE.md convention lines (e.g. navigation structure described two different ways) → update the stale side

**12. Wiki Page Size** — pages grow. Flag for [[#Operation-Split]]:
- Pages > 200 lines → candidates for split
- Pages covering 2+ visibly independent topics (H2 boundaries) → candidates even if < 200 lines

**13. Suggest New Questions** — Think proactively:
- What sources are missing that would strengthen the wiki?
- What topics need deeper exploration?
- Are there areas where the wiki says "TODO" or is thin on detail?
- What questions would a new team member ask that the wiki can't answer yet?

### Lint Report Format

```markdown
## Wiki Lint Report — [date]

### Stale Content
- [ ] [[page]] — section X references function Y which was renamed/removed

### Contradictions
- [ ] [[page-a]] says X, but [[page-b]] says Y

### Orphans
- [ ] file.md exists but not in index.md

### Missing Cross-References
- [ ] [[page-a]] should link to [[page-b]] (both discuss topic Z)

### Coverage Gaps
- [ ] Feature X has no wiki page
- [ ] Recent spec Y not ingested

### Summary
N issues found: X stale, Y contradictions, Z orphans, W gaps
```

After presenting the report, offer to fix all issues.

---

## Operation: Split

Break an over-grown wiki page into focused successors. Lint flags candidates (check #12); this operation executes the split cleanly.

### When to Split

- Page > ~200 lines (soft limit from Page Conventions)
- Page covers 2+ independent topics with visible H2 boundaries
- Lint item #12 fires

### Process

1. **Identify boundaries** — usually H2 sections. Propose N successor pages with titles and which sections land in each.
2. **Confirm with user** — present the split plan before touching files. User may merge sections, rename successors, or abort.
3. **Create successor pages** using the Page Template. Each inherits relevant `## Sources` from the original.
4. **Rewrite or delete original** — either keep it as a hub page (just a list of `[[successor]]` links if the umbrella topic still makes sense) or delete it outright.
5. **Rewire cross-references** — scan wiki for `[[old-page]]` and replace with the correct `[[new-page]]`. Grep the whole `{wiki}/` tree.
6. **Update `## See also`** on every page that referenced the original — point to the specific successor, not the generic replacement.
7. **Update `{wiki}/index.md`** — remove old entry, add N new entries with one-line descriptions.
8. **Append to `log.md`:**
```markdown
## [YYYY-MM-DD] split | old-page → new-a + new-b
- Reason: lint check #12 flagged 247 lines / 3 independent topics
- Successors: [[new-a]] (topic X), [[new-b]] (topic Y)
- Cross-refs updated: N pages
```

### Anti-Patterns

- **Don't split for size alone.** A focused 210-line page is fine. Size is a heuristic, not a rule.
- **Don't leave a bait-and-switch hub** (original title, but just a list of links) unless the umbrella topic has standalone value. Prefer deletion + cross-ref rewire.
- **Don't forget the log.md entry.** Future lint runs need to know the split happened, so they don't re-flag stubs.

---

## Operation: Init (bootstrap-aware)

Set up wiki, OR detect existing structure and propose migration.

### When to Init

- User asks to create/initialize a wiki
- Wiki discovery (Step 0) found no existing wiki
- User asks to "bootstrap" / "migrate" / "reorganize" project around wiki

### Discovery

1. **Find CLAUDE.md** (walk up dirs from cwd)
2. **Determine wiki state:**
   - `absent` — no `docs/wiki/` exists
   - `v1` — `docs/wiki/` exists but no `concepts/entities/transcripts/` substructure
   - `current` — full three-layer structure
3. **Scan project for migration candidates** (only if state ≠ current):
   - Raw binaries (PDF, DOCX, images, spreadsheets) in non-hidden, non-wiki dirs
   - Analytical MDs (README, analysis, notes) outside `docs/wiki/`
   - Existing concept-like MDs that should move to `concepts/`
   - Duplicate MDs (raw README that overlap wiki content)

### Plan (interactive)

Before any move, present:
- Concept candidates → list of MDs to move into `concepts/`
- Entity candidates → suggest stubs from mentions in existing wiki
- Binary candidates → list of binaries to move to `archive/` + create transcript
- Dupes → list of MDs to delete (with justification)
- Stale folders → list to remove after content migrated

Ask per group: "Migrate these? [y/N/per-file]". User retains veto on each.

### Execute

After consent:

1. Create missing dirs: `concepts/`, `entities/{categories}/`, `transcripts/`, `archive/{paths}/`
2. Add `archive/` to `.gitignore`
3. Move concept MDs → `concepts/`
4. For each binary:
   - Move to `archive/{path}/{naming-convention}.{ext}`
   - Generate transcript → `transcripts/{slug}.md`
   - Create entity page stub → `entities/{category}/{slug}.md`
5. Create entity stubs for entities mentioned in concepts (lazy: only key/recurring ones)
6. Create `{wiki}/schema.md` with layers, operations summary, `Entity Categories`, `Document Types`, `File Naming`. Add a single `## Wiki` pointer in CLAUDE.md: _"Wiki schema and operations → `docs/wiki/schema.md`. Skill: `wiki`."_ (for v1/v2 migrations — move existing CLAUDE.md sections into `schema.md` and replace them with the pointer)
7. Delete approved duplicates
8. Update `index.md` (three sections: Concepts | Entities | Transcripts)
9. Append `log.md` with migration record

---

## Operation: Cleanup

Post-migration / periodic housekeeping AND structural reorganization of existing content.

### When to Cleanup

- After init/bootstrap completes
- User says "wiki cleanup", "почисть wiki/вікі"
- Periodically (every ~10 sessions or after major changes)
- **When migrating content between CLAUDE.md and wiki** (e.g. extracting implementation details, consolidating duplicates). This is the canonical home for "wiki refactor" — not `ingest-source` (no new material entering) and not `lint` (not read-only report). Use the log tag `cleanup` with a descriptive subject.

### Process

1. Remove empty directories under `docs/wiki/` and `archive/`
2. Verify `archive/` is in `.gitignore`; add if missing
3. Verify schema exists at `{wiki}/schema.md` (preferred). If schema lives in CLAUDE.md sections instead, propose migration: move to `{wiki}/schema.md`, leave a 1-line pointer in CLAUDE.md. If both exist — propose collapsing into schema.md only.
4. Find unused entity stubs (entity pages with no cross-refs from anywhere) — propose deletion
5. Find concept pages not in `index.md` and vice versa — propose fixes
6. Append cleanup actions to `log.md`

---

## Proactive Wiki Maintenance

Beyond explicit commands, maintain wiki awareness during normal work. Tie triggers to git activity — it's concrete, whereas "after a feature" is vague.

**Commit scope `feat(`** → suggest `ingest-source`. New capability = new synthesis to capture.

**Commit scope `refactor(`** → suggest `lint` on concepts mentioning the touched paths. Refactors invalidate wiki facts; lint surfaces the stale ones. No full lint — just the relevant pages.

**Commit scope `docs(`** touching `docs/superpowers/specs/` (or equivalent raw-sources dir) → `ingest-source` is mandatory. Specs are the primary wiki feedstock.

**Commit touches CLAUDE.md** → check whether added/edited lines are convention (keep) vs implementation detail (propose `cleanup` to migrate into wiki). This is the counterpart to Lint check #11 but catches drift at commit time, before it accumulates.

**Binary file appears in `tmp/`** → suggest `ingest-binary` (already covered by description triggers).

**After discovering a gotcha during coding:** If a non-obvious behavior bit you, append to the gotchas page. Don't wait for the next feature.

**After reading wiki during work:** If you notice stale info while consulting the wiki, fix it immediately — don't leave known-stale content.

**Before committing:** Check whether wiki schema (`{wiki}/schema.md`) or concept pages need updates.

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Creating a second wiki when one exists | ALWAYS run discovery (Step 0) first. Check CLAUDE.md, search for existing index.md. |
| Adding implementation details to CLAUDE.md | CLAUDE.md = rules and conventions only. Details → wiki pages. |
| Duplicating code in wiki | Wiki describes WHAT and WHY. Code shows HOW. |
| Forgetting to update index.md | ALWAYS update index after creating/renaming pages |
| Forgetting to append to log.md | ALWAYS append after any ingest or significant update |
| Creating pages for ephemeral info | Wiki = persistent knowledge. Tasks/debugging = conversation only. |
| Giant monolithic pages | Split at ~200 lines. One focused topic per page. |
| Missing cross-references | Every page should have `## See also`. Check related pages too. |
| Ingesting without reading existing pages first | ALWAYS read index + relevant pages before writing. Integrate, don't duplicate. |
| Leaving stale info when updating | When adding new info, also check and fix outdated facts on the same page. |
| Using hardcoded wiki paths | ALWAYS discover wiki location via CLAUDE.md first. |
| Writing wiki schema into CLAUDE.md on init | Schema belongs in `{wiki}/schema.md`. CLAUDE.md only gets a 1-line pointer. |
| Maintaining duplicate schema in both locations | Collapse to `{wiki}/schema.md` only. Leave 1-line pointer in CLAUDE.md. |
