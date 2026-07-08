# Plan — Wiki Skill v4.4.0: wiki-only crystallization, no embedded cleanup-prompt

**Date:** 2026-07-07
**Spec:** `docs/superpowers/specs/2026-07-07-v44-simplification.md`
**Working root (all paths absolute under):** `/Users/a/Library/CloudStorage/Dropbox/AI/claude-wiki-skill-v44-simplification`
**Nature:** pure behavior-surface deletion. No wiki-schema change (`wiki_version` stays `"4.0"`, zero migrations). Skill version minor bump `4.3.0` → `4.4.0` (major stays `4`).

## Worktree discipline (applies to EVERY task)

- This is a **separate worktree**; your shell cwd may be a DIFFERENT worktree. NEVER bare `git`.
- All git: `git -C "/Users/a/Library/CloudStorage/Dropbox/AI/claude-wiki-skill-v44-simplification" …`.
- All Read/Edit/Write and file Bash: ABSOLUTE paths under the root above only.
- Tests / any run: `cd "/Users/a/Library/CloudStorage/Dropbox/AI/claude-wiki-skill-v44-simplification" && bash tests/skill-contracts.sh`.
- Before each commit: `git -C "…root…" status --short` MUST show exactly your intended files. Empty / wrong files → you wrote to the wrong worktree; fix the absolute path before committing.
- Commit only your task's files with explicit absolute paths: `git -C "…root…" add <abs paths> && git -C "…root…" commit …`.

## Token map (verified 2026-07-07 — where each removed token currently lives)

Contract-guarded (CI-load-bearing) tokens and their `references/` occurrences:
- `🧹` → `references/cleanup-flow.md:6`, `references/reflection.md:33`
- `writing-skills` → `references/crystallization.md:42,57,84,89`, `references/reflection.md:10,24`
- `set_skill_link` (crystallization only) → `references/crystallization.md:68`
- `Two entry points` → `references/cleanup-flow.md:27`

NON-guarded tokens (grep-sweep only, safe in later commits):
- `cleanup-prompt` → `references/self-improvement.md:21`, `references/cleanup-flow.md:3,19,50`, `references/operation-lint.md:388`, `references/maintenance-and-mistakes.md:60`, `references/operation-wiki-status.md:3,101`, `references/reflection.md:38,80`
- `set_skill_link` (non-crystallization) → `references/self-improvement.md:11` (must remove for sweep; NOT in `install.sh`/`uninstall.sh` — those STAY)
- `винеси в скіл` → `references/crystallization.md:24`
- `skill — delegated` / `skill — created` → `references/crystallization.md:42,89`, `references/reflection.md:10,24`

Guard phrase that MUST survive untouched: `never emit a separate РЕФЛЕКСІЯ block` at `references/operation-lint.md:386` (it has a contract guard; do not fold it into any sed of "РЕФЛЕКСІЯ block or cleanup-prompt").

Scenario-file tokens live under `tests/scenarios/` — NOT scanned by the new `references/`-scoped guards, so they are safe in a later commit (Task 4).

## Atomicity contract (spec §"Атомарність", lines 102-109)

The guard-383 flip and the new anti-return guards MUST land in the **same commit** as the token removal from `references/`. Reason: neither half is CI-green alone — a guard-flip without token removal fails (anti-return sees the token still present); token removal without the flip fails (old guard 383 requires `set_skill_link` present). No intermediate red state may exist. **Task 1 is therefore one atomic commit spanning the three primary reference files + `tests/skill-contracts.sh`.**

---

## Task 1 — ATOMIC: crystallization/reflection/cleanup-flow surgery + contract guards (SINGLE COMMIT)

This is the CI-load-bearing unit. All four file edits below land in ONE commit; the test suite must be green only after all of them are applied together.

