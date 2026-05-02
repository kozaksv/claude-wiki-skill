---
name: wiki
version: "4.0.0"
description: >
  Manage a project's LLM Wiki (Karpathy pattern) — three layers (concepts,
  entities, transcripts) plus archive/ for binaries. Eight operations:
  init, ingest-source, ingest-binary, query, lint, cleanup, split, wiki-status.
  Triggers: "ingest"/"додай до wiki/вікі", "wiki/вікі lint/query/cleanup/status",
  "оновити/перевір wiki/вікі", "що каже wiki про...", "знайди у вікі",
  any binary in tmp/. "вікі" = "wiki". Also use PROACTIVELY after feat/
  refactor commits and when binaries land in tmp/.
---

# LLM Wiki (Karpathy Pattern)

A persistent, compounding knowledge base maintained by Claude. Instead of re-discovering knowledge each session, the wiki accumulates synthesized understanding across conversations.

This skill is **project-agnostic** — it discovers the wiki location automatically.

## Philosophy

From Karpathy's original pattern (https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f):

> _"the LLM is rediscovering knowledge from scratch on every question. There's no accumulation."_

> _"The tedious part of maintaining a knowledge base is not the reading or the thinking — it's the bookkeeping. Humans abandon wikis because the maintenance burden grows faster than the value. LLMs don't get bored, don't forget to update a cross-reference, and can touch 15 files in one pass."_

