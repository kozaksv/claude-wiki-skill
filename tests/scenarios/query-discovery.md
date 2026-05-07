# Scenario: Query discovery — proactive trigger on natural phrasing

Five sub-scenarios that exercise the proactive query model defined in `SKILL.md`
→ frontmatter description (proactive trigger c) and `## Operation: Query` →
`### When to Query` (master rule). Each runs against a v4-shaped test wiki and
asserts whether the skill correctly invoked Query before generating
project-specific content — without requiring the user to use the word "wiki".

## Common setup

Mock wiki state (shared by all sub-scenarios):

- `docs/wiki/schema.md` with `wiki_version: "4.0"` frontmatter (current state)
- `docs/wiki/index.md`, `docs/wiki/log.md`, `docs/wiki/.usage.json` present
- `docs/wiki/concepts/` populated; in particular:
  - `concepts/openssh-on-windows-dc.md` exists with a paste-able PowerShell
    install block and post-install verification commands
  - `concepts/dev-auth-bypass.md` exists with the better-auth cookie recipe
- `docs/wiki/entities/uran.md` exists pointing at `[[openssh-on-windows-dc]]`

The test isn't about whether the wiki has the right content — it's about
whether the skill **finds and reads** that content before the agent answers
from training-data memory.

---

## Sub-scenario 1: Positive — natural Ukrainian phrasing triggers query

### Setup

User opens a fresh session in this project and types:

```
давай налаштуємо openssh на uran
```

Note: no "wiki", "вікі", "знайди", or any other explicit-trigger keyword.

### Expected skill behavior

1. Frontmatter description's proactive trigger (c) matches the «налаштуємо X»
   shape → skill activates.
2. `### When to Query` master rule fires — agent recognizes this is a
   project-specific setup task, defaults to query before generating.
3. Agent runs Query operation:
   - reads `index.md`
   - identifies relevant pages (entity `uran`, concept `openssh-on-windows-dc`)
   - reads them (`bump_view` for each)
4. Agent uses the wiki content directly — pastes the PS install block from
   `openssh-on-windows-dc.md` rather than re-generating from memory.

### Manual verification

- Telemetry: `view_count` for both `entities/uran.md` and
  `concepts/openssh-on-windows-dc.md` increments by 1 in `.usage.json`.
- Agent's reply contains the **same PS block as the wiki page**, not a
  paraphrased / regenerated version. Diff between agent reply and wiki page
  content for the install block should be zero modulo whitespace.
- Agent cites `[[openssh-on-windows-dc]]` (or equivalent reference syntax)
  visibly in the reply, so the user knows where the answer came from.

### Why this matters

This is the canonical regression case from the skill's reflection examples.
The pre-v4.1 failure mode: user types "налаштуй X", skill doesn't activate,
agent generates from memory, content is correct-ish but lacks
project-specific decisions. Sub-scenario 1 is the cure.

---

## Sub-scenario 2: Positive — query finds page; no re-derivation

### Setup

Mid-session continuation. User asks:

```
а як та auth bypass cookie взагалі працює?
```

The wiki has `concepts/dev-auth-bypass.md` covering this exactly.

### Expected skill behavior

1. Frontmatter trigger matches «як працює X» shape.
2. Agent does Query — finds `dev-auth-bypass.md`, reads it.
3. Agent answers from the wiki page, citing `[[dev-auth-bypass]]`. Does NOT
   re-derive the explanation from training data even if it "knows" how
   better-auth works generally.

### Manual verification

- `view_count` for `concepts/dev-auth-bypass.md` increments.
- Agent's explanation matches the wiki page's framing, not a generic
  better-auth tutorial.
- If the wiki page mentions a project-specific quirk (e.g. "we keep this
  cookie httpOnly=false in dev to allow client-side debugging"), that quirk
  must appear in the agent's reply.

### Edge case: wiki page is incomplete

If the wiki page covers half the question, the agent reads what's there,
answers from it, and explicitly flags the gap: «Wiki покриває X, але про Y
сторінка мовчить — додам після твого підтвердження.» Then crystallization
(append-to-page proposal) becomes eligible.

---

## Sub-scenario 3: Discovery signal — query finds nothing, crystallization
candidate flagged

### Setup

User asks:

```
як ми робимо backup для postgres у staging?
```

No wiki page covers this. Project does have a backup workflow but it lives
only in commit history and shell aliases, not the wiki.

### Expected skill behavior

1. Agent runs Query — searches `index.md` and headlines, finds nothing
   relevant (or only weakly relevant pages like `concepts/postgres-setup.md`
   that doesn't cover backup).
2. Agent reports the find-nothing result honestly: «У wiki не знайшов сторінки
   про staging-backup. Дивлюся git history / scripts.»
3. Agent investigates via other channels (git log, `package.json` scripts,
   ad-hoc grep) and synthesizes the answer.
4. Agent **flags this as a crystallization candidate**. After answering, the
   reflection block (if it fires) lists this in the `Автоматизував:` field as
   a wiki proposal: «wiki: concepts/postgres-staging-backup.md».

### Manual verification

- The find-nothing case is reported, not silently ignored.
- After the answer, a `🔁 Помічаю патерн:` block proposes a wiki page (per
  `## Self-Improvement Loop > ### Crystallization`).
- If the user accepts (`y`), the new page is filed; if `n`, the refusal is
  recorded session-scoped.

### Why this matters

This sub-scenario exercises the **discovery ↔ crystallization pair**: query
reads what was saved, crystallization saves what was re-derived. Find-nothing
isn't a failure — it's a signal.

---

## Sub-scenario 4: Anti-noise — ambient commands don't trigger query

### Setup

During a turn the user types:

```
ls
```

or:

```
покажи git log
```

or:

```
що в pwd
```

### Expected skill behavior

1. Frontmatter trigger does not match — these are exploration/ambient ops,
   not project-specific content questions.
2. Skill may activate (or may not), but in either case Query is NOT invoked.
3. Agent runs the literal command (`ls`, `git log`, `pwd`) and shows output.

### Manual verification

- No `bump_view` for any wiki page during the turn.
- No `Read` of `docs/wiki/index.md` happens before the `ls` / `git log` /
  `pwd` execution.
- Agent does NOT volunteer wiki content for ambient questions. Wiki is
  reserved for project-specific knowledge retrieval.

### Edge case: ambient + project-specific in the same turn

If the user says «покажи git log і скажи що каже wiki про auth», split:
- `git log` runs immediately (ambient, no query).
- The «що каже wiki про auth» half explicitly invokes Query → fires normally.

---

## Sub-scenario 5: Backward compat — explicit "wiki" keyword still works

### Setup

User types one of:

- «що каже wiki про auth»
- «знайди у вікі про uran»
- «wiki query openssh»

### Expected skill behavior

1. Frontmatter trigger matches the explicit-keyword form (preserved from
   pre-v4.1).
2. Agent runs Query as before.

### Manual verification

- The explicit-form triggers fire identically to the proactive form: same
  Query operation, same telemetry, same citation behavior.
- This is a regression test: the v4.1 proactive enhancement must not break
  any pre-existing explicit invocation.

### Why this matters

Even though users no longer need the "wiki" keyword (sub-1 demonstrates the
proactive path), advanced users who know the keyword should still be able to
invoke Query directly. Removing the explicit form would punish them.
