## Operation: Lint

Periodic health-check of the wiki.

### When to Lint

- User explicitly asks ("wiki lint", "перевір wiki")
- Periodically (every ~10 sessions or after major changes)
- When something feels off or inconsistent during other operations

Discovery must already have found a git root. If git metadata (`.git/`
directory or `.git` file) is missing, do not run Lint. Step 0 decides what to
show: if wiki artifacts exist (orphan wiki), the orphan-wiki repair gate from
`references/discovery-versioning.md` will offer `git init` to preserve the
existing wiki; otherwise tell the user to initialize git first or run `wiki
init` and confirm the git-init gate.

### Checklist

Run through each check and report findings:

**1. Staleness (Karpathy content-verification)** — **Don't infer staleness from timestamps, view counts, or any other algorithmic heuristic.** Whether a page is stale is a judgment that lives inside the page's content vs. the world it claims to describe. The only way to know is to read the page in full and verify its claims. Telemetry is for **prioritization** (which page to read first), never for **flagging** (auto-marking pages as stale).

**Process:**

1. **Determine the verification subset — no menu.** Pick the subset by this rule, in priority order:
   - **If the user named a path-based scope** in the trigger (e.g. "лінт `concepts/architecture/`", "лінт all `entities/contracts/`") — verify exactly that scope.
   - **If the user described a topic in natural language** ("перевір склад", "все про курси", "сторінки про закупки") — resolve via topic resolution flow (see below) BEFORE running. Don't guess silently; confirm the resolved list with the user first.
   - **If the user said "швидко" / "fast" / "top-10" / "топ-10"** — verify only top-10 most-edited active + unprotected pages. Sort `report()` by `patch_count desc, last_patched_at asc`, filter `state == "active"` and `protected == false`, take the first 10.
   - **Otherwise — default: full lint.** Verify ALL active + unprotected pages, in priority order (sort by `patch_count desc, last_patched_at asc`; protected pages skipped). This matches the convention from other linters (ESLint, mypy, ruff): "lint" = full check by default.

   State the chosen subset at the top of the report (e.g. "Verified subset: full — N active pages" or "Verified subset: top-10 most-edited active" or "Verified subset: `concepts/architecture/` — N pages").

   **Heads-up before starting full lint — only for larger wikis.** If `report()` finds fewer than 20 active + unprotected pages, skip the heads-up entirely and start verification immediately; on small wikis the full pass is short enough that asking about scope is pure friction. Otherwise print **exactly this block, nothing else**, then end the turn:

   ```
   🔍 Готую повний лінт: N активних сторінок.
      Pin-protected (skipped): K сторінок.

   Повний режим читає кожну сторінку і верифікує claims проти диска —
   це найповніший і найдовший прохід.

   Скажи `далі` для продовження. Або обмеж скоуп:
     • `швидко`                        — top-10 most-edited
     • тема словами                    — напр. «перевір склад», «все про курси»
     • шлях до теки                    — напр. `concepts/architecture/`
   ```

   Substitute real `N` and `K` from `report()`. Skip this block when (a) the user already named a path-based scope, described a topic, or said "швидко" (the choice was already explicit), or (b) `N < 20` — small wikis run full lint without a scope dialog.

   **Forbidden additions to the heads-up.** Do NOT print, alongside or after the block:

   - **Time estimates** — no "≈45-60 хв", "це довго", "великий контекст". The user can decide; rough estimates are noisy and frequently wrong.
   - **Recommendations against the user's choice** — no "рекомендую почати з пасивних перевірок", "80% цінності за 20% часу", "краще оберіть швидко". The user invoked the default; respect it.
   - **Invented hybrid modes** — no "пасивні перевірки + content-verification на 5-7 'гарячих' сторінок", no curated page lists ("data-model, purchase-flow, template-course-flow"). The only legitimate scopes are: full (default), "швидко" (top-10), user-named scope. Period.
   - **Closing chooser** — no "Що обираєш?", no "[1]/[2]/[3]". The block IS the prompt; the user's next message is the answer.

   **What the user's next message means:**

   - **`далі` / `продовжуй` / `ок` / `так`** → start verification on the announced full subset.
   - **`швидко`** → cancel this run, restart with top-10 most-edited.
   - **A path-based scope** (e.g. `concepts/architecture/`, `вікі лінт entities/contracts/`) → cancel this run, restart with that scope.
   - **A natural-language topic** (e.g. "перевір склад", "все про закупки") → cancel this run, enter Topic Resolution Flow (see below).
   - **`стоп` / `відміна` / `не треба`** → cancel and acknowledge.
   - Anything else / unrelated question → treat as continuation of the announced full subset, but pause if you're unsure. When in doubt — ask, don't autopilot.

   **Never present a multi-option subset menu** like "[a] top-edited / [b] oldest / [c] by category / [d] specific list". The user names a scope, says "швидко", describes a topic, or the default full lint applies — there is no in-Lint chooser. Page protection always applies regardless of subset (skip `protected == true` unless the user first runs `wiki unprotect <path>`).

