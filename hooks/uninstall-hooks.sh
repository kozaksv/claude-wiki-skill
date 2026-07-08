#!/usr/bin/env bash
# hooks/uninstall-hooks.sh
#
# Removes the wiki skill's two global Claude Code hooks from
# ~/.claude/settings.json (docs/superpowers/plans/2026-07-08-v45-hooks.md
# Task 4). Mirrors install-hooks.sh's locking, read-under-lock, backup and
# atomic-write discipline exactly (same single mkdir lock-directory mutex,
# same trap-based crash recovery) — only the merge step differs: strip,
# never add. Using the SAME single primitive as install-hooks.sh is what
# keeps a concurrent install and uninstall mutually exclusive (codex-атк
# P1); two different primitives on ~/.claude/settings.json would not.
#
# Granularity matches install-hooks.sh: only elements of a matcher-entry's
# nested `hooks[]` array whose `command` contains the `/skills/wiki/hooks/`
# marker are removed. A matcher-entry is dropped once its `hooks[]` is
# empty; an event array (`SessionStart`/`PostToolUse`) is dropped once it
# holds no entries. Everything else in settings.json is untouched.
#
# Exits 0 when there is nothing to do (no python3, or settings.json does
# not exist). Any real failure (unreadable/corrupt settings.json, lock
# timeout, write failure) exits non-zero with a message on stderr and
# leaves settings.json untouched.

set -uo pipefail

fail() {
  echo "uninstall-hooks: $*" >&2
  exit 1
}

if ! command -v python3 >/dev/null 2>&1; then
  echo "uninstall-hooks: python3 not found — skipping hook removal" >&2
  exit 0
fi

: "${HOME:?uninstall-hooks: HOME is not set}"
HOME_DIR="$HOME"
CLAUDE_DIR="$HOME_DIR/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
LOCK_DIR="$SETTINGS_FILE.lockdir"
LOCK_TIMEOUT="${WIKI_HOOKS_LOCK_TIMEOUT:-10}"
LOCK_POLL="${WIKI_HOOKS_LOCK_POLL:-0.2}"
LOCK_MAX_AGE="${WIKI_HOOKS_LOCK_MAX_AGE:-3600}"
MARKER="/skills/wiki/hooks/"

if [ ! -f "$SETTINGS_FILE" ]; then
  # Nothing installed, nothing to remove.
  exit 0
fi

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
  # BSD `stat -f %m` (macOS) vs GNU `stat -c %Y` (Linux) are mutually
  # rejected by each other's stat — EXCEPT GNU stat also accepts `-f`
  # (its own, unrelated --file-system flag) without erroring, so
  # `stat -f %m "$d"` on Linux does not fail cleanly: it silently emits
  # non-numeric filesystem-status text instead of an mtime. Validate each
  # candidate's output is a plain integer before trusting it, rather than
  # trusting "non-empty" as if it meant "correct".
  mtime="$(stat -f %m "$d" 2>/dev/null)"
  case "$mtime" in
    ''|*[!0-9]*) mtime="" ;;
  esac
  if [ -z "$mtime" ]; then
    mtime="$(stat -c %Y "$d" 2>/dev/null)"
    case "$mtime" in
      ''|*[!0-9]*) mtime="" ;;
    esac
  fi
  [ -z "$mtime" ] && return 1
  now="$(date +%s)"
  echo $((now - mtime))
}

reclaim_lock() {
  # Atomically CLAIM the stale lock before destroying it (fixwave0-1 P0,
  # TOCTOU) — mirrors install-hooks.sh reclaim_lock exactly: rename(2) lets
  # exactly ONE of several same-verdict claimers win; losers re-loop
  # instead of tearing down the winner's freshly re-acquired live lock.
  local claim="$LOCK_DIR.claim.$$"
  if mv "$LOCK_DIR" "$claim" 2>/dev/null; then
    rm -rf "$claim" 2>/dev/null
  fi
}