### 1a. `references/crystallization.md`
- **Intro (line 3):** "one of two artifact types" → single artifact (wiki page). Rewrite the last sentence so the agent proposes a wiki page (`concepts/{name}.md`), never a skill.
- **Types table (lines 5-8):** delete the `| **skill** | … |` row (line 8). Keep the `wiki` row; **preserve verbatim** the judgment criterion "I re-derived this content from scratch this session — …".
- **`Why no scripts/ tier` callout (line 10):** compress to a short historical note pointing at the Migration Log in `references/discovery-versioning.md` (scripts tier removed v4.1).
- **`Memory is not a tier either` callout (line 12):** compress to 2-3 lines (boundary wiki vs auto-memory); drop the trailing "operates only on wiki and skill artifacts" → "operates only on wiki pages".
- **Explicit-user trigger (line 24):** narrow the trigger phrases to `"збережи у вікі"` / `"save as wiki page"` — REMOVE `"винеси в скіл"`. Keep the script-refusal sentence (Division of Labor) or fold it into the anti-noise rule.
- **Proposal format (lines 33-38):** `{wiki | skill}: {proposed-path}` → `wiki: {proposed-path}`.
- **Behavior on response (lines 42-44):** `y` branch records only `wiki — {path}`; drop `skill — delegated…` / `skill — created…` variants and the "(or, for skill, follow `### Skill creation / delegation`)" clause. `n`/`пізніше` unchanged.
- **`### Skill creation / delegation` section (lines 55-89):** DELETE entirely (delegation, direct-create fallback, canonical/export topology, installer-safety, the skill-proposal block). This removes `writing-skills` (57,84,89), `set_skill_link` (68), and `skill — created/delegated` (89).
- **Anti-noise rules (lines 91-100):** delete "Don't propose a skill when a wiki page covers it" (line 99). Rewrite "Don't crystallize user-runnable scripts" (line 100) to close with "the wiki page is the single crystallization artifact." Keep the other anti-noise bullets.

### 1b. `references/reflection.md`
- **Line 10:** `Автоматизував:` value list → `wiki — concepts/{name}.md` or `нічого` + reason; drop the two `skill —` variants and the `writing-skills` mention.
- **Line 24 (strict template):** same field-value simplification: `{wiki — concepts/{name}.md  /  нічого + причина}`.
- **Lines 32-36 (🧹 interrogation block inside the template) + line 38 (its explanation):** DELETE the interactive `🧹 … [y]/[n]` interrogation — this is the prompt-fatigue source (a y/n question after *every* reflection). Removes `🧹` (33) and `cleanup-prompt` (38). **Do NOT drop the automatic drift surface outright (review P1).** Replace it with a single **conditional passive drift notice**, emitted **only** when `trigger: pre-commit` AND passive drift signals exist (dead cross-refs / schema drift — the same cheap, no-LLM-read, no-`view_count`-bump signals `wiki status` already computes). Shape: one non-interactive line, no y/n menu, no `🧹` glyph, e.g. `⚠️ Вікі: {N} пасивних дрифт-сигналів — запусти` `` `wiki status` `` `для деталей`. It asks nothing and runs nothing — it only points the user at the manual entry point. For every other trigger (todo-completion / periodic / explicit / memory-flush), and whenever no drift signal is present, the block ends on `Автоматизував:` (plus the optional `Перевірив:` section) with no notice. Rationale: preserves a low-frequency, automatic path to *noticing* drift without the per-reflection interrogation the spec removes.
- **Line 80 (anti-noise bullet):** "(entered via `wiki status [a]/[b]/[c]` or via the РЕФЛЕКСІЯ cleanup-prompt)" → "(entered via `wiki status [a]/[b]/[c]`)".