> _"connections between documents are as valuable as the documents themselves"_ (Vannevar Bush's Memex)

The wiki is not documentation. It is synthesized understanding that compounds across sessions. Cross-references are first-class — a page with no `[[wikilinks]]` is suspect.

## Division of Labor

Karpathy draws a sharp line: the human curates and directs; the LLM does everything mechanical.

| Human | LLM |
|---|---|
| Curate sources (decide what's worth ingesting) | Read and synthesize those sources |
| Direct the analysis (ask good questions) | Summarize, cross-reference, update pages |
| Think about what it all means | All bookkeeping: index, log, `[[wikilinks]]`, `## See also` |
| Veto LLM proposals on init / cleanup / schema changes | Propose, never execute destructive ops without consent |

> _"You never (or rarely) write the wiki yourself — the LLM writes and maintains all of it."_

If you catch yourself hand-editing wiki pages page-by-page, it's a skill failure — prefer running the relevant operation.

## Modularity

> _"Everything mentioned above is optional and modular — pick what's useful, ignore what isn't."_

Not every project needs every layer or operation:

- **No binary documents (PDFs, contracts, images)?** → skip `entities/` and `transcripts/`. Run only `concepts/`. Skip `ingest-binary` and `doc-extract` dependency.
- **Small wiki (< 20 pages)?** → lint once per quarter, not every 10 sessions. Skip `split` entirely.
- **No raw sources dir?** → `ingest-source` still works from code diffs and conversation context; don't force a `specs/` folder.
- **Schema minimal?** → `schema.md` can be 10 lines. No need for populated Entity Categories or Document Types until the project actually has categories.

The eight operations are a **palette**, not a checklist. A code project might use only `ingest-source` + `query` + `lint`. A research project might lean heavily on `ingest-binary`. Adapt.

## Step 0: Discover Wiki Location and Schema

**Before any operation**, locate both the wiki directory and its schema. Follow this sequence:

1. **Find CLAUDE.md** — look in the current working directory, then walk up parent directories until found
2. **Read CLAUDE.md's Wiki section** — look for a `## Wiki` section that declares wiki paths (e.g., "Wiki (`docs/wiki/`)")
3. **Verify wiki exists** — check that the discovered directory contains `index.md`
4. **If no Wiki section in CLAUDE.md** — search for `docs/wiki/index.md` relative to CLAUDE.md location
5. **Locate schema** — wiki schema (layers, operations, conventions, `Entity Categories`, `Document Types`, `File Naming`) lives in exactly one of:
   - **Preferred (v3+):** `{wiki}/schema.md` — canonical location, keeps wiki metadata out of CLAUDE.md resident context
   - **Legacy (v1–v2):** sections inside `CLAUDE.md` itself (`## Wiki`, `## Entity Categories`, `## Document Types`, `## File Naming`)

   Try `{wiki}/schema.md` first. Fall back to CLAUDE.md sections. When both exist, prefer `schema.md` and flag the duplication during next lint.
6. **If wiki not found at all** — tell the user: "No wiki found. Would you like me to initialize one?" Then delegate to the **Init (bootstrap-aware)** operation below — it detects project state (5-state model: `absent` / `legacy` / `current` / `older` / `newer`), creates the three-layer structure (`concepts/`, `entities/`, `transcripts/`) with `archive/` outside git, proposes migration for existing artifacts, and writes schema to `{wiki}/schema.md`.
7. **Compare versions** — read `wiki_version` from `{wiki}/schema.md` frontmatter (if absent → state = `legacy`). Read your own `version` from this SKILL.md frontmatter. Determine state per the Versioning & Migration table. If state ≠ `current`, halt the requested operation and follow the migration flow.

All paths below use `{wiki}` as placeholder for the discovered wiki directory (e.g., `docs/wiki/`). Replace mentally with the actual path.

**CRITICAL: Never create a second wiki.** If you find an existing wiki, use it. If CLAUDE.md references a wiki path, trust it. Only create a new wiki when none exists anywhere in the project.

**Why schema.md is preferred over CLAUDE.md sections:** CLAUDE.md loads into resident context on every session start, so every byte there is paid on every turn. Wiki schema is operational metadata for the wiki itself — it's needed only during wiki operations, not on every conversation. Moving it to `{wiki}/schema.md` reduces resident-context bloat without losing anything, because wiki operations always discover the wiki first anyway.

_Note: this is a v3 evolution from Karpathy's original pattern, which placed schema in CLAUDE.md/AGENTS.md. The rationale is purely operational (resident-context cost); the spirit (schema as co-evolved governance document) is preserved. Projects following the original pattern (v1–v2) continue to work via the CLAUDE.md fallback._

## Versioning & Migration

Every wiki has a version stored in `{wiki}/schema.md` frontmatter:

```yaml
---
wiki_version: "4.0"
last_migration: "2026-05-01"
---
```

The skill itself has a version in this file's frontmatter (`version: "4.0.0"`).

### State detection on Step 0

After locating the wiki and reading `schema.md`, compare versions:

| State | Condition | Action |
|---|---|---|
| `current` | `wiki_version` == skill major version | Continue with operation |
| `legacy` | Wiki exists but `wiki_version` field absent in frontmatter | Identify version interactively, then propose migration |
| `older` | `wiki_version` < skill version | Generate migration plan, ask user once |
| `newer` | `wiki_version` > skill version | Warn user, ask whether to continue |
| `absent` | No wiki found | Defer to Init operation (bootstrap) |

### Migration plan format

For `older` and `legacy` states, present a single approval block:

```
⚠️ Wiki версії 3.0, скіл — 4.0. Потрібна міграція.

План:
  1. {step 1 description}
  2. {step 2 description}
  ...

Зроблю всі N кроків одразу? [y] / [n] / [пропусти крок N]
```

Wait for explicit `y`. On `n`, abort the operation. On `пропусти крок N`, exclude that step and re-confirm.

### Migration is explicit, not silent

Wiki migrations involve directory/file creation, gitignore changes, and frontmatter additions — user-visible changes that warrant explicit consent. Backfill of missing fields **inside** `.usage.json` records (forward-compat fields like `state`, `protected`, `archived_at`) IS silent. Only structural migrations require the plan-then-confirm flow.

### Migration Log

`schema.md` carries a `## Migration Log` section that records what changed between versions. Each entry:

```markdown
### 4.0 (2026-05-01)
- Added `.usage.json` telemetry sidecar
- Added `wiki_version` frontmatter to schema.md
- Added РЕФЛЕКСІЯ block as required behavior
- Added Tiered crystallization
- Added `wiki status` operation
- Reformulated Lint as Karpathy content-verification
```

When proposing a migration plan, the skill reads its own SKILL.md frontmatter `version` and the wiki's `schema.md` `## Migration Log` to determine what changed.

### Optional config knobs in `schema.md` frontmatter

Optional `nudge_interval: <N>` in `schema.md` frontmatter overrides the default crystallization periodic nudge frequency (default ~15 tool-calling iterations). Set to `0` to disable the periodic nudge while keeping hard triggers (pre-commit, TodoWrite-completion, explicit user) active. See `## Self-Improvement Loop` → `### Tiered Crystallization` for the trigger model.

## Telemetry Sidecar (.usage.json)

Each wiki carries a small sidecar file `{wiki}/.usage.json` that tracks per-page activity. It is gitignored, per-clone, and never blocks an operation if it goes wrong. The sidecar exists to **prioritize** what to read or verify next — never to flag pages as stale on its own. Staleness is judged by reading content (see `## Operation: Lint`).

### Path

`{wiki}/.usage.json` — dotfile, sibling to `schema.md`, `index.md`, `log.md`. Created during Init and on legacy → v4 migration.

### Gitignored

Telemetry is per-clone, not shared. In team contexts, sharing would create constant merge noise (every read by every dev/CI generates a diff). The skill bootstrap (init / migration) adds `{wiki}/.usage.json` to `.gitignore` automatically.

### Record structure

The file is a JSON dict — keys are page paths relative to `{wiki}/` (e.g. `concepts/purchase-flow.md`), values are records with this shape:

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
    "protected": false,
    "archived_at": null
  }
}
```

All ten fields are present for every record. Timestamps are ISO 8601 UTC. `state`, `protected`, `archived_at` are forward-compat fields (v5+ will use them for curator/auto-transitions); v4.0 reads them as defaults but does not act on them.

**Field-rename compat (v4.0.0 → v4.0.x): `pinned` → `protected`.** The earliest v4.0.0 release used `pinned` as the field name; subsequent commits renamed it to `protected` for clearer English semantics matching the user-facing «захищена» term. **On read, accept either name as truthy** — old records with `pinned: true` are treated as `protected: true`. **On the first write to a record carrying the legacy `pinned` field**, silently migrate: copy the value to `protected`, drop the old `pinned` key. No version-bump prompt for this — it's a field-level backfill (per Versioning & Migration silent-backfill rule).

### Semantic mapping

| Field | Meaning in wiki | When to increment |
|---|---|---|
| `view_count` / `last_viewed_at` | view = consult | You read the page via the `Read` tool (level-1 disclosure during Query, Lint, Ingest) |
| `use_count` / `last_used_at` | use = synthesis-applied | The page is cited as `[[wikilink]]` in a new or updated page body |
| `patch_count` / `last_patched_at` | patch = modified | You perform `Edit` or `Write` on the page |
| `created_at` | birth timestamp | Set once on first record creation; never changes |
| `state`, `protected`, `archived_at` | forward-compat | v4.0 does not write these except defaults (`"active"`, `false`, `null`) |

### Mutator API (instructional)

These are the actions you must perform on `.usage.json` during operations. Read the file, mutate the in-memory dict, write atomically (see Tolerance below). If a path key is missing on a `bump_*`, create the record with all ten default fields, then increment.

| Action | When to call | Effect |
|---|---|---|
| `bump_view(path)` | After reading a wiki page with the `Read` tool | `view_count += 1`; `last_viewed_at = now`; create record if absent |
| `bump_use(path)` | After adding a new `[[wikilink]]` to `path` from another page's body | `use_count += 1`; `last_used_at = now`; create record if absent |
| `bump_patch(path)` | After `Edit`/`Write` on the page (including new file creation) | `patch_count += 1`; `last_patched_at = now`; create record with `created_at = now` if absent |
| `forget(path)` | After `Cleanup` deletes an orphan, after `Split` deletes the original | Remove the key from the dict |
| `report()` | During `Lint` and `wiki status` | Return the full sortable list (path + all fields) for prioritization |

Translate these into concrete file mutations: read JSON, modify dict, write back atomically. Do not maintain counters in memory across turns — re-read the file each operation.

### Tolerance rules

The wiki operation must never fail because of telemetry. Apply these rules:

- **Atomic write** — write to a temp file in the same directory, then rename over the target. Never partial-write `.usage.json` directly.
- **Corrupt read → `{}`** — if the file is unparseable JSON, treat it as an empty dict and continue. Do not restore from a template; subsequent writes will rebuild it.
- **Write fail → log only, do not raise** — if you cannot write the sidecar (disk full, permission denied, etc.), surface a warning to the user but let the wiki operation succeed. Telemetry is best-effort.
- **Backfill missing keys silently** — if a record exists but lacks newer fields (e.g. an old record without `protected`), fill the missing fields with defaults (`"active"`, `false`, `null`) on read. This is the only silent-migration path; structural migrations require explicit consent (see `## Versioning & Migration`).

### Role: prioritization, not flagging

Telemetry never marks a page as "stale". It surfaces signals that help you choose where to look first:

| Field | Used for |
|---|---|
| `view_count`, `last_viewed_at` | "Hot" pages — high-view = consulted often, prioritize for content-verification |
| `use_count`, `last_used_at` | "Central" pages — high cite-count = nodes whose drift cascades through the wiki |
| `patch_count`, `last_patched_at` | "Drift risk" — sort by largest `patch_count` and oldest `last_patched_at` for `Lint` candidates |
| `created_at` | Display in `wiki status` output, used for "longest unverified" sorting |

Lint and `wiki status` use these to propose a small subset of pages to read in full. The actual judgment ("is this stale?") still requires a content read.

## Self-Improvement Loop

The wiki is not just a passive store — it is a feedback loop. After meaningful work the agent emits a **РЕФЛЕКСІЯ block** (a strict-template visible narrative) that surfaces what was learned, where it was filed, and whether anything is worth automating. This is the wiki's debug-readability layer: it lets the user (and the agent itself, on the next session) see how knowledge accumulated.

### Overview

Reflection has two purposes:

