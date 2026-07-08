## Operation: Wiki Doctor

Read-only diagnostic. Collects the health of the wiki *and* the optional
Claude Code hook-provisioning layer, prints a structured ✅/⚠️ report, then
offers a DECIDE menu of repairs. **Doctor itself changes nothing** — every
repair it offers is an existing mechanism (Step 0 repair gates, `wiki init`
migration, `install-hooks.sh`/`uninstall-hooks.sh`, manual telemetry). Doctor
only collects, reports, and routes; it never writes on its own initiative.

### When to invoke

User says one of:

- "wiki doctor"
- "полікуй вікі"
- "перевір здоров'я вікі"
- "онови вікі"

If the trigger is ambiguous, confirm before running — same rule as `wiki status`.

### Reference Loading Map (internal)

Doctor draws on these references while running its checks — load them as needed, not all up front:

| Check group | Reference |
|---|---|
| Pointers, schema version | `references/discovery-versioning.md` |
| Hooks, heartbeats | `references/discovery-versioning.md` (Hook provisioning) |
| `.usage.json` fields, `_hooks` metadata | `references/telemetry.md` |
| Known pitfalls to call out in the report | `references/maintenance-and-mistakes.md` |

### Process

```
0. DISCOVER wiki location (Step 0 above) — also gives version state
1. RUN the 6 check groups below (read-only, never write)
2. PRINT structured report (template below)
3. OFFER a numbered repair menu built only from findings that have ⚠️
4. ROUTE the user's choice into the matching existing mechanism (never a
   new, doctor-specific repair path)
```

### Check groups

**(1) Pointers.** Re-run the pointer-validation part of Step 0
(`CLAUDE.md`/`AGENTS.md`/`GEMINI.md` → `## Wiki` → resolves to `{wiki}/index.md`)
without acting on it. ✅ every discovered instruction file's pointer resolves
to a valid `index.md`. ⚠️ a pointer is stale/broken/missing for an agent whose
instruction file exists — repair routes to the existing Step 0
pointer-repair/cross-agent-sync flow (`references/discovery-versioning.md`).

**(2) Schema version.** Read `wiki_version` from `{wiki}/schema.md`
frontmatter and compare its **major** component against this SKILL.md's
`version` major — an **equal-major** comparison, never exact full-version
string equality. Per the Versioning & Migration table: schema major `4`
(from `wiki_version: "4.0"`, `"4.1"`, …) matches skill major `4` (from
`version: "4.5.0"`, `"4.4.0"`, …). v4.x releases change agent/installer
behavior, not the on-disk wiki schema, so a fresh v4.x skill still writes
(and reads back) `wiki_version: "4.0"` and that is `current` — comparing the
full version strings for equality would wrongly flag every healthy v4 wiki
as legacy/older. ✅ state is `current` (schema major == skill major). ⚠️
state is `legacy`/`older`/`newer` per the Versioning & Migration table —
repair routes to the existing migration flow, never an auto-migration from
doctor itself.

**(3) `.usage.json`.** Parse the sidecar. ✅ parses as JSON, and every
non-`_`-prefixed record carries all ten fields (`view_count`, `use_count`,
`patch_count`, `last_viewed_at`, `last_used_at`, `last_patched_at`,
`created_at`, `state`, `protected`, `archived_at`). ⚠️ file is unparseable
(repair: treat as `{}`, let the next write rebuild it — same tolerance rule
as normal operation, not a doctor-specific fix); ⚠️ a record is missing
fields (repair: silent backfill on next read/write, per
`references/telemetry.md` tolerance rules); ⚠️ **phantom records** — a page
path key with no corresponding file under `{wiki}/concepts/`,
`{wiki}/entities/`, or `{wiki}/transcripts/` (repair: drop the orphaned
record on the next telemetry write, purely bookkeeping). Keys starting with
`_` (e.g. a future `_hooks` metadata key) are **not** page records and must
never be flagged as phantom or missing-fields — they are reserved metadata,
skip them in this check entirely.

**(4) Symlink exports.** Check the cross-agent symlink exports from the
canonical `~/.claude/skills/wiki/` clone (per Core Invariants — DRY topology,
shared canonical registry). ✅ expected per-agent export symlinks exist and
resolve to the canonical clone. ⚠️ an export is missing or dangling — repair
routes to the existing installer self-heal (same mechanism Init already uses
to fix cross-agent skill export drift).

