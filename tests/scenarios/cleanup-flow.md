# Scenario: Cleanup-flow end-to-end

Four sub-scenarios that exercise the unified cleanup-flow inside
`references/self-improvement.md`. The flow
has two entry points (РЕФЛЕКСІЯ embedded `[y]` prompt and `wiki status`
`[a/b/c]`) that funnel into the same downstream mechanics: subset
selection → content-verification → per-page action menu.

The four sub-scenarios cover:

1. **РЕФЛЕКСІЯ entry point** — `[y]` → subset → verification → user picks
   `глянь і онови`
2. **`wiki status` entry point** — `[a]` → top-5 most edited → user picks
   `видали` → double-confirmation flow
3. **Page protection** — user attempts `видали` on a `protected: true` page;
   skill refuses with helpful message
4. **Snapshot rollback** — destructive op completes, user regrets, runs
   `git revert HEAD`, wiki restored

---

## Sub-scenario 1: РЕФЛЕКСІЯ → `глянь і онови`

User just finished a feature; reflection fires; embedded cleanup prompt
appears; user accepts; one finding surfaces; user picks `глянь і онови`.

### Setup

Mock wiki state:

- `docs/wiki/schema.md` — `wiki_version: "4.0"`.
- `docs/wiki/concepts/template-course-flow.md`:

  ```markdown
  # Template & Course Flow

  Templates → Courses → Schedule → Intake.

  ## Sources
  - `docs/superpowers/specs/2026-04-13-course-builder-design.md`
  - `apps/api/src/routes/courses.ts`
  ```

- `apps/api/src/routes/courses.ts` exists.
- `docs/superpowers/specs/2026-04-13-course-builder-design.md` exists.
- `docs/wiki/.usage.json` records `template-course-flow.md` with
  `patch_count: 6`, `last_patched_at: 2026-04-30T15:00:00Z`.

The page also makes a body claim: «`courses.ts` exports `cancelCourse()`
which sets `cancelledAt`». The current source code on disk renamed the
function to `markCourseCancelled()` (the field is unchanged) — so one
claim drifted, one holds.

### Trigger

User completes a TodoWrite list. Reflection fires. The trailing prompt:

```
🧹 Показати список того, що в wiki могло застаріти?
   [y] показати  /  [n] продовжуємо
```

User: `y`.

### Expected skill behavior

1. Enter subset selection. Show menu `[a] / [b] / [c]`. User picks `[a]`
   Top-5 most edited.
2. Sort `report()` by `patch_count desc, last_patched_at asc`. Filter
   `state == "active"` and `protected == false`. Top entry:
   `template-course-flow.md`.
3. **Read** `concepts/template-course-flow.md` in full → bumps
   `view_count` to its prior value + 1.
4. Verify each claim:
   - Source files exist → both hold.
   - Body claim about `cancelCourse()` → grep
     `apps/api/src/routes/courses.ts` for `cancelCourse` → not found.
     Function `markCourseCancelled` exists. **Claim drifted.**
5. Present finding with the action menu:

   ```
   🔍 concepts/template-course-flow.md
       Claim: «exports cancelCourse() which sets cancelledAt»
       Disk:  function is markCourseCancelled() (cancelledAt unchanged)

       1 — глянь і онови   (прочитаю + поправлю claim синхронно)
       2 — видали          (потребує double-confirm)
       3 — захисти
       4 — merge
       5 — розбий
       (глянь обидві — недоступно, пара сторінок не виявлена)

       Вибір [1/2/3/4/5]:
   ```

6. User: `1`.
7. Skill:
   - Edits the page: replace `cancelCourse()` → `markCourseCancelled()`
     in the relevant sentence.
   - Shows the diff inline before saving.
   - On confirm, writes the file and calls `bump_patch(template-course-flow.md)`
     in `.usage.json` (`patch_count: 6 → 7`, `last_patched_at` updated).
   - **Does NOT** snapshot before — `глянь і онови` is non-destructive
     (Edit, not delete/merge). Snapshot is reserved for `видали` /
     `merge` / `розбий`.