1. **Visible reasoning** — a short, predictable block that lets the user verify the agent didn't just edit files, it actually thought about the diff. Hermes-style silent telemetry stays in `.usage.json`; РЕФЛЕКСІЯ is the loud counterpart.
2. **Crystallization trigger** — every reflection is an opportunity to ask "is this pattern worth saving as a script / wiki page / skill?". Tiered Crystallization is documented in the subsection below; the reflection block names what was crystallized in the `Автоматизував:` field (one of `tier 1 — scripts/...sh`, `tier 2 — scripts/...py`, `tier 3 — concepts/....md`, `tier 4 — delegated to writing-skills`, or `нічого` with reason).

Reflection fires on **events**, not on a timer the skill maintains. The agent is responsible for self-checking the trigger conditions on every operation — there is no harness-side counter.

### РЕФЛЕКСІЯ block format (strict template)

Print this verbatim at the end of a triggered turn. Do not paraphrase the field labels — they are part of the contract:

```
📚 РЕФЛЕКСІЯ — {YYYY-MM-DD HH:MM} — trigger: {todo-completion / pre-commit / memory-flush / explicit / periodic-nudge}

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

The trailing horizontal-rule + cleanup-prompt is part of the block — see "Cleanup-prompt" below for the safety contract behind it.

### Triggers

| Event | Fires reflection? | Notes |
|---|---|---|
| Last todo in TodoWrite → `completed` | ✅ | Hard event — fires once per todo-list completion |
| TodoWrite cleared (all todos removed) | ✅ | Treat as completion |
| Pre-commit moment (immediately before `git commit`) | ✅ | Hard event — paired with crystallization nudge |
| Both above within ~60 seconds | One block, deduplicated | Don't double-fire when a todo completes and you commit right after |
| Memory flush (user says "save before /compress" or "flush memory") | ✅ | User-explicit — the harness does not signal compression to skills |
| Periodic nudge: every ~15 tool-calling iterations since last reflection | ✅ — backup signal | Self-checked — see note below |
| User explicit ("зроби рефлексію", "reflect now") | ✅ | Manual override |
| Read-only block (no `Edit`, no `Write`, no `Bash` with side-effects) | ❌ | Anti-noise rule |
| Trivial single edit without TodoWrite or commit context | ❌ | Anti-noise rule |

**About periodic-nudge and memory-flush:** these are not harness-emitted events. The wiki skill is purely instructional Markdown; it has no way to count tool calls or detect imminent context compression from outside. The discipline is:

- **Periodic nudge** — on every wiki operation, briefly check whether ~15 tool calls have happened since the last reflection block was emitted. If yes, fire a reflection. This is approximate self-checking, not a precise counter.
- **Memory flush** — only fires on the user-explicit phrase ("save before /compress" / "збережи перед стисненням" / "flush memory"). Document in your reply that you cannot detect impending compression unprompted.

Treat hard events (TodoWrite-completion, pre-commit, explicit user) as the reliable signals. Periodic nudge is a backup.

### Field rules

- **Дізнався** must contain a real insight or be explicit about its absence: «Дізнався: нічого нового — стандартна реалізація за патерном [[X]]». Never leave the field empty or write filler like "багато всього".
- **Чому це краще** appears only if "Дізнався" had real content. Otherwise omit the line entirely (do not write "n/a" or "—").
- **Зберіг у wiki** is a `[[wikilinks]]` list, or the explicit phrase «не торкав wiki — нічого синтетичного». If you touched only `log.md` / `index.md` (bookkeeping), say so explicitly: «лише log.md / index.md — bookkeeping».
- **Автоматизував** is mandatory. If nothing crystallized, write one of: `нічого — операція разова` / `нічого — порогу не досягнуто (поточний M/3)` / `нічого — юзер відмовив раніше` / `нічого — патерн не повторюється`. The user wants to see that the question was asked.
- **Перевірив** appears only when structural files (`index.md`, `schema.md`, `log.md`, `.usage.json`) were modified in this block. Use ✅ for confirmed updates, ⚠️ for intentional skips with one-line reason. Skip the section entirely if no structural files were touched.

### Anti-noise rule

Reflection skips entirely if the block contained **only** `Read` operations — no `Edit`, no `Write`, no `Bash` with side effects (anything beyond `ls`/`grep`/`cat`/`git log`/`git status`/`wc`/`find` etc. counts as a side effect). There's nothing to reflect on; printing forced narrative would violate the debug-readability premise — signal would drown in noise.

Concretely:

- A pure Query operation that only read pages → no reflection.
- A Lint that produced a report but didn't apply fixes → no reflection (it's a read-only survey).
- A `wiki status` invocation → no reflection (meta-operation, no edits).
- An Ingest-Source that read 5 pages and edited 3 → reflection fires.
- An Init that created files → reflection fires (structural changes always reflect).

If unsure, lean toward firing reflection — over-reporting is recoverable, under-reporting hides reasoning. Anti-noise is for the obvious cases (literally nothing was written).

### Tiered Crystallization

The reflection's `Автоматизував:` field isn't decorative — it's the agent's answer to a real question: **is anything from this block worth saving so the next session doesn't have to re-derive it?** When the answer is yes, the agent **proposes** (never silently creates) one of four tiers. Choose the lowest tier that captures the value; over-tiering creates maintenance debt.

| Tier | Artifact | Storage | What the model judges (during a periodic nudge) |
|---|---|---|---|
| 1. Bash one-liner | shell script ≤20 lines | `scripts/{name}.sh` in project | "Same simple command repeated this session — would a one-liner save tokens / typos next time?" |
| 2. Python script | Python with args + error handling | `scripts/{name}.py` in project | "Multi-step flow with conditions or parsing repeated more than once — does it justify a real script?" |
| 3. Wiki concept page | new `concepts/{name}.md` | `{wiki}/concepts/` | "I've explained the same concept across sessions and no existing page covers it — file it so the next query finds it." |
| 4. Full skill | new `~/.claude/skills/{name}/SKILL.md` | user-level skills | "Multi-step flow with clear trigger conditions, reusable across projects — warrants a real skill, not just a script." |

**These are heuristics for the model's holistic judgment during a periodic nudge — NOT counters this skill maintains algorithmically.** Hermes-Agent's `tools/skill_manager_tool.py` is purely CRUD; the trigger model is a periodic nudge that asks "consider crystallizing", and the model decides. Don't try to count normalized commands or de-dupe argv vectors. Read the room.

### Crystallization triggers

| Trigger | Default | Behavior |
|---|---|---|
| Periodic nudge | Every ~15 tool-calling iterations since the last crystallization check | Self-checked. On each operation, briefly notice whether ~15 tool calls have passed; if yes, ask yourself "є щось варте автоматизації?" and surface a proposal if the answer is yes. The skill is purely instructional — there is no harness-side counter; the model is responsible for self-pacing. |
| Pre-commit | Immediately before `git commit` | Hard trigger — paired with reflection. Always check for crystallization candidates at this moment. |
| TodoWrite-completion | Last todo → `completed` | Hard trigger — paired with reflection. |
| Pre-compression flush | User-explicit ("save before /compress" / "збережи перед стисненням") | Guaranteed turn for writing crystallizable patterns out before context is lost. The harness does not signal compression to skills, so this depends on the user. |
| Explicit user | "save this as bash" / "make it a script" / "винеси в скіл" | Manual override — skip judgment, go straight to proposal at the requested tier. |
| Disabled | `nudge_interval: 0` in `{wiki}/schema.md` frontmatter | Disables the periodic nudge only. Hard triggers (pre-commit, TodoWrite-completion, explicit user) still fire. |

The default cadence (~15 iterations) can be overridden per-wiki via `nudge_interval: <N>` in `schema.md` frontmatter — see `## Versioning & Migration` for the knob.

