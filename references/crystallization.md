### Crystallization

The reflection's `Автоматизував:` field isn't decorative — it's the agent's answer to a real question: **is anything from this block worth saving so the next session doesn't have to re-derive it?** When the answer is yes, the agent **proposes** (never silently creates) a single wiki-page artifact — never a skill.

| Type | Artifact | Storage | What the model judges (during a periodic nudge) |
|---|---|---|---|
| **wiki** | new or extended `concepts/{name}.md` (recipe, ready-made block, concept explanation) | `{wiki}/concepts/` | "I re-derived this content from scratch this session — paste-able block, recipe, or concept the next session would also need. File it so the next read finds it instead of regenerating." |

**Why no `scripts/` tier.** Earlier versions proposed `scripts/{name}.sh` and `scripts/{name}.py` as crystallization tiers; removed v4.1 as a Division-of-Labor violation (user-runnable artifacts don't belong in an agent-curated store). See the Migration Log in `references/discovery-versioning.md` for the historical entry.

**Memory is not a tier either.** The auto-memory mechanism already saves user feedback / preferences automatically, without skill involvement. Wiki is the project-scoped, version-controlled, lint-verified store; auto-memory is the volatile sticky-note layer. They are perpendicular; this skill operates only on wiki pages.

**These are heuristics for the model's holistic judgment during a periodic nudge — NOT counters this skill maintains algorithmically.** The trigger model is a periodic nudge that asks "consider crystallizing", and the model decides. Don't try to count normalized commands or de-dupe argv vectors. Read the room.

### Crystallization triggers

| Trigger | Default | Behavior |
|---|---|---|
| Periodic nudge | Every ~15 tool-calling iterations since the last crystallization check | Self-checked. On each operation, briefly notice whether ~15 tool calls have passed; if yes, ask yourself "є щось варте автоматизації?" and surface a proposal if the answer is yes. The skill is purely instructional — there is no harness-side counter; the model is responsible for self-pacing. |
| Pre-commit | Immediately before `git commit` | Hard trigger — paired with reflection. Always check for crystallization candidates at this moment. |
| Task-completion | Last todo/plan item → `completed` | Hard trigger — paired with reflection. |
| Pre-compression flush | User-explicit ("save before /compress" / "збережи перед стисненням") | Guaranteed turn for writing crystallizable patterns out before context is lost. The harness does not signal compression to skills, so this depends on the user. |
| Explicit user | "збережи у вікі" / "save as wiki page" | Manual override — skip judgment, go straight to a wiki proposal. If the user asks for a script (`scripts/*.sh` / `*.py`), explain that this skill no longer crystallizes user-runnable scripts (Division of Labor) and offer the wiki-page equivalent. The user can still create a script manually if they want — the skill just doesn't propose it. |
| Disabled | `nudge_interval: 0` in `{wiki}/schema.md` frontmatter | Disables the periodic nudge only. Hard triggers (task-completion, pre-commit, explicit user) still fire. |

The default cadence (~15 iterations) can be overridden per-wiki via `nudge_interval: <N>` in `schema.md` frontmatter — see `## Versioning & Migration` for the knob.

### Proposal format

The skill **proposes**; the user decides. Never `Write` a wiki page silently. Use this exact block:

```
🔁 Помічаю патерн: {one-line description of the recurring pattern, with concrete count}
   wiki: {proposed-path}

   Створити? [y] / [n] / [пізніше]
```

Behavior on each response:

- `y` → create the artifact, show its content inline, stage it for commit. The reflection's `Автоматизував:` field records `wiki — {path}`.
- `n` → do not create. Record the refusal for this normalized pattern in this session — **do not re-propose the same pattern this session**. The reflection's `Автоматизував:` field records `нічого — юзер відмовив раніше`.
- `пізніше` → do not create now, but the pattern is still eligible for re-proposal at the next nudge. The reflection's `Автоматизував:` field records `нічого — відкладено`.

A concrete wiki example:

```
🔁 Помічаю патерн: за сесію двічі надрукував той самий 60-рядковий PowerShell install-block для OpenSSH на Windows DC.
   wiki: concepts/openssh-on-windows-dc.md (з вбудованим PS-блоком + коли застосовувати)

   Створити? [y] / [n] / [пізніше]
```

### Anti-noise rules for crystallization

The proposal flow has its own anti-noise constraints, separate from the reflection-block anti-noise rule:

- **Don't propose if the user already refused this normalized pattern in this session.** Refusals are sticky for the session.
- **Don't propose for ambient commands** — `ls`, `cd`, `pwd`, `git status`, `git log`, `cat`, `wc`, `grep` of well-known paths. These are exploration noise, not patterns worth crystallizing.
- **Don't propose if arguments are radically different each time.** If you ran `curl` against five different URLs with five different cookies, that's ad-hoc exploration, not a crystallizable pattern. Look for repeated *shape*, not repeated *invocation*.
- **Don't propose wiki for one-shot content** — deploys, schema migrations, one-time data fixes. Even if the same block was generated three times in a row, if it has no recurring lookup value (the script will never run again, the migration is done), filing it wastes wiki real estate. Crystallize only when "next session will need to read this" is plausibly true.
- **Don't crystallize user-runnable scripts.** If you find yourself wanting to propose `scripts/{name}.sh` or `scripts/{name}.py` as a saved artifact, stop — that route was deliberately removed (Division of Labor). Either capture the underlying content as a wiki page the agent reads back, or run an inline command at the moment of need without crystallizing — the wiki page is the single crystallization artifact.
