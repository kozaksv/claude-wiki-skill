### Cleanup-flow

The cleanup-flow is the **single canonical path** for any "the wiki has drifted, let's fix it" moment. The single entry point is `wiki status`; downstream is subset selection → content-verification → Two-Tier classification (AUTO auto-applied, DECIDE/INFO via the action menu below). This subsection is the contract; everything in `## Operation: Lint` and `## Operation: Wiki Status` is a delegation target.

### Passive drift notice

At the end of a `trigger: pre-commit` РЕФЛЕКСІЯ block (see `references/reflection.md`), if passive drift signals exist (dead cross-refs / schema drift — the same cheap, no-LLM-read, no-`view_count`-bump signals `wiki status` already computes), the skill appends a single non-interactive line:

```
⚠️ Вікі: {N} пасивних дрифт-сигналів — запусти `wiki status` для деталей
```

This fires at most once per pre-commit turn, only when a passive drift signal is present, and it is a **pointer**, not a second entry point — it names `wiki status` as the place to act; it does not itself offer a menu, ask `[y]/[n]`, or mutate anything. No other trigger (todo-completion, periodic-nudge, explicit, memory-flush) ever shows it, and a pre-commit turn with no drift signal shows nothing either.

**Anti-recursion rule (hard), re-scoped.** The passive drift notice **MUST NOT** appear at the end of a Lint run, a `wiki status` run, or any cleanup-flow run — those already end on their own report, and re-surfacing the notice there would ask the user to redo work they just finished.

#### Action menu (per-page / per-finding)

The six verbs below are the menu for **DECIDE / elevated-INFO** findings only — AUTO findings are already applied (and committed) before the report; the user reverts them with `відкат` / `відкат N`, they are never offered a verb (повний контракт AUTO/DECIDE/INFO — `## Operation: Lint › Two-Tier Autonomy`). After verification, the skill presents DECIDE/INFO findings with a numbered list. For each finding, the user picks an action verb (Ukrainian wording is the contract — do not translate):

