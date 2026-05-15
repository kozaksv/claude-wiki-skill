## Self-Improvement Loop

The wiki is not just a passive store — it is a feedback loop. After meaningful work the agent emits a **РЕФЛЕКСІЯ block** (a strict-template visible narrative) that surfaces what was learned, where it was filed, and whether anything is worth automating. This is the wiki's debug-readability layer: it lets the user (and the agent itself, on the next session) see how knowledge accumulated.

### Overview

Reflection has two purposes:

1. **Visible reasoning** — a short, predictable block that lets the user verify the agent didn't just edit files, it actually thought about the diff. Hermes-style silent telemetry stays in `.usage.json`; РЕФЛЕКСІЯ is the loud counterpart.
2. **Crystallization trigger** — every reflection is an opportunity to ask "is this pattern worth saving so the next session doesn't have to re-derive it?". Crystallization is documented in the subsection below; the reflection block names what was crystallized in the `Автоматизував:` field (one of `wiki — concepts/{name}.md`, `skill — delegated to writing-skills`, `skill — created at {path}`, or `нічого` with reason).

Reflection fires on **events**, not on a timer the skill maintains. The agent is responsible for self-checking the trigger conditions on every operation — there is no harness-side counter.

### РЕФЛЕКСІЯ block format (strict template)

Print this verbatim at the end of a triggered turn. Do not paraphrase the field labels — they are part of the contract:

