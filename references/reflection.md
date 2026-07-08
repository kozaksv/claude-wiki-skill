## Self-Improvement Loop

The wiki is not just a passive store — it is a feedback loop. After meaningful work the agent emits a **РЕФЛЕКСІЯ block** (a strict-template visible narrative) that surfaces what was learned, where it was filed, and whether anything is worth automating. This is the wiki's debug-readability layer: it lets the user (and the agent itself, on the next session) see how knowledge accumulated.

### Overview

Reflection has two purposes:

1. **Visible reasoning** — a short, predictable block that lets the user verify the agent didn't just edit files, it actually thought about the diff. Hermes-style silent telemetry stays in `.usage.json`; РЕФЛЕКСІЯ is the loud counterpart.
2. **Crystallization trigger** — every reflection is an opportunity to ask "is this pattern worth saving so the next session doesn't have to re-derive it?". Load `references/crystallization.md` when a proposal is plausible; the reflection block names what was crystallized in the `Автоматизував:` field (`wiki — concepts/{name}.md`, or `нічого` with reason).

Reflection fires on **events**, not on a timer the skill maintains. The agent is responsible for self-checking the trigger conditions on every operation — there is no harness-side counter.

### РЕФЛЕКСІЯ block format (strict template)

Print this verbatim at the end of a triggered turn. Do not paraphrase the field labels — they are part of the contract:

```
📚 РЕФЛЕКСІЯ — {YYYY-MM-DD HH:MM} — trigger: {todo-completion / pre-commit / memory-flush / explicit / periodic-nudge}

Дізнався: {one sentence — what new insight emerged}
Чому це краще: {one or two sentences — why it works, why this approach}
Зберіг у wiki: [[page-a]], [[page-b]]   (or: «не торкав wiki — нічого синтетичного»)
Автоматизував: {wiki — concepts/{name}.md  /  нічого + причина}

[ONLY if structural files were touched (index.md / schema.md / log.md / .usage.json):]
Перевірив:
  ✅ {what was updated}
  ✅ {what was updated}
  ⚠️ {what was skipped and why}
```

The block ends on `Автоматизував:` (or `Перевірив:` when present) — no trailing interrogation, no y/n menu. The **one exception**: on a `trigger: pre-commit` turn where passive drift signals exist (dead cross-refs / schema drift — the same cheap, no-LLM-read signals `wiki status` computes), append a single non-interactive pointer line after the block:

```
⚠️ Вікі: {N} пасивних дрифт-сигналів — запусти `wiki status` для деталей
```

This asks nothing and runs nothing — it only points at the manual entry point (`wiki status`). It never appears on any other trigger, and it never appears on a pre-commit turn with no drift signal. See `references/cleanup-flow.md` for the full contract behind this notice.

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
- A cleanup-flow run (entered via `wiki status [a]/[b]/[c]`) → no reflection. The action menu and revert section in the cleanup report serve the same purpose.
- An Ingest-Source that read 5 pages and edited 3 → reflection fires.
- An Init that created files → reflection fires (structural changes always reflect).

If unsure, lean toward firing reflection — over-reporting is recoverable, under-reporting hides reasoning. Anti-noise is for the obvious cases (literally nothing was written).
