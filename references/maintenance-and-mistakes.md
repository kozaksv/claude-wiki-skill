## Proactive Wiki Maintenance

Beyond explicit commands, maintain wiki awareness during normal work. Tie triggers to git activity — it's concrete, whereas "after a feature" is vague.

**Commit scope `feat(`** → suggest `ingest-source`. New capability = new synthesis to capture.

**Commit scope `refactor(`** → suggest `lint` on concepts mentioning the touched paths. Refactors invalidate wiki facts; lint surfaces the stale ones. No full lint — just the relevant pages.

**Commit scope `docs(`** touching `docs/superpowers/specs/` (or equivalent raw-sources dir) → `ingest-source` is mandatory. Specs are the primary wiki feedstock.

**Commit touches an agent instruction file** → check whether added/edited lines are convention (keep) vs implementation detail (propose `cleanup` to migrate into wiki). This is the counterpart to Lint check #11 but catches drift at commit time, before it accumulates.

**Binary file appears in `tmp/`** → suggest `ingest-binary` (already covered by description triggers).

**After discovering a gotcha during coding:** If a non-obvious behavior bit you, append to the gotchas page. Don't wait for the next feature.

**After reading wiki during work:** If you notice stale info while consulting the wiki, fix it immediately — don't leave known-stale content.

