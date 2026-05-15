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

**Step 7 — Update telemetry.** Mutate `{wiki}/.usage.json` per the rules in `## Telemetry Sidecar`:
- For each existing page **read** during this ingest → `bump_view(path)`.
- For each page **modified** (Edit/Write) → `bump_patch(path)`. New pages are recorded with `created_at = now` on their first patch.
- For each new `[[wikilink]]` you added pointing to another page → `bump_use(target_path)`.

Do this once at the end of the operation, not after every individual file touch. Telemetry must never block the ingest — see Tolerance rules.

**Step 8 — Protect auto-suggest for critically-rare pages.** For each **new** page created in this ingest (not for updates), check if it looks intentionally rare-read. Trigger if either:

- Frontmatter contains a tag matching `security`, `incident`, `migration`, `compliance`, or `recovery`, OR
- Filename contains any of those prefixes (e.g. `security-token-rotation.md`, `incident-2026-02-15.md`, `migration-0026-per-serving.md`, `compliance-gdpr-export.md`, `recovery-db-restore.md`).

Ask the user:

```
Сторінка [[{slug}]] виглядає як критично-рідкісна. Запропонувати захист? [y/n]
```

On `y`: read `.usage.json`, set `protected: true` on this page's record (creating the record with defaults if absent), write atomically. Pinning does not bump `patch_count` — it's a metadata mutation. On `n`: leave `protected: false`. Page protection then kicks in during future Lint runs (see `## Operation: Lint > Page protection during Lint`).

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
| Semantic labels (a commit/migration/version identifier paired with what it meant) | Derivable counts / inventories — test counts, migration counts, route counts, endpoint counts (use `ls`/`grep`/`wc`) |

### IMPORTANT: Wiki vs. Agent Instruction Files

When updating documentation after implementing a feature:
- **Agent instruction files** (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`) get ONLY: new conventions, rules, data model summary changes (1-2 lines max)
- **Wiki** gets: implementation details, how things work, component behavior, API specifics
- If in doubt whether something is a "convention" or "implementation detail" — it's wiki
- Reference wiki from instruction files when needed: "Details → see [[page-name]] in wiki"

### After completion

If this operation was triggered by a TodoWrite-completion or is part of a pre-commit moment, emit a РЕФЛЕКСІЯ block per `references/reflection.md`. Ingest-Source almost always involves Edit/Write on at least one wiki page, so the anti-noise rule rarely applies — only skip reflection if you somehow read sources but ended up making no edits at all.

---