### Proposal format

The skill **proposes**; the user decides. Never `Write` a script, page, or skill silently. Use this exact block:

```
🔁 Помічаю патерн: {one-line description of the recurring pattern, with concrete count}
   Tier {N} ({type}): {proposed-path}

   Створити? [y] / [n] / [пізніше]
```

Behavior on each response:

- `y` → create the file, show its content inline, stage it for commit. The reflection's `Автоматизував:` field records `tier {N} — {path}`.
- `n` → do not create. Record the refusal for this normalized pattern in this session — **do not re-propose the same pattern this session**. The reflection's `Автоматизував:` field records `нічого — юзер відмовив раніше`.
- `пізніше` → do not create now, but the pattern is still eligible for re-proposal at the next nudge. The reflection's `Автоматизував:` field records `нічого — відкладено`.

A concrete tier-1 example:

```
🔁 Помічаю патерн: за останні 15 ітерацій ти 3 рази робив curl з cookie better-auth + grep по JSON.
   Tier 1 (bash one-liner): scripts/auth-curl.sh

   Створити? [y] / [n] / [пізніше]
```

### Tier-4 delegation to writing-skills

Tier 4 has the highest bar — a full skill with its own SKILL.md, conventions, evals, and trigger-description. **The wiki skill does NOT create SKILL.md itself.** It delegates to the `superpowers:writing-skills` skill, which knows skill conventions (frontmatter format, evals, naming, the broader skill ecosystem). This skill knows wiki conventions; that one knows skill conventions. Honor the separation.

The tier-4 proposal therefore looks slightly different — it asks for permission to delegate, not for permission to create:

```
🔁 Цей flow підходить для повноцінного скіла: 5 кроків, чіткі тригери, реюзабельно між проєктами.
   Tier 4 (full skill): передати у superpowers:writing-skills для оформлення?

   [y] делегуй  /  [n] не зараз  /  [пізніше]
```

On `y`, hand off to `superpowers:writing-skills` with a one-paragraph brief describing the flow, triggers, and intended scope. The reflection's `Автоматизував:` field records `tier 4 — delegated to writing-skills (subject: {brief})`. Do not create `~/.claude/skills/{name}/SKILL.md` directly from this skill under any circumstances.

### Anti-noise rules for crystallization

The proposal flow has its own anti-noise constraints, separate from the reflection-block anti-noise rule:

- **Don't propose if the user already refused this normalized pattern in this session.** Refusals are sticky for the session.
- **Don't propose for ambient commands** — `ls`, `cd`, `pwd`, `git status`, `git log`, `cat`, `wc`, `grep` of well-known paths. These are exploration noise, not patterns worth scripting.
- **Don't propose if arguments are radically different each time.** If you ran `curl` against five different URLs with five different cookies, that's ad-hoc exploration, not a scriptable pattern. Look for repeated *shape*, not repeated *invocation*.
- **Don't propose tier 1 or 2 for one-shot operations** — deploys, schema migrations, one-time data fixes. Even if the user runs them three times in a row, they're not a recurring pattern; they're one task done in three steps.
- **Lowest viable tier wins.** Don't propose tier 3 when tier 1 covers it; don't propose tier 4 when tier 3 covers it. Over-tiering is its own form of noise.

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

### Why a reflection block at all

Karpathy's pattern is silent: read, write, move on. Hermes adds telemetry, also silent. But a coding agent navigating an interactive session benefits from a small visible breadcrumb after each meaningful chunk — it tells the user "yes, I noticed this was a recurring pattern" or "no, nothing new here". The strict template prevents drift into rambling reflection essays; the trigger table prevents spam; anti-noise keeps it relevant. The reflection block is the wiki's interactive companion to its silent telemetry sidecar.

## Three Layers (within Wiki)

The wiki itself has three internal layers:

```
{wiki}/concepts/         → themes, processes, rules (synthesis)
{wiki}/entities/         → specific things (people, contracts, objects, ...)
{wiki}/transcripts/      → full text of binaries (for grep / LLM context)
```

Plus external layers:

```
Raw Binaries (immutable) → archive/ (gitignored, outside wiki)
Schema (conventions)     → {wiki}/schema.md (preferred, v3+)
                         → CLAUDE.md sections (legacy, v1–v2)
```

**Concepts** — the existing layer. Themes, gotchas, architectural decisions.

**Entities** — hub pages for specific things. Each entity page has:
- Frontmatter with `type: entity`, `category`, `key`, project-specific fields
- Synthesis (what this is, why it matters)
- Cross-refs (to other entities, concepts, transcripts, binaries)

**Lazy entity creation:** create an entity page only when a document or
operation actually references the entity. Don't pre-populate from inventories.

**Transcripts** — auto-generated MD with full text of a binary. Frontmatter
links back to source binary and corresponding entity page. No synthesis,
no editing — pure raw text for grep and LLM context.

**Naming** — for documents:  `{YYYY-MM-DD}_{type}_{slug}.{ext}`.
For templates: `template_{type}_{slug}.{ext}`.
For abstract entities: `{slug}.md`.
Cyrillic OK. Spaces → `-`. Forbidden: `/\?*<>:|`, quotes, dots (except before ext).

## Navigation Files

| File | Purpose | Format |
|------|---------|--------|
| `{wiki}/index.md` | Catalog of all pages, organized by category | `- [[page-name]] — one-line description` |
| `{wiki}/log.md` | Chronological record of all operations | `## [YYYY-MM-DD] operation \| Subject` + optional `touched: [[page-a]], [[page-b]]` line for searchability |

**Read `index.md` FIRST** for any wiki operation — it's your map.

---

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

### IMPORTANT: Wiki vs. CLAUDE.md

When updating documentation after implementing a feature:
- **CLAUDE.md** gets ONLY: new conventions, rules, data model summary changes (1-2 lines max)
- **Wiki** gets: implementation details, how things work, component behavior, API specifics
- If in doubt whether something is a "convention" or "implementation detail" — it's wiki
- Reference wiki from CLAUDE.md when needed: "Details → see [[page-name]] in wiki"

### After completion

If this operation was triggered by a TodoWrite-completion or is part of a pre-commit moment, emit a РЕФЛЕКСІЯ block per `## Self-Improvement Loop`. Ingest-Source almost always involves Edit/Write on at least one wiki page, so the anti-noise rule rarely applies — only skip reflection if you somehow read sources but ended up making no edits at all.

