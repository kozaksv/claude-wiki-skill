#!/usr/bin/env bash
# hooks/install-hooks.sh
#
# Idempotently registers the wiki skill's two global Claude Code hooks
# (SessionStart, PostToolUse) into ~/.claude/settings.json
# (docs/superpowers/plans/2026-07-08-v45-hooks.md Task 4).
#
# Design (see plan Task 4 for the full rationale):
#   1. Serialized read-modify-write under ONE exclusive mutex: an atomic
#      `mkdir` lock-directory (~/.claude/settings.json.lockdir). A single
#      primitive is used for EVERY invocation — never flock-when-available /
#      mkdir-otherwise — because two different primitives guarding the same
#      resource are not mutually exclusive: an flock holder and a concurrent
#      mkdir holder (whether flock is missing on one, or the caller sets
#      WIKI_HOOKS_FORCE_MKDIR_LOCK) would both enter the critical section and
#      corrupt settings.json (codex-атк P1). The mkdir lock records its own
#      PID inside the lock dir and installs an EXIT/INT/TERM trap plus
#      pid-liveness + mtime-age reclaim, so a crash or interrupt while
#      holding the lock can never deadlock a future run — nothing is lost by
#      not using flock. PID liveness is NEVER trusted on its own: an
#      operating system recycles PIDs, so if the original lock holder
#      crashed and its PID was later reassigned to an unrelated
#      long-running process, `kill -0 $pid` would report "alive" forever
#      and a liveness-only check would deadlock every future install/
#      uninstall permanently. To close that hole, lock age is the ultimate
#      authority: a lock older than LOCK_MAX_AGE is ALWAYS force-reclaimed
#      regardless of what kill -0 says about the recorded pid (P1,
#      fixwave0-2) — liveness only ever extends the wait, it never blocks
#      reclamation forever.
#   2. settings.json is read fresh, under the lock, immediately before the
#      merge — never a cached/earlier snapshot.
#   3. A timestamped backup is written before any merge (only once the
#      existing file is confirmed to be valid JSON).
#   4. The merge (python3) is idempotent and operates at the granularity of
#      individual entries inside each matcher-entry's nested `hooks[]`
#      array: only elements whose `command` contains the
#      `/skills/wiki/hooks/` marker are removed; a matcher-entry is dropped
#      entirely only once its `hooks[]` becomes empty. Two fresh wiki
#      entries are appended. Everything else in settings.json is untouched.
#   5. The registered command always points at the canonical symlink path
#      `$HOME/.claude/skills/wiki/hooks/{session-start,post-tool-use}.sh`
#      (the same $SKILL_LINK install.sh:19 uses) — never the physical
#      clone/worktree the installer happens to run from — so the marker
#      matches identically across machines/clones and re-runs never
#      accumulate duplicates or orphans. $HOME is used literally (not
#      canonicalized) because hook `command` strings get no tilde
#      expansion.
#   6. Registered commands fail open: `test -x {script} && {script} || exit
#      0` — a missing/broken canonical script silently no-ops instead of
#      blocking Read/Edit/Write globally.
#   7. The write is atomic: python3 writes to a tmp file in the same
#      directory as settings.json and `os.replace`s it into place.
#
# Always exits 0 only when there is genuinely nothing to do (no python3);
# any real failure (unreadable/corrupt settings.json, lock timeout, write
# failure) exits non-zero with a message on stderr and leaves
# settings.json untouched.

set -uo pipefail

fail() {
  echo "install-hooks: $*" >&2
  exit 1
}

if ! command -v python3 >/dev/null 2>&1; then
  echo "install-hooks: python3 not found — skipping hook registration" >&2
  exit 0
fi

: "${HOME:?install-hooks: HOME is not set}"
HOME_DIR="$HOME"
CLAUDE_DIR="$HOME_DIR/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
LOCK_DIR="$SETTINGS_FILE.lockdir"
LOCK_TIMEOUT="${WIKI_HOOKS_LOCK_TIMEOUT:-10}"
LOCK_POLL="${WIKI_HOOKS_LOCK_POLL:-0.2}"
# Absolute ceiling on lock age (P1, fixwave0-2 — PID-recycle deadlock
# guard): once a lock dir is older than this, it is ALWAYS force-reclaimed
# regardless of whether the recorded pid currently looks alive. This is
# deliberately much larger than LOCK_TIMEOUT (which only governs how long
# a *waiting* invocation blocks on a live-looking owner) — it exists
# purely so a crashed holder whose pid gets reassigned to some unrelated
# long-running process can never wedge the lock forever.
LOCK_MAX_AGE="${WIKI_HOOKS_LOCK_MAX_AGE:-3600}"
MARKER="/skills/wiki/hooks/"
CANON_SESSION_START="$CLAUDE_DIR/skills/wiki/hooks/session-start.sh"
CANON_POST_TOOL_USE="$CLAUDE_DIR/skills/wiki/hooks/post-tool-use.sh"

