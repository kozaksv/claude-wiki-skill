# Wiki Skill v4.0 — Self-Improvement Loop (Hermes-aligned)

**Date:** 2026-05-01
**Skill:** `~/.claude/skills/wiki/` (symlink → `~/Library/CloudStorage/Dropbox/AI/claude-wiki-skill/`)
**Current version:** 3.0 (legacy, no `wiki_version` frontmatter)
**Target version:** 4.0
**Inspired by:** [Hermes-Agent](https://github.com/NousResearch/hermes-agent) by Nous Research (Apache 2.0)

## Purpose

Upgrade the universal wiki-skill (used across many projects, not Health-specific) so the agent self-improves between sessions. Adopt Hermes architectural patterns (telemetry sidecar, periodic nudges, memory flush, dotfile metadata) where they fit, but keep Karpathy's read-and-judge philosophy as the core for staleness detection. Add a visible reflection narrative for debugging AI reasoning.

## Non-goals

- No background fork / aux-model curator pass (deferred to v5+; Hermes feature, but overengineer for now)
- No automatic `active → stale → archived` page transitions (deferred to v5+)
- No bounded session memory (`MEMORY.md`/`USER.md`) — the wiki is unbounded knowledge accumulation; session memory is a separate concern
- No SOUL.md / personality file
- No external skill directories pattern

## Architecture overview

### What's new in v4.0

1. **Versioning + migration** — `schema.md` gains `wiki_version` frontmatter and `## Migration Log` section. Skill detects mismatch on Step 0 and proposes a plan.
2. **РЕФЛЕКСІЯ block** — strict-template visible narrative printed at multi-triggers (TodoWrite-completion, pre-commit, memory flush, explicit user request).
3. **Tiered crystallization** — periodic nudge + commit/TodoWrite events ask the model "anything worth crystallizing?". Four tiers: bash → python → wiki page → SKILL.md.
4. **Telemetry sidecar** — `docs/wiki/.usage.json` (gitignored, Hermes-aligned dotfile) tracks view/use/patch counts and timestamps per page.
5. **`wiki status` operation** — new manual pull-model command that shows wiki state without requiring an active reflection trigger.
6. **Karpathy-aligned staleness** — content verification by LLM read+judge, not algorithmic timestamps. Telemetry serves prioritization, not flagging.

### File-system changes

```
docs/wiki/
  schema.md           ← +frontmatter (wiki_version), +## Migration Log
  index.md            ← unchanged
  log.md              ← unchanged
  concepts/           ← unchanged
  entities/           ← unchanged
  transcripts/        ← unchanged
  .usage.json         ← NEW — telemetry sidecar (gitignored)
```

### Skill file changes (SKILL.md in the wiki-skill repo)

- `version: "4.0.0"` in frontmatter
- New section `## Self-Improvement Loop` (РЕФЛЕКСІЯ format, triggers, crystallization)
- New section `## Versioning & Migration` (how to detect, how to plan)
- `Operation: Init` extends with detect-and-plan for version migration
- `Operation: Lint` becomes Karpathy-aligned content-verification pass; uses telemetry for prioritization only
- New `Operation: Wiki Status` (manual pull-model)

### Adopted Hermes philosophy

- ✅ Knowledge compounds across sessions (Karpathy + Hermes)
- ✅ Never auto-deletes — worst outcome is `archive/` (recoverable)
- ✅ User curates, LLM mechanizes (vetoable at every step)
- ✅ Telemetry sidecar pattern (atomic write, corrupt-tolerant, log-only failures, backfill missing keys)
- ✅ Dotfile for metadata, gitignored, per-clone
- ✅ Verbatim API naming (`view_count`/`use_count`/`patch_count`)
- ✅ Memory flush before context compression
- ✅ Periodic nudges as crystallization trigger (not algorithmic counters)

### Conscious divergences from Hermes

- **Loud reflection narrative** instead of silent telemetry — chosen for debug visibility
- **Strict reflection template** with mandatory fields — supports debug-readability
- **Multi-trigger reflection** (events: TodoWrite, pre-commit) plus periodic backup — natural punctuation in interactive coding
- **Anti-noise rule** — skip reflection if no edits in the block
- **Tiered crystallization (4 levels)** — bash/python/wiki page/skill — instead of single `skill_manage`
- **Embedded cleanup-prompt in reflection flow** — plus separate `wiki status` command for pull-model
- **Karpathy content-verification staleness** — instead of access-pattern-based stale flagging

## 1. Versioning + Migration

### `schema.md` frontmatter

```yaml
---
wiki_version: "4.0"
last_migration: "2026-05-01"
---

# Wiki Schema
... existing content ...

## Migration Log

### 4.0 (2026-05-01)
- Added `.usage.json` telemetry sidecar
- Added `wiki_version` frontmatter to this file
- Added РЕФЛЕКСІЯ block as required behavior in skill
- Added Tiered crystallization (no structural wiki changes)
- Added `wiki status` operation
- Reformulated Lint as Karpathy content-verification

### 3.0 (previous)
- Schema moved out of CLAUDE.md → `schema.md`, replaced with 1-line pointer
- Three-layer structure (concepts/entities/transcripts)

### 2.0 → 3.0 path
- (descriptions of what moved where)
```

### Skill behavior on Step 0 (discovery)

Every wiki operation begins with:

1. Read `schema.md` frontmatter → `wiki_version` of project.
2. Compare to skill's own `version` (from skill's `SKILL.md` frontmatter).
3. **Equal:** continue.
4. **Project older:** stop, generate migration plan, show as one block, ask once.
5. **Project newer:** warn and ask whether to continue (skill might be outdated).
6. **Missing `wiki_version` (legacy):** assume "3.0" or earlier, propose interactive identification, then migration.