### Topic Resolution Flow

When the user describes a topic in natural language ("перевір склад", "все про курси", "сторінки про закупки"), don't guess silently. Resolve to a concrete page list and confirm with the user before running content-verification.

**Process:**

1. **Read `index.md`** + the first descriptive paragraph (or `description:` frontmatter field, if present) of each candidate page. Don't read full pages yet — that's wasteful pre-confirmation.

2. **Match the topic to candidate pages.** Use semantic judgement: title contains the keyword, description mentions the theme, page covers a related sub-topic. Be liberal — it's better to over-include and let the user trim than to miss a relevant page.

3. **If 0 candidates match** → fall back to clarification (case below). Don't run an empty lint.

4. **If 1+ candidates match** → present the resolved list and ask for confirmation:

   ```
   🎯 Тема: «<user's words>»
      Знайшов N сторінок:
        • [[page-a]] — <one-line description from index>
        • [[page-b]] — <one-line description from index>
        • [[page-c]] — <one-line description from index>

   Скажи `так` для запуску, або корегуй: «прибери [[page-b]]»,
   «додай [[page-d]]», «лише [[page-a]] [[page-c]]».
   ```

5. **User responds:**
   - `так` / `ок` / `запускай` → run content-verification on the resolved list. State the subset at the top of the report (e.g. "Verified subset: тема «склад» — 3 pages").
   - **Edits the list** ("прибери X", "додай Y", "лише A і C") → apply the edits, show the updated list, ask for confirmation again.
   - **Switches scope** (`далі` / `швидко` / path / different topic) → cancel resolution, dispatch by usual rules.
   - `стоп` → cancel.

**Ambiguous topic — clarification required.** When the topic is too broad ("перевір вікі") or too narrow ("перевір те що змінилось" without a clear referent), don't autopilot. Print:

```
🤔 Не зрозумів обмеження — тема надто широка / нема явного референса.

Активні теки у вікі: <list of top-level dirs from index — concepts/, entities/X/, entities/Y/...>
Назви шлях, конкретну тему («перевір склад»), або скажи `далі` для повного лінта.
```

Then end the turn. Don't pre-pick a default — the user explicitly described something they wanted, falling back silently to full lint hides the mismatch.

Page protection always applies during resolution: protected pages are excluded from the candidate list and from any final resolved subset.

