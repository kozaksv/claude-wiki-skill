# Scenario: Crystallization proposals

Five sub-scenarios that exercise the proposal flow defined in
`references/crystallization.md`. Each runs against a
v4-shaped test wiki and asserts whether the skill emitted a `🔁 Помічаю патерн:`
proposal (or correctly suppressed one) and what landed in the reflection's
`Автоматизував:` field.

## Common setup

Mock wiki state (shared by all sub-scenarios):

- `docs/wiki/schema.md` with `wiki_version: "4.0"` frontmatter (current state)
- `docs/wiki/index.md`, `docs/wiki/log.md`, `docs/wiki/.usage.json` present
- `docs/wiki/concepts/` populated with a few existing pages
- `.gitignore` contains `docs/wiki/.usage.json`

The trigger for crystallization checks throughout this file is **periodic nudge**
(the agent self-checks ~15 tool-calling iterations since the last crystallization
check) unless noted otherwise. The `Автоматизував:` field cited in each scenario
appears in the РЕФЛЕКСІЯ block at the close of the relevant turn — see
`reflection-triggers.md` for the surrounding block format.

The skill recognizes only **one artifact type**: `wiki` (a concept page the
active agent reads back). User-runnable
`scripts/*.sh` and `scripts/*.py` were intentionally removed as a crystallization
target — see "Why no `scripts/` tier" in `references/crystallization.md`.
Sub-scenarios 2 and 3 below
assert that script-shaped proposals are correctly suppressed.

---

## Sub-scenario 1: Wiki page (recurring conceptual content)

### Setup

During this session, and based on log evidence from prior sessions
(`docs/wiki/log.md`), the agent has explained the same conceptual mechanism
three times across turns: how `cookie better-auth.session_token` interacts with
the dev server's middleware to bypass the login form.

No existing wiki page covers this. The repetition is in the *explanation* — the
user keeps asking variations of "why does this auth recipe work" and the agent
keeps re-deriving the answer.

### Trigger

The 15-iteration nudge fires after the third re-explanation.

### Expected skill behavior

1. Agent recognizes that the same content has been re-derived without a wiki
   page to read back next session.
2. Agent searches existing wiki for any page covering this topic. Finds none.
3. Agent emits a wiki proposal.

### Expected output (proposal block)

```
🔁 Помічаю патерн: за сесію тричі пояснював як better-auth.session_token cookie
   обходить login flow у dev. Жодна wiki-сторінка це не покриває.
   wiki: docs/wiki/concepts/dev-auth-bypass.md

   Створити? [y] / [n] / [пізніше]
```

### Expected agent behavior on each user response

| User reply | Agent action | `Автоматизував:` field value |
|---|---|---|
| `y` | Create `docs/wiki/concepts/dev-auth-bypass.md` with frontmatter (`category: dev-recipes`), narrative section, `## Sources` block pointing at the auth middleware code, and `## See also`. Append `index.md` and `log.md`. `bump_patch` for the new page in `.usage.json`. | `wiki — concepts/dev-auth-bypass.md` |
| `n` | Do not create. Record refusal for this normalized pattern in this session — do not re-propose this session. | `нічого — юзер відмовив раніше` |
| `пізніше` | Do not create now; pattern remains eligible for re-proposal at next nudge. | `нічого — відкладено` |

### Manual verification

- On `y`: `cat docs/wiki/concepts/dev-auth-bypass.md` shows a coherent narrative,
  not a copy-paste of three Q&A blocks.
- `index.md` lists the new page under Concepts.
- `log.md` has the crystallization entry.

### Wiki-page integrity check

The page's value to a future agent session is that it can be read **before**
re-deriving the explanation. A wiki page that just paraphrases the user's
question without explaining the actual mechanism fails the test even if it
passes the on-disk assertions.

---

## Sub-scenario 2: Anti-pattern — recurring command does NOT yield a script proposal

### Setup

During this session the agent has run, three times across different turns:

```
curl -s -b "better-auth.session_token=..." http://localhost:3001/api/courses \
  | jq '.data[] | select(.cancelledAt == null) | .id'
```

Each invocation has the same shape — same cookie name, same endpoint pattern,
same `jq` filter — only the path after `/api/` changes between sessions, but the
shape is stable.

In an older version of this skill, the agent would have proposed a tier-1 bash
one-liner at `scripts/auth-curl.sh`. That tier was removed because user-runnable
scripts shift mechanical work back to the user (Division of Labor).

### Trigger

The 15-iteration mark passes during a routine wiki query. The agent self-checks
the periodic nudge.

### Expected skill behavior

1. Agent reviews recent tool history, recognizes the repeating shape.
2. Agent considers crystallization. The only artifact type is `wiki` — neither
   a script nor a skill is a valid crystallization target.
3. Agent evaluates whether there's a recurring lookup value (the cookie format
   has gotchas worth documenting once, the endpoint shape is part of a
   conceptual auth flow that gets re-explained, etc.). If the curl is just a
   tool for inspecting the API and the value is purely runtime, no wiki page
   is warranted.
