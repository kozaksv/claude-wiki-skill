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
# Exits 0 only when there is verifiably nothing to do: settings.json does
# not exist, OR python3 is unavailable but settings.json carries no hook
# marker anyway. Any real failure — including python3 being unavailable
# WHILE the marker is still present, since removal can then never be
# verified — (unreadable/corrupt settings.json, lock timeout, write
# failure) exits non-zero with a message on stderr and leaves settings.json
# untouched. This matters because uninstall.sh checks this script's exit
# code before deciding whether it is safe to delete the clone that hosts
# this recovery script (fixwave0-4 P2): a false "0 = cleaned up" here would
# let --remove-clones destroy the only remaining way to clean up orphaned
# global hook entries.

set -uo pipefail

fail() {
  echo "uninstall-hooks: $*" >&2
  exit 1
}

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

if ! command -v python3 >/dev/null 2>&1; then
  # python3 is required to safely parse/rewrite settings.json. If the file
  # still carries our hook marker we cannot perform (or verify) removal, so
  # this is a REAL failure, not a no-op — see the exit-code contract above.
  # grep is a best-effort substring check (not JSON-aware) but that is
  # exactly the same "marker in command string" test the python merge step
  # below uses, so it is precise enough to distinguish "nothing to do" from
  # "removal needed but impossible".
  if grep -Fq "$MARKER" "$SETTINGS_FILE" 2>/dev/null; then
    fail "python3 not found — cannot remove hook entries from $SETTINGS_FILE (marker still present)"
  fi
  echo "uninstall-hooks: python3 not found — no hook markers present in $SETTINGS_FILE, nothing to remove" >&2
  exit 0
fi

# shellcheck source=lib/settings-lock.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/settings-lock.sh"

# Single, universal mutex: the mkdir lock-directory, for every invocation —
# the SAME primitive install-hooks.sh uses, so install and uninstall exclude
# each other. Deliberately NOT flock-when-available/mkdir-otherwise (codex-атк
# P1). WIKI_HOOKS_FORCE_MKDIR_LOCK is retained only for backward-compatible
# test invocations and is now a no-op since mkdir is always used.
wiki_lock_acquire "$LOCK_DIR" || fail "could not acquire lock on $SETTINGS_FILE within ${LOCK_TIMEOUT}s"

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