```
📚 РЕФЛЕКСІЯ — {YYYY-MM-DD HH:MM} — trigger: {todo-completion / pre-commit / memory-flush / explicit / periodic-nudge}

Дізнався: {one sentence — what new insight emerged}
Чому це краще: {one or two sentences — why it works, why this approach}
Зберіг у wiki: [[page-a]], [[page-b]]   (or: «не торкав wiki — нічого синтетичного»)
Автоматизував: {wiki — concepts/{name}.md  /  skill — delegated to writing-skills  /  skill — created at {path}  /  нічого + причина}

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
| Task/todo item → `completed` in the active agent's plan tool | ✅ | Hard event — fires once per todo-list completion |
| Plan/todo list cleared (all todos removed) | ✅ | Treat as completion |
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

Treat hard events (task-completion, pre-commit, explicit user) as the reliable signals. Periodic nudge is a backup.

For agents without a TodoWrite-like plan/todo tool, the TodoWrite-completion trigger is simply unavailable. Reflection and crystallization still fire on pre-commit, explicit user requests, memory-flush requests, and periodic nudges.

### Field rules

- **Дізнався** must contain a real insight or be explicit about its absence: «Дізнався: нічого нового — стандартна реалізація за патерном [[X]]». Never leave the field empty or write filler like "багато всього".
- **Чому це краще** appears only if "Дізнався" had real content. Otherwise omit the line entirely (do not write "n/a" or "—").
- **Зберіг у wiki** is a `[[wikilinks]]` list, or the explicit phrase «не торкав wiki — нічого синтетичного». If you touched only `log.md` / `index.md` (bookkeeping), say so explicitly: «лише log.md / index.md — bookkeeping».
- **Автоматизував** is mandatory. If nothing crystallized, write one of: `нічого — операція разова` / `нічого — патерн не повторюється` / `нічого — юзер відмовив раніше` / `нічого — відкладено`. The user wants to see that the question was asked. Do not invent counter-style explanations like "поточний 2/3" — there is no algorithmic threshold; see "Read the room" rule below.
- **Перевірив** appears only when structural files (`index.md`, `schema.md`, `log.md`, `.usage.json`) were modified in this block. Use ✅ for confirmed updates, ⚠️ for intentional skips with one-line reason. Skip the section entirely if no structural files were touched.

### Anti-noise rule

Reflection skips entirely if the block contained **only** `Read` operations — no `Edit`, no `Write`, no `Bash` with side effects (anything beyond `ls`/`grep`/`cat`/`git log`/`git status`/`wc`/`find` etc. counts as a side effect). There's nothing to reflect on; printing forced narrative would violate the debug-readability premise — signal would drown in noise.

Concretely:

- A pure Query operation that only read pages → no reflection.
- A Lint run → **no reflection, ever** (regardless of whether AUTO bucket wrote edits). The lint report itself — with 🟢 Авто-застосовано / 🟡 Потребує твого рішення / 🔵 Примітки / ВІДКАТ sections — already **is** the visible reasoning. Layering a РЕФЛЕКСІЯ block on top duplicates the structure, and the report's own ВІДКАТ section already exposes revert handles. No extra synthesis required.
- A `wiki status` invocation → no reflection (meta-operation, no edits).
- A cleanup-flow run (entered via `wiki status [a]/[b]/[c]` or via the РЕФЛЕКСІЯ cleanup-prompt) → no reflection. The action menu and revert section in the cleanup report serve the same purpose.
- An Ingest-Source that read 5 pages and edited 3 → reflection fires.
- An Init that created files → reflection fires (structural changes always reflect).

If unsure, lean toward firing reflection — over-reporting is recoverable, under-reporting hides reasoning. Anti-noise is for the obvious cases (literally nothing was written).

### Crystallization

The reflection's `Автоматизував:` field isn't decorative — it's the agent's answer to a real question: **is anything from this block worth saving so the next session doesn't have to re-derive it?** When the answer is yes, the agent **proposes** (never silently creates) one of two artifact types.

| Type | Artifact | Storage | What the model judges (during a periodic nudge) |
|---|---|---|---|
| **wiki** | new or extended `concepts/{name}.md` (recipe, ready-made block, concept explanation) | `{wiki}/concepts/` | "I re-derived this content from scratch this session — paste-able block, recipe, or concept the next session would also need. File it so the next read finds it instead of regenerating." |
| **skill** | new user-level skill (`SKILL.md`) | active agent's user skill registry | "Multi-step flow with clear trigger conditions, reusable across projects — warrants a real skill, not just a wiki page." |

**Why no `scripts/` tier.** Earlier versions proposed `scripts/{name}.sh` and `scripts/{name}.py` as crystallization tiers. They violated the Division of Labor stated at the top of this file: those scripts are **user-runnable** artifacts (`bash scripts/x.sh`, `python scripts/x.py | pbcopy`) — that pushes mechanical work onto the user, who in this skill's model only directs and curates. The right artifact for "I generated the same content twice" is a wiki page the agent reads back, not a generator the user runs. If a one-shot inline command is genuinely useful, write it inline at the moment of use; do not crystallize it as a user-facing tier.

**Memory is not a tier either.** The auto-memory mechanism in the system prompt already saves user feedback / preferences automatically (e.g. "user dislikes script-tier proposals" lands in `~/.claude/.../memory/feedback_*.md` without skill involvement). Wiki is the project-scoped, version-controlled, lint-verified store — auto-memory is the volatile sticky-note layer. They are perpendicular; this skill operates only on wiki and skill artifacts.

**These are heuristics for the model's holistic judgment during a periodic nudge — NOT counters this skill maintains algorithmically.** The trigger model is a periodic nudge that asks "consider crystallizing", and the model decides. Don't try to count normalized commands or de-dupe argv vectors. Read the room.

### Crystallization triggers

| Trigger | Default | Behavior |
|---|---|---|
| Periodic nudge | Every ~15 tool-calling iterations since the last crystallization check | Self-checked. On each operation, briefly notice whether ~15 tool calls have passed; if yes, ask yourself "є щось варте автоматизації?" and surface a proposal if the answer is yes. The skill is purely instructional — there is no harness-side counter; the model is responsible for self-pacing. |
| Pre-commit | Immediately before `git commit` | Hard trigger — paired with reflection. Always check for crystallization candidates at this moment. |
| Task-completion | Last todo/plan item → `completed` | Hard trigger — paired with reflection. |
| Pre-compression flush | User-explicit ("save before /compress" / "збережи перед стисненням") | Guaranteed turn for writing crystallizable patterns out before context is lost. The harness does not signal compression to skills, so this depends on the user. |
| Explicit user | "збережи у вікі" / "винеси в скіл" / "save as wiki page" | Manual override — skip judgment, go straight to proposal at the requested type. If the user asks for a script (`scripts/*.sh` / `*.py`), explain that this skill no longer crystallizes user-runnable scripts (Division of Labor) and offer the wiki-page equivalent. The user can still create a script manually if they want — the skill just doesn't propose it. |
| Disabled | `nudge_interval: 0` in `{wiki}/schema.md` frontmatter | Disables the periodic nudge only. Hard triggers (task-completion, pre-commit, explicit user) still fire. |

The default cadence (~15 iterations) can be overridden per-wiki via `nudge_interval: <N>` in `schema.md` frontmatter — see `## Versioning & Migration` for the knob.

### Proposal format

The skill **proposes**; the user decides. Never `Write` a wiki page, create a skill, or hand off to a skill-authoring helper silently. Use this exact block:

```
🔁 Помічаю патерн: {one-line description of the recurring pattern, with concrete count}
   {wiki | skill}: {proposed-path}

   Створити? [y] / [n] / [пізніше]
```

Behavior on each response:

- `y` → create the artifact, show its content inline, stage it for commit (or, for skill, follow `### Skill creation / delegation`). The reflection's `Автоматизував:` field records `wiki — {path}`, `skill — delegated to writing-skills (subject: {brief})`, or `skill — created at {path}`.
- `n` → do not create. Record the refusal for this normalized pattern in this session — **do not re-propose the same pattern this session**. The reflection's `Автоматизував:` field records `нічого — юзер відмовив раніше`.
- `пізніше` → do not create now, but the pattern is still eligible for re-proposal at the next nudge. The reflection's `Автоматизував:` field records `нічого — відкладено`.

A concrete wiki example:

```
🔁 Помічаю патерн: за сесію двічі надрукував той самий 60-рядковий PowerShell install-block для OpenSSH на Windows DC.
   wiki: concepts/openssh-on-windows-dc.md (з вбудованим PS-блоком + коли застосовувати)

   Створити? [y] / [n] / [пізніше]
```

### Skill creation / delegation

A skill has the highest bar — its own SKILL.md, conventions, evals, and trigger-description. If the active agent has access to a dedicated skill-authoring helper (for example `superpowers:writing-skills` in Claude, or a native skill-authoring helper in Codex/Gemini), delegate there because it knows skill conventions (frontmatter format, evals, naming, the broader skill ecosystem). This skill knows wiki conventions; the helper knows skill conventions.

If the active agent does **not** have such a helper (common in Codex/Gemini contexts), create the SKILL.md directly after explicit user approval. Use the same shared canonical topology as the installer so future client changes do not strand the skill in one agent's private registry:

- Canonical skill: `~/.claude/skills/{name}/SKILL.md`
- Codex export: `~/.agents/skills/{name}` → `~/.claude/skills/{name}`
- Gemini export: `~/.gemini/skills/{name}` → `~/.claude/skills/{name}`

This applies even when the user currently works only from Codex or Gemini. `~/.claude/skills/` is the shared canonical registry for this stack; it does not require Claude Code to be installed.

Use installer-style safety when creating this topology. The reference implementation is `install.sh`:
translate the same checks used by `set_skill_link` and `export_skill_link` into the current agent's available shell/edit tool calls.

- Canonical path absent → create `~/.claude/skills/{name}/` and write `SKILL.md`.
- Broken canonical symlink → replace it with a real canonical directory only after saying so in the response.
- Canonical symlink to another target, plain file, or non-empty real directory with an existing `SKILL.md` → stop and ask the user to resolve/rename it; do not overwrite.
- Empty canonical directory → use it.
- Export symlink already points at canonical → leave it.
- Broken export symlink → replace it.
- Export symlink to another target, plain file, or real directory → skip that export, report the real current state, and keep the canonical skill usable. Do not copy the skill into `.agents` or `.gemini`.

Keep the generated skill minimal: frontmatter with `name` and trigger-only `description`, concise instructions, and no extra README unless the target skill format explicitly requires it.

The skill proposal therefore looks slightly different — it asks for permission to create or delegate:

```
🔁 Цей flow підходить для повноцінного скіла: 5 кроків, чіткі тригери, реюзабельно між проєктами.
   skill: оформити як user-level skill (delegate to writing-skills if available, otherwise create directly)?

   [y] створи  /  [n] не зараз  /  [пізніше]
```

On `y`, prefer handing off to `superpowers:writing-skills` when available, with a one-paragraph brief describing the flow, triggers, intended scope, and the shared canonical + symlink export topology. If no helper is available, create the skill directly in the registry described above and show the path. The reflection's `Автоматизував:` field records either `skill — delegated to writing-skills (subject: {brief})` or `skill — created at {path}`.

### Anti-noise rules for crystallization

The proposal flow has its own anti-noise constraints, separate from the reflection-block anti-noise rule:

- **Don't propose if the user already refused this normalized pattern in this session.** Refusals are sticky for the session.
- **Don't propose for ambient commands** — `ls`, `cd`, `pwd`, `git status`, `git log`, `cat`, `wc`, `grep` of well-known paths. These are exploration noise, not patterns worth crystallizing.
- **Don't propose if arguments are radically different each time.** If you ran `curl` against five different URLs with five different cookies, that's ad-hoc exploration, not a crystallizable pattern. Look for repeated *shape*, not repeated *invocation*.
- **Don't propose wiki for one-shot content** — deploys, schema migrations, one-time data fixes. Even if the same block was generated three times in a row, if it has no recurring lookup value (the script will never run again, the migration is done), filing it wastes wiki real estate. Crystallize only when "next session will need to read this" is plausibly true.
- **Don't propose a skill when a wiki page covers it.** Wiki is the cheaper, lower-maintenance store. Promote to skill only when the pattern is multi-step, has clear triggers, and is reusable across projects. Over-promotion is its own form of noise.
- **Don't crystallize user-runnable scripts.** If you find yourself wanting to propose `scripts/{name}.sh` or `scripts/{name}.py` as a saved artifact, stop — that route was deliberately removed (Division of Labor). Either capture the underlying content as a wiki page the agent reads back, or run an inline command at the moment of need without crystallizing.

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