| Action | What the skill does | Telemetry effect |
|---|---|---|
| `глянь і онови` | Read page + cited code, update content synchronously, show diff before saving | `bump_patch(path)` |
| `видали` | Delete the file, remove from `index.md`, mark in `.usage.json` | `forget(path)` |
| `захисти` | Set `protected: true` in `.usage.json` — cleanup-flow skips this page | toggle `protected` |
| `merge` | Propose merging two pages into one; triggers a separate flow that asks which is the target and which is the source | `forget(merged-into-other)` + `bump_patch(target)` |
| `розбий` | Invoke the existing `## Operation: Split` on this page | (split's own telemetry, normally `bump_patch` on each successor) |
| `глянь обидві` | Verbose side-by-side diff + recommendation (used when content-verification surfaces a contradiction between two pages) | (no immediate mutation; user then picks per-page action on each side) |

Render the menu with the verbs in Ukrainian, e.g.:

```
🔍 Знайдено: concepts/purchase-flow.md — джерело `docs/superpowers/specs/2025-12-01-purchase-receive.md` не існує.

   1 — глянь і онови   (прочитаю + поправлю claim синхронно)
   2 — видали          (видалю сторінку повністю — потребує double-confirm)
   3 — захисти             (помічу як захищену, виключу з cleanup-flow)
   4 — merge           (об'єднати з іншою сторінкою)
   5 — розбий          (запустити split)
   6 — глянь обидві    (тільки якщо є парна сторінка-кандидат)

   Вибір [1/2/3/4/5/6]:
```

Six verbs is the full menu. If a verb doesn't make sense for the finding (e.g. `глянь обидві` without a paired page), omit that line — never offer a no-op.

#### Safety layers

Three layers protect against accidental destruction:

1. **Double confirmation for `видали`.** The user picked `2` once. The skill **re-shows the list** of what will be deleted (path + first 200 chars of the page) and asks for a second confirmation that **must literally be `yes`**, not `y`. Single-character confirmations are too easy to slip on (touchpad, autocomplete, double-Enter). Example:

   ```
   ⚠️  Підтверди видалення:
       concepts/purchase-flow.md  (124 рядки, останній patch 2026-04-30)

       Перші 200 символів:
       > Multi-step purchase → receive → inventory creation flow. ...

       Якщо точно видалити — напиши `yes` (саме слово, не `y`).
       Будь-яка інша відповідь — скасування.
   ```

   Only `yes` (case-insensitive, trimmed) proceeds. Anything else cancels with no telemetry effect.

2. **Snapshot + committed destructive change.** Immediately before `видали` / `merge` / `розбий` mutates the wiki, if the working tree has uncommitted changes under `{wiki}`, the skill first commits them as a snapshot:

   ```bash
   git commit -m "chore(wiki): snapshot before {operation}"
   ```

   Use the literal verb in `{operation}` — `видали`, `merge`, `розбий`. The snapshot separates the user's pending edits from the destructive change so neither can sweep the other in. If the tree is already clean, skip the snapshot — the wiki lives in a git repo and history is already the anchor; do not create empty marker commits.

   Then apply the destructive change and **commit it as its own commit**:

   ```bash
   git commit -m "chore(wiki): {operation} {path}"
   ```

   Rollback is a one-liner that reverts exactly that destructive commit:

   ```bash
   git revert HEAD
   ```

   The skill mentions this in its post-operation message: «Якщо передумаєш — `git revert HEAD` поверне сторінку». Committing the destruction itself is what makes that hint true: an uncommitted deletion would leave `git revert HEAD` pointing at the snapshot instead and restore nothing.

   `.usage.json` is gitignored by default, so `git revert HEAD` restores the
   page and `index.md` without restoring the removed telemetry entry. If the
   agent notices this after a revert, it may offer to re-record a baseline entry
   with `bump_view`; do not do it silently.

3. **Page protection.** Even if the user typed `видали` (and even if they made it through double-confirmation), if the target page has `protected: true` in `.usage.json`, the skill **refuses** with a helpful message and does nothing. Example:

   ```
   ⛔ concepts/security-recovery.md помічена як `protected: true` —
       захищена від cleanup-flow.

       Якщо точно треба видалити:
         1) wiki unprotect concepts/security-recovery.md
         2) повтори видалення

       Це додатковий запобіжник проти випадкового знесення
       критичних сторінок (security, incident, migration).
   ```

   The same page protection applies to `merge` (when the protected page is the source side — protected page cannot be silently absorbed into another). For `глянь і онови` and `захисти` itself the protection is a no-op (these are non-destructive).

#### Telemetry effects summary

After each completed action, mutate `.usage.json` exactly once:

| Action | Mutator call(s) |
|---|---|
| `глянь і онови` | `bump_patch(path)` |
| `видали` | `forget(path)` |
| `захисти` | toggle `protected: true` |
| `unpin` (via `wiki unprotect`, see below) | toggle `protected: false` |
| `merge` | `forget(source-path)` + `bump_patch(target-path)` |
| `розбий` | delegated to `## Operation: Split` (it bumps each successor's `created_at` and patches the index) |
| `глянь обидві` | no immediate mutation — the per-page action chosen afterward triggers its own mutator |

A cancelled action (user said anything other than `yes` to a `видали` confirm, or page protection refused) leaves `.usage.json` untouched.

### `wiki protect <path>` and `wiki unprotect <path>`

Two micro-operations let the user toggle the `protected` field in `.usage.json` outside of the cleanup-flow context — useful when adding a page that should be born protected (security recipes, incident postmortems, migration runbooks), or when the user wants to liberate a previously-protected page so it rejoins normal cleanup.

| Command | What it does |
|---|---|
| `wiki protect <path>` | Set `protected: true` for `<path>` in `.usage.json`. Page is now skipped by `[a]` / `[b]` and refused by `видали` until unprotected. |
| `wiki unprotect <path>` | Set `protected: false` for `<path>` in `.usage.json`. Page rejoins the normal cleanup-flow and can be proposed for verification or destructive action. |

After either toggle, the skill confirms the new state and notes which protections (de)apply. Example output:

```
✅ concepts/security-recovery.md → protected: true
   Сторінка тепер виключена з cleanup-flow ([a]/[b]/[c] її не запропонують).
   Спроба `видали` буде відхилена з підказкою про `wiki unprotect`.
```

```
✅ concepts/legacy-feature.md → protected: false
   Сторінка повертається в нормальний cleanup-flow.
   Може з'явитись у [a] / [b] proposals і прийняти `видали`.
```

These commands do **not** fire reflection — they are pure metadata toggles, no content edited. Apply the **anti-noise rule** and skip the РЕФЛЕКСІЯ block.

The `<path>` argument is the wiki-relative path (e.g. `concepts/security-recovery.md`, `entities/contracts/acme-2026.md`). If the path does not match a wiki page, the skill refuses with a one-line error rather than creating an empty `.usage.json` entry.