### 1c. `references/cleanup-flow.md`
- **`### Cleanup-prompt embedded in reflection` section (lines 1-22):** DELETE the interactive `🧹 … [y]/[n]` embedded prompt — the code block, its safety contract, and the 3-ignore fade rule. Removes `🧹` (6) and `cleanup-prompt` (3,19). **Replace with a short `### Passive drift notice` subsection** (review P1 — keep an automatic surface): document the pre-commit-only, drift-gated, non-interactive one-liner defined in 1b — it fires at most once per pre-commit turn and only when passive drift exists, it is a *pointer* to `wiki status` (not a second entry point, not an auto-fix), and it uses `⚠️`, never `🧹`. **Keep the Anti-recursion rule**, re-scoped to the notice: the passive drift notice MUST NOT appear at the end of a Lint / `wiki status` / cleanup-flow run — those end on their own report. Word the whole subsection without the literal `cleanup-prompt` token (grep-sweep, Task 6).
- **File must now START with `### Cleanup-flow`** (spec edge-case, line 152-154 of spec). Verify the first non-blank line is `### Cleanup-flow`. (The new `### Passive drift notice` subsection, if placed first, would violate this — put it AFTER `### Cleanup-flow`, or fold it into the notice contract inside that subsection, so the file still starts with `### Cleanup-flow`.)
- **`#### Two entry points, same downstream flow` (lines 27-40):** collapse the heading + 2-row table + "Both lead to" prose into ONE sentence: single entry point is `wiki status`; the downstream is `subset selection → content-verification → Two-Tier classification (AUTO auto-applied, DECIDE/INFO via the action menu)`. Do NOT describe the downstream as a plain "action menu" for every finding — that is the stale pre-Two-Tier contract (review r2 P1 Concern 3). Removes `Two entry points` (27). (The pre-commit passive drift notice is NOT an entry point — it only tells the user to run `wiki status` — so cleanup-flow still has exactly one entry point and the `Two entry points` anti-return guard stays valid.)
- **`#### Action menu (per-page / per-finding)` section (lines 42-70) — reconcile with Two-Tier Autonomy (review r2 P1 Concern 3).** The current framing "After verification, the skill presents findings with a numbered list. For each finding, the user picks an action" (line 42) contradicts `## Operation: Lint`'s Two-Tier contract, under which **AUTO findings are auto-applied and committed BEFORE the report** and only **DECIDE / elevated-INFO** findings wait for a user verb. Make `## Operation: Lint`'s `### Two-Tier Autonomy` the single source of truth for *which* findings auto-apply vs. wait; re-scope cleanup-flow's action-menu subsection to document only the **verb vocabulary for DECIDE / INFO findings** (invoked as `<item-number> <verb>` per the Lint numbering contract), not a gate applied to every finding. Concretely: rewrite the intro sentence at line 42 to say the six verbs are the menu for DECIDE / elevated-INFO items (AUTO items are already applied — the user reverts them with `відкат N`, they are never offered a verb), and add a one-line cross-ref «повний контракт AUTO/DECIDE/INFO — `## Operation: Lint › Two-Tier Autonomy`». Keep the six verb rows, their telemetry-effect column, and the render example — only the "every finding waits" framing changes.
- **Intro para (lines 23-25):** drop "Both entry points (the embedded РЕФЛЕКСІЯ prompt and the `wiki status` command)" → single entry (`wiki status`).
- **`захисти` row (line 50):** "future cleanup-prompts skip this page" → "cleanup-flow skips this page". Removes `cleanup-prompt(s)` (50).
- Leave the **verb semantics** (the six action verbs and their telemetry-effect column), safety layers (double-confirm / snapshot / page-protection), telemetry-effects summary, and `wiki protect/unprotect` sections unchanged — only the per-finding *gate framing* (line 42) is re-scoped to DECIDE/INFO per the bullet above.

### 1d. `tests/skill-contracts.sh`
- **Flip guard at line 383:** the current `grep -q 'set_skill_link' references/crystallization.md || fail …` becomes an ANTI-return guard — presence of `set_skill_link` in `crystallization.md` must FAIL. Idiom to match the file's existing anti-return style:
  ```sh
  grep -q 'set_skill_link' "$ROOT/references/crystallization.md" &&
    fail "crystallization must not reference installer skill helpers (skill tier removed in 4.4)"
  ```
- **Add three anti-return guards** (same idiom, scoped exactly as written):
  - `grep -rq '🧹' "$ROOT/references/" && fail "cleanup-prompt emoji must not appear in references/ (removed in 4.4)"` — this bans the *interactive* `🧹` interrogation glyph only; the retained pre-commit passive drift notice (1b/1c) is deliberately `⚠️`, not `🧹`, so it does not (and must not) trip this guard.
  - `grep -rq 'writing-skills' "$ROOT/references/" && fail "skill-delegation must not appear in references/ (skill tier removed in 4.4)"`
  - `grep -q 'Two entry points' "$ROOT/references/cleanup-flow.md" && fail "cleanup-flow must have a single entry point (wiki status)"`
  - Confirm `grep`/`grep -r` return non-zero when absent so `&&` short-circuits to no-fail. Use `grep -rq` (or a subshell) consistent with how other multi-file guards in the file are written; verify by reading nearby guards first.
- Do NOT touch the `Автоматизував:` field guards (lines ~390-395), the strict-template guard (~386), the `never emit a separate РЕФЛЕКСІЯ block` guard, or any version-major guard.

### Tests / Verify (Task 1)
1. `cd "/Users/a/…v44-simplification" && bash tests/skill-contracts.sh` → GREEN. This is the TDD gate: the flipped + new guards prove the tokens are gone AND that regressions would re-fail.
2. Sanity greps on the atomic scope only:
   - `grep -rn '🧹\|writing-skills\|Two entry points' /Users/a/…/references/` → zero.
   - `grep -n 'set_skill_link' /Users/a/…/references/crystallization.md` → zero.
   - First non-blank line of `references/cleanup-flow.md` is `### Cleanup-flow`.
   - `references/reflection.md` strict-template block ends on `Автоматизував:` / `Перевірив:` (no `🧹`, no horizontal rule after it).