2. **For each selected page, read in full and verify claims:**
   - **Sources existing** — every path under `## Sources` resolves on disk
   - **Flows match code** — described flows correspond to current implementation (call out `git log` or grep checks if needed)
   - **Entity relationships accurate** — claimed parent/child / has-many / belongs-to relations match the data model
   - **Internal `[[wikilinks]]` resolve** — every wikilink in the body points to a page that exists
   - **Stated counts AND inventories match reality** — if the page asserts "N tests / N migrations / N routes" (count) OR contains a one-row-per-file table/list (inventory of specs, migrations, routes), run `ls`/`grep`/`wc` and compare. **Default action: DROP, not UPDATE.** Derivable counts and inventories drift faster than any maintenance cadence can catch; deleting them pushes the read to `ls`/`grep` which is always current. Keep cross-cutting semantic synthesis (clusters, conceptual groupings, criteria for adding new entries) — but a row-per-file mirror of the disk is the inventory anti-pattern, drop the table and replace with a pointer.

   **2a. ALWAYS also content-verify resident agent instruction files** — regardless of subset (full / швидко / scope / topic), every discovered `CLAUDE.md`, `AGENTS.md`, and `GEMINI.md` that can affect this project is read and verified per check #11 (Karpathy content-classification: convention/detail/history/dead/verbose). Findings flow into the same AUTO/DECIDE/INFO buckets and share the report's sequential numbering. Instruction files are not wiki pages (no `.usage.json` record), so prioritization signals don't apply — they are verified every lint run as first-class targets. If you complete a lint run without reading the discovered instruction files, the lint is **incomplete** — that's a hard rule, not a guideline.