---

## Operation: Ingest-Binary

Process a binary artifact (PDF, DOCX, image) into the wiki and archive.

### When to Ingest-Binary

- User drops a file into `tmp/`
- User says "ingest this PDF/DOCX/file", "додай цей документ"
- A new signed contract / certificate / letter arrives

### Process

1. **Detect / ask category** — suggest from `Entity Categories` in schema
   (`{wiki}/schema.md`, fallback to CLAUDE.md). If user wants a new category,
   add a row to schema.md (or CLAUDE.md for legacy v1–v2 layout)
2. **Detect / ask type** — suggest from `Document Types` in schema
   (same fallback order). If new type, add a row to schema.md (or CLAUDE.md legacy)
3. **Propose slug** — from filename + date + parties;
   ask user to confirm or edit
4. **Extract text → transcript (via `doc-extract` skill):**

   Call:
   ```bash
   bash ~/.claude/skills/doc-extract/bin/extract.sh <source_file> \
     --out <wiki>/transcripts/<slug>.md \
     --format md
   ```

   Handle exit code:
   - `0` — transcript created, proceed.
   - `10` (extraction_failed) — STOP. Read stderr method_chain;
     tell user: "doc-extract пройшов каскад [методи], вийшло N символів.
     Варіанти: (1) вручну → summary, (2) Read tool (LLM, дорого),
     (3) пропустити". Wait for user decision.
   - `20` (missing_dependency) — STOP. Run
     `bash ~/.claude/skills/doc-extract/bin/doctor.sh`, show output,
     ask user to install missing deps, then retry.
   - `30` (unsupported_format) — ask user to skip or convert first.
   - `40/50` — caller bug, show stderr.

   **Важливо:** wiki більше НЕ падає на Read tool (LLM vision) сам.
   Єдиний шлях до LLM — явне рішення юзера у відповідь на exit 10.
   Це уникає дорогих silent fallback'ів.

   Если `doc-extract` скіл відсутній — повідом юзера, покажи
   install-команду: `curl -fsSL https://raw.githubusercontent.com/kozaksv/claude-doc-extract-skill/main/install.sh | bash`
5. **Move binary → `archive/{path}/{slug}.{ext}`** (per File Naming convention)
6. **Create entity page → `entities/{category}/{slug}.md`:**
   - Frontmatter (type=entity, category, key, binary, transcript, project-specific fields)
   - Synthesis (LLM proposes — user edits)
   - Cross-refs: scan transcript for mentions of other entities;
     if entity exists → link; if not → lazy-create stub and link
7. **Update related entity pages** — for each entity touched, append to its
   "Documents" section a link to this new entity page
8. **Update concepts** — if new info changes a concept (e.g., new exception
   for `discrepancies`), propose update; ask user to confirm
9. **Update navigation:**
   - `entities/index.md` (or wiki/index.md Entities section): append row
   - `transcripts/index.md`: append row
   - `log.md`: append `## [YYYY-MM-DD] ingest-binary | <description>`
10. **Update telemetry** (`.usage.json`, see `## Telemetry Sidecar`):
    - New entity page → `bump_patch(entities/{category}/{slug}.md)` (creates record with `created_at`)
    - New transcript → `bump_patch(transcripts/{slug}.md)`
    - Modified `entities/index.md` / `transcripts/index.md` → `bump_patch(...)`
    - Each existing entity page touched (back-link to new doc) → `bump_patch(...)`
    - Each `[[wikilink]]` you added pointing to another wiki page → `bump_use(target_path)`
11. **Protect auto-suggest for critically-rare pages.** For the **new** entity page created in step 6, check if it looks intentionally rare-read. Trigger if either:

    - Frontmatter contains a tag matching `security`, `incident`, `migration`, `compliance`, or `recovery`, OR
    - Filename / slug contains any of those prefixes (e.g. `security-cf-tunnel-rotation.md`, `incident-2026-02-15.md`, `migration-stock-pickings.md`, `compliance-gdpr-export.md`, `recovery-runbook.md`).

    Ask the user:

    ```
    Сторінка [[{slug}]] виглядає як критично-рідкісна. Запропонувати захист? [y/n]
    ```

    On `y`: read `.usage.json`, set `protected: true` on the new entity page's record, write atomically. Pinning does not bump `patch_count`. On `n`: leave `protected: false`. Page protection then kicks in during future Lint runs (see `## Operation: Lint > Page protection during Lint`).

### After completion

If this operation was triggered by a TodoWrite-completion or is part of a pre-commit moment, emit a РЕФЛЕКСІЯ block per `## Self-Improvement Loop`. Ingest-Binary always creates structural artifacts (entity page, transcript, archive move, navigation updates), so reflection should fire and include the `Перевірив:` section listing structural files touched. Anti-noise does not apply.

---

## Operation: Query

Search the wiki to answer a question about the project.

### When to Query

- When the user asks about architecture, flows, or design decisions
- When Claude needs context about how a system works before making changes
- When searching for gotchas before touching a specific area
- When the user says "що каже wiki про...", "wiki query", "знайди у wiki"

### Process

```
0. DISCOVER wiki location (Step 0 above)
1. READ {wiki}/index.md
2. IDENTIFY relevant pages from index (usually 1-3)
3. READ those pages
4. SYNTHESIZE answer with citations: [[page-name]]
5. If answer is valuable and reusable → FILE BACK as new wiki page
6. UPDATE telemetry — call bump_view(path) for each page read in step 3
```

After step 3, for each page you read with the `Read` tool, call `bump_view(path)` against `.usage.json` (see `## Telemetry Sidecar`). If step 5 fires and you create or edit a page, also call `bump_patch(new_path)` and `bump_use(target)` for each `[[wikilink]]` added.

### Filing Back

When a query produces a valuable synthesis (comparison, analysis, connection between topics), consider saving it as a new wiki page. This is a key Karpathy insight: **good answers compound into the knowledge base** rather than disappearing into chat history.

Ask yourself: "Would this answer be useful in a future session?" If yes → create a page.

### After completion

Query is read-only by default — apply the **anti-noise rule** and skip the РЕФЛЕКСІЯ block (see `## Self-Improvement Loop`). The exception is when step 5 (Filing Back) fires and you actually create or edit a wiki page: that turns the operation into a synthesis-write, and reflection should fire as if it were an Ingest-Source.

---

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

If the user picks `[a]/[b]/[c]` or a passive fix and that downstream flow makes edits, reflection fires from the downstream operation (Lint or the passive `Edit`) on its own terms — not from `wiki status`. Do not double-fire.

---

## Operation: Lint

Periodic health-check of the wiki.

### When to Lint