3. `git -C "…root…" status --short` shows exactly: `references/crystallization.md`, `references/reflection.md`, `references/cleanup-flow.md`, `tests/skill-contracts.sh`.

### Commit (Task 1)
`git -C "…root…" add` the four files above, then
`git -C "…root…" commit -m "feat(v44): wiki-only crystallization + single-entry cleanup-flow + contract guards"`.

---

## Task 2 — Cross-reference cleanup in remaining references + SKILL.md + version bump

Independent of Tasks 3-5; MUST run after Task 1 (Task 1 owns the primary files). Files here are disjoint from Task 1. Not CI-guarded individually — needed for the final grep-sweep.

Edits:
- **`references/self-improvement.md`**
  - Lines 9-12 (crystallization.md description): drop "or user-level skill, including Codex/Gemini direct-create fallback and installer-style topology safety (`set_skill_link` / `export_skill_link`)" → describe crystallization.md as "deciding whether repeated work should become a wiki page". Removes `set_skill_link` (11).
  - Lines 13 + 20-21 (cleanup-flow.md description + closing line): drop "embedded cleanup prompt," and the trailing "or cleanup-prompt" → "must not append a separate РЕФЛЕКСІЯ block." Removes `cleanup-prompt` (21).
- **`references/operation-wiki-status.md`**
  - Line 3: drop "This is the active counterpart to the embedded cleanup-prompt in the РЕФЛЕКСІЯ block: same downstream flow, different entry point." (single entry point now).
  - Line 101: "Do not emit a separate РЕФЛЕКСІЯ block or cleanup-prompt from …" → "Do not emit a separate РЕФЛЕКСІЯ block from …".
  - **`[a]/[b]/[c]` menu framing — relabel as mutating, not read-only (review r2 P1 Concern 2).** Now that `wiki status` is the sole cleanup entry point, its `[a]/[b]/[c]` choices delegate to `## Operation: Lint`, which under the Two-Tier Autonomy contract **auto-applies and commits AUTO-tier fixes without per-finding confirmation**. The current menu header at line 70 (`🔍 Хочеш зробити content-check (LLM читає сторінки, верифікує claims)?`) frames the options as read-only and is now misleading — a parenthetical disclosure alone is NOT enough (r2 review: the *labels* must signal mutation). Fix the labels themselves:
    - Rewrite the header (line 70) so it names lint/autofix, e.g. `🔧 Запустити лінт-верифікацію обраного зрізу? Читає сторінки і одразу застосовує очевидні (disk-grounded) виправлення окремими reverting-комітами; спірні (DECIDE) чекають на твоє рішення.`
    - Amend each `[a]/[b]/[c]` option label (lines 72-74) to read as an action that runs lint on that subset (e.g. `[a] Лінт топ-5 найбільш редагованих (drift risk найвищий)`), not a passive "check".
    - Amend the routing-table rows (lines 89-91) and the After-completion note (line 101) to state that the delegated Lint auto-applies AUTO fixes as individual `auto-fix(wiki): #N` commits after a snapshot, revertible with `відкат` / `відкат N`, while DECIDE findings wait.
    - Keep the Lint autonomy contract itself unchanged (the `>10 AUTO fixes` batch-confirm threshold, snapshot-before-fix, page-protection all still apply — this task only relabels the entry, it does not add or weaken any Lint behavior). Do NOT reintroduce a `cleanup-prompt` token.
  - **Passive fixes `[1]/[2]` must gain snapshot + rollback (review r2 P1 Concern 1).** Today the routing table (line 92) and template `[пасивні fix'и]` block (lines 75-78) apply each passive fix as a bare inline `Edit` that bumps `patch_count` — **no snapshot, no per-fix commit, no `відкат` handle** — a silent mutation right after a screen the user reads as "status". This is the same consent/rollback gap as `[a]/[b]/[c]`. Fix: **route the passive fixes through the SAME Lint AUTO/DECIDE machinery** rather than applying them inline. Concretely:
    - Reframe cross-ref-drift and schema-drift passive findings as Lint findings: cross-ref drift → an AUTO finding (broken-`[[wikilink]]` removal, a documented Lint AUTO pattern); schema drift → classify per Lint's rules (undeclared category on a single entity may be AUTO; a schema-split/legacy-schema question is DECIDE). When the user picks `[1]/[2]` (or "all passive"), hand those specific findings to `## Operation: Lint`'s auto-apply mechanics: snapshot commit → per-fix `auto-fix(wiki): #N` reverting commit(s) → `відкат N` handle; DECIDE-classified ones surface with the action menu instead of mutating.
    - Rewrite the `[1]/[2]/...` routing-table row (line 92) accordingly: replace "Apply the passive fix directly — no LLM read of the page needed … Each fix is a single `Edit`" with delegation into the Lint AUTO/DECIDE flow (snapshot + reverting per-fix commit + `відкат`). Update the template label (lines 75-78) and process step 8 (line 37) / step 9 (line 38) so passive fixes read as "queued into the lint auto-fix flow", not an inline edit.
    - Update the **After completion** paragraph (lines 97-101): the status *print* stays read-only at the meta-level, but selecting `[1]/[2]` now runs the Lint auto-fix machinery, so the "read-only at the meta-level" wording must scope explicitly to the status print, and the downstream mutation + `відкат` handle must be acknowledged there.
    - Do NOT alter the Lint autonomy contract itself (thresholds, snapshot idiom, protection); this reuses it. Do NOT reintroduce a `cleanup-prompt` token.
