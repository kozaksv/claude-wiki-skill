## Operation: Wiki Status

Manual pull-model overview of wiki health. Print a structured snapshot of the wiki and offer the user a menu of follow-up actions (content-verification or passive fixes). **Never auto-fired** — only invoked when the user explicitly asks.

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
3a. DETECT hooks state from `_hooks` (see `references/telemetry.md` →
    reserved `_hooks` key and dual-signal rule):
     - No `_hooks` key at all, or the canonical hook marker absent from
       `~/.claude/settings.json` → «не встановлені»
     - `_hooks` present but both `session_start_at`/`post_tool_use_at`
       stale or absent → «heartbeat застарілий»
     - `session_start_at` fresh but `post_tool_use_at` stale/absent →
       «інжект є, телеметрія мертва» (the injected-but-dead state)
     - Both `session_start_at` and `post_tool_use_at` fresh → «активні»
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
8. OFFER action menu (a/b/c content-verification + numbered passive fixes, all queued into the lint auto-fix flow)
9. ROUTE the user choice into `## Operation: Lint` — a/b/c as content-verification subsets, numbered passive fixes as findings entering Lint's own AUTO/DECIDE flow
```

**Telemetry note — meta-operation:** `wiki status` itself does NOT bump `view_count` for surveyed pages. Reading `.usage.json` and counting page files is bookkeeping, not consultation. The only `Read` here is the JSON sidecar (which is not a wiki page). If the user later picks `[a]/[b]/[c]` and the content-verification flow reads pages, *those* reads bump `view_count` normally.

### Output template

Print this verbatim shape (substitute real numbers, real `[[wikilinks]]`, real timestamps). Bilingual style preserved — Ukrainian section labels, English field names where they're API-accurate:

```
📊 Wiki Status — {wiki-path}

Версія: {N.M} ({стан: актуальна / застаріла / новіша за скіл})
Сторінок: {total} (concepts: {C}, entities: {E}, transcripts: {T})
Прив'язаних бінарних файлів у archive/: {B}
Хуки: {✅ активні / ⚠️ не встановлені — wiki doctor / ⚠️ heartbeat застарілий — wiki doctor / ⚠️ інжект є, телеметрія мертва (свіжий session_start_at, застарілий post_tool_use_at) — wiki doctor}

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
🔧 Запустити лінт-верифікацію обраного зрізу? Читає сторінки і одразу застосовує
очевидні (disk-grounded) виправлення окремими reverting-комітами; спірні (DECIDE)
чекають на твоє рішення.

  [a] Лінт топ-5 найбільш редагованих (drift risk найвищий)
  [b] Лінт топ-5 найдовше unverified (нема recent edit'у — claims могли застаріти)
  [c] Лінт конкретних сторінок — вкажи [[page-names]]
  [пасивні fix'и — теж через лінт-flow]:
    [1] cross-ref у [[source-page]]
    [2] schema-drift у [[entity-page]]
  [n] нічого
```

If a section has nothing to show (no protected pages, no passive issues), keep the section header and write the inline fallback in `«italic-quoted form»` so the structure stays predictable across runs.

### Action menu routing

The menu items are reachable; they don't execute new logic embedded in `wiki status`:

| Choice | What happens |
|---|---|
| `[a]` Top-5 most edited | Delegate to `## Operation: Lint` — content-verification flow with the `most-edited` priority filter applied to the top 5 entries from `report()` sorted by `patch_count desc, last_patched_at asc`. Lint's own AUTO/DECIDE split applies: AUTO findings are applied after a snapshot commit, one `auto-fix(wiki): #N` commit per fix, revertible with `відкат` / `відкат N`; DECIDE findings wait for the user. |
| `[b]` Top-5 longest unverified | Delegate to `## Operation: Lint` — content-verification flow sorted by `last_patched_at asc` (oldest first), filtered to `state == "active"` and `protected == false`. Same AUTO (snapshot + per-fix `auto-fix(wiki): #N` commit, revertible) / DECIDE (waits) split as above. |
| `[c]` Specific pages | User supplies `[[page-names]]`; delegate to `## Operation: Lint` content-verification on that exact set. Same AUTO (snapshot + per-fix `auto-fix(wiki): #N` commit, revertible) / DECIDE (waits) split as above. |
| `[1]/[2]/...` Passive fixes | Route into the **same Lint AUTO/DECIDE flow**, not a bare inline `Edit`. Cross-ref drift (broken `[[wikilink]]`) is reframed as a Lint AUTO finding — snapshot commit, then its own `auto-fix(wiki): #N` reverting commit, revertible with `відкат N`. Schema drift is classified per Lint's own rules: an undeclared `category`/`type` on a single entity may qualify as AUTO (same snapshot + `auto-fix(wiki): #N` treatment); a schema split or legacy-value migration is DECIDE and surfaces Lint's action menu instead of auto-applying. |
| `[n]` Nothing | Print "OK, нічого не зроблено" and end the operation |

**Delegation contract:** the chosen subset (a list of page paths, or the passive-fix findings themselves) is handed to `## Operation: Lint`, which produces the report, applies AUTO fixes behind the snapshot + per-fix commit idiom, and surfaces DECIDE findings with the per-finding action menu.

### After completion

The status print itself is read-only at the meta-level (read sidecar, count files, grep wikilinks — no `Edit` / `Write` happens while `wiki status` is printing the snapshot and menu). Apply the **anti-noise rule** and skip the РЕФЛЕКСІЯ block for the print step.

That read-only scope ends the moment the user picks `[a]/[b]/[c]` or a numbered passive fix: those choices hand off into `## Operation: Lint`, which mutates the wiki (snapshot commit, then per-AUTO-finding `auto-fix(wiki): #N` commits) and is revertible with `відкат` / `відкат N`. The Lint report/confirmation from that downstream flow is the visible reasoning for those mutations. Do not emit a separate РЕФЛЕКСІЯ block from `wiki status`, Lint, or cleanup-flow.

---