- User explicitly asks ("wiki lint", "перевір wiki")
- Periodically (every ~10 sessions or after major changes)
- When something feels off or inconsistent during other operations

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

   **Heads-up before starting full lint — always.** Print **exactly this block, nothing else**, then end the turn:

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

   Substitute real `N` and `K` from `report()`. Skip this block ONLY when the user already named a path-based scope, described a topic, or said "швидко" (the choice was already explicit).

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

   **2a. ALWAYS also content-verify CLAUDE.md** — regardless of subset (full / швидко / scope / topic), the project's `CLAUDE.md` is **always** read and verified per check #11 (Karpathy content-classification: convention/detail/history/dead/verbose). Findings flow into the same AUTO/DECIDE/INFO buckets and share the report's sequential numbering. CLAUDE.md is not a wiki page (no `.usage.json` record), so prioritization signals don't apply — it's verified every lint run as a first-class target. If you complete a lint run without reading CLAUDE.md, the lint is **incomplete** — that's a hard rule, not a guideline. Common failure mode: LLM treats "selected pages" (wiki) as the only verification target and skips CLAUDE.md silently. The spec wires CLAUDE.md in explicitly to prevent this.

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
- Are all categories used in `entities/` declared in schema (`{wiki}/schema.md` preferred, CLAUDE.md legacy)?
- Are all types in slugs declared in schema `## Document Types`?
- Is schema split between `{wiki}/schema.md` AND CLAUDE.md sections (duplication)? → propose collapsing to schema.md only
- Does CLAUDE.md still carry full schema instead of a 1-line pointer? → propose migration
- If drift found — propose updating schema

**11. CLAUDE.md Content Verification (Karpathy-style)** — CLAUDE.md is resident context paid on every session, every conversation, every tool call. Wiki is lazy (read on demand). The skill **reads CLAUDE.md in full** and judges each line/section by content type — **no algorithmic line-count threshold**. Length is a symptom, content-type ratio is the real question.

**Per-line classification** — every line falls into one of these:

a. **CONVENTION/RULE (KEEP)** — what the project does/doesn't do, naming patterns, workflow rules, architectural principles, data model summary at a level useful for every session. These earn resident context.

b. **IMPLEMENTATION DETAIL (MIGRATE)** — how something works internally, component props, function signatures, exact file paths, API endpoints, sub-feature behaviors. These are looked up when needed; they don't belong in resident context. Identify the target wiki page for each migrated line.

c. **HISTORY NOTE (MOVE TO LOG)** — "X removed in <date>", "Y migrated to Z", "deprecated since vN", "previously called A, now B". Belong in `git log` or `wiki/log.md`, not resident context.

d. **DEAD REFERENCE (DELETE)** — wikilink to a page that doesn't exist in the wiki tree, file path to a deleted file, mention of a removed feature/library/table. Verifiable via `ls`/`grep`.

e. **VERBOSE PHRASING (CONDENSE)** — sentence that's 400+ chars when 80 would do, repeated qualifications, redundant explanations across multiple lines. Same rule lives shorter.

**Cross-checks:**

- For each `[[wikilink]]` in CLAUDE.md: target page exists AND covers the cross-linked topic (otherwise CLAUDE.md carries duplicated content).
- For each convention line: doesn't contradict the wiki page that elaborates it.

**Bias toward shrinking.** When a line could plausibly live in either CLAUDE.md or wiki, default to wiki. Resident context is a precious budget — every byte is paid forever. The default question is «can this be shorter? can this move to a lazy page?», not «is this important enough to delete?».

**Tier mapping** (per the standard AUTO/DECIDE/INFO contract):

