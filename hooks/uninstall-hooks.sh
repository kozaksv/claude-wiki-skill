#!/usr/bin/env bash
# hooks/uninstall-hooks.sh
#
# Removes the wiki skill's two global hooks (SessionStart, PostToolUse) from
# EVERY client settings file install-hooks.sh knows how to register into:
# ~/.claude/settings.json (docs/superpowers/plans/2026-07-08-v45-hooks.md
# Task 4) AND ~/.qwen/settings.json (docs/superpowers/plans/
# 2026-08-13-v46-qwen.md Task 7 — install-hooks.sh's register_into gained a
# second, sequential call for qwen; this script gained the mirror-image
# deregister_from so an uninstall actually undoes everything an install can
# do. Before this, uninstall-hooks.sh only ever touched ~/.claude/
# settings.json — uninstall.sh trusted its exit 0 as "fully cleaned up" and
# proceeded to delete $SKILL_DIR under --remove-clones, permanently
# stranding any wiki hook entries install-hooks.sh had written into
# ~/.qwen/settings.json (agy-атк / codex-кор P1, wave3). Mirrors
# install-hooks.sh's locking, read-under-lock, backup and atomic-write
# discipline exactly (same single mkdir lock-directory mutex PER settings
# file, same trap-based crash recovery) — only the merge step differs:
# strip, never add. Using the SAME single primitive as install-hooks.sh is
# what keeps a concurrent install and uninstall mutually exclusive on the
# SAME file (codex-атк P1); two different primitives on the same
# settings.json would not. Locks for different clients' files are separate
# mutexes, taken SEQUENTIALLY (claude first, then qwen) — never nested,
# exactly like register_into's two calls.
#
# Granularity matches install-hooks.sh: only elements of a matcher-entry's
# nested `hooks[]` array whose `command` contains the `/skills/wiki/hooks/`
# marker (or, for qwen, the legacy `~/.qwen/hooks/wiki-session-start.sh`
# wrapper marker install-hooks.sh also migrates away from) are removed. A
# matcher-entry is dropped once its `hooks[]` is empty; an event array
# (`SessionStart`/`PostToolUse`) is dropped once it holds no entries.
# Everything else in each settings.json is untouched.
#
# Exit-code contract (per client file, and overall): exits 0 only when
# there is verifiably nothing to do for every client file that exists:
# settings.json does not exist for that client, OR python3 is unavailable
# but no client's settings.json carries a hook marker anyway. Any real
# failure for ANY client file — including python3 being unavailable WHILE a
# marker is still present in ANY client file, since removal can then never
# be verified — (unreadable/corrupt settings.json, lock timeout, write
# failure) makes the WHOLE script exit non-zero with a message on stderr,
# leaving that client's settings.json untouched (an already-cleaned earlier
# client stays cleaned — partial-failure semantics mirror install-hooks.sh's
# spec R8). This matters because uninstall.sh checks this script's exit
# code before deciding whether it is safe to delete the clone that hosts
# this recovery script (fixwave0-4 P2, extended by wave3 to cover qwen): a
# false "0 = cleaned up" here would let --remove-clones destroy the only
# remaining way to clean up orphaned global hook entries in ANY client's
# settings.json.

set -uo pipefail

fail() {
  echo "uninstall-hooks: $*" >&2
  exit 1
}

: "${HOME:?uninstall-hooks: HOME is not set}"
HOME_DIR="$HOME"
CLAUDE_DIR="$HOME_DIR/.claude"
QWEN_DIR="$HOME_DIR/.qwen"
CLAUDE_SETTINGS="$CLAUDE_DIR/settings.json"
QWEN_SETTINGS="$QWEN_DIR/settings.json"
LOCK_TIMEOUT="${WIKI_HOOKS_LOCK_TIMEOUT:-10}"
LOCK_POLL="${WIKI_HOOKS_LOCK_POLL:-0.2}"
LOCK_MAX_AGE="${WIKI_HOOKS_LOCK_MAX_AGE:-3600}"
MARKER="/skills/wiki/hooks/"
# Old qwen wrapper-script path install-hooks.sh migrates away from (T7 spec
# note 4) — stripped alongside the canonical $MARKER so an uninstall run
# against a not-yet-migrated qwen install still cleans up fully instead of
# leaving the legacy entry behind.
LEGACY_QWEN_MARKER="/.qwen/hooks/wiki-session-start.sh"

