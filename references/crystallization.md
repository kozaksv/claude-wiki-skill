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