- **AUTO**: dead wikilinks (point to non-existent pages — verify via wiki tree), dead file path references (verify via `ls`), confirmed-stale history notes (`grep` confirms the migrated/removed thing is gone), drift-prone counts inside CLAUDE.md ("N tests").
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
  - **Версія схеми** — only on **mismatch** between `{wiki}/schema.md`'s `wiki_version` and the skill's frontmatter version. When they match, this line is redundant fog.
  - **Велика сторінка** — only when at least one page is > 200 lines **and not already in 🟡** as a split candidate (otherwise it'd be duplicated). When the skill judged a large page coherent and decided not to split, this line is the FYI; when it judged it splittable, the 🟡 entry covers it.

If all three 🔵 lines lack triggers, omit the 🔵 block entirely.

When ALL buckets (🟢 / 🟡 / 🔵) are empty (clean wiki, nothing applied, nothing pending, nothing notable), print exactly one line: «✅ Лінт чистий. N сторінок перевірено, дрейфу не виявлено.»

**Never close Lint with a multi-option "куди далі?" menu** that mixes paradigms — e.g. `[1] verify subset / [2] another subset / [3] specific list / [4] split page X / [5] stop without verification`. Per-finding actions in 🟡 are offered with the unified action menu (see `## Self-Improvement Loop > ### Cleanup-flow`). When the report is done, the operation is done — wait for user to act on findings or say `відкат`.

### After completion

Lint mutates wiki content whenever AUTO findings exist (snapshot + per-fix commits applied during step 3). Anti-noise rule applies only when **all** of the following hold:
- AUTO bucket was empty (nothing auto-applied).
- DECIDE bucket was empty (no judgment-call actions taken yet).
- The lint produced a "✅ чистий" or pure-INFO report.

In that case (read-only run), skip the РЕФЛЕКСІЯ block per `## Self-Improvement Loop`.

Otherwise — emit РЕФЛЕКСІЯ once, summarizing the auto-applied AUTO bucket. DECIDE actions the user later picks each trigger their own reflection via the cleanup-flow contract. Don't double-fire: the auto-apply reflection is one block at end of lint; per-DECIDE reflections fire as the user resolves them.

If the user says `відкат` / `відкат N` after the lint report, the revert itself is a wiki-content mutation and emits its own brief reflection («Відкатив N правок. Файли повернуто.»).

---

## Operation: Split

Break an over-grown wiki page into focused successors. Lint flags candidates (check #12); this operation executes the split cleanly.

### When to Split

- Page > ~200 lines (soft limit from Page Conventions)
- Page covers 2+ independent topics with visible H2 boundaries
- Lint item #12 fires

### Process

1. **Identify boundaries** — usually H2 sections. Propose N successor pages with titles and which sections land in each.
2. **Confirm with user** — present the split plan before touching files. User may merge sections, rename successors, or abort.
3. **Create successor pages** using the Page Template. Each inherits relevant `## Sources` from the original.
4. **Rewrite or delete original** — either keep it as a hub page (just a list of `[[successor]]` links if the umbrella topic still makes sense) or delete it outright. **If deleted**, call `forget(original_path)` against `.usage.json` (see `## Telemetry Sidecar`). For each successor, telemetry will auto-create a record on the first patch — no manual init needed.
5. **Rewire cross-references** — scan wiki for `[[old-page]]` and replace with the correct `[[new-page]]`. Grep the whole `{wiki}/` tree.
6. **Update `## See also`** on every page that referenced the original — point to the specific successor, not the generic replacement.
7. **Update `{wiki}/index.md`** — remove old entry, add N new entries with one-line descriptions.
8. **Append to `log.md`:**
```markdown
## [YYYY-MM-DD] split | old-page → new-a + new-b
- Reason: lint check #12 flagged 247 lines / 3 independent topics
- Successors: [[new-a]] (topic X), [[new-b]] (topic Y)
- Cross-refs updated: N pages
```

### Anti-Patterns

- **Don't split for size alone.** A focused 210-line page is fine. Size is a heuristic, not a rule.
- **Don't leave a bait-and-switch hub** (original title, but just a list of links) unless the umbrella topic has standalone value. Prefer deletion + cross-ref rewire.
- **Don't forget the log.md entry.** Future lint runs need to know the split happened, so they don't re-flag stubs.

### After completion

If this operation was triggered by a TodoWrite-completion or is part of a pre-commit moment, emit a РЕФЛЕКСІЯ block per `## Self-Improvement Loop`. Split always rewrites multiple files (successors + cross-refs + index + log) and almost always touches `index.md` and `log.md`, so reflection should fire and include the `Перевірив:` section. Anti-noise does not apply.

---

## Operation: Init (bootstrap-aware)

Set up wiki, OR detect existing structure and propose migration.

### When to Init

- User asks to create/initialize a wiki
- Wiki discovery (Step 0) found no existing wiki
- User asks to "bootstrap" / "migrate" / "reorganize" project around wiki

### Discovery

1. **Find CLAUDE.md** (walk up dirs from cwd)
2. **Determine wiki state** (5-state model, aligned with `## Versioning & Migration > State detection on Step 0`):

   | State | Condition | Action |
   |---|---|---|
   | `absent` | No `docs/wiki/` exists | Bootstrap from scratch (proceed to project-type detection + Plan below) |
   | `legacy` | Wiki exists but no `wiki_version` field in `schema.md` frontmatter | Identify version interactively, then propose migration |
   | `current` | `wiki_version` matches skill's version | Nothing to do — abort Init, tell user wiki is up to date |
   | `older` | `wiki_version` < skill's version | Generate migration plan, ask user once |
   | `newer` | `wiki_version` > skill's version | Warn user, ask whether to continue |

3. **Scan project for migration candidates** (only if state is `legacy` or `older`):
   - Raw binaries (PDF, DOCX, images, spreadsheets) in non-hidden, non-wiki dirs
   - Analytical MDs (README, analysis, notes) outside `docs/wiki/`
   - Existing concept-like MDs that should move to `concepts/`
   - Duplicate MDs (raw README that overlap wiki content)

### Project-type detection (only for `absent` state)

When bootstrapping a fresh wiki, scan project root for type signals to propose initial `entities/` categories. This is a SUGGESTION — user can override or pick custom categories.

| Signal (file present in project root) | Suggested `entities/` categories |
|---|---|
| `package.json` / `tsconfig.json` | `components/`, `services/` |
| `Cargo.toml` | `modules/`, `traits/` |
| `requirements.txt` / `pyproject.toml` | `modules/`, `classes/` |
| `go.mod` | `packages/`, `interfaces/` |
| `*.csproj` | `classes/`, `services/` |
| `pom.xml` / `build.gradle` | `packages/`, `services/` |
| no code signals (research / personal / docs project) | `people/`, `documents/` |

If multiple signals match (polyglot repo), union the suggested categories and let the user prune. After detection, surface the proposed list inside the Bootstrap plan template (step 5: `entities/`) so the user sees what they're approving.

**Scope warning.** Project-type detection ONLY influences proposed initial categories at bootstrap time. It does NOT affect any other behavior — in particular, it does NOT feed into staleness scoring or content-verification (see `## Operation: Lint`), and it does NOT lock future categories (any category can be added later via `ingest-binary` lazy-creation).

### Plan (interactive)

For `legacy` / `older` migrations, before any move, present:
- Concept candidates → list of MDs to move into `concepts/`
- Entity candidates → suggest stubs from mentions in existing wiki
- Binary candidates → list of binaries to move to `archive/` + create transcript
- Dupes → list of MDs to delete (with justification)
- Stale folders → list to remove after content migrated

Ask per group: "Migrate these? [y/N/per-file]". User retains veto on each.

### Bootstrap plan template (for `absent` state)

For a fresh wiki (state = `absent`), present this single-block plan after project-type detection finishes. Substitute `{detected_type}` with the matched signal (e.g., `package.json`) and `{category-list}` with the suggested categories from the table above; substitute `{today}` with the current date in `YYYY-MM-DD` form.

```
📂 Створюю нову wiki у docs/wiki/

План:
  1. docs/wiki/schema.md — frontmatter (wiki_version: "4.0", last_migration: "{today}", nudge_interval: 15) + три розділи (Layers / Operations / Conventions) + Migration Log
  2. docs/wiki/index.md — порожній з трьома секціями (Concepts | Entities | Transcripts)
  3. docs/wiki/log.md — порожній з заголовком
  4. docs/wiki/concepts/ — порожня папка
  5. docs/wiki/entities/ — пропонована структура для {detected_type}: {category-list}
  6. docs/wiki/transcripts/ — порожня папка
  7. docs/wiki/.usage.json — порожній dict {}
  8. archive/ — поза wiki (gitignored)
  9. CLAUDE.md — додати 1-line pointer "Wiki schema → docs/wiki/schema.md"
  10. .gitignore — додати "archive/" і "docs/wiki/.usage.json"

[y] так, створи все  /  [n] скасувати
```

After confirmation (`y`), execute all 10 steps in order using the Execute checklist below. After execution, append `## [{today}] init | bootstrap fresh wiki v4.0` to `log.md`. On `n`, abort and leave the project untouched.

### Execute

After consent:

1. Create missing dirs: `concepts/`, `entities/{categories}/`, `transcripts/`, `archive/{paths}/`
2. Add `archive/` to `.gitignore`
3. Move concept MDs → `concepts/`
4. For each binary:
   - Move to `archive/{path}/{naming-convention}.{ext}`
   - Generate transcript → `transcripts/{slug}.md`
   - Create entity page stub → `entities/{category}/{slug}.md`
5. Create entity stubs for entities mentioned in concepts (lazy: only key/recurring ones)
6. Create `{wiki}/schema.md` with frontmatter, layers description, operations summary, `Entity Categories`, `Document Types`, `File Naming`, and `## Migration Log` section seeded with v4.0 entry. Frontmatter template:

   ```yaml
   ---
   wiki_version: "4.0"
   last_migration: "{today}"
   nudge_interval: 15      # tool-calling iterations between crystallization nudges; 0 disables periodic nudge
   ---
   ```

   Add a single `## Wiki` pointer in CLAUDE.md: _"Wiki schema and operations → `docs/wiki/schema.md`. Skill: `wiki`."_ (for v1/v2 migrations — move existing CLAUDE.md sections into `schema.md` and replace them with the pointer)
6a. Create `{wiki}/.usage.json` with `{}` (empty dict). This is the telemetry sidecar — see `## Telemetry Sidecar`.
6b. Add `{wiki}/.usage.json` to `.gitignore`. Telemetry is per-clone, not shared.
7. Delete approved duplicates
8. Update `index.md` (three sections: Concepts | Entities | Transcripts)
9. Append `log.md` with migration record

### Versioning during Init

For all migration-from-legacy paths, follow the explicit plan format described in `## Versioning & Migration`. After successful migration, write `## Migration Log` entry documenting the path taken (e.g., "v1 → v4 via init bootstrap").

### After completion

Init is the most structurally heavy operation in the skill — it creates `schema.md`, `index.md`, `log.md`, `.usage.json`, edits `.gitignore`, writes a CLAUDE.md pointer, and may move binaries into `archive/`. Always emit a РЕФЛЕКСІЯ block per `## Self-Improvement Loop` after Init completes (regardless of trigger), and always include the `Перевірив:` section listing every structural file created or modified. Anti-noise does not apply — Init by definition writes.

---

## Operation: Cleanup

Post-migration / periodic housekeeping AND structural reorganization of existing content.

### When to Cleanup

- After init/bootstrap completes
- User says "wiki cleanup", "почисть wiki/вікі"
- Periodically (every ~10 sessions or after major changes)
- **When migrating content between CLAUDE.md and wiki** (e.g. extracting implementation details, consolidating duplicates). This is the canonical home for "wiki refactor" — not `ingest-source` (no new material entering) and not `lint` (not read-only report). Use the log tag `cleanup` with a descriptive subject.

### Process

1. Remove empty directories under `docs/wiki/` and `archive/`
2. Verify `archive/` is in `.gitignore`; add if missing
3. Verify schema exists at `{wiki}/schema.md` (preferred). If schema lives in CLAUDE.md sections instead, propose migration: move to `{wiki}/schema.md`, leave a 1-line pointer in CLAUDE.md. If both exist — propose collapsing into schema.md only.
4. Find unused entity stubs (entity pages with no cross-refs from anywhere) — propose deletion. For each page deleted, call `forget(path)` against `.usage.json` (see `## Telemetry Sidecar`).
5. Find concept pages not in `index.md` and vice versa — propose fixes
6. Append cleanup actions to `log.md`

### After completion

If this operation was triggered by a TodoWrite-completion or is part of a pre-commit moment, emit a РЕФЛЕКСІЯ block per `## Self-Improvement Loop`. Cleanup that only **proposed** fixes (no user consent yet, no edits applied) is a read-only survey — apply the **anti-noise rule** and skip reflection. Cleanup that actually applied fixes (deletions, schema migration, index/log updates) is a structural change — fire reflection and include the `Перевірив:` section.

---

## Proactive Wiki Maintenance

Beyond explicit commands, maintain wiki awareness during normal work. Tie triggers to git activity — it's concrete, whereas "after a feature" is vague.

**Commit scope `feat(`** → suggest `ingest-source`. New capability = new synthesis to capture.

**Commit scope `refactor(`** → suggest `lint` on concepts mentioning the touched paths. Refactors invalidate wiki facts; lint surfaces the stale ones. No full lint — just the relevant pages.

**Commit scope `docs(`** touching `docs/superpowers/specs/` (or equivalent raw-sources dir) → `ingest-source` is mandatory. Specs are the primary wiki feedstock.

**Commit touches CLAUDE.md** → check whether added/edited lines are convention (keep) vs implementation detail (propose `cleanup` to migrate into wiki). This is the counterpart to Lint check #11 but catches drift at commit time, before it accumulates.

**Binary file appears in `tmp/`** → suggest `ingest-binary` (already covered by description triggers).

**After discovering a gotcha during coding:** If a non-obvious behavior bit you, append to the gotchas page. Don't wait for the next feature.

**After reading wiki during work:** If you notice stale info while consulting the wiki, fix it immediately — don't leave known-stale content.

**Before committing:** Check whether wiki schema (`{wiki}/schema.md`) or concept pages need updates.

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Creating a second wiki when one exists | ALWAYS run discovery (Step 0) first. Check CLAUDE.md, search for existing index.md. |
| Adding implementation details to CLAUDE.md | CLAUDE.md = rules and conventions only. Details → wiki pages. |
| Duplicating code in wiki | Wiki describes WHAT and WHY. Code shows HOW. |
| Forgetting to update index.md | ALWAYS update index after creating/renaming pages |
| Forgetting to append to log.md | ALWAYS append after any ingest or significant update |
| Creating pages for ephemeral info | Wiki = persistent knowledge. Tasks/debugging = conversation only. |
| Giant monolithic pages | Split at ~200 lines. One focused topic per page. |
| Missing cross-references | Every page should have `## See also`. Check related pages too. |
| Ingesting without reading existing pages first | ALWAYS read index + relevant pages before writing. Integrate, don't duplicate. |
| Leaving stale info when updating | When adding new info, also check and fix outdated facts on the same page. |
| Using hardcoded wiki paths | ALWAYS discover wiki location via CLAUDE.md first. |
| Writing wiki schema into CLAUDE.md on init | Schema belongs in `{wiki}/schema.md`. CLAUDE.md only gets a 1-line pointer. |
| Maintaining duplicate schema in both locations | Collapse to `{wiki}/schema.md` only. Leave 1-line pointer in CLAUDE.md. |
| Auto-flagging staleness by timestamp | Use Karpathy content-verification — read pages and judge claims. Telemetry is for prioritization, not flagging. |
| Creating crystallization artifact silently | Skill ALWAYS proposes (y/n/пізніше). Never `Write` a script/page/skill without explicit user approval. |
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
| Using a line-count threshold for CLAUDE.md (e.g. ">150 lines") | Algorithmic threshold contradicts Karpathy content-verification. Read CLAUDE.md in full, classify each line (convention/detail/history/dead/verbose), propose AUTO for verifiable dead refs, DECIDE for judgment calls, INFO for the content-type breakdown. Length is a symptom; the real question is content-type ratio. Default bias: when ambiguous, propose moving to wiki — CLAUDE.md is paid every session, every byte counts. |
| Maintaining row-per-file inventory tables (specs, migrations, routes) in wiki | Disk maintains the inventory authoritatively (`ls`/`grep`); wiki copy is Sisyphean — every new file requires a wiki edit, drift is guaranteed. AUTO-drop the inventory; replace with a pointer command (`\`ls apps/web/e2e/*.spec.ts\``). Keep cross-cutting synthesis only — clusters («auth*.spec.ts — auth-flow group»), criteria («коли додавати новий e2e»), conceptual categories («3 типи: smoke / integration / regression»). Do NOT auto-add per-file labels for missing specs — that recreates the very pattern lint is removing. |
| Skipping CLAUDE.md during lint (treating "selected pages" as wiki-only) | CLAUDE.md is project-wide convention, **always** verified, regardless of subset. Step 2a in Process explicitly wires this in. If a lint run finishes without producing a CLAUDE.md classification breakdown (or auto-fixes for dead refs), the lint is incomplete — re-run or finish the missed verification. CLAUDE.md doesn't sit in `.usage.json`, so don't expect prioritization signals to surface it; the spec adds it as an always-on target separate from the wiki subset. |