mkdir -p "$CLAUDE_DIR" 2>/dev/null || fail "cannot create $CLAUDE_DIR"

# shellcheck source=lib/settings-lock.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/settings-lock.sh"

# Single, universal mutex: the mkdir lock-directory, for every invocation.
# Deliberately NOT flock-when-available/mkdir-otherwise — mixing the two on
# the same resource loses mutual exclusion (codex-атк P1). The legacy
# WIKI_HOOKS_FORCE_MKDIR_LOCK env is retained only for backward-compatible
# test invocations; it is now a no-op since mkdir is always used.
wiki_lock_acquire "$LOCK_DIR" || fail "could not acquire lock on $SETTINGS_FILE within ${LOCK_TIMEOUT}s"

# Test-only seam: hold the lock open for a bit so tests can exercise
# interrupt/trap-cleanup behavior deterministically. No-op by default.
if [ "${WIKI_HOOKS_TEST_SLEEP_AFTER_LOCK:-0}" != "0" ]; then
  sleep "${WIKI_HOOKS_TEST_SLEEP_AFTER_LOCK}"
fi

TS="$(date +%Y%m%d%H%M%S)"
BACKUP_FILE="$SETTINGS_FILE.bak-wiki-hooks-$TS"

if ! python3 - "$SETTINGS_FILE" "$BACKUP_FILE" "$MARKER" "$CANON_SESSION_START" "$CANON_POST_TOOL_USE" <<'PYEOF'
import json
import os
import shutil
import sys
import tempfile

settings_file, backup_file, marker, canon_start, canon_post = sys.argv[1:6]

data = {}
existed = os.path.exists(settings_file)
if existed:
    try:
        with open(settings_file, "r", encoding="utf-8") as fh:
            raw = fh.read()
    except OSError as exc:
        sys.stderr.write("install-hooks: cannot read %s: %s\n" % (settings_file, exc))
        sys.exit(1)
    stripped = raw.strip()
    if stripped:
        try:
            data = json.loads(raw)
        except json.JSONDecodeError as exc:
            sys.stderr.write(
                "install-hooks: %s is not valid JSON: %s\n" % (settings_file, exc)
            )
            sys.exit(1)
    if not isinstance(data, dict):
        sys.stderr.write(
            "install-hooks: %s top-level value is not a JSON object\n" % settings_file
        )
        sys.exit(1)
    try:
        shutil.copy2(settings_file, backup_file)
    except OSError as exc:
        sys.stderr.write("install-hooks: backup failed: %s\n" % exc)
        sys.exit(1)

hooks = data.get("hooks")
if hooks is None:
    hooks = {}
elif not isinstance(hooks, dict):
    sys.stderr.write("install-hooks: 'hooks' key is not a JSON object\n")
    sys.exit(1)
data["hooks"] = hooks


def strip_marker(event_name):
    entries = hooks.get(event_name)
    if not isinstance(entries, list):
        return
    kept = []
    for entry in entries:
        if not isinstance(entry, dict):
            kept.append(entry)
            continue
        inner = entry.get("hooks")
        if isinstance(inner, list):
            filtered = [
                h
                for h in inner
                if not (isinstance(h, dict) and marker in str(h.get("command", "")))
            ]
            if len(filtered) == 0:
                # Whole entry was ours alone -> drop the entry.
                continue
            if len(filtered) != len(inner):
                entry = dict(entry)
                entry["hooks"] = filtered
        kept.append(entry)
    hooks[event_name] = kept


strip_marker("SessionStart")
strip_marker("PostToolUse")


def add_entry(event_name, matcher, command):
    entries = hooks.get(event_name)
    if not isinstance(entries, list):
        entries = []
    entries.append(
        {
            "matcher": matcher,
            "hooks": [{"type": "command", "command": command}],
        }
    )
    hooks[event_name] = entries


session_cmd = 'test -x "%s" && "%s" || exit 0' % (canon_start, canon_start)
post_cmd = 'test -x "%s" && "%s" || exit 0' % (canon_post, canon_post)

add_entry("SessionStart", "startup|clear|compact", session_cmd)
add_entry("PostToolUse", "Read|Edit|Write|MultiEdit", post_cmd)

dir_name = os.path.dirname(settings_file) or "."
fd, tmp_path = tempfile.mkstemp(prefix=".settings.json.", dir=dir_name)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    os.replace(tmp_path, settings_file)
except Exception:
    try:
        os.unlink(tmp_path)
    except OSError:
        pass
    raise
PYEOF
then
  fail "settings.json merge failed — nothing written"
fi

echo "install-hooks: SessionStart + PostToolUse зареєстровано в $SETTINGS_FILE" >&2

exit 0