- **`references/operation-lint.md`**
  - Line 388: "do not append a РЕФЛЕКСІЯ block or cleanup-prompt." → "do not append a РЕФЛЕКСІЯ block."
  - **DO NOT TOUCH line 386** (`never emit a separate РЕФЛЕКСІЯ block` — guarded).
- **`references/maintenance-and-mistakes.md`**
  - Line 60: rewrite the mistake row so it no longer references the removed embedded cleanup-prompt; keep the lint/status/cleanup-flow "report is the visible reasoning, no extra РЕФЛЕКСІЯ block" point. Remove `cleanup-prompt` and the stale "line 308"/"Cleanup-prompt section" cross-refs.
- **`SKILL.md`**
  - Line 3: `version: "4.3.0"` → `version: "4.4.0"`.
  - Line 109 (Reference Loading Map): "Reflection / crystallization / new skill creation" → "Reflection / crystallization".

### Tests / Verify (Task 2)
- `cd … && bash tests/skill-contracts.sh` → GREEN (version-major still `4`; contract tests over SKILL.md + references pass).
- `grep -rn 'cleanup-prompt' /Users/a/…/references/` → zero.
- `grep -n 'set_skill_link' /Users/a/…/references/self-improvement.md` → zero.
- `grep -n 'version:' /Users/a/…/SKILL.md` → `4.4.0`.
- `git -C "…root…" status --short` shows only the five files above.

### Commit (Task 2)
`… commit -m "refactor(v44): drop cleanup-prompt/skill-tier cross-refs; bump skill to 4.4.0"`.

---

## Task 3 — Migration Log entry + stale version example (`references/discovery-versioning.md`)

Independent; after Task 1. Single file.

Edits:
- Add a new Migration Log entry `### 4.4.0 (2026-07-07)` (insert above `### 4.3.0 (2026-06-02)` at line 387, matching the existing entry style at lines 387-405). Content:
  - No schema migration (`wiki_version` stays `"4.0"`); zero migrations for existing wikis.
  - Crystallization → wiki-only; skill tier removed (delegation + direct-create topology gone).
  - Embedded cleanup-prompt removed; cleanup-flow now single-entry via `wiki status`.
  - Motivation: prompt fatigue (question after every reflection) + unused skill tier (installer-safety / export-topology surface never paid off).
  - This entry is the ONLY place `set_skill_link` / `writing-skills` / `cleanup-prompt` history may be mentioned (Migration Log is exempt from the grep-sweep — keep it descriptive, avoid re-introducing the exact guarded tokens `🧹` / `writing-skills` if a paraphrase works, to avoid any accidental guard trip; note the guards are scoped to other files, but discovery-versioning.md is under `references/` so the `🧹` and `writing-skills` anti-return guards WOULD catch it — therefore write the entry WITHOUT the literal `🧹` glyph and WITHOUT the literal `writing-skills` string; say "the emoji cleanup-prompt" and "skill-authoring delegation" instead).