3. **Classify findings into three tiers (AUTO / DECIDE / INFO), then act accordingly.** This is the autonomy contract — Lint is no longer a read-only operation. See `### Two-Tier Autonomy` subsection below for full rules. Short version:
   - **AUTO findings** (no genuinely competing alternative — there's an obvious correct fix): apply automatically after creating a snapshot. Each fix is its own commit.
   - **DECIDE findings** (multiple actions genuinely compete — `видали` vs `глянь і онови` vs `merge` vs `розбити`): surface with the action menu. The user invokes by item number + verb (e.g. `5 merge`).
   - **INFO findings** (notes/context): listed for awareness; user can elevate to action by number + verb (e.g. `7 розбий`).

   **All items in the report — AUTO, DECIDE, INFO — receive a single sequential number from 1 to N across the whole report.** No A/D prefixes. The user references any item by its number; verb context disambiguates intent (`відкат N` only applies to AUTO; `N <verb>` applies to DECIDE or elevated INFO).

   **Forbidden DECIDE pattern: binary `глянь і онови` / `залиш як є`.** If the only alternative to applying the fix is to perpetuate an identified bug, that's not a competing alternative — that's a fake choice. Such findings belong in AUTO, not DECIDE. Use DECIDE only when alternatives are genuinely defensible from different angles.

4. **`.usage.json` is read here for prioritization only** — sort order (`patch_count desc, last_patched_at asc`) so most-likely-drifted pages are verified first, and protection filter (skip `protected == true`). The presence of low view_count or old last_viewed_at is **never** a reason to flag a page as stale on its own. A 0-view page may be a perfectly correct security recipe that just hasn't been needed yet (which is exactly why protection exists).

### Page protection during Lint

Some pages are **intentionally rare-read** — security recipes, incident postmortems, migration runbooks, compliance notes, recovery procedures. They earn their value precisely because they sit untouched until the rare moment they're needed. Algorithmic staleness checks (least-viewed, oldest-edited) would score these pages as "stale" forever, which is exactly wrong.

**Page protection rules:**

- A page with `protected: true` in `.usage.json` is **skipped** by every subset variant — full lint, "швидко" top-10, and any user-named scope. It is also **excluded** from any "candidates for content-verification" auto-list.
- The Lint report **must** include a separate `### Захищені` line listing these pages (so the user remembers they exist), but **never** flags them as `глянь і онови` or `видали`.
- To verify or modify a protected page, the user must first run `wiki unprotect <path>`. After unprotecting, the page becomes a normal Lint candidate; the user can re-protect afterwards with `wiki protect <path>`.
- Protect/unprotect is a sidecar mutation: read `.usage.json`, set/clear `protected`, write atomically (see Telemetry Tolerance rules). Protecting does not bump `patch_count` for the page itself.
- Protect auto-suggest fires during Ingest-Source / Ingest-Binary when a new page looks critically-rare (security / incident / migration / compliance / recovery). See those operations for the exact prompt.

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
- Are all categories used in `entities/` declared in schema (`{wiki}/schema.md` preferred, instruction-file schema legacy)?
- Are all types in slugs declared in schema `## Document Types`?
- Is schema split between `{wiki}/schema.md` AND instruction-file sections (duplication)? → DECIDE finding: collapse to schema.md only
- Does an agent instruction file still carry full schema instead of a 1-line pointer? → DECIDE finding: migrate to a 1-line pointer
- If drift found — propose updating schema

**11. Agent Instruction File Content Verification (Karpathy-style)** — `CLAUDE.md`, `AGENTS.md`, and `GEMINI.md` are resident or high-priority context paid across sessions. Wiki is lazy (read on demand). The skill **reads discovered instruction files in full** and judges each line/section by content type — **no algorithmic line-count threshold**. Length is a symptom, content-type ratio is the real question.

**Per-line classification** — every line falls into one of these:

a. **CONVENTION/RULE (KEEP)** — what the project does/doesn't do, naming patterns, workflow rules, architectural principles, data model summary at a level useful for every session. These earn resident context.

b. **IMPLEMENTATION DETAIL (MIGRATE)** — how something works internally, component props, function signatures, exact file paths, API endpoints, sub-feature behaviors. These are looked up when needed; they don't belong in resident context. Identify the target wiki page for each migrated line.

c. **HISTORY NOTE (MOVE TO LOG)** — "X removed in <date>", "Y migrated to Z", "deprecated since vN", "previously called A, now B". Belong in `git log` or `wiki/log.md`, not resident context.

d. **DEAD REFERENCE (DELETE)** — wikilink to a page that doesn't exist in the wiki tree, file path to a deleted file, mention of a removed feature/library/table. Verifiable via `ls`/`grep`.

e. **VERBOSE PHRASING (CONDENSE)** — sentence that's 400+ chars when 80 would do, repeated qualifications, redundant explanations across multiple lines. Same rule lives shorter.

**Cross-checks:**

- For each `[[wikilink]]` in an instruction file: target page exists AND covers the cross-linked topic (otherwise the instruction file carries duplicated content).
- For each convention line: doesn't contradict the wiki page that elaborates it.

**Bias toward shrinking.** When a line could plausibly live in either an instruction file or wiki, default to wiki. Resident context is a precious budget — every byte is paid forever. The default question is «can this be shorter? can this move to a lazy page?», not «is this important enough to delete?».

**Tier mapping** (per the standard AUTO/DECIDE/INFO contract):

- **AUTO**: dead wikilinks (point to non-existent pages — verify via wiki tree), dead file path references (verify via `ls`), confirmed-stale history notes (`grep` confirms the migrated/removed thing is gone), drift-prone counts inside instruction files ("N tests").
- **DECIDE**: convention-vs-implementation-detail calls (line is genuinely ambiguous), section-level migration proposals (move whole H2 to wiki), condensation rewrites (3 paragraphs → 1 sentence — preserve meaning vs. acceptable loss).
- **INFO**: content-type breakdown (e.g. «CLAUDE.md: 42 рядки конвенцій, 18 implementation details, 5 history notes, 3 dead refs — 68 рядків загалом»). User sees ratio at a glance.

The breakdown is the actionable lever — high "implementation details" count means many DECIDE/AUTO findings are coming, not «CLAUDE.md is too big in absolute terms».

**12. Wiki Page Size** — pages grow. Flag for [[#Operation-Split]]:
- Pages > 200 lines → candidates for split
- Pages covering 2+ visibly independent topics (H2 boundaries) → candidates even if < 200 lines

**13. Suggest New Questions** — Think proactively:
- What sources are missing that would strengthen the wiki?
- What topics need deeper exploration?
- Are there areas where the wiki says "TODO" or is thin on detail?
- What questions would a new team member ask that the wiki can't answer yet?

### Two-Tier Autonomy

Lint is **autonomous** for objective findings and **deferential** for judgment calls. The classification is per-finding, decided after content-verification produced raw evidence.

#### Tier AUTO — apply automatically (no per-finding confirmation)

A finding qualifies as AUTO **if all of these hold**:

- **Disk-grounded evidence** (or wiki-internal evidence): a literal `grep` / `ls` / `cat` / wiki-tree check confirmed the drift. Not "I think this is stale based on vibes".
- **Reversible**: the change can be cleanly reverted by `git revert <commit>`.
- **No genuinely competing alternative**: «not applying the fix» would mean perpetuating the identified bug, not a defensible-different choice. The test: ask «if I do nothing, is the wiki worse?» If yes, AUTO.

Concrete AUTO patterns:

- **Derivable count deletions** — page says "N tests / N migrations / N routes", `grep -c` returns a different number → delete the count, keep the surrounding semantic label.
- **Derivable inventory deletions** — page contains a TABLE or LIST that mirrors what `ls`/`grep` produces (e.g. spec-by-spec table with one-line label per file, migration list, route inventory). Maintenance is Sisyphean — every new file requires a wiki edit, drift is guaranteed. AUTO action: **drop the inventory**, replace with a pointer (e.g. `Повний список — \`ls apps/web/e2e/*.spec.ts\``). Keep ONLY synthesis content the disk can't show: cross-cutting clusters («auth*.spec.ts покривають auth-flow»), conceptual groupings («3 категорії: smoke, integration, regression»), criteria («коли додавати новий e2e»). Don't replace 17-row table with a 17-cluster description — most should disappear.
- **Source path corrections** — page references `apps/X/Y.ts`, file moved to `apps/X/Z.ts`, real path is unambiguous → rewrite the path.
- **Dead legacy mentions** — page describes table/function/file that `grep` confirms doesn't exist anywhere in the codebase → delete the mention/section.
- **Broken `[[wikilinks]]`** — link points to a page that doesn't exist in the wiki tree → remove the link, keep surrounding text.
- **Dead `## Sources` lines** — `## Sources` lists a file that doesn't exist on disk → delete the line.
- **Mass renames driven by skill's own refactor** — when the skill's API or convention changed (e.g. `pinned` → `protected`, `wiki pin` → `wiki protect`) and a wiki page documents the old form, rewrite throughout. Multi-edit but mechanical and unambiguous.
- **Drift-prone suffix removal** — line ranges (`schema.ts:128-155`), test counts inside parentheses, anything that drifts faster than the maintenance cadence → drop the volatile fragment, keep the semantic anchor.
- **Skill-confidence content additions** — when adding stub content is mechanical from disk evidence (e.g. empty `## Sources` sections marked «hub-сторінка» on pages that genuinely have no external sources): apply with the skill's best content. **Do NOT auto-add per-file labels for new specs/migrations/routes** — that recreates the inventory anti-pattern. Revert is a one-word command if the user disagrees.

Anything else is DECIDE.

#### Tier DECIDE — surface for user judgment

DECIDE is reserved for **genuinely competing actions** — multiple defensible paths, each reasonable from a different angle. The presence of `залиш як є` as a sole alternative to `глянь і онови` is **not** a real competition — that goes in AUTO.

Real DECIDE cases:

- **Cross-page contradictions** — page A says X, page B says Y. Which is canonical? Multiple actions: `глянь A` (fix A by B) / `глянь B` (fix B by A) / `merge` / `розбити обидві`.
- **Split candidates** — page > 200 lines, where to cut depends on the reader's mental model. Actions: `розбити X` / `merge with Y` / `залиш` (judgment that current scope is coherent).
- **Page deletion vs update** — page describes deprecated feature; should it be deleted entirely or updated to reflect current state? Actions: `видали` / `глянь і онови` / `merge into Y`.
- **Anything with 3+ defensible actions, none dominant.**

#### Tier INFO — context, no action

- Pinned-list (so the user remembers protected pages exist).
- Schema version status.
- Largest page (with note "structurally coherent → keep" or "split candidate → DECIDE").
- Subset that was verified.

#### Finding numbering — sequential, single namespace

All items in the report — AUTO, DECIDE, INFO — share one sequential namespace **1...N** in render order:

```
🟢 Авто-застосовано:   1, 2, 3, 4    (AUTO bucket)
🟡 Потребує рішення:    5, 6           (DECIDE bucket)
🔵 Примітки:            7, 8           (INFO bucket — also numbered, also actionable)
```

No prefixes. No restart-per-block. One number per item, top to bottom. The verb the user types disambiguates:
- `відкат` only applies to AUTO. `відкат 2` = revert AUTO #2.
- `<N> <verb>` applies to DECIDE or INFO (elevation). `5 merge` / `7 розбий`.

Renumbering restarts each lint run.

#### Auto-apply mechanics

When AUTO findings exist:

1. **Snapshot commit** — `git commit -m "chore(wiki): snapshot before lint auto-fixes"` on the current state. Stage only `docs/wiki/` if working tree has unrelated changes.
2. **Per-fix commits** — each AUTO finding becomes its own commit:
   - Message: `auto-fix(wiki): #<N> <one-line description>` where `<N>` is the item number (e.g. `auto-fix(wiki): #2 drop derivable count from ui-components.md`)
   - Body: short rationale + grep evidence (e.g. `grep -c '^test\\b' ui-components.test.tsx → 14, page said 7`)
3. **Then** present the report (see `### Lint Report Format`).

The `#<N>` token in commit messages is the lookup key for `відкат N`. Separate commits per fix enable partial revert.

#### ВІДКАТ — natural-language revert

After the report is shown, the user can revert auto-fixes with one of:

- **`відкат`** (no number) → revert ALL auto-fix commits in reverse order. Skill runs `git revert <last-fix-commit> ... <first-fix-commit> --no-edit` and reports: «Відкатив усі N правок. Файли повернуто до стану перед лінтом.»
- **`відкат <N>`** (e.g. `відкат 2`) → revert only the matching auto-fix commit (located by `#<N>` token in its message). Skill runs `git revert <fix-commit> --no-edit` and reports: «Відкатив правку №<N> (опис). Інші правки лишились.»

If `<N>` doesn't correspond to an AUTO item (e.g. user types `відкат 5` when 5 is a DECIDE item), the skill answers: «5 — це DECIDE-finding, не auto-fix. `відкат` стосується тільки авто-застосованих. Для DECIDE використай `5 <verb>`.»

`відкат` does NOT touch the snapshot commit itself — that stays in history as a witness anchor (per the cleanup-flow rollback contract). It also does not undo DECIDE/elevated-INFO actions the user has already applied; those are independent commits with their own revert paths.

**Locating auto-fix commits** is via `git log --grep='auto-fix(wiki): #<N>'` from the most recent snapshot commit forward. Don't assume `HEAD~N` — DECIDE/INFO actions taken between report and revert may sit between HEAD and the auto-fixes.

#### DECIDE & INFO invocation

For DECIDE findings AND for elevating INFO findings, the user types the item number followed by an action verb:

- `5 merge` — apply `merge` to item 5
- `6 розбити` — apply `розбити` to item 6
- `5 глянь units-system` — when the action takes a target argument, include it after the verb
- `7 захисти` — elevate INFO item 7 (e.g. a large-page note) into a `захисти` action
- `5` alone (no verb) → if the item has only one dominant action, apply it; otherwise ask «який verb для №5?» (don't pick a default silently)
- `5 пропусти` / `5 залиш` → user explicitly skips this DECIDE/INFO; record in the report's tail as «№5 skipped по запиту користувача»

The action menu in each DECIDE finding **shows verbs only** (no per-finding numbered sub-menu). User invokes by `<item-number> <verb>`. Numbered sub-menus inside a finding are forbidden — they recreate exactly the ambiguity sequential numbering was designed to prevent.

INFO items don't carry an action menu by default (they're notes), but verbs that make sense for the item-type are accepted on elevation: large-page note → `розбити` / `захисти` / `merge`, schema-mismatch alert → `wiki init` (skill runs init).

#### Safety ceiling

If the AUTO bucket has > 10 fixes for a single lint run, **don't** auto-apply. Instead, demote all AUTO findings into DECIDE (still using sequential numbering) with a single batch prompt: «Знайдено N автоматичних правок (більше за поріг 10). Скажи `так` для застосування всіх, `3 7 9` для конкретних номерів, або `ні` для жодної.» Reason: high count usually signals either a wiki that drifted heavily (worth a human eye) or a misclassification (also worth a human eye). Convenience win of full automation isn't worth the risk above this threshold.

### Lint Report Format

The user-facing report is **Ukrainian**. The template:

```markdown
## Звіт лінта вікі — [дата]

Перевірено: <напр. «повний прохід — 27 активних сторінок» / «швидко — top-10 most-edited» / «`concepts/architecture/` — 3 сторінки» / «тема «склад» — 3 сторінки»>.

🟢 **Авто-застосовано** (знімок створено перед)

  1. `<page>.md` — <one-line action> (<коротке disk-grounded обґрунтування>)
  2. `<page>.md` — <one-line action> (<обґрунтування>)
  ...

  **↩️  Відкат:**
  • Скажи `відкат` — поверну всі (знімок готовий)
  • Скажи `відкат 2` — поверну лише №2

🟡 **Потребує твого рішення** (справжній multi-action)

  5. `<page>.md` ↔ `<page>.md` — <опис судження-кейсу з 3+ defensible actions>
     Дія: `5 глянь A` / `5 глянь B` / `5 merge` / `5 розбити обидві`

  6. `<page>.md` (276 рядків) — split candidate
     Дія: `6 розбити` / `6 merge with <page>` / `6 залиш`

🔵 **Примітки** (показується лише якщо є хоч один пункт нижче з тригером)

  7. Захищені сторінки (K, захищені від cleanup): `<list>` — `wiki unprotect <path>` щоб перевірити
  8. ⚠️ Версія схеми: вікі на `vX.Y`, скіл на `vZ.W` — `8 wiki init` для міграції
  9. Велика сторінка: `<page>.md` (N рядків, не ділимо — <структурно когерентна тощо>) — elevate: `9 розбий` / `9 захисти`
```

Numbering continues from the AUTO/DECIDE buckets. INFO items are noted by default but accept verbs on elevation (`<N> <verb>`); the verb that makes sense is shown inline with each note.

**Empty-buckets-omitted rule applies to every block:**

- **🟢** Авто-застосовано — show only when AUTO bucket has ≥ 1 finding.
- **🟡** Потребує рішення — show only when DECIDE bucket has ≥ 1 finding.
- **🔵** Примітки — each line has a trigger; the block appears only when **at least one** triggers:
  - **Захищені** — only when `K > 0`. Don't introduce the protect concept to users who haven't protected anything; «Захищених: 0» is noise.
  - **Версія схеми** — only on **schema major mismatch** between `{wiki}/schema.md`'s `wiki_version` and the skill frontmatter version. When schema majors match, this line is redundant fog.
  - **Велика сторінка** — only when at least one page is > 200 lines **and not already in 🟡** as a split candidate (otherwise it'd be duplicated). When the skill judged a large page coherent and decided not to split, this line is the FYI; when it judged it splittable, the 🟡 entry covers it.

If all three 🔵 lines lack triggers, omit the 🔵 block entirely.

When ALL buckets (🟢 / 🟡 / 🔵) are empty (clean wiki, nothing applied, nothing pending, nothing notable), print exactly one line: «✅ Лінт чистий. N сторінок перевірено, дрейфу не виявлено.»

**Never close Lint with a multi-option "куди далі?" menu** that mixes paradigms — e.g. `[1] verify subset / [2] another subset / [3] specific list / [4] split page X / [5] stop without verification`. Per-finding actions in 🟡 are offered with the unified action menu (see `references/cleanup-flow.md`). When the report is done, the operation is done — wait for user to act on findings or say `відкат`.

### After completion

Lint, `wiki status`, and cleanup-flow never emit a separate РЕФЛЕКСІЯ block. The lint report itself is the visible reasoning layer: it shows what was verified, what was auto-applied, what needs a decision, and how to revert. Adding reflection after that is recursive noise.

If AUTO fixes were applied, the report's 🟢 / ВІДКАТ sections carry the explanation and rollback handles. If the user later says `відкат` / `відкат N`, perform the revert and print a short confirmation («Відкатив N правок. Файли повернуто.»), but still do not append a РЕФЛЕКСІЯ block or cleanup-prompt.

---