### Migration plan format

Single approval block (variant D from brainstorm):

```
⚠️ Wiki версії 3.0, скіл — 4.0. Потрібна міграція.

План:
  1. Створити docs/wiki/.usage.json (порожній dict)
  2. Додати frontmatter у docs/wiki/schema.md (wiki_version: "4.0")
  3. Додати секцію ## Migration Log у docs/wiki/schema.md
  4. Додати "docs/wiki/.usage.json" до .gitignore
  5. Записати у docs/wiki/log.md: "## [2026-05-01] migration | 3.0 → 4.0"

Зроблю всі 5 кроків одразу? [y] / [n] / [пропусти крок N]
```

### Migration is explicit, not silent

Even though Hermes silently backfills missing JSON keys via `_empty_record()`, the wiki migration involves directory/file creation, gitignore changes, and frontmatter additions. These are user-visible changes that warrant explicit consent. Backfill of missing fields **inside** `.usage.json` records (forward-compat fields like `state`, `pinned`, `archived_at`) IS silent, Hermes-style. Only structural migrations require the plan-then-confirm flow.

## 2. РЕФЛЕКСІЯ block

### Format (strict template)

```
📚 РЕФЛЕКСІЯ — {YYYY-MM-DD HH:MM} — trigger: {todo-completion / pre-commit / memory-flush / explicit}

Дізнався: {one sentence — what new insight emerged}
Чому це краще: {one or two sentences — why it works, why this approach}
Зберіг у wiki: [[page-a]], [[page-b]]   (or: «не торкав wiki — нічого синтетичного»)
Автоматизував: {tier 1 bash / tier 2 python / tier 3 wiki page / tier 4 skill / нічого + причина}

[ONLY if structural files were touched (index.md / schema.md / log.md / .usage.json):]
Перевірив:
  ✅ {what was updated}
  ✅ {what was updated}
  ⚠️ {what was skipped and why}

──────────────────────────────────────────
🧹 Показати список того, що в wiki могло застаріти?
   Я лише покажу — нічого не змінюватиму без твого слова.
   [y] показати  /  [n] продовжуємо
```

### Triggers

| Event | Fires reflection? |
|---|---|
| Last todo in TodoWrite → completed | ✅ |
| TodoWrite cleared | ✅ |
| Pre-commit moment (before `git commit`) | ✅ |
| Both within 60 seconds | One block, deduplicated |
| Memory flush (context compression imminent) | ✅ — guaranteed turn |
| Periodic nudge: every 15 tool-calling iterations | ✅ — backup signal |
| User explicit "зроби рефлексію" | ✅ |
| Read-only block (no edits/writes/side-effects) | ❌ anti-noise rule |
| Trivial single edit without TodoWrite/commit | ❌ |

### Field rules

- **Дізнався** must contain a real insight or be explicit about its absence: «Дізнався: нічого нового — стандартна реалізація за патерном [[X]]».
- **Чому це краще** appears only if "Дізнався" had real content. Otherwise omit the line entirely.
- **Зберіг у wiki** is `[[wikilinks]]` list, or explicit «не торкав wiki».
- **Автоматизував** is mandatory. If nothing crystallized: `нічого — операція разова` / `нічого — порогу не досягнуто (поточний M/3)` / `нічого — юзер відмовив раніше`.