if ! command -v python3 >/dev/null 2>&1; then
  # python3 is required to safely parse/rewrite settings.json. If ANY
  # client's file still carries a wiki hook marker we cannot perform (or
  # verify) removal there, so this is a REAL failure, not a no-op — see the
  # exit-code contract above. grep is a best-effort substring check (not
  # JSON-aware) but that is exactly the same "marker in command string" test
  # the python merge step below uses, so it is precise enough to
  # distinguish "nothing to do" from "removal needed but impossible".
  marker_present=0
  for f in "$CLAUDE_SETTINGS" "$QWEN_SETTINGS"; do
    [ -f "$f" ] || continue
    if grep -Fq "$MARKER" "$f" 2>/dev/null || grep -Fq "$LEGACY_QWEN_MARKER" "$f" 2>/dev/null; then
      marker_present=1
    fi
  done
  if [ "$marker_present" = "1" ]; then
    fail "python3 not found — cannot remove hook entries (marker still present)"
  fi
  echo "uninstall-hooks: python3 not found — no hook markers present, nothing to remove" >&2
  exit 0
fi

# shellcheck source=lib/settings-lock.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/settings-lock.sh"

# deregister_from <client> <settings_file> <legacy_marker>
#
# Removes the wiki skill's SessionStart + PostToolUse entries for ONE
# client's settings_file. Mirrors register_into in install-hooks.sh (same
# per-file lock/backup/atomic-write discipline) but only ever strips, never
# adds. <legacy_marker> is an additional command substring to strip
# alongside the canonical $MARKER; pass "" when there is none for this
# client (claude has none).
#
# Returns 0 on success or genuine no-op (settings_file absent — nothing was
# ever registered there), 1 on any real failure. Never `exit`s directly on
# a merge failure (releases its own lock first so a later call in the same
# process can still proceed on lock-acquisition failure it DOES fail hard
# via `fail`, matching register_into: no lock is held yet there, so nothing
# needs releasing and a caller chaining multiple deregister_from calls must
# abort immediately without attempting the next client).
deregister_from() {
  local client="$1" settings_file="$2" legacy_marker="$3"
  local lock_dir ts backup_file

  if [ ! -f "$settings_file" ]; then
    # Nothing installed for this client, nothing to remove.
    return 0
  fi

  lock_dir="$settings_file.lockdir"
  wiki_lock_acquire "$lock_dir" || fail "$client: could not acquire lock on $settings_file within ${LOCK_TIMEOUT}s"

  # Test-only seam: hold the lock open for a bit so tests can exercise
  # interrupt/trap-cleanup behavior deterministically. No-op by default.
  if [ "${WIKI_HOOKS_TEST_SLEEP_AFTER_LOCK:-0}" != "0" ]; then
    sleep "${WIKI_HOOKS_TEST_SLEEP_AFTER_LOCK}"
  fi

  ts="$(date +%Y%m%d%H%M%S)"
  backup_file="$settings_file.bak-wiki-hooks-$ts"

  if ! python3 - "$client" "$settings_file" "$backup_file" "$MARKER" "$legacy_marker" <<'PYEOF'
import json
import os
import shutil
import sys
import tempfile

client, settings_file, backup_file, marker, legacy_marker = sys.argv[1:6]

if not os.path.exists(settings_file):
    sys.exit(0)

try:
    with open(settings_file, "r", encoding="utf-8") as fh:
        raw = fh.read()
except OSError as exc:
    sys.stderr.write("uninstall-hooks: %s: cannot read %s: %s\n" % (client, settings_file, exc))
    sys.exit(1)

data = {}
stripped = raw.strip()
if stripped:
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        sys.stderr.write(
            "uninstall-hooks: %s: %s is not valid JSON: %s\n" % (client, settings_file, exc)
        )
        sys.exit(1)
if not isinstance(data, dict):
    sys.stderr.write(
        "uninstall-hooks: %s: %s top-level value is not a JSON object\n" % (client, settings_file)
    )
    sys.exit(1)

try:
    shutil.copy2(settings_file, backup_file)
except OSError as exc:
    sys.stderr.write("uninstall-hooks: %s: backup failed: %s\n" % (client, exc))
    sys.exit(1)

hooks = data.get("hooks")
have_hooks = isinstance(hooks, dict)


def has_marker(command):
    command = str(command)
    if marker in command:
        return True
    if legacy_marker and legacy_marker in command:
        return True
    return False


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
                if not (isinstance(h, dict) and has_marker(h.get("command", "")))
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
    echo "uninstall-hooks: $client: settings.json merge failed — nothing written" >&2
    wiki_lock_release "$lock_dir"
    return 1
  fi

  wiki_lock_release "$lock_dir"
  return 0
}

deregister_from claude "$CLAUDE_SETTINGS" "" || exit 1

# Second, SEQUENTIAL deregistration for qwen (wave3): the claude critical
# section above has already released its lock (deregister_from always
# releases before returning), so this never nests a second lock inside the
# first. Absence of ~/.qwen/settings.json is not an error — deregister_from
# returns 0 immediately for a client file that does not exist, the same
# "nothing installed" no-op the claude path already relied on before this
# file grew a second client.
deregister_from qwen "$QWEN_SETTINGS" "$LEGACY_QWEN_MARKER" || exit 1

exit 0
