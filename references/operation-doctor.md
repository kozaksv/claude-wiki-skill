## Operation: Wiki Doctor

Read-only diagnostic for wiki content/storage and optional local hook provisioning.
Doctor collects evidence and offers repairs; it never installs hooks, rewrites
metadata, migrates schemas or changes Git state as a diagnostic side effect.

### When to invoke

User asks `wiki doctor`, «перевір здоров'я вікі» or «діагностуй хуки».
An explicit **skill/hook update** uses `references/updating.md`, not a read-only
version check masquerading as an update. An explicit content update uses the
writing workflow. Do not interpret «онови» as proof an update was performed.

### References

Load `discovery-versioning.md` for pointers/schema, `telemetry.md` for local
counters and `updating.md` for installation repair. Read `writer-core.md` before
interpreting legacy protection. `maintenance-and-mistakes.md` covers known pitfalls.

### Process

1. Discover the wiki and Git boundary using the shared discovery parser.
2. Run the six check groups below without writes.
3. Print findings with evidence, verified scope and unavailable checks.
4. Offer repairs only for concrete findings; route an accepted repair to its
   existing mechanism. A previously authorized repair does not need a second gate.

### Check groups

**(1) Pointers.** Validate discovered `CLAUDE.md`, `AGENTS.md`, `GEMINI.md` and
`QWEN.md` Wiki/Вікі pointers against the actual index. Missing or stale pointers
are reported, not rewritten. Repair uses the existing explicit pointer-repair or
`wiki init` workflow; never initialize a second wiki.

**(2) Schema.** Compare the **major** of `wiki_version` and the skill version.
Compare schema major against skill major, never full version equality.
For example, schema `4.0` and skill `4.10.0` are compatible. The schema version
is not an installed-hook version. Legacy/older/newer schema findings route to the
existing migration procedure, not an automatic migration by doctor.

**(3) `.usage.json` and protection.** Parse with duplicate-key rejection. Missing
counters are unavailable, not zero-use evidence. Missing optional fields can be
reported for maintenance backfill; a read-only diagnostic does not write them.
Skip `_`-prefixed metadata when enumerating page records. Resolve records against
the actual knowledge-page tree, including custom folders/history and excluding
navigation/log files. Report orphan records without dropping them.

**Corrupt telemetry stays byte-identical.** Do not treat it as `{}` and rebuild it:
it may carry legacy `protected`/`pinned` state. Unknown legacy protection blocks
destructive maintenance for pages without explicit durable `policy.json` entries.
Use `writer-core.md` and `telemetry.md` for recovery, never invent a doctor-only
reset mechanism. A new absent sidecar and a corrupt existing sidecar are different.

**(4) Canonical install and exports.** Check that `~/.claude/skills/wiki` resolves
to the intended Git checkout, then verify `~/.agents/skills/wiki`,
`~/.gemini/skills/wiki` and `~/.qwen/skills/wiki` exports. Report actual commit,
behavior version and local modifications when accessible; do not infer latest
remote state from a version string. Export repair is `install.sh --repair-exports`.

**(5) Hooks.** Use the read-only inventory:

```bash
bash "$HOME/.claude/skills/wiki/hooks/doctor.sh" --project "<verified-project-root>"
```

Repeat `--project` only for user-selected projects/worktrees. The report checks
user settings and these projects' settings/local settings, canonical commands,
matchers, duplicate/legacy registrations, `disableAllHooks`, executable scripts
and their SHA-256 identities. Python missing, settings corruption or inaccessible
paths are specific failures, not «no hooks found». Managed/plugin hooks are outside
this mutator's scope; inspect `/hooks` without deleting or executing unknown commands.

A `WIKI DISCOVERY (hook)` block proves discovery ran, **not** READ FIRST and not
that all registrations are current. A second `WIKI INDEX (hook-injected)` block
is evidence to investigate another registration or old context. Neither block is
permission to reinstall blindly. Use the inventory and the accepted repair flow.

Check heartbeats **separately**:

- Fresh `_hooks.session_start_at`: SessionStart telemetry wrote a heartbeat.
- Fresh `_hooks.post_tool_use_at` after a qualifying knowledge-page Read/Edit/Write:
  positive evidence that the per-tool telemetry recorded an event.
- Stale or absent PostToolUse: **unconfirmed**, not automatically dead. Index,
  schema, log pages and shell-based reads are excluded; different clones have
  separate sidecars. Lack of an eligible event is not a hook failure.

Call the historic «SessionStart живий, PostToolUse-телеметрія мертва» /
*injected-but-dead* state confirmed only after independent evidence of a qualifying
same-clone event with no corresponding write (or a concrete missing interpreter,
invalid registration or write error). Do not start an unbounded transcript scan
on every startup. Normal reads may trigger independently installed hooks; doctor
itself does not invoke a synthetic mutating hook or manually bump counters.

**(6) Git state.** Report uncommitted wiki changes and inaccessible Git metadata.
Suggest committing before maintenance; an unreachable worktree uses existing
`git worktree repair` guidance. Doctor never initializes Git or commits changes.

### Output

```text
🩺 Wiki Doctor — <wiki path>
1. Покажчики: <finding>
2. Схема: <finding>
3. Телеметрія / захист: <finding>
4. Canonical install / exports: <finding>
5. Hooks: <registration audit; discovery and PostToolUse evidence separately>
6. Git: <finding>
Область перевірки: <actual paths; unavailable/unchecked sources>
```

Include concrete findings, not placeholders. Repairs must explain which files
will change. Hook repair uses `install-hooks.sh --verify --project <root>`;
actual version update uses `updating.md`. Failed verification is an incomplete
repair, never a success merely because the text skill is usable.
