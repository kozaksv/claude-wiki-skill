# Scenario: Tiered Crystallization proposals

Six sub-scenarios that exercise the proposal flow defined in `SKILL.md` →
`## Self-Improvement Loop` → `### Tiered Crystallization`. Each runs against a
v4-shaped test wiki and asserts whether the skill emitted a `🔁 Помічаю патерн:`
proposal (or correctly suppressed one under anti-noise rules), at which tier, and
what landed in the reflection's `Автоматизував:` field.

## Common setup

Mock wiki state (shared by all sub-scenarios):

- `docs/wiki/schema.md` with `wiki_version: "4.0"` frontmatter (current state)
- `docs/wiki/index.md`, `docs/wiki/log.md`, `docs/wiki/.usage.json` present
- `docs/wiki/concepts/` populated with a few existing pages
- Project root has `scripts/` directory (initially empty)
- `.gitignore` contains `docs/wiki/.usage.json`

The trigger for crystallization checks throughout this file is **periodic nudge**
(the agent self-checks ~15 tool-calling iterations since the last crystallization
check) unless noted otherwise. The `Автоматизував:` field cited in each scenario
appears in the РЕФЛЕКСІЯ block at the close of the relevant turn — see
`reflection-triggers.md` for the surrounding block format.

---

## Sub-scenario 1: Tier 1 (bash one-liner)

### Setup

During this session the agent has run, three times across different turns:

```
curl -s -b "better-auth.session_token=..." http://localhost:3001/api/courses \
  | jq '.data[] | select(.cancelledAt == null) | .id'
```

Each invocation has the same shape — same cookie name, same endpoint pattern,
same `jq` filter — only the path after `/api/` changes between sessions, but the
shape is stable.

### Trigger

The 15-iteration mark passes during a routine wiki query. The agent self-checks
the periodic nudge.

### Expected skill behavior

1. Agent reviews recent tool history, recognizes the repeating shape.
2. Agent confirms it's not on the anti-noise list (not ambient; arguments share
   shape; not a one-shot operation).
3. Agent emits a tier-1 proposal.

### Expected output (proposal block)

```
🔁 Помічаю патерн: за останні 15 ітерацій ти 3 рази робив curl з cookie better-auth + jq по JSON.
   Tier 1 (bash one-liner): scripts/auth-curl.sh

   Створити? [y] / [n] / [пізніше]
```

### Expected agent behavior on each user response

| User reply | Agent action | `Автоматизував:` field value |
|---|---|---|
| `y` | Create `scripts/auth-curl.sh` (≤20 lines, accepts path + filter as args), show its content inline, stage with `git add scripts/auth-curl.sh`. | `tier 1 — scripts/auth-curl.sh` |
| `n` | Do not create. Record refusal for this normalized pattern in this session — do not re-propose this session. | `нічого — юзер відмовив раніше` |
| `пізніше` | Do not create now; pattern remains eligible for re-proposal at next nudge. | `нічого — відкладено` |

### Manual verification

- On `y`: `ls scripts/auth-curl.sh` exists, file is ≤20 lines, executable bit
  set, `git diff --cached` shows it staged.
- On `n`: at the next nudge in the same session, the agent does NOT propose the
  same pattern again, even if the curl invocation repeats.
- On `пізніше`: at the next nudge (~15 iterations later), the agent re-checks
  and may re-propose if the pattern is still active.

---

## Sub-scenario 2: Tier 2 (Python script)

### Setup

During this session the agent has, twice in different turns, parsed the API's
JSON response, joined data from two endpoints, computed a derived value, and
piped through error-handling logic for missing fields. Each time it took 6-8
tool calls of `Read`, `Bash` (curl), and inline reasoning.

### Trigger

The 15-iteration nudge fires. Agent recognizes a multi-step flow with
conditions and parsing, repeated more than once.

### Expected skill behavior

1. Agent reviews recent flow, sees that bash + jq alone is not enough (needs
   conditional branching, error handling, possibly retries).
2. Agent picks tier 2, not tier 1 — bash one-liner won't capture the value.
3. Agent emits a tier-2 proposal.

