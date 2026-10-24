# Antigravity CLI 1.4.7 hook fixtures

Raw runtime captures for the Wiki Watchdog epic
([#21](https://github.com/kozaksv/claude-wiki-skill/issues/21)), stage A.
They record what `agy` CLI **1.4.7** actually sent to project-level hooks on
2026-10-24. They are evidence for an adapter profile, **not** a tested Watchdog
adapter and not a claim about other Antigravity versions, the IDE or 2.0.

## Method

- Two throwaway Git repositories `app` and `infra`, each with a tiny wiki;
  `app` has `AGENTS.md` with a `## Wiki` pointer.
- `app/.agents/hooks.json` registers the named key `wiki-watchdog-probe`
  (see [`probe/hooks.json`](probe/hooks.json)) for `SessionStart`,
  `PreInvocation`, `PostToolUse` (`*`), `PostInvocation` and `Stop`.
  The global `~/.gemini/config/hooks.json` was not touched.
- Nested sessions: `agy --print … --add-dir infra` from `app`, model
  `claude-opus-5-5-low`, `--mode accept-edits`. Run 2 continued one
  conversation with `--conversation <id>`.
- Handler: [`probe/logger.py`](probe/logger.py). It injects
  `PROBE-*` ephemeral tokens and asks for one Stop continuation.

| File | Scenario |
|---|---|
| `run1-events.jsonl`, `run1-transcript.jsonl` | Reads in two workspaces, write and edit **refused** by the harness (non-empty `error`), `run_command` |
| `run2-events.jsonl`, `run2-parent-transcript.jsonl` | Turn 1: ephemeral visibility and Stop `continue`. Turn 2 (resume): `write_file` with `Append`. Turn 3: manual `/compact`. Turn 4: `invoke_subagent` (research) |
| `run2-subagent-transcript.jsonl` | The research subagent's own conversation |

Run 1 used an earlier logger revision: ephemeral messages on invocations 0–1
only, Stop always allowed, and no transcript tail.

## Sanitization

- Paths are rewritten: `/probe` (run 2 root), `/probe-run1` (run 1 root),
  `~/…` for the home directory. Timestamps are relative (`ms`).
- Environment: the logger originally captured more than needed. Fixtures keep
  only the names in `inherited_env_names_allowlisted`
  (`ANTIGRAVITY_CONVERSATION_ID`, `ANTIGRAVITY_TRAJECTORY_ID`,
  `ANTIGRAVITY_PROJECT_ID`), never values.
- Transcript steps keep `step_index/source/type/status` and at most 600
  characters of `content`. The original length is kept as
  `content_truncated_from`.

`tests/test_agy_fixtures.py` checks these sanitization rules and the
observations below.

## Observations (agy CLI 1.4.7)

1. **Hook cwd** is the directory containing `hooks.json` (`app/.agents`), not
   the project. `workspacePaths` lists `app` and `infra` in launch order.
2. **Tool names in `PostToolUse`:** `read_file {Path}`,
   `write_file {Path, Content, Append}`, `edit_file {Path, Target, Replacement}`,
   `run_command {CommandLine, …}`, `invoke_subagent`, `send_message`. The web
   documentation's `view_file` / `write_to_file` names were not observed.
3. **Failed tools** still emit `PostToolUse` with a non-empty `error`.
4. **Stop:** a normal finish is `terminationReason: "NO_TOOL_CALL"`. The
   `/compact` turn ends with `TERMINAL_CUSTOM_HOOK`. `model_stop` was not
   observed. `{"decision":"continue","reason":…}` produces a
   `Stop hook blocked termination: …` system message, and the next Stop has
   `executionNum: 1`. `executionNum`/`invocationNum` reset on every new
   execution: a new user turn, or a wake-up from a subagent message.
5. **`fullyIdle`** was `false` on a parent Stop while its subagent was still
   running; a later Stop arrived with `true`.
6. **Final text at Stop:** the last transcript line already was the new
   `PLANNER_RESPONSE` in every captured Stop with `transcript_tail_at_stop`.
7. **Ephemeral messages** live for one model invocation. They are appended to
   the latest step (a user message **or tool output**), adjacent ones are
   concatenated without a separator, and they persist in the transcript as
   `SYSTEM_SDK / EPHEMERAL_MESSAGE` steps.
8. **SessionStart** fires for a new conversation and for each subagent (with
   empty `lastUserInput`). It has no `source` field and did not fire on
   `--conversation` resume or after `/compact`.
9. **Compact:** no hook event, but `/compact` writes a `SYSTEM / CHECKPOINT`
   transcript step (`# Resuming from a compaction…`). `initialNumSteps` keeps
   increasing across it.
10. **Invocation identity:** `invocationNum` restarts per execution;
    `(conversationId, initialNumSteps)` was unique per PreInvocation.
11. **Subagent parentage:** `PostToolUse(invoke_subagent)` carries only
    `args`, but the parent transcript's `GENERIC` result step contains the child
    `conversationId`, `logAbsoluteUri` and `workspaceUris`. The parent
    `PostToolUse` was logged before the child's `SessionStart`.
12. **Resume** via `--conversation` in print mode adds a low-priority
    `SYSTEM_MESSAGE` notice about stopped subagents/background tasks.

## Not covered

Automatic compaction at the context limit, Antigravity IDE/2.0, `PreToolUse`,
subagents with `Workspace: branch/share`, Claude Code and Codex CLI. Re-capture
for every adapter version the Watchdog claims to support.
