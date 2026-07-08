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
#      not using flock.
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
MARKER="/skills/wiki/hooks/"
CANON_SESSION_START="$CLAUDE_DIR/skills/wiki/hooks/session-start.sh"
CANON_POST_TOOL_USE="$CLAUDE_DIR/skills/wiki/hooks/post-tool-use.sh"

mkdir -p "$CLAUDE_DIR" 2>/dev/null || fail "cannot create $CLAUDE_DIR"

LOCK_ACQUIRED_MKDIR=0

on_exit() {
  local ec=$? owner=""
  if [ "$LOCK_ACQUIRED_MKDIR" = "1" ]; then
    # Tear down the lock ONLY when the pid file names us ($$) — NEVER on an
    # empty/absent pid (agy-атк P0, wave4). An empty pid here is ambiguous:
    # it can be our own mid-acquire window, but it can just as well be a NEW
    # owner's mid-acquire window after an mtime-age reclaim of our stalled
    # lock (we slept between mkdir and echo, B reclaimed and mkdir'ed, B has
    # not written its pid yet, we wake up and exit). Deleting on empty pid
    # would destroy B's live lock and let a third process corrupt
    # settings.json concurrently. The trade-off of never deleting an
    # empty-pid lock: if we crash in our own mkdir→echo window, our lock dir
    # lingers until the next client's mtime-age fallback reclaims it
    # (self-healing, bounded by LOCK_TIMEOUT) — correctness over speed.
    owner="$(cat "$LOCK_DIR/pid" 2>/dev/null)"
    if [ "$owner" = "$$" ]; then
      rm -f "$LOCK_DIR/pid" 2>/dev/null
      rmdir "$LOCK_DIR" 2>/dev/null
    fi
  fi
  exit "$ec"
}
trap on_exit EXIT INT TERM

is_pid_alive() {
  [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null
}

dir_age_seconds() {
  local d="$1" mtime now
  mtime="$(stat -f %m "$d" 2>/dev/null)"
  if [ -z "$mtime" ]; then
    mtime="$(stat -c %Y "$d" 2>/dev/null)"
  fi
  [ -z "$mtime" ] && return 1
  now="$(date +%s)"
  echo $((now - mtime))
}

# mkdir-based fallback lock: atomic `mkdir` as the mutex. Crash/interrupt
# recovery relies on the EXIT/INT/TERM trap above (installed before this
# ever runs) — the pid file is written FIRST, the directory removed
# SECOND, so a bare `rmdir` on a nonempty dir never hangs a cleanup.
acquire_mkdir() {
  local start elapsed pid age now
  start="$(date +%s)"
  while true; do
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      # Flip the cleanup flag BEFORE writing the pid file: if a signal
      # lands in the narrow window between `mkdir` succeeding and the pid
      # write below, on_exit must still know it owns (and must remove)
      # this lock dir, even pid-less.
      LOCK_ACQUIRED_MKDIR=1
      echo $$ >"$LOCK_DIR/pid" 2>/dev/null
      return 0
    fi
    if [ -f "$LOCK_DIR/pid" ]; then
      pid="$(cat "$LOCK_DIR/pid" 2>/dev/null)"
    else
      pid=""
    fi
    if [ -n "$pid" ] && is_pid_alive "$pid"; then
      : # live owner — never steal, just wait.
    elif [ -n "$pid" ]; then
      # Non-empty pid naming a dead/unreadable process -> genuinely stale
      # lock; force-clear and retry.
      rm -f "$LOCK_DIR/pid" 2>/dev/null
      rmdir "$LOCK_DIR" 2>/dev/null
      continue
    else
      # Empty OR absent pid file. An empty pid file is NOT a dead owner: it
      # is the winner's mid-acquire race window — `mkdir` has succeeded and
      # `echo $$` has created but not yet filled the pid file. Force-clearing
      # here would steal a lock whose owner is a live process about to run
      # under it, defeating mutual exclusion (agy-атк P1). Treat empty
      # EXACTLY like absent: fall back to mtime age as the ONLY reclaim
      # signal, so only a genuinely abandoned lock is ever reclaimed. Remove
      # the (possibly-present, possibly-empty) pid file before rmdir, since
      # rmdir fails on a non-empty directory.
      age="$(dir_age_seconds "$LOCK_DIR" 2>/dev/null)"
      if [ -n "${age:-}" ] && [ "$age" -gt "$LOCK_TIMEOUT" ]; then
        rm -f "$LOCK_DIR/pid" 2>/dev/null
        rmdir "$LOCK_DIR" 2>/dev/null
        continue
      fi
    fi
    now="$(date +%s)"
    elapsed=$((now - start))
    if [ "$elapsed" -ge "$LOCK_TIMEOUT" ]; then
      return 1
    fi
    sleep "$LOCK_POLL"
  done
}

# Single, universal mutex: the mkdir lock-directory, for every invocation.
# Deliberately NOT flock-when-available/mkdir-otherwise — mixing the two on
# the same resource loses mutual exclusion (codex-атк P1). The legacy
# WIKI_HOOKS_FORCE_MKDIR_LOCK env is retained only for backward-compatible
# test invocations; it is now a no-op since mkdir is always used.
acquire_mkdir || fail "could not acquire lock on $SETTINGS_FILE within ${LOCK_TIMEOUT}s"

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

exit 0
