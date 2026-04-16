---
name: wiki
description: >
  Use when managing a project's LLM Wiki knowledge base (Karpathy pattern).
  TRIGGER on: "ingest", "додай до wiki", "додай до вікі", "wiki lint", "вікі лінт",
  "wiki query", "оновити wiki", "оновити вікі", "перевір wiki", "перевір вікі",
  "що каже wiki про...", "що каже вікі про...", "знайди у вікі",
  or any request to update/search/maintain project documentation.
  "вікі" = "wiki" — users may use either form interchangeably.
  Also use PROACTIVELY after completing significant features, specs, or architectural changes —
  if new patterns, gotchas, or decisions emerged during implementation, they belong in the wiki.
  Three operations: ingest (process source → update wiki pages + index + log),
  query (read index → find pages → synthesize answer), lint (health-check for staleness/contradictions/orphans).
---

# LLM Wiki (Karpathy Pattern)

A persistent, compounding knowledge base maintained by Claude. Instead of re-discovering knowledge each session, the wiki accumulates synthesized understanding across conversations.

This skill is **project-agnostic** — it discovers the wiki location automatically.

## Step 0: Discover Wiki Location

**Before any operation**, locate the wiki. Follow this sequence:

1. **Find CLAUDE.md** — look in the current working directory, then walk up parent directories until found
2. **Read CLAUDE.md's Wiki section** — look for a `## Wiki` section that declares wiki paths (e.g., "Wiki (`docs/wiki/`)")
3. **Verify wiki exists** — check that the discovered directory contains `index.md`
4. **If no Wiki section in CLAUDE.md** — search for `docs/wiki/index.md` relative to CLAUDE.md location
5. **If wiki not found at all** — tell the user: "No wiki found. Would you like me to initialize one?" Then create `docs/wiki/` with `index.md` and `log.md` next to CLAUDE.md, and add a Wiki section to CLAUDE.md.

All paths below use `{wiki}` as placeholder for the discovered wiki directory (e.g., `docs/wiki/`). Replace mentally with the actual path.

**CRITICAL: Never create a second wiki.** If you find an existing wiki, use it. If CLAUDE.md references a wiki path, trust it. Only create a new wiki when none exists anywhere in the project.

## Three Layers

```
Raw Sources (immutable)     →  declared in CLAUDE.md Wiki section
Wiki (LLM-maintained)       →  {wiki}/
Schema (conventions)        →  CLAUDE.md "Wiki" section
```

- **Raw Sources**: design specs, articles, external docs. Claude reads but NEVER modifies.
- **Wiki**: structured markdown pages with `[[wikilinks]]`. Claude writes and maintains. Human reads and curates.
- **Schema**: CLAUDE.md defines conventions. This skill defines operations.

## Navigation Files

| File | Purpose | Format |
|------|---------|--------|
| `{wiki}/index.md` | Catalog of all pages, organized by category | `- [[page-name]] — one-line description` |
| `{wiki}/log.md` | Chronological record of all operations | `## [YYYY-MM-DD] operation \| Subject` |

**Read `index.md` FIRST** for any wiki operation — it's your map.

---

## Operation: Ingest

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
```

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

**7. Suggest New Questions** — Think proactively:
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

## Operation: Init

Set up a wiki in a project that doesn't have one yet.

### When to Init

- User asks to create/initialize a wiki
- Wiki discovery (Step 0) found no existing wiki

### Process

1. Find CLAUDE.md location (project root)
2. Create `docs/wiki/` directory relative to CLAUDE.md
3. Create `docs/wiki/index.md` with empty category structure
4. Create `docs/wiki/log.md` with initial entry
5. Add Wiki section to CLAUDE.md (schema layer) with:
   - Layer descriptions (raw sources, wiki, schema)
   - Navigation file locations
   - Operation summaries (ingest/query/lint)
   - Page conventions
6. Ask the user what to ingest first

---

## Proactive Wiki Maintenance

Beyond explicit commands, maintain wiki awareness during normal work:

**After implementing a feature:** "I notice this introduced [new pattern/gotcha/flow]. Should I ingest this into the wiki?"

**After discovering a gotcha:** If you hit a non-obvious behavior while coding, suggest adding it to the gotchas page.

**After reading wiki during work:** If you notice stale info while consulting the wiki for a task, fix it immediately — don't leave known-stale content.

**Before committing:** Check if CLAUDE.md wiki schema or wiki pages need updates (per project conventions).

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