**Before committing:** Check whether wiki schema (`{wiki}/schema.md`) or concept pages need updates.

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Running wiki in a non-git directory | Stop. Git is the foundation of the wiki; Init may ask to run `git init`, every other operation must refuse until git metadata (`.git/` directory or `.git` file) exists. |
| Creating a second wiki when one exists | ALWAYS run discovery (Step 0) first. Check agent instruction files, search for existing index.md. |
| Adding implementation details to agent instruction files | Instruction files = rules and conventions only. Details → wiki pages. |
| Duplicating code in wiki | Wiki describes WHAT and WHY. Code shows HOW. |
| Forgetting to update index.md | ALWAYS update index after creating/renaming pages |
| Forgetting to append to log.md | ALWAYS append after any ingest or significant update |
| Creating pages for ephemeral info | Wiki = persistent knowledge. Tasks/debugging = conversation only. |
| Giant monolithic pages | Split at ~200 lines. One focused topic per page. |
| Missing cross-references | Every page should have `## See also`. Check related pages too. |
| Ingesting without reading existing pages first | ALWAYS read index + relevant pages before writing. Integrate, don't duplicate. |
| Leaving stale info when updating | When adding new info, also check and fix outdated facts on the same page. |
| Using hardcoded wiki paths | ALWAYS discover wiki location via agent instruction files first. |
| Writing wiki schema into an instruction file on init | Schema belongs in `{wiki}/schema.md`. Instruction files only get a 1-line pointer. |
| Maintaining duplicate schema in both locations | Collapse to `{wiki}/schema.md` only. Leave 1-line pointer in the instruction file. |
| Auto-flagging staleness by timestamp | Use Karpathy content-verification — read pages and judge claims. Telemetry is for prioritization, not flagging. |
| Creating crystallization artifact silently | Skill ALWAYS proposes (y/n/пізніше). Never `Write` a wiki page, create a skill, or hand off to a skill-authoring helper without explicit user approval. |
| Proposing `scripts/*.sh` or `scripts/*.py` as crystallization | Removed in v4.1 — user-runnable scripts violate Division of Labor (mechanical work belongs to LLM, not user). Crystallize content as a wiki page the agent reads back, or run inline at the moment of need. |
| Treating `.usage.json` as user-visible | It's metadata, gitignored, per-clone. Don't mention specific counter values to user unless `wiki status` is invoked. |
| Migrating `wiki_version` silently | Migration is explicit plan-then-confirm for structural changes. Only field-level backfill in `.usage.json` is silent. |
| Skipping reflection because "small change" | Anti-noise rule applies only to read-only blocks. Any edit/write block produces reflection. |
| Closing Lint with a multi-option "куди далі?" menu | Lint = report + per-finding actions. Subset is decided BEFORE running (full by default, "швидко" for top-10, or user-named scope), never via a closing chooser. Mixing in `split` / `skip-verification` is also wrong — split is its own operation, content-verification is core not optional. |
| Padding the lint heads-up with time estimates, recommendations, or hybrid modes | Heads-up is exactly the block from spec, nothing else. No "≈45-60 хв", no "рекомендую почати з пасивних перевірок", no "80% цінності за 20% часу", no curated 5-7-page lists, no closing "Що обираєш?". The user invoked default lint; the block lists the three legitimate alternatives and ends the turn. |
| Asking the user to choose per AUTO finding | AUTO-tier findings (derivable counts, dead legacy, broken paths, dead wikilinks) are applied automatically with a snapshot — that's the autonomy contract. Per-finding confirmation belongs only to DECIDE-tier (contradictions, coverage gaps, splits, pins). If a finding is disk-grounded, atomic, and reversible, it goes to AUTO, not DECIDE. |
| Burying the revert hint in technical syntax | ВІДКАТ section is a top-level part of the report, not a footnote. Use natural Ukrainian commands `відкат` / `відкат N`, not `git revert HEAD~1`. The user must see, at a glance, that auto-changes are reversible with one word. |
| Writing user-facing report in English | The Lint Report Format is Ukrainian for everything the user reads — section headers ("Авто-застосовано", "Потребує твого рішення", "Примітки"), action verbs (`глянь і онови`, `залиш як є`), revert keyword (`відкат`). Only file paths, code identifiers, and proper names stay in their native form. |
| Showing 🔵 Примітки items that lack a trigger | Each line in 🔵 has a precondition: protected line only when K > 0, schema version only on mismatch, large-page only when > 200 lines AND not already in 🟡. Don't print «Захищених: 0» or «Версія схеми: v4.0 (поточна)» — those introduce vocabulary or ops-metadata the user doesn't need. If no line triggers, omit the 🔵 block entirely. |
| Putting binary `глянь і онови` / `залиш як є` in a DECIDE menu | Fake choice — `залиш як є` means perpetuate the bug, not a defensible alternative. If only one action is sensible, the finding belongs in AUTO with auto-apply. DECIDE is reserved for 3+ genuinely competing actions (e.g. `видали` vs `глянь і онови` vs `merge` vs `розбити`). |
| Numbering AUTO and DECIDE both starting at 1 | Use a SINGLE sequential namespace 1..N across the whole report (AUTO + DECIDE + INFO). No A/D prefixes. Verb context disambiguates intent: `відкат N` only applies to AUTO; `<N> <verb>` applies to DECIDE / INFO elevation. Renderer never restarts numbering between blocks. |
| Per-finding numbered sub-menu inside a DECIDE entry | DECIDE finding's action menu shows **verbs only**, no numbered sub-menu. User invokes by `<N> <verb>` where `<N>` is the item's report-wide number. Numbered sub-menus inside a finding recreate exactly the ambiguity sequential numbering was designed to prevent. |
| Leaving INFO items unnumbered while AUTO/DECIDE have numbers | All items in the report get a number, including 🔵 Примітки. Without numbering, the user can't reference an INFO item to elevate it (e.g. say `9 розбий` to split a noted large page). Bullet points (`•`) for INFO items violate the «every assertion has a number» rule. |
| Using a line-count threshold for instruction files (e.g. ">150 lines") | Algorithmic threshold contradicts Karpathy content-verification. Read instruction files in full, classify each line (convention/detail/history/dead/verbose), propose AUTO for verifiable dead refs, DECIDE for judgment calls, INFO for the content-type breakdown. Length is a symptom; the real question is content-type ratio. Default bias: when ambiguous, propose moving to wiki — resident instruction files are paid often, every byte counts. |
| Maintaining row-per-file inventory tables (specs, migrations, routes) in wiki | Disk maintains the inventory authoritatively (`ls`/`grep`); wiki copy is Sisyphean — every new file requires a wiki edit, drift is guaranteed. AUTO-drop the inventory; replace with a pointer command (`\`ls apps/web/e2e/*.spec.ts\``). Keep cross-cutting synthesis only — clusters («auth*.spec.ts — auth-flow group»), criteria («коли додавати новий e2e»), conceptual categories («3 типи: smoke / integration / regression»). Do NOT auto-add per-file labels for missing specs — that recreates the very pattern lint is removing. |
| Skipping instruction files during lint (treating "selected pages" as wiki-only) | Agent instruction files are project-wide convention, **always** verified, regardless of subset. Step 2a in Process explicitly wires this in. If a lint run finishes without producing an instruction-file classification breakdown (or auto-fixes for dead refs), the lint is incomplete — re-run or finish the missed verification. Instruction files don't sit in `.usage.json`, so don't expect prioritization signals to surface them; the spec adds them as always-on targets separate from the wiki subset. |
| Emitting a separate РЕФЛЕКСІЯ block after `вікі лінт` / `вікі статус` / cleanup-flow | Recursive: lint *is* the cleanup, the report *is* the visible reasoning. Adding reflection after a report that already shows what was verified, auto-applied, and pending is noise. The anti-noise rule (`references/reflection.md`) and the explicit Anti-recursion rule (`references/cleanup-flow.md`) together require: no reflection after lint, status, or cleanup-flow. The report ends the turn — period. |