### Expected output (proposal block)

```
🔁 Помічаю патерн: за сесію двічі робив join двох API endpoints + умовну агрегацію з обробкою missing fields.
   Tier 2 (Python script): scripts/aggregate-courses.py

   Створити? [y] / [n] / [пізніше]
```

### Expected agent behavior on `y`

- Create `scripts/aggregate-courses.py` with argparse for inputs, structured
  error handling, and clear `--help` output.
- Show content inline, stage with `git add`.
- Reflection's `Автоматизував:` field records `tier 2 — scripts/aggregate-courses.py`.

### Manual verification

- `python3 scripts/aggregate-courses.py --help` returns a usage block.
- File handles the missing-field case observed during the session (regression).
- `git diff --cached` shows it staged but not committed (user commits when ready).

### Tier discrimination check

If the same flow had been a single curl + jq with a static filter, the agent
should have proposed tier 1 instead. **Lowest viable tier wins** — see anti-noise
rules.

---

## Sub-scenario 3: Tier 3 (wiki concept page)

### Setup

During this session, and based on log evidence from prior sessions
(`docs/wiki/log.md`), the agent has explained the same conceptual mechanism
three times across turns: how `cookie better-auth.session_token` interacts with
the dev server's middleware to bypass the login form.

No existing wiki page covers this. The repetition is **conceptual**, not
command-shaped — the user keeps asking variations of "why does this auth
recipe work" and the agent keeps re-deriving the answer.

### Trigger

The 15-iteration nudge fires after the third re-explanation.

### Expected skill behavior

1. Agent recognizes that the repetition is in the *explanation*, not in the
   *command sequence*. Tier 1/2 don't apply (there's no repeated invocation
   shape — the commands are routine).
2. Agent searches existing wiki for any page covering this topic. Finds none.
3. Agent emits a tier-3 proposal.

### Expected output (proposal block)

```
🔁 Помічаю патерн: за сесію тричі пояснював як better-auth.session_token cookie
   обходить login flow у dev. Жодна wiki-сторінка це не покриває.
   Tier 3 (wiki concept page): docs/wiki/concepts/dev-auth-bypass.md

   Створити? [y] / [n] / [пізніше]
```

### Expected agent behavior on `y`

- Create `docs/wiki/concepts/dev-auth-bypass.md` with frontmatter (`category:
  dev-recipes`), a short narrative section, a `## Sources` block pointing at
  the auth middleware code, and a `## See also` linking to related pages.
- Append `index.md` with the new entry.
- Append `log.md` with `## [{today}] crystallize | tier 3 dev-auth-bypass`.
- `bump_patch` for the new page in `.usage.json`.
- Reflection's `Автоматизував:` field records `tier 3 — concepts/dev-auth-bypass.md`.

### Manual verification

- `cat docs/wiki/concepts/dev-auth-bypass.md` shows a coherent narrative, not a
  copy-paste of three Q&A blocks.
- `index.md` lists the new page under Concepts.
- `log.md` has the crystallization entry.

### Tier discrimination check

If the topic had been a single command-shape (regardless of how many times
explained), tier 1 should have won — a `scripts/auth-curl.sh` recipe is
self-documenting and tokenwise cheaper than a wiki page. Tier 3 is for
*conceptual* repetition that doesn't reduce to a command.

---

## Sub-scenario 4: Tier 4 (full skill via writing-skills delegation)

### Setup

