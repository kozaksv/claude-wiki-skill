### Cleanup-prompt embedded in reflection

The trailing block (after the horizontal rule) is an **embedded cleanup-prompt**:

```
🧹 Показати список того, що в wiki могло застаріти?
   Я лише покажу — нічого не змінюватиму без твого слова.
   [y] показати  /  [n] продовжуємо
```

**Safety contract:**

- `[y]` → the agent **only displays** a candidate list (top-N by drift signal from `.usage.json`, plus passive findings like cross-ref drift). It **does not** edit, delete, or modify any wiki content. The list is informational; any action taken from it requires a separate explicit instruction from the user.
- `[n]` → the agent continues the conversation. Reflection block is closed.
- No reply within the same turn → treat as `[n]`. Do not block waiting; the user can come back to it.

The prompt is short on purpose — it's a passive offer, not an interrogation. If the user does not engage in three consecutive reflections, scale back to firing it only on pre-commit moments (still optional from the user side). This avoids prompt fatigue.

**Anti-recursion rule (hard).** The cleanup-prompt **MUST NOT** appear at the end of a Lint run, a `wiki status` run, or any cleanup-flow run — independent of whether reflection itself would have fired. The prompt's purpose is to *bridge* normal work (a feature commit, a finished todo) into a wiki-cleanup pass. Bridging from a cleanup to a cleanup is recursive: the user has just seen what's stale and chosen which fixes to apply; offering «показати, що могло застаріти?» asks them to redo the work they finished one screen ago. Concretely: when emitting output at the end of `вікі лінт` / `вікі статус` / a cleanup-flow run, omit the cleanup-prompt block unconditionally. Combined with the anti-noise rule above (no reflection after lint / status / cleanup-flow), this means those operations end on their own report and nothing else.

The same downstream flow (subset selection → content-verification → action menu) is also reachable from the `wiki status` operation. Both entry points lead to identical mechanics; this is documented in detail under `## Operation: Wiki Status` below and in the `### Cleanup-flow` subsection that immediately follows.

### Cleanup-flow

The cleanup-flow is the **single canonical path** for any "the wiki has drifted, let's fix it" moment. Both entry points (the embedded РЕФЛЕКСІЯ prompt and the `wiki status` command) funnel into the same mechanics: subset selection → content-verification → per-page action menu. This subsection is the contract; everything in `## Operation: Lint` and `## Operation: Wiki Status` is a delegation target.

#### Two entry points, same downstream flow

| Entry point | Trigger | What the user picks |
|---|---|---|
| **РЕФЛЕКСІЯ embedded prompt** | Passive — emitted at the end of a reflection-firing turn | `[y]` показати → enters subset selection |
| **`wiki status` command** | Active — user typed `wiki status` / `вікі статус` | `[a]` / `[b]` / `[c]` directly picks a subset |

Both lead to:

1. **Subset selection** — top-5 most edited (`[a]`), top-5 longest unverified (`[b]`), or specific pages / category (`[c]`). Page protection filters out `protected: true` pages from `[a]` and `[b]` automatically.
2. **Content-verification** — skill reads each picked page in full (this bumps `view_count`), checks claims against cited code and disk state, surfaces drift findings.
3. **Action menu** — for each finding, the user picks one of the actions below.

The two entry points share the same code path on purpose. There is no "lite" cleanup vs. "full" cleanup; the only difference is which trigger surfaced the prompt.

#### Action menu (per-page / per-finding)

After verification, the skill presents findings with a numbered list. For each finding, the user picks an action verb (Ukrainian wording is the contract — do not translate):

| Action | What the skill does | Telemetry effect |
|---|---|---|
| `глянь і онови` | Read page + cited code, update content synchronously, show diff before saving | `bump_patch(path)` |
| `видали` | Delete the file, remove from `index.md`, mark in `.usage.json` | `forget(path)` |
| `захисти` | Set `protected: true` in `.usage.json` — future cleanup-prompts skip this page | toggle `protected` |
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

2. **Snapshot before destructive ops.** Immediately before `видали` / `merge` / `розбий` actually mutates the wiki, the skill commits the current state:

   ```bash
   git commit -m "chore(wiki): snapshot before {operation}"
   ```

   Use the literal verb in `{operation}` — `видали`, `merge`, `розбий`. The commit captures the wiki *before* the destructive change, so rollback is a one-liner:

   ```bash
   git revert HEAD
   ```

   The skill mentions this in its post-operation message: «Якщо передумаєш — `git revert HEAD` поверне до знімка». Do not skip the snapshot just because the working tree «looked clean»; if there's nothing to commit, run an empty commit (`--allow-empty`) so the rollback anchor still exists.

   `.usage.json` is gitignored by default, so `git revert HEAD` may restore the
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