### Anti-noise rule

Reflection skips entirely if the block contained only `Read` operations (no `Edit`, no `Write`, no `Bash` with side-effects). There's nothing to reflect on; printing forced narrative would violate the debug-readability premise (signal would drown in noise).

## 3. Tiered Crystallization

### Tier matrix

| Tier | Artifact | Storage | What the model judges (during a periodic nudge) |
|---|---|---|---|
| 1. Bash one-liner | shell script ≤20 lines | `scripts/{name}.sh` in project | "I've run a similar simple command multiple times this session — would a one-liner script save tokens?" |
| 2. Python script | Python with args, error handling | `scripts/{name}.py` | "I've run a multi-step flow with conditions/parsing more than once — does it justify a Python script?" |
| 3. Wiki concept page | new `concepts/{name}.md` | `docs/wiki/concepts/` | "I'm explaining the same concept again across sessions and no existing page covers it" |
| 4. Full skill | new `~/.claude/skills/{name}/SKILL.md` | user-level skills | "This is a multi-step flow with trigger conditions, reusable across projects — warrants a full skill" |

**Note:** these are heuristics for the model's holistic judgment during a periodic nudge — NOT counters the skill maintains algorithmically. Hermes pattern: model judges, skill provides the prompt.

### Trigger model (Hermes-aligned)

NOT an algorithmic counter on normalized commands. Hermes's `tools/skill_manager_tool.py` is purely CRUD; the trigger is **periodic nudge** — every N tool-calling iterations the agent gets a system reminder "consider crystallizing".

| Trigger | Default | Behavior |
|---|---|---|
| Periodic nudge | Every 15 tool-calling iterations | Skill injects hint into next turn: "🔍 Зробив 15 операцій — є щось варте автоматизації?". Agent judges holistically |
| Pre-commit | Before `git commit` | Hard trigger (paired with reflection) |
| TodoWrite-completion | Last todo → completed | Hard trigger (paired with reflection) |
| Pre-compression flush | Detect imminent context compression | Guaranteed turn for writing to wiki/scripts |
| Explicit user | "save this as bash/python/skill" | Manual override |
| Disabled | `nudge_interval: 0` in `schema.md` | User can disable periodic, keep hard triggers |

### Proposal flow

Skill **proposes**, never creates silently:

```
🔁 Помічаю патерн: за останні 15 ітерацій ти 3 рази робив curl з cookie better-auth + grep по JSON.
   Tier 1 (bash one-liner): scripts/auth-curl.sh
   
   Створити? [y] / [n] / [пізніше]
```