# mkdir-based fallback lock: same contract as install-hooks.sh
# acquire_mkdir — pid file written first, directory removed second (see
# on_exit above), so a bare `rmdir` on a nonempty dir never hangs cleanup.
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
    if [ -n "$pid" ]; then
      # PID-recycle deadlock guard (P1, fixwave0-2) — mirrors
      # install-hooks.sh: liveness of a stored pid is never, on its own,
      # grounds to wait forever (the OS may have recycled a crashed
      # holder's pid onto an unrelated long-running process). Age is
      # checked FIRST and wins unconditionally past LOCK_MAX_AGE.
      age="$(dir_age_seconds "$LOCK_DIR" 2>/dev/null)"
      if [ -n "${age:-}" ] && [ "$age" -gt "$LOCK_MAX_AGE" ]; then
        reclaim_lock
        continue
      elif is_pid_alive "$pid"; then
        : # live owner within the max-age bound — never steal, just wait.
      else
        # Non-empty pid naming a dead/unreadable process -> genuinely
        # stale lock; atomically claim + destroy and retry immediately.
        reclaim_lock
        continue
      fi
    else
      # Empty OR absent pid file. An empty pid file is NOT a dead owner: it
      # is the winner's mid-acquire race window — `mkdir` has succeeded and
      # `echo $$` has created but not yet filled the pid file. Force-clearing
      # here would steal a lock whose owner is a live process about to run
      # under it, defeating mutual exclusion (agy-атк P1). Treat empty
      # EXACTLY like absent: fall back to mtime age as the ONLY reclaim
      # signal, so only a genuinely abandoned lock is ever reclaimed
      # (atomic claim-then-destroy — see reclaim_lock).
      age="$(dir_age_seconds "$LOCK_DIR" 2>/dev/null)"
      if [ -n "${age:-}" ] && [ "$age" -gt "$LOCK_TIMEOUT" ]; then
        reclaim_lock
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

# Single, universal mutex: the mkdir lock-directory, for every invocation —
# the SAME primitive install-hooks.sh uses, so install and uninstall exclude
# each other. Deliberately NOT flock-when-available/mkdir-otherwise (codex-атк
# P1). WIKI_HOOKS_FORCE_MKDIR_LOCK is retained only for backward-compatible
# test invocations and is now a no-op since mkdir is always used.
acquire_mkdir || fail "could not acquire lock on $SETTINGS_FILE within ${LOCK_TIMEOUT}s"

# Test-only seam: hold the lock open for a bit so tests can exercise
# interrupt/trap-cleanup behavior deterministically. No-op by default.
if [ "${WIKI_HOOKS_TEST_SLEEP_AFTER_LOCK:-0}" != "0" ]; then
  sleep "${WIKI_HOOKS_TEST_SLEEP_AFTER_LOCK}"
fi

TS="$(date +%Y%m%d%H%M%S)"
BACKUP_FILE="$SETTINGS_FILE.bak-wiki-hooks-$TS"

if ! python3 - "$SETTINGS_FILE" "$BACKUP_FILE" "$MARKER" <<'PYEOF'
import json
import os
import shutil
import sys
import tempfile

settings_file, backup_file, marker = sys.argv[1:4]

if not os.path.exists(settings_file):
    sys.exit(0)

try:
    with open(settings_file, "r", encoding="utf-8") as fh:
        raw = fh.read()
except OSError as exc:
    sys.stderr.write("uninstall-hooks: cannot read %s: %s\n" % (settings_file, exc))
    sys.exit(1)

data = {}
stripped = raw.strip()
if stripped:
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        sys.stderr.write(
            "uninstall-hooks: %s is not valid JSON: %s\n" % (settings_file, exc)
        )
        sys.exit(1)
if not isinstance(data, dict):
    sys.stderr.write(
        "uninstall-hooks: %s top-level value is not a JSON object\n" % settings_file
    )
    sys.exit(1)

try:
    shutil.copy2(settings_file, backup_file)
except OSError as exc:
    sys.stderr.write("uninstall-hooks: backup failed: %s\n" % exc)
    sys.exit(1)

hooks = data.get("hooks")
have_hooks = isinstance(hooks, dict)


def strip_marker(event_name):
    if not have_hooks:
        return
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
                continue
            if len(filtered) != len(inner):
                entry = dict(entry)
                entry["hooks"] = filtered
        kept.append(entry)
    if kept:
        hooks[event_name] = kept
    else:
        hooks.pop(event_name, None)


strip_marker("SessionStart")
strip_marker("PostToolUse")

if have_hooks:
    if hooks:
        data["hooks"] = hooks
    else:
        data.pop("hooks", None)

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