8. No extra РЕФЛЕКСІЯ block appears after this cleanup-flow edit. The
   content-verification finding, chosen action, diff, and confirmation are the
   visible reasoning for the cleanup pass; adding the embedded cleanup prompt
   again would be recursive.

### Telemetry effect

`.usage.json` after:

```json
{
  "concepts/template-course-flow.md": {
    "view_count": <prev+1>,
    "patch_count": 7,
    "last_patched_at": "<now>",
    "state": "active", "protected": false
  }
}
```

---

## Sub-scenario 2: `wiki status` → `видали` with double-confirm

User invokes `wiki status` directly, picks `[a]`, content-verification
flags one page, user picks `видали`, double-confirmation flow plays out.

### Setup

Mock wiki state:

- `docs/wiki/concepts/legacy-feature-flag.md` — describes a feature flag
  that was removed from the codebase six months ago. The page's `## Sources`
  list points to a deleted spec and a deleted route file.
- `.usage.json` for `legacy-feature-flag.md`: `patch_count: 9`
  (the page was actively maintained back when the flag mattered),
  `last_patched_at: 2025-10-12T...`, `protected: false`.
- It tops the `[a]` ranking (highest `patch_count`).

### Trigger

User: `wiki status`.

### Expected skill behavior

1. Skill prints status (no `view_count` bumps for surveyed pages — `wiki
   status` is a meta-operation).
2. User: `[a]`.
3. Skill delegates to Lint content-verification on the top-5 most edited.
   Reads each page in full (each read bumps `view_count`).
4. For `legacy-feature-flag.md`: both source files in `## Sources` →
   missing on disk. Body references `flagsService.isLegacyFeatureEnabled()`
   → not found in current codebase.
5. Action menu surfaces; user: `2` (`видали`).
6. **Double-confirmation kicks in:**

   ```
   ⚠️  Підтверди видалення:
       concepts/legacy-feature-flag.md  (87 рядків, останній patch 2025-10-12)

       Перші 200 символів:
       > Legacy feature flag introduced in 2024-Q3 to gate the experimental ...

       Якщо точно видалити — напиши `yes` (саме слово, не `y`).
       Будь-яка інша відповідь — скасування.
   ```

7. User: `yes`.
8. **Snapshot before delete:**

   ```bash
   git commit -m "chore(wiki): snapshot before видали"
   ```

9. Skill deletes the file, removes from `index.md`, calls
   `forget(concepts/legacy-feature-flag.md)` in `.usage.json`.
10. Skill confirms with rollback hint: «Якщо передумаєш — `git revert
    HEAD` поверне до знімка».
11. The lint-driven flow ends with its own confirmation and rollback hint. No
    extra РЕФЛЕКСІЯ block or cleanup-prompt appears after `wiki status` /
    cleanup-flow.

### Cancellation variant

If at step 7 the user types `y` (single character), `Y`, `так`, or
anything other than the literal word `yes` (case-insensitive after
trimming) — skill cancels with no telemetry effect, no snapshot, no
delete. Print:

```
↩️ Скасовано — для видалення треба написати саме `yes`.
   Файл concepts/legacy-feature-flag.md залишається як був.
```

---

## Sub-scenario 3: Page protection on `видали`

User attempts to delete a `protected: true` page; skill refuses regardless
of how the user got there.

### Setup

Mock wiki state:

- `docs/wiki/concepts/security-recovery.md` — incident-recovery runbook,
  intentionally rare-read but high value.
- `.usage.json` records `protected: true`, `view_count: 0`, `patch_count: 1`.
- A separate page (e.g. via `[c]` user-specified) lists this path
  explicitly, OR the user invokes the action menu directly on it.

### Trigger

Either path is valid:

- (a) `wiki status` → `[c]` → user types `concepts/security-recovery.md`
  → action menu → user picks `2` (видали).