4. Agent emits **either** a wiki proposal (if the cURL pattern reflects a
   recurring concept) **or** no proposal at all (runtime-only inspection).
   Agent does **not** propose `scripts/auth-curl.sh` and does **not** propose
   any kind of skill artifact — a single-shape command isn't a multi-step flow,
   and the skill has no skill-shaped crystallization tier to propose into
   regardless.

### Expected output

Either:

```
🔁 Помічаю патерн: за сесію тричі робив curl з cookie better-auth для інспекції live API.
   wiki: docs/wiki/concepts/dev-api-inspection.md (з cookie-форматом + типовими jq-фільтрами)

   Створити? [y] / [n] / [пізніше]
```

…or no proposal block (if the agent judges this purely runtime exploration with
no recurring lookup value).

The skill **must NOT** emit any of:

- `tier 1 (bash one-liner): scripts/auth-curl.sh`
- `tier 2 (Python script): scripts/anything.py`
- A proposal whose proposed-path begins with `scripts/`
- A proposal offering to delegate to (or directly create) a skill artifact

### Manual verification

- `grep -E "scripts/.*\.(sh|py)" turn-output` → zero matches inside any
  `🔁 Помічаю патерн:` block.
- `grep -E "tier (1|2|3|4)" turn-output` → zero matches in proposal blocks
  (numbered tiers are gone entirely).
- If a wiki proposal fired and the user accepted, the resulting page is a
  *concept page the active agent reads back*, not a copy-paste of the cURL command with
  no surrounding context.

### Why this matters

This is a regression test against re-introducing user-runnable script tiers. If
a future change restores them, this sub-scenario must catch it.

---

## Sub-scenario 3: Anti-pattern — explicit "save as bash" trigger

### Setup

The user explicitly says one of: «винеси оце в bash-скрипт», «save this as
bash», «create a script for this».

### Expected skill behavior

1. Agent does **not** silently create the script.
2. Agent does **not** propose `scripts/{name}.sh` as a crystallization tier.
3. Agent briefly explains that user-runnable scripts are no longer a
   crystallization target (Division of Labor) and offers the wiki-page
   equivalent: capture the same content as a concept page the active agent reads back.
4. If the user insists on a script regardless, the agent can create it as a
   one-off file (the user's explicit request overrides skill conventions),
   but reflection's `Автоматизував:` field records `нічого — юзер попросив
   скрипт поза tier-моделлю` rather than fabricating a tier name.

### Expected output (illustration)

```
Скіл більше не пропонує user-runnable скрипти як крихталізацію — вони перекидають mechanical work назад на тебе. Замість того ось рівноцінний варіант:

🔁 Помічаю патерн: ...
   wiki: docs/wiki/concepts/{name}.md (з готовим bash-блоком всередині, який активний агент читає і виконує сам наступного разу)

   Створити? [y] / [n] / [пізніше]
```

### Manual verification

- The agent's reply contains the explanation about the removed script tier.
- A wiki-equivalent proposal is offered.
- If the user still says "ні, мені треба скрипт", the agent can create it
  manually but does not pretend it's a crystallization tier.

---

## Sub-scenario 4: Anti-noise — refused pattern not re-proposed

### Setup

Sub-scenario 1 fires; the user replies `n`. The session continues. The same
auth-bypass explanation surfaces three more times in subsequent turns (user
asks fresh variations of the same question).

### Trigger

The next periodic nudge (~15 iterations after the refusal).

### Expected skill behavior

1. Agent does its periodic-nudge self-check.
2. Agent recognizes the auth-bypass conceptual repetition again.
3. Agent finds the refusal record for this normalized pattern in the session.
4. Agent **does not** re-propose. The refusal is sticky for the session.

### Expected output

No `🔁 Помічаю патерн:` block for this pattern. If a *different* pattern is
crystallization-eligible, that one may surface; otherwise the periodic nudge
silently passes (the agent may still emit the surrounding РЕФЛЕКСІЯ block, but
its `Автоматизував:` field reads `нічого — юзер відмовив раніше` rather than a
fresh proposal).

### Manual verification

- Search the post-refusal turns for `🔁 Помічаю патерн: .* better-auth.session_token`
  → must return zero matches for the rest of the session.
- The session's refusal record is implicit (not persisted across sessions). In
  a fresh session the agent may re-propose, since session-scoped refusal is
  intentional — the user might change their mind day-over-day.

---

## Sub-scenario 5: Anti-noise — ambient commands ignored

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
3. Agent **does not** propose any wiki page wrapping `ls`, `git
   status`, `cat`, etc.

### Expected output

No `🔁 Помічаю патерн:` block. Any reflection that fires on hard events shows
`Автоматизував: нічого — патерн не повторюється` (not a proposal).

### Manual verification

- No `concepts/git-status-helper.md` or similar gets proposed at any point.
- The anti-noise rule explicitly listing `ls / cd / pwd / git status / git log /
  cat / wc / grep` of well-known paths covers this case — see
  `references/crystallization.md` → `### Anti-noise rules for crystallization`.

### Edge case: ambient command as part of a larger flow

If the agent runs `git status` once and `git diff` once and then a custom
multi-step verification, the verification flow itself may still be
crystallization-eligible — but its proposal must describe the *flow*, not the
ambient prefix. The anti-noise rule excludes the prefix from triggering, not
from the wider context.