- **Line 250:** update the stale example `version: "4.2.0"` and the "(`4` for `4.2.0`)" phrasing so it is not contradicted by the new minor; align with current skill version wording (v4.x behavior changes, schema stays `4.0`). Keep the major-comparison logic intact.

### Tests / Verify (Task 3)
- `cd … && bash tests/skill-contracts.sh` → GREEN. Critically confirms the new Migration Log text did NOT reintroduce `🧹` or `writing-skills` under `references/` (those guards scan all of `references/`).
- `grep -c '### 4.4.0' /Users/a/…/references/discovery-versioning.md` → 1.
- `git -C "…root…" status --short` → only `references/discovery-versioning.md`.

### Commit (Task 3)
`… commit -m "docs(v44): migration log entry for 4.4.0 (no schema migration)"`.

---

## Task 4 — Test scenarios: rename + rewrite to new contracts

Independent; after Task 1. Touches only `tests/scenarios/*` and `tests/README.md` (disjoint from Tasks 1-3, 5). NOT scanned by the `references/`-scoped guards, so CI stays green regardless of order — but the final grep-sweep (Task 6) covers `tests/scenarios/`, so all tokens must go.

Edits:
- **Rename** `tests/scenarios/crystallization-tiers.md` → `tests/scenarios/crystallization.md` via `git -C "…root…" mv`.
  - Delete **Sub-scenario 2** (skill via writing-skills, lines ~92-192 incl. "Separation-of-concerns check" and "wiki-vs-skill discrimination check").
  - Intro (lines 24-29): "two artifact types (wiki / skill)" → single artifact type (wiki page).
  - **Sub-scenario 3** (recurring command ≠ script proposal, ~line 194): extend the expected behavior so the agent proposes NEITHER a script NOR a skill (only wiki, if anything). Remove the "Two options remain: wiki or skill" framing (line 221) and the `skill` rejection sub-bullet (228) → wiki-only reasoning.
  - Remove `writing-skills` / `set_skill_link` / `skill — created|delegated` residue (lines 114,128,144,148,153,157,161,178).
  - Renumber remaining sub-scenarios (1, 3→2, 4→3, 5→4, 6→5) and fix all internal references (e.g. "Sub-scenarios 3 and 4" at line 29).
- **`tests/scenarios/reflection-triggers.md`**
  - Strip the interactive `🧹 … [y]/[n]` tail from the three expected outputs at lines 59, 105, 183. For non-pre-commit triggers (and pre-commit turns with no passive drift), the block ends on `Автоматизував:` / `Перевірив:` with no trailing prompt.
  - Add/keep coverage for the retained **pre-commit passive drift notice** (1b): assert that a `trigger: pre-commit` reflection **with** passive drift present ends with the single `⚠️ … wiki status …` pointer line (non-interactive, no `🧹`, no y/n), and that the same trigger **without** drift, plus every non-pre-commit trigger, emits **no** notice. Use `⚠️`, never `🧹`, so the scenario stays clean under the Task 6 sweep.
  - Rewrite the assertions ~179-207 ("The block ends with the embedded cleanup-prompt", safety-contract, horizontal-rule manual check, `cleanup-prompt` mentions) → assert the interactive prompt is gone and the only possible tail is the conditional passive drift notice above. Do not use the literal `cleanup-prompt` token.
- **`tests/scenarios/cleanup-flow.md`**
  - Rewrite the two-entry-points framing (lines 5, 11-13, 22-24) → single entry via `wiki status`.
  - Sub-scenario 1 "РЕФЛЕКСІЯ → `глянь і онови`" (entered via embedded prompt, incl. 🧹 at line 59): convert entry to `wiki status` → `[a]/[b]/[c]`. Remove `🧹` (59) and `cleanup-prompt` (108,185).
  - **Reconcile the action-menu expectation with Two-Tier Autonomy (review r2 P1 Concern 3):** any sub-scenario that asserts "for each finding the user picks a verb" must be rewritten so AUTO findings are shown as already-applied (revertible via `відкат N`) and only DECIDE / elevated-INFO findings await a `<N> <verb>`. The six verbs stay as the DECIDE/INFO vocabulary.
  - Keep the double-confirm / page-protection sub-scenarios (mechanics unchanged).