- (b) From a РЕФЛЕКСІЯ `[y]` → `[c]` flow with the same explicit listing
  (per spec, `[c]` does NOT bypass page protection).

### Expected skill behavior

1. Skill detects `protected: true` on the target.
2. **Refuse before even offering double-confirmation.** No snapshot, no
   delete, no telemetry mutation. Print:

   ```
   ⛔ concepts/security-recovery.md помічена як `protected: true` —
       захищена від cleanup-flow.

       Якщо точно треба видалити:
         1) wiki unprotect concepts/security-recovery.md
         2) повтори видалення

       Це додатковий запобіжник проти випадкового знесення
       критичних сторінок (security, incident, migration).
   ```

3. State unchanged. `.usage.json` for this page is identical before/after.
4. The same protection triggers if the user picks `merge` and the protected
   page is the source side. For `глянь і онови` and `захисти` itself the
   protection is a no-op (these are non-destructive).

### Unprotecting + re-attempt

If the user runs `wiki unprotect concepts/security-recovery.md`:

1. Skill toggles `protected: false` in `.usage.json`.
2. Confirms: «✅ concepts/security-recovery.md → protected: false …».
3. User can now re-attempt `видали`; the normal double-confirm flow
   applies (the page is no longer page-protected).

---

## Sub-scenario 4: Snapshot rollback

User completed a destructive op, regrets it, uses the snapshot anchor to
restore.

### Setup

Continuing from Sub-scenario 2 — the user said `yes`, the page was
deleted, the snapshot commit `chore(wiki): snapshot before видали` is
on `HEAD~1`, and the actual deletion is on `HEAD` (or a few commits
later if the operation also touched `index.md` and `.usage.json`).

Concrete `git log --oneline` after the destructive op might look like:

```
abc1234 chore(wiki): cleanup — видалено concepts/legacy-feature-flag.md
def5678 chore(wiki): snapshot before видали
...
```

### Trigger

User: `повертай як було` / «зроби `git revert`» / explicitly runs
`git revert HEAD`.

### Expected behavior

1. `git revert HEAD` creates a new commit that undoes the deletion
   (restores the file, restores `index.md`, restores the `.usage.json`
   record — provided `.usage.json` was tracked in the snapshot; it is
   gitignored by default, so the JSON sidecar may need a manual
   `bump_patch` re-record).
2. The snapshot commit `def5678` is **not** rewound — it remains in
   history as a witness. This is intentional: `git revert` is forward-
   adding, not history-rewriting, so the rollback itself is auditable.
3. The wiki tree on disk now matches what existed at snapshot time
   (modulo the `.usage.json` caveat — see below).

### `.usage.json` caveat

Because `.usage.json` is gitignored by default (per spec — telemetry is
per-clone, not committed), `git revert` does NOT restore the
`.usage.json` entry that `forget()` removed. The user has two options:

- (a) Accept that telemetry restarts from zero for the restored page.
  This is usually fine — telemetry is for prioritization, not content.
- (b) Manually re-create the `.usage.json` entry by reading the page
  once (which auto-creates a default record via the mutator API).

The skill mentions this in the post-operation hint after `видали`:

> «Зверни увагу: `.usage.json` у gitignore, тому `git revert` поверне
>  файл сторінки, але не лічильники. При першому новому read лічильники
>  створяться заново з дефолтами.»

### Telemetry effect

After `git revert HEAD`:

- File on disk: restored.
- `index.md`: restored.
- `.usage.json`: still missing the entry (caveat above) — restoring
  requires a fresh consultation of the page.

---

## Notes on test execution

These are mental-walkthrough scenarios for verifying `SKILL.md` routing plus
`references/` instructions, not automated tests. Each sub-scenario should be readable
end-to-end as a story: setup → trigger → expected skill behavior →
telemetry effect.

When integrating during Phase I (final integration), walk each
sub-scenario against the latest `SKILL.md` + `references/` contract and note any gaps under an
"Issues Found" header in this file.
