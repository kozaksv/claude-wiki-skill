## Operation: Wiki Status

Manual pull-model overview of wiki health. Print a structured snapshot of the wiki and offer the user a menu of follow-up actions (content-verification or passive fixes). **Never auto-fired** — only invoked when the user explicitly asks. This is the active counterpart to the embedded cleanup-prompt in the РЕФЛЕКСІЯ block: same downstream flow, different entry point.

### When to invoke

User says one of:

- "wiki status"
- "вікі статус"
- "як справи у вікі" / "як справи у wiki"
- "огляд wiki" / "огляд вікі"
- "покажи стан wiki"

If the trigger is ambiguous (e.g. user just says "wiki?"), confirm before running — don't second-guess.

### Process

```
0. DISCOVER wiki location (Step 0 above) — also gives version state
1. READ {wiki}/.usage.json — full dict, tolerant of missing/corrupt (treat as {})
2. COUNT pages per layer:
     - {wiki}/concepts/*.md
     - {wiki}/entities/**/*.md  (recursive — entities are categorized)
     - {wiki}/transcripts/*.md
3. COUNT binaries in archive/ (the project-level archive sibling, gitignored)
4. COMPUTE activity rankings from .usage.json:
     - Top 2 by view_count (most consulted)
     - Top 2 by use_count (most cited as [[wikilinks]])
     - Top 2 by patch_count (most edited)
5. LIST protected pages (records where protected == true)
6. DETECT passive issues — these need NO LLM read:
     - Cross-ref drift: grep [[wikilinks]] in every page, flag links that don't resolve
     - Schema drift: scan entity-page frontmatter for category/type values
       not declared in schema.md
7. PRINT structured display (template below)
8. OFFER action menu (a/b/c content-verification + numbered passive fixes)
9. ROUTE the user choice to the appropriate operation
```

**Telemetry note — meta-operation:** `wiki status` itself does NOT bump `view_count` for surveyed pages. Reading `.usage.json` and counting page files is bookkeeping, not consultation. The only `Read` here is the JSON sidecar (which is not a wiki page). If the user later picks `[a]/[b]/[c]` and the content-verification flow reads pages, *those* reads bump `view_count` normally.

### Output template

Print this verbatim shape (substitute real numbers, real `[[wikilinks]]`, real timestamps). Bilingual style preserved — Ukrainian section labels, English field names where they're API-accurate:

```
📊 Wiki Status — {wiki-path}

Версія: {N.M} ({стан: актуальна / застаріла / новіша за скіл})
Сторінок: {total} (concepts: {C}, entities: {E}, transcripts: {T})
Прив'язаних бінарних файлів у archive/: {B}

Активність (з .usage.json):
  Найчастіше консультуються:  [[page-x]] ({n} view), [[page-y]] ({n})
  Найбільш цитуються:         [[page-a]] ({n} use), [[page-b]] ({n})
  Найбільш редагуються:       [[page-p]] ({n} patch), [[page-q]] ({n})

Захищені:
  • [[secret-rotation-recipe]]
  • [[incident-2026-02-15]]
  (or: «жодних — ще нічого не захищено»)

⚠️ Знайдено пасивно:
  • Cross-ref drift: [[source-page]] → [[broken-target]] (видалено)
  • Schema drift: [[entity-page]] використовує category="legacy" (нема в schema.md)
  (or: «нічого — пасивних дрифтів не знайдено»)

──────────────────────────────────────────
🔍 Хочеш зробити content-check (LLM читає сторінки, верифікує claims)?

  [a] Топ-5 найбільш редагованих (drift risk найвищий)
  [b] Топ-5 найдовше unverified (нема recent edit'у — claims могли застаріти)
  [c] Конкретні сторінки — вкажи [[page-names]]
  [пасивні fix'и]:
    [1] cross-ref у [[source-page]]
    [2] schema-drift у [[entity-page]]
  [n] нічого
```

If a section has nothing to show (no protected pages, no passive issues), keep the section header and write the inline fallback in `«italic-quoted form»` so the structure stays predictable across runs.

### Action menu routing

The menu items are reachable; they don't execute new logic embedded in `wiki status`:

| Choice | What happens |
|---|---|
| `[a]` Top-5 most edited | Delegate to `## Operation: Lint` — content-verification flow with the `most-edited` priority filter applied to the top 5 entries from `report()` sorted by `patch_count desc, last_patched_at asc` |
| `[b]` Top-5 longest unverified | Delegate to `## Operation: Lint` — content-verification flow sorted by `last_patched_at asc` (oldest first), filtered to `state == "active"` and `protected == false` |
| `[c]` Specific pages | User supplies `[[page-names]]`; delegate to `## Operation: Lint` content-verification on that exact set |
| `[1]/[2]/...` Passive fixes | Apply the passive fix directly — no LLM read of the page needed. Cross-ref drift = remove or replace the broken `[[wikilink]]`; schema drift = update the entity's `category`/`type` field or propose a schema.md addition. Each fix is a single `Edit` and bumps `patch_count` for the modified page. |
| `[n]` Nothing | Print "OK, нічого не зроблено" and end the operation |

**Delegation contract:** the chosen subset (a list of page paths) is handed to `## Operation: Lint`'s content-verification step, which produces the report and per-page action menu.

### After completion

`wiki status` is read-only at the meta-level (read sidecar, count files, grep wikilinks — no `Edit` / `Write` happens during the status print itself). Apply the **anti-noise rule** and skip the РЕФЛЕКСІЯ block.

If the user picks `[a]/[b]/[c]` or a passive fix and that downstream flow makes edits, that downstream report/confirmation is the visible reasoning. Do not emit a separate РЕФЛЕКСІЯ block or cleanup-prompt from `wiki status`, Lint, or cleanup-flow.

---
