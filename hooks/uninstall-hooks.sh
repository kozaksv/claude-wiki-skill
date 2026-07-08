#!/usr/bin/env bash
# hooks/uninstall-hooks.sh
#
# Removes the wiki skill's two global Claude Code hooks from
# ~/.claude/settings.json (docs/superpowers/plans/2026-07-08-v45-hooks.md
# Task 4). Mirrors install-hooks.sh's locking, read-under-lock, backup and
# atomic-write discipline exactly (same lock file, same lock-dir fallback,
# same trap-based crash recovery) — only the merge step differs: strip,
# never add.
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
LOCK_FILE="$SETTINGS_FILE.lock"
LOCK_DIR="$SETTINGS_FILE.lockdir"
LOCK_TIMEOUT="${WIKI_HOOKS_LOCK_TIMEOUT:-10}"
LOCK_POLL="${WIKI_HOOKS_LOCK_POLL:-0.2}"
MARKER="/skills/wiki/hooks/"

if [ ! -f "$SETTINGS_FILE" ]; then
  # Nothing installed, nothing to remove.
  exit 0
fi

LOCK_ACQUIRED_MKDIR=0

on_exit() {
  local ec=$?
  if [ "$LOCK_ACQUIRED_MKDIR" = "1" ]; then
    rm -f "$LOCK_DIR/pid" 2>/dev/null
    rmdir "$LOCK_DIR" 2>/dev/null
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
      if [ -n "$pid" ] && is_pid_alive "$pid"; then
        : # live owner — never steal, just wait.
      else
        rm -f "$LOCK_DIR/pid" 2>/dev/null
        rmdir "$LOCK_DIR" 2>/dev/null
        continue
      fi
    else
      age="$(dir_age_seconds "$LOCK_DIR" 2>/dev/null)"
      if [ -n "${age:-}" ] && [ "$age" -gt "$LOCK_TIMEOUT" ]; then
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

# WIKI_HOOKS_FORCE_MKDIR_LOCK lets tests exercise the mkdir-fallback path
# deterministically even on hosts where `flock` happens to be installed.
if [ "${WIKI_HOOKS_FORCE_MKDIR_LOCK:-0}" = "1" ] || ! command -v flock >/dev/null 2>&1; then
  acquire_mkdir || fail "could not acquire lock on $SETTINGS_FILE within ${LOCK_TIMEOUT}s"
else
  exec 9>"$LOCK_FILE" 2>/dev/null || fail "cannot open lock file $LOCK_FILE"
  flock -w "$LOCK_TIMEOUT" 9 || fail "could not acquire lock on $SETTINGS_FILE within ${LOCK_TIMEOUT}s"
fi

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