- **`tests/scenarios/wiki-status.md`** (review r2 P1 Concerns 1 & 2 — this scenario encodes the OLD inline-mutation contract at lines ~226)
  - Relabel the `[a]/[b]/[c]` expected-behavior rows so they read as "run lint on subset → AUTO auto-applied with snapshot + `auto-fix(wiki): #N` commits + `відкат`, DECIDE waits", not read-only content-check.
  - Rewrite the `1` and `2` routing rows (lines ~226): they must NOT be "a real edit, not a meta-op" applied inline. Assert instead that picking `1`/`2` routes the passive finding into the Lint AUTO/DECIDE machinery (snapshot → per-fix reverting commit → `відкат`), matching operation-wiki-status.md's rewritten contract.
  - Keep the page-protection expectation (`[[secret-rotation-recipe]]` excluded from `[b]`) unchanged.
- **`tests/scenarios/integration-checklist.md`**
  - Line 60: drop "or cleanup-prompt".
  - Line 125: rewrite to wiki-only (remove skill-type delegation / `writing-skills` bullet).
  - Line 143: drop "or cleanup-prompt".
  - Line 145 (context bullet ~"Cross-agent direct skill creation clarified"): remove — the skill-creation path no longer exists.
  - Also update lines ~123-126 (crystallization checklist bullets) to wiki-only and remove the `set_skill_link` reference at 153-area if present.
- **`tests/scenarios/staleness-content-verification.md`**
  - Line 99: "No extra РЕФЛЕКСІЯ block or cleanup-prompt appears after the lint report." → drop "or cleanup-prompt".
- **`tests/README.md`**
  - Line 20: update entry #5 to the new file name `crystallization.md` and wiki-only description (drop "Codex/Gemini-only direct-create … canonical topology").

### Tests / Verify (Task 4)
- `cd … && bash tests/skill-contracts.sh` → GREEN.
- `grep -rn '🧹\|writing-skills\|cleanup-prompt\|set_skill_link\|skill — delegated\|skill — created' /Users/a/…/tests/scenarios/ /Users/a/…/tests/README.md` → zero.
- `git -C "…root…" status --short` shows the rename (`R` for crystallization-tiers→crystallization) + the edited scenario files + `tests/README.md`; no dangling reference to `crystallization-tiers`.
- Manual read of the renamed `crystallization.md` for prompt-contract coherence (scenarios are prompt contracts, not executable — a silent logic error changes expected agent behavior).

### Commit (Task 4)
`… commit -m "test(v44): rename crystallization scenario + drop skill-tier/cleanup-prompt cases"`.

---

## Task 5 — README.md

Independent; after Task 1. Single file.

Edits:
- Bullets ~118, ~126 (crystallization description): → wiki-only, annotate "(Перероблено у v4.1 і v4.4)".
- Line 3 header: `Skill behavior version: 4.3.0` → `4.4.0`; adjust the "v4.1/v4.2/v4.3 changed …" enumeration to include v4.4 as behavior-only, schema stays `4.0`.
- Add a `v4.4.0` row to the version table (~lines 174-179) describing wiki-only crystallization + single-entry cleanup-flow.
- Optionally add a short "What's new in v4.4" note near the existing "What's new in v4.3" (line 31) — keep it brief.

### Tests / Verify (Task 5)
- `grep -n '4.4' /Users/a/…/README.md` shows the header + table row.
- `grep -rn '🧹\|writing-skills\|cleanup-prompt' /Users/a/…/README.md` → zero (README is in the grep-sweep scope).
- `git -C "…root…" status --short` → only `README.md`.

### Commit (Task 5)
`… commit -m "docs(v44): README crystallization wiki-only + version table row"`.

---

## Task 6 — Final integration verification (no code; gate before hand-off)

Run only after Tasks 1-5 are all committed. Produces no commit (pure verification); if it finds a residue, route the fix back to the owning task.

Steps (spec §Верифікація, lines 171-180):
1. `cd "/Users/a/…v44-simplification" && bash tests/skill-contracts.sh` → GREEN.
2. **Grep-sweep** — zero matches across `SKILL.md`, `references/`, `tests/scenarios/`, `tests/README.md`, `README.md`, EXCEPT the Migration Log entry in `discovery-versioning.md` and dated `docs/specs/` | `docs/plans/`:
   ```
   grep -rn -- '🧹' … ; grep -rn 'writing-skills' … ; grep -rn 'cleanup-prompt' … ;
   grep -rn 'Two entry points' … ; grep -rn 'set_skill_link' …  (expect only install.sh/uninstall.sh) ;
   grep -rn 'винеси в скіл' … ; grep -rn 'skill — delegated' … ; grep -rn 'skill — created' …
   ```
   `set_skill_link` is EXPECTED to remain in `install.sh` / `uninstall.sh` (they install the wiki-skill itself — out of scope, do NOT touch).