**(5) Hooks.** Three sub-checks, all read-only:
- **Marker present?** Does `~/.claude/settings.json` contain a hook entry
  whose `command` uses the canonical symlink path
  `~/.claude/skills/wiki/hooks/…` (not a resolved-clone path)? ✅ marker
  present. ⚠️ marker absent — this project could benefit from hook
  provisioning; repair routes to the Hook provisioning DECIDE
  (`references/discovery-versioning.md`), not a silent install from doctor.
- **Scripts executable, python3 present?** ✅ `hooks/session-start.sh` and
  `hooks/post-tool-use.sh` (and `hooks/lib/*.sh`) are executable, and
  `python3` resolves on `PATH`. ⚠️ a script lost its executable bit, or
  `python3` is missing — report the exact cause (hooks fail open silently
  otherwise, this is the one place that surfaces *why*); repair is `chmod +x`
  on the affected script(s), or "install python3" as a manual note (doctor
  does not install interpreters).
- **Heartbeats — checked SEPARATELY, never conflated.** `index injected`
  (fresh `_hooks.session_start_at`) and `telemetry active` (fresh
  `_hooks.post_tool_use_at`) are two independent signals — see
  `references/telemetry.md` for the full dual-signal rule. ✅ both
  timestamps are fresh. ⚠️ `session_start_at` fresh but `post_tool_use_at`
  stale or absent → **"SessionStart живий, PostToolUse-телеметрія мертва"**
  — the *injected-but-dead* state: the index-injection hook fires, but the
  per-Read/Edit/Write telemetry hook does not (missing `python3`, a stdin
  field mismatch, or a write failure). Report this distinctly from "no
  marker at all" — it means hooks are registered and partially working, not
  simply absent. ⚠️ both timestamps stale or absent while the marker is
  present → hooks are registered but not firing at all; repair routes to
  re-checking the marker's `command` path and script executability (the two
  checks above), never a blind reinstall.

**(6) Git state of the wiki.** ✅ `{wiki}/` has no uncommitted changes and
the containing repo's git metadata is reachable (Step 0's git-root
requirement still holds). ⚠️ uncommitted wiki edits exist — report them,
suggest committing before further wiki writes (consistent with the
git-backed-wiki invariant: snapshots/rollback/lint auto-fixes rely on
commits); ⚠️ git metadata unreachable (e.g. a `.git` file pointing at a
removed worktree) — same guidance as Step 0: `git worktree repair` or
re-create the repo, doctor does not touch git state itself.

### Output template

```
🩺 Wiki Doctor — {wiki-path}

1. Pointери:            ✅ / ⚠️ {details}
2. Версія схеми:         ✅ / ⚠️ {details}
3. .usage.json:          ✅ / ⚠️ {details}
4. Симлінк-експорти:     ✅ / ⚠️ {details}
5. Хуки:
     маркер:             ✅ / ⚠️ {details}
     виконуваність/py3:  ✅ / ⚠️ {details}
     heartbeat:          ✅ / ⚠️ {details}
6. Git-стан wiki:        ✅ / ⚠️ {details}

{numbered repair menu built only from ⚠️ findings, or "Усе гаразд, ремонт не потрібен." if none}
```

Every `{details}` slot is filled with the real, concrete finding — never a
placeholder left un-substituted in the actual response.

### Repair routing — no new mechanisms

Doctor is a **read-only aggregator**. Every repair it offers already exists
elsewhere in the skill:

| Finding | Existing repair mechanism |
|---|---|
| Stale/broken pointer | Step 0 pointer-repair / cross-agent sync (`discovery-versioning.md`) |
| Schema state ≠ `current` | Existing migration flow (`discovery-versioning.md`) |
| Corrupt/incomplete `.usage.json` | Existing tolerance rules — treat-as-`{}` / silent backfill (`telemetry.md`) |
| Phantom telemetry record | Drop on next telemetry write |
| Missing/dangling symlink export | Existing installer self-heal |
| No hook marker | Hook provisioning DECIDE (`discovery-versioning.md`), not a silent install |
| Marker present, no inject | Re-check `command` path + script executability — **not** a blind reinstall |
| Injected-but-dead telemetry | Report the cause (python3 / stdin / write-fail); manual telemetry continues as fallback per `telemetry.md` |
| Uncommitted wiki edits | Suggest a commit before further writes |
| Unreachable git metadata | `git worktree repair` / re-create the repo (same as Step 0) |

Doctor never invents a repair path that doesn't already exist for that
finding class.