- `y` → creates file, shows content, stages for commit; reflection records `Автоматизував: tier 1 — scripts/auth-curl.sh`.
- `n` → not created; skill records refusal for this normalized pattern in this session (don't re-propose).
- `пізніше` → not created; skill may re-propose at next nudge.

### Tier-3 (wiki page) judgment

Triggered when the agent recognizes a **conceptual** repetition (3+ sentences explaining the same system behavior across sessions, not covered by any existing wiki page). Periodic nudge is the right framing: model judges, not normalized-string counter.

### Tier-4 (full skill)

Highest bar — skill **delegates** to `superpowers:writing-skills` instead of creating SKILL.md itself:

```
🔁 Цей flow підходить для повноцінного скіла: 5 кроків, чіткі тригери, реюзабельно.
   Запропонувати створити через writing-skills? [y/n]
```

This honors separation of concerns: writing-skills knows skill conventions; wiki-skill knows wiki conventions.

### Anti-noise rules

- Don't propose if user already refused this normalized pattern in this session
- Don't propose for ambient commands (`ls`, `cd`, `git status`)
- Don't propose if arguments are radically different each time (looks like ad-hoc exploration)
- Don't propose tier 1/2 for one-shot operations (deploy, migration), even if recurring

## 4. Telemetry sidecar (`.usage.json`)

### Path

`docs/wiki/.usage.json` — dotfile, sibling to `schema.md`/`index.md`/`log.md`. Hermes pattern.

### Gitignored

Telemetry is per-clone, not shared. In team contexts, sharing would create constant merge noise (every read by every dev/CI generates a diff). Hermes pattern: telemetry lives in user-local hidden state, not project-shared content.

Skill bootstrap (init/upgrade) adds `docs/wiki/.usage.json` to `.gitignore` automatically.

### Record structure (Hermes-verbatim API, semantic adapted to wiki)

```json
{
  "concepts/purchase-flow.md": {
    "view_count": 0,
    "use_count": 0,
    "patch_count": 0,
    "last_viewed_at": null,
    "last_used_at": null,
    "last_patched_at": null,
    "created_at": "2026-05-01T14:32:00Z",
    "state": "active",
    "pinned": false,
    "archived_at": null
  }
}
```

Semantic mapping:

| Hermes (skills) | Wiki adaptation | Increment trigger |
|---|---|---|
| `view_count` | view = consult | Skill reads page via `Read` tool (level 1 disclosure) |
| `use_count` | use = synthesis-applied | Page mentioned as `[[wikilink]]` in a new or updated page |
| `patch_count` | patch = modified | Skill performs `Edit`/`Write` on the page |

### Forward-compat fields

`state`, `pinned`, `archived_at` are present even though v4.0 doesn't use them. This is forward compatibility — when v5+ adds curator/auto-transitions, no migration needed.

### Mutator API (Python-style pseudo, internal to skill)

```python
bump_view(path)    # Read tool fired on the page
bump_use(path)     # page cited via [[wikilink]] in new/edited page
bump_patch(path)   # Edit/Write fired on the page
forget(path)       # delete record (used by cleanup/split)
report()           # full sortable list for cleanup-prompt and lint
```

### Tolerance (Hermes-aligned)

- Atomic write: `tempfile.mkstemp` + `os.replace` (Python) or equivalent.
- Corrupt read → return `{}`. Don't restore from template; rebuild via subsequent writes.
- Write fail → log only, **do not raise**. Telemetry never blocks the wiki operation.
- Missing keys on read → backfill via `_empty_record()` defaults.

### Role: prioritization, not flagging

Telemetry does NOT determine "stale". It informs:

| Field | Used for |
|---|---|
| `view_count`, `last_viewed_at` | Activity overview in `wiki status`. Prioritize high-view pages first when running content-verification |
| `use_count`, `last_used_at` | Show "central pages" — high cite-count = nodes with cascade impact if drifted |
| `patch_count`, `last_patched_at` | Sortable for "longest unpatched among active" — top candidates for content-verification read |
| `created_at` | Display in status output |

## 5. Karpathy-aligned staleness (Lint reformulated)

### Principle

Staleness is a content property, verified by LLM read+judgment. NOT by timestamps, NOT by git activity, NOT by source-file mtime drift. The skill's existing Lint check #1 already documents this:

> Read each wiki page and verify key claims against current code: do referenced files/functions still exist? Do described flows match current implementation? Are entity relationships accurate? Has the data model changed since last update?

This is the work LLMs don't get bored doing.

### Why algorithmic approaches were rejected

- "30 days no view" — false positives for rarely-read-but-critical pages (security, incident, migration recipes)
- Project-activity gating via `git log` — fails for non-code projects (research, personal notes, AI conversations)
- Source-mtime drift — only works when wiki pages have `## Sources` pointing to code files, fails otherwise
- All algorithmic approaches conflate "rarely accessed" with "outdated"

### Smart staleness flow

When user opts into staleness check (via reflection cleanup-prompt `[y]` or via `wiki status` action choice):

1. **Skill proposes a subset** to verify (full-wiki check is expensive in tokens):
   ```
   📊 У wiki 23 сторінки. Перевіряти всі — багато контексту.
      Можу почати з:
      [a] Топ-5 найбільш редагованих за останній час (highest drift risk)
      [b] Топ-5 найдовше unverified (нема recent edit'у і claims могли застаріти)
      [c] Усі сторінки за категорією (вкажи: concepts/entities/transcripts)
      [d] Конкретні: вкажи [[page-names]]
   ```

2. **For each selected page, skill reads in full** and verifies claims:
   - Files/functions/classes in `## Sources` — do they exist? (file existence check, not mtime)
   - Described flows — match current code? (read code, compare to text)
   - Entity relationships in frontmatter — accurate?
   - Internal `[[wikilinks]]` — resolve?
   - Stated counts/inventories — match reality? (per the no-derivable-counts convention, these shouldn't exist; if found, flag for deletion)

3. **Skill reports findings**, doesn't auto-flag:
   ```
   📋 Перевірка [[purchase-flow]]:
     ✅ Sources existing: usePurchases.ts, schema.ts, 0023_*.ts
     ⚠️ Claim "знижки бувають discountPct і discountAbs" — у схемі тепер також
        per-item discount, на сторінці не згадано (рядок 47)
     ⚠️ Wiki link [[old-receive-flow]] не резолвиться — сторінку видалено?
     ✅ Решта claims — підтверджуються
   
   Дії: [онови / лиши як є / pin / видали]
   ```

### Passive staleness signals (no LLM read needed)

These can be flagged automatically without content verification, because they're checked at ingest/edit time:

- **Cross-ref drift** — `[[wikilink]]` to non-existent page
- **Schema drift** — page frontmatter uses category/type not in current `schema.md`

### Pin protection

Pages flagged in frontmatter as `security` / `incident` / `migration` / `compliance` / `recovery` (or filename matching these prefixes) get auto-suggested for pin during ingest:

```
Сторінка [[secret-rotation-recipe]] виглядає як критично-рідкісна. 
Запропонувати pin? [y/n]
```

`pinned: true` in `.usage.json`:
- Skipped by content-verification proposals
- Refused by `видали` action (must `wiki unpin <path>` first)
- Hermes-aligned: pin is a hard fence

## 6. `wiki status` operation (manual pull-model)

### When invoked

User says: "wiki status", "вікі статус", "як справи у вікі", "огляд wiki". Manual only — never auto-fired.

### Output

```
📊 Wiki Status — docs/wiki/

Версія: 4.0 (актуальна)
Сторінок: 23 (concepts: 18, entities: 4, transcripts: 1)
Прив'язаних binаrіев в archive/: 7

Активність (з .usage.json):
  Найчастіше консультуються:  [[purchase-flow]] (15 view), [[intake-stock]] (12)
  Найбільш цитуються:         [[dose-dimensions]] (8 use), [[stock-pickings]] (6)
  Найбільш редагуються:       [[course-builder]] (5 patch), [[intake-stock]] (3)

Pinned:
  • [[secret-rotation-recipe]]
  • [[incident-2026-02-15]]

⚠️ Знайдено пасивно:
  • Cross-ref drift: [[old-auth-middleware]] → [[middleware-rules]] (видалено)
  • Schema drift: [[doc-template]] використовує category="legacy" (нема в schema)
  
──────────────────────────────────────────
🔍 Хочеш зробити content-check (LLM читає сторінки, верифікує claims)?

  [a] Топ-5 найбільш редагованих (drift risk найвищий)
  [b] Топ-5 найдовше unverified
  [c] Конкретні сторінки — вкажи [[page-names]]
  [пасивні fix'и]:
    [1] cross-ref у [[old-auth-middleware]]
    [2] schema-drift у [[doc-template]]
  [n] нічого
```

`a/b/c` → invokes Karpathy content-verification flow (section 5).
`1/2` → applies passive fix without content read (link removal/replacement, schema update).

## 7. Bootstrap (init operation, extended)

### State detection (from Step 0)

| State | Condition | Action |
|---|---|---|
| `absent` | No `docs/wiki/` exists | Bootstrap from scratch |
| `legacy` | Wiki exists but no `wiki_version` in `schema.md` frontmatter | Identify version, then migrate |
| `current` | `wiki_version` matches skill's version | Continue |
| `older` | `wiki_version` < skill's version | Generate migration plan |
| `newer` | `wiki_version` > skill's version | Warn, ask whether to continue |

### Project type auto-suggest (only for `absent`)

Skill scans project root for type signals — purely to seed `entities/` categories. **Does not affect any other behavior.**

| Signal | Suggested entities categories |
|---|---|
| `package.json` / `tsconfig.json` | `components/`, `services/` |
| `Cargo.toml` | `modules/`, `traits/` |
| `requirements.txt` / `pyproject.toml` | `modules/`, `classes/` |
| `go.mod` | `packages/`, `interfaces/` |
| no code signals | `people/`, `documents/` |

User can override or pick custom categories.

### Bootstrap plan format (for `absent`)

```
📂 Створюю нову wiki у docs/wiki/

План:
  1. docs/wiki/schema.md — frontmatter (wiki_version: "4.0") + три розділи + Migration Log
  2. docs/wiki/index.md — порожній з трьома секціями (Concepts | Entities | Transcripts)
  3. docs/wiki/log.md — порожній з заголовком
  4. docs/wiki/concepts/ — порожня папка
  5. docs/wiki/entities/ — пропонована структура для {detected_type}: {category-list}
  6. docs/wiki/transcripts/ — порожня папка
  7. docs/wiki/.usage.json — порожній dict
  8. archive/ — поза wiki (gitignored)
  9. CLAUDE.md — додати 1-line pointer "Wiki schema → docs/wiki/schema.md"
  10. .gitignore — додати "archive/" і "docs/wiki/.usage.json"

[y] так, створи все  /  [n] скасувати
```

## 8. Cleanup-flow (consolidated)

### Two entry points, same flow

1. **Embedded prompt in РЕФЛЕКСІЯ** (passive, after major work) — `🧹 Показати список того, що в wiki могло застаріти?`
2. **`wiki status` command** (active, on-demand) — full status output with action choices

Both lead to the same content-verification + passive-fix flow described in sections 5 and 6.

### Action menu (per-page)

| Action | Behavior |
|---|---|
| `глянь і онови` | Skill reads page + cited code, updates content synchronously |
| `видали` | `forget(path)` in `.usage.json` + delete file + remove from `index.md` |
| `pin` | `pinned: true` in `.usage.json` — future cleanup-prompts skip |
| `merge` | Propose merging two pages into one; triggers separate flow |
| `розбий` | Invokes existing `split` operation |
| `глянь обидві` | Verbose diff + recommendation (for contradictions) |

### Safety layers

1. **Double confirmation for `видали`** — skill re-shows the list, waits for `yes` (not `y`).
2. **Snapshot before destructive ops** — before `видали` / `merge` / `розбий`, skill commits current state with message `chore(wiki): snapshot before {operation}`. Rollback = `git revert`.
3. **Pin protection** — even on `видали` for a pinned page, skill refuses with warning. User must `wiki unpin <path>` first.

### Telemetry updates after actions

| Action | Telemetry effect |
|---|---|
| `видали` | `forget(path)` |
| `merge` | `forget(merged-into-other)`; target gets `bump_patch` |
| `pin` / `unpin` | toggle `pinned` field |
| `глянь і онови` | `bump_patch(path)` |

## Implementation phases (preview for plan-writing)

This spec deliberately does NOT prescribe phasing or task ordering — that's writing-plans territory. High-level groupings the plan author should consider:

- **Phase A:** versioning skeleton (`wiki_version` frontmatter + Migration Log + version-comparison logic in Step 0)
- **Phase B:** telemetry sidecar (`.usage.json` + mutator API + bootstrap creation + gitignore)
- **Phase C:** РЕФЛЕКСІЯ block (template + triggers + anti-noise + integration with all wiki ops)
- **Phase D:** Tiered crystallization (periodic nudge + proposal flow + tier-4 delegation to writing-skills)
- **Phase E:** `wiki status` operation
- **Phase F:** Karpathy-reformulated Lint (content-verification + prioritization + passive fixes)
- **Phase G:** Init bootstrap-extension (state detection + project-type suggest + plan format)
- **Phase H:** Cleanup-flow consolidation (action menu + safety layers + pin protection)

Phases A and B are foundational; others can run in parallel pairs (C+D, E+F, G+H).

## Open questions (deferred to implementation)

- **Periodic nudge mechanism** — skill itself can only emit instructions in SKILL.md saying "after every N tool calls, do X". The harness doesn't currently expose iteration counters to skills. Implementation may need to rely on instruction-based discipline + commit/TodoWrite hard-triggers as the actual reliable signals. Investigate at plan-writing time.
- **Memory flush detection** — Claude Code doesn't expose "imminent compression" signals to skills. The mechanism may need to fall back to user-explicit triggers ("save before compress"). Investigate.
- **Periodic nudge config knob** — `nudge_interval: 0` would live where? In `schema.md` frontmatter, or in CLAUDE.md, or in user-level skill settings. Decide at plan-writing.
- **Pin auto-suggest tags** — exact list of frontmatter values that trigger pin proposal. Initial set: `security`, `incident`, `migration`, `compliance`, `recovery`. Plan author should validate with examples.

## References

- Karpathy LLM Wiki pattern: https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f
- Hermes-Agent docs: https://hermes-agent.nousresearch.com/docs/
- Hermes `tools/skill_usage.py`: https://github.com/NousResearch/hermes-agent/blob/main/tools/skill_usage.py
- Hermes `agent/curator.py`: https://github.com/NousResearch/hermes-agent/blob/main/agent/curator.py
- Hermes `tools/skill_manager_tool.py`: https://github.com/NousResearch/hermes-agent/blob/main/tools/skill_manager_tool.py
- Hermes config defaults (nudge intervals): https://github.com/NousResearch/hermes-agent/blob/main/cli-config.yaml.example
- Existing wiki skill SKILL.md: `~/Library/CloudStorage/Dropbox/AI/claude-wiki-skill/SKILL.md`