3. **Structural connectivity (manual):**
   - `references/cleanup-flow.md` first non-blank line is `### Cleanup-flow`.
   - `references/reflection.md` РЕФЛЕКСІЯ strict template ends on `Автоматизував:` / `Перевірив:` (no trailing 🧹 prompt).
   - No file references the old scenario name `crystallization-tiers`.
4. Confirm `git -C "…root…" log --oneline -6` shows the five commits (Tasks 1-5) on top of `d3efe1d`.

---

## Edge-cases & risk notes (carry into execution)

- **`set_skill_link` double meaning:** it legitimately stays in `install.sh`/`uninstall.sh` (installs the wiki-skill). Only remove it from `references/crystallization.md` (Task 1) and `references/self-improvement.md` (Task 2). The new guard targets `crystallization.md` ONLY.
- **Guard-phrase collision:** `never emit a separate РЕФЛЕКСІЯ block` (`operation-lint.md:386`) is guarded and must survive — do not fold it into any "РЕФЛЕКСІЯ block or cleanup-prompt" replacement.
- **Version-major guard:** minor bump `4.3.0`→`4.4.0` keeps major `4`; the version-major contract guard must still pass (verify in Tasks 1/2).
- **discovery-versioning.md under `references/`:** the `🧹` and `writing-skills` anti-return guards scan ALL of `references/`, so the new Migration Log entry must NOT contain the literal `🧹` glyph or the literal string `writing-skills` (paraphrase instead) — see Task 3.
- **Existing wikis:** `wiki_version` unchanged → Step-0 detect sees no mismatch → no migration prompt. Zero-migration guarantee.
- **Ordering / parallelism:** Task 1 first (owns primary files + guards). Tasks 2-5 touch disjoint files and may run in any order (or in parallel by subagents) after Task 1; if parallel, serialize the git commits (shared index). Task 6 last.
- **Review P1 — cleanup auto-trigger not dropped outright (Concern 1):** the interactive `🧹 [y]/[n]` interrogation is removed (prompt fatigue), but a **conditional pre-commit passive drift notice** replaces it (Tasks 1b/1c/4) so drift is still surfaced automatically without a per-reflection question. It is non-interactive, drift-gated, `⚠️`-marked (not `🧹`), and only *points at* the manual `wiki status` — so it neither trips the `🧹` guard nor adds a second cleanup entry point. This is a deliberate, minimal divergence from the spec's literal "delete outright"; if the spec (`docs/superpowers/specs/2026-07-07-v44-simplification.md`) is treated as frozen, reconcile it with a one-line note there in a follow-up — out of scope for this plan-review fix.
- **Review P1/r2 — `wiki status` content-check is not read-only (Concern 2):** because `wiki status` is now the sole cleanup entry, its `[a]/[b]/[c]` delegate to Lint (which auto-applies + commits AUTO fixes). **r2 escalation:** a parenthetical disclosure is not enough — the `[a]/[b]/[c]` *header and option labels themselves* must name lint/autofix so they no longer read as read-only (Task 2). This relabels the entry only; the Lint autonomy contract, the `>10 AUTO` batch-confirm threshold, snapshot-before-fix, and page-protection are unchanged. A fully read-only (dry-run) status remains a separate future spec, not this plan.
- **Review r2 — `wiki status` passive fixes `[1]/[2]` mutated without rollback/consent (Concern 1):** the old contract applied `[1]/[2]` as bare inline `Edit`s (no snapshot / no commit / no `відкат`) right after a "status" screen. Fixed by routing passive fixes through the SAME Lint AUTO/DECIDE machinery as `[a]/[b]/[c]` (snapshot → per-fix reverting commit → `відкат N`; DECIDE-classified ones wait) — Tasks 2 + 4. Reuses the existing Lint contract, does not add new autonomy.
- **Review r2 — cleanup-flow.md action-menu contradicted Two-Tier Autonomy (Concern 3):** cleanup-flow.md's "for each finding the user picks a verb" framing predates Lint's AUTO-auto-apply. Fixed by making `## Operation: Lint › Two-Tier Autonomy` the single source of truth for AUTO-vs-wait, and re-scoping cleanup-flow's action menu to the DECIDE/INFO verb vocabulary only (Tasks 1c + 4). The six verbs and safety layers are unchanged; only the "every finding waits" framing is corrected.