During the session the agent has executed a 5-step flow with clear trigger
conditions ("user pastes a screenshot of a store order → extract order data →
match line items to wiki entities → create Purchase record → run a verification
query"). The flow has been repeated twice in this session and three times in
prior sessions (per log evidence).

The flow is reusable across projects (it's not Health-specific — any project
with order screenshots and a Purchase entity could use it).

### Trigger

The 15-iteration nudge fires.

### Expected skill behavior

1. Agent recognizes a multi-step flow with explicit triggers, reusable across
   projects → tier 4 territory.
2. **Crucial:** the wiki skill does NOT create `~/.claude/skills/{name}/SKILL.md`
   itself. It delegates to `superpowers:writing-skills`.
3. Agent emits a tier-4 proposal that asks for permission to *delegate*, not to
   *create*.

### Expected output (proposal block)

```
🔁 Цей flow підходить для повноцінного скіла: 5 кроків, чіткі тригери, реюзабельно між проєктами.
   Tier 4 (full skill): передати у superpowers:writing-skills для оформлення?

   [y] делегуй  /  [n] не зараз  /  [пізніше]
```

### Expected agent behavior on `y`

- Hand off to `superpowers:writing-skills` with a one-paragraph brief
  describing the flow, its triggers, and intended scope. The hand-off itself
  is what creates the skill files; this skill does not write SKILL.md.
- Reflection's `Автоматизував:` field records `tier 4 — delegated to writing-skills (subject: {brief})`.

### Manual verification

- After `y`, the next turn shows `superpowers:writing-skills` as the active
  skill, not `wiki`.
- No `Write` tool call from the wiki skill targets `~/.claude/skills/...`.
- Reflection's `Автоматизував:` field clearly cites the delegation, not a
  direct creation.

### Separation-of-concerns check

If the wiki skill ever creates `~/.claude/skills/{name}/SKILL.md` directly,
that's a bug — file an issue. Skill conventions (frontmatter, evals, naming,
ecosystem placement) live in `superpowers:writing-skills`. The wiki skill knows
wiki conventions only.

---

## Sub-scenario 5: Anti-noise — refused pattern not re-proposed

### Setup

Sub-scenario 1 fires; the user replies `n`. The session continues. The same
curl + jq pattern recurs three more times in subsequent turns.

### Trigger

The next periodic nudge (~15 iterations after the refusal).

### Expected skill behavior

1. Agent does its periodic-nudge self-check.
2. Agent recognizes the curl + jq pattern again.
3. Agent finds the refusal record for this normalized pattern in the session.
4. Agent **does not** re-propose. The refusal is sticky for the session.

### Expected output

No `🔁 Помічаю патерн:` block for this pattern. If a *different* pattern is
crystallization-eligible, that one may surface; otherwise the periodic nudge
silently passes (the agent may still emit the surrounding РЕФЛЕКСІЯ block, but
its `Автоматизував:` field reads `нічого — юзер відмовив раніше` rather than a
fresh proposal).

### Manual verification

- Search the post-refusal turns for `🔁 Помічаю патерн: .* curl .* better-auth`
  → must return zero matches for the rest of the session.
- The session's refusal record is implicit (not persisted across sessions). In
  a fresh session the agent may re-propose, since session-scoped refusal is
  intentional — the user might change their mind day-over-day.

---

## Sub-scenario 6: Anti-noise — ambient commands ignored

### Setup

During this session the agent has run, ~20 times across turns:

- `ls -la`
- `cd ~/some/path`
- `pwd`
- `git status`
- `git log --oneline -5`
- `cat README.md`

These are exploration noise — the agent is navigating, not executing a
repeatable workflow.

### Trigger

The 15-iteration periodic nudge fires.

### Expected skill behavior

1. Agent reviews recent tool history.
2. Agent recognizes the candidates as ambient commands per anti-noise rules.
3. Agent **does not** propose any tier 1/2 script wrapping `ls`, `git status`,
   `cat`, etc.

### Expected output

No `🔁 Помічаю патерн:` block. Any reflection that fires on hard events shows
`Автоматизував: нічого — патерн не повторюється` (not a proposal).

### Manual verification

- No `scripts/ls-helper.sh` or similar gets proposed at any point in the session.
- The anti-noise rule explicitly listing `ls / cd / pwd / git status / git log /
  cat / wc / grep` of well-known paths covers this case — see `SKILL.md` →
  `### Anti-noise rules for crystallization`.

### Edge case: ambient command as part of a larger flow

If the agent runs `git status` once and `git diff` once and then a custom
multi-step verification, the verification flow itself may still be
crystallization-eligible — but its proposal must describe the *flow*, not the
ambient prefix. The anti-noise rule excludes the prefix from triggering, not
from the wider context.
