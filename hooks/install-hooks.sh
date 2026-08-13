#!/usr/bin/env bash
# hooks/install-hooks.sh
#
# Idempotently registers the wiki skill's two global hooks (SessionStart,
# PostToolUse) into a client's settings.json.
# (docs/superpowers/plans/2026-07-08-v45-hooks.md Task 4;
#  docs/superpowers/plans/2026-08-13-v46-qwen.md Task 6 — the whole
#  lock->read->backup->merge->atomic-write protocol was pulled out of the
#  top level into a single `register_into <client> ...` function so a later
#  task (T7) can call it a second time for a second client (qwen) without a
#  second copy of this logic. This file itself still calls it exactly ONCE,
#  for claude — the qwen call is added in T7, deliberately kept out of this
#  diff so the existing tests below serve as a pure regression detector for
#  the claude branch staying byte-identical.)
#
# Design (see plan Task 4/6 for the full rationale):
#   1. Serialized read-modify-write under ONE exclusive mutex PER CLIENT: an
#      atomic `mkdir` lock-directory ("$settings_file.lockdir", e.g.
#      ~/.claude/settings.json.lockdir), acquired/released by
#      hooks/lib/settings-lock.sh (wiki_lock_acquire/
#      wiki_lock_release). A single primitive is used for EVERY invocation
#      — never flock-when-available / mkdir-otherwise — because two
#      different primitives guarding the same resource are not mutually
#      exclusive: an flock holder and a concurrent mkdir holder (whether
#      flock is missing on one, or the caller sets
#      WIKI_HOOKS_FORCE_MKDIR_LOCK) would both enter the critical section
#      and corrupt settings.json (codex-атк P1). Locks are taken
#      SEQUENTIALLY, never nested — each register_into call explicitly
#      releases its own lock before returning, not only via the shared
#      EXIT/INT/TERM trap the lib installs.
#   2. settings.json is read fresh, under the lock, immediately before the
#      merge — never a cached/earlier snapshot.
#   3. A timestamped backup ("$settings_file.bak-wiki-hooks-$TS") is written
#      before any merge (only once the existing file is confirmed to be
#      valid JSON), via shutil.copy2 (preserves the source's permissions).
#   4. The merge (python3) is idempotent and operates at the granularity of
#      individual entries inside each matcher-entry's nested `hooks[]`
#      array: only elements whose `command` contains the
#      `/skills/wiki/hooks/` marker (or, when a non-empty legacy marker is
#      passed, that marker too) are removed; a matcher-entry is dropped
#      entirely only once its `hooks[]` becomes empty. Two fresh wiki
#      entries are appended. Everything else in settings.json is untouched.
#   5. The registered command always points at the canonical script paths
#      passed in by the caller (for claude:
#      `$HOME/.claude/skills/wiki/hooks/{session-start,post-tool-use}.sh`,
#      the same $SKILL_LINK-relative symlink path install.sh:19 sets up) —
#      never the physical clone/worktree the installer happens to run from
#      — so the marker
#      matches identically across machines/clones and re-runs never
#      accumulate duplicates or orphans. $HOME is used literally (not
#      canonicalized) because hook `command` strings get no tilde
#      expansion.
#   6. Registered commands fail open: `test -x {script} && {script} || exit
#      0` — a missing/broken canonical script silently no-ops instead of
#      blocking the client's tool calls globally. This is a RUNTIME
#      property of the registered command, distinct from the install-time
#      orphan guard in (8) below.
#   7. The write is atomic: python3 writes to a tmp file in the same
#      directory as settings_file and `os.replace`s it into place. Result
#      permissions: an EXISTING file's st_mode is preserved (captured
#      before the write, chmod'ed onto the tmp file before the replace) —
#      otherwise os.replace would silently narrow it to whatever mkstemp
#      picked (0600). A freshly-created file gets 0600 (mkstemp's default),
#      appropriate since these files can carry secrets (env, mcpServers).
#   8. Read-under-lock TOCTOU guard (spec R11): settings_file is opened via
#      os.open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) (both flags
#      Windows-degradable via getattr(..., 0), the pattern already
#      canonized in hooks/session-start.sh / hooks/post-tool-use.sh, commit
#      445180a) followed by os.fstat -> stat.S_ISREG on the *already open*
#      fd. A pre-open existence/type check is not enough — a swap to a FIFO
#      between the check and the open() call would still hang the process
#      forever while it holds the settings lock; O_NONBLOCK keeps the
#      open() itself from blocking, and the fstat on the open fd closes the
#      TOCTOU window atomically. A non-regular target (FIFO, socket,
#      directory, device, symlink) refuses the whole operation
#      (non-zero, nothing written) rather than risk it. ENOENT is the
#      ordinary "no file yet" case (fresh create), not an error.
#   9. Orphan-write guard (spec R12): each register_into call snapshots,
#      BEFORE requesting the lock, whether both canonical scripts it is
#      about to register are present+executable. If they were NOT present
#      at that point, a still-missing pair after the lock is acquired is
#      the ordinary "not installed system-wide yet" case covered by (6)
#      above and is not an error. But if they WERE present before the wait
#      and are gone by the time the lock is actually held, that is the
#      specific race where `uninstall.sh --remove-clones` tore down
#      $SKILL_DIR while this installer was blocked waiting for the lock —
#      writing entries now would create fresh orphans pointing at a
#      just-deleted clone. That case refuses with a "skill clone vanished
#      while waiting for lock" message and nothing is written.
#
# Always exits 0 only when there is genuinely nothing to do (no python3);
# any real failure (unreadable/corrupt settings.json, lock timeout, write
# failure, vanished clone) exits non-zero with a client-prefixed message on
# stderr (`install-hooks: <client>: …`) and leaves that client's
# settings.json untouched. No settings-file content is ever printed.

set -uo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "install-hooks: python3 not found — skipping hook registration" >&2
  exit 0
fi

: "${HOME:?install-hooks: HOME is not set}"
HOME_DIR="$HOME"
CLAUDE_DIR="$HOME_DIR/.claude"
LOCK_TIMEOUT="${WIKI_HOOKS_LOCK_TIMEOUT:-10}"
MARKER="/skills/wiki/hooks/"
CANON_SESSION_START="$CLAUDE_DIR/skills/wiki/hooks/session-start.sh"
CANON_POST_TOOL_USE="$CLAUDE_DIR/skills/wiki/hooks/post-tool-use.sh"

# shellcheck source=lib/settings-lock.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/settings-lock.sh"

# fail <client> <message> — used only for the initial lock-acquisition
# check below, where no lock is held yet: a hard `exit 1` there is exactly
# right (nothing to release, and a caller chaining multiple register_into
# calls — see T7 — must abort immediately without attempting the next
# client, same as today's behavior). Every OTHER failure branch inside
# register_into happens AFTER the lock is held and releases it explicitly
# before `return`ing 1 instead, so a later call in the same process can
# still proceed.
fail() {
  echo "install-hooks: $1: $2" >&2
  exit 1
}

# register_into <client> <settings_file> <session_script> <post_script> \
#               <session_matcher> <post_matcher> <legacy_marker>
#
# Registers/refreshes the wiki skill's SessionStart + PostToolUse hooks for
# ONE client's settings_file. <legacy_marker> is an additional command
# substring to strip alongside the canonical $MARKER (used by T7 to migrate
# away from an older qwen wrapper-script path); pass "" when there is no
# legacy marker for this client (claude has none).
#
# Returns 0 on success or genuine no-op, 1 on any real failure — never
# `exit`s directly, so the single top-level call below controls the
# process's actual exit code.
register_into() {
  local client="$1" settings_file="$2" session_script="$3" post_script="$4"
  local session_matcher="$5" post_matcher="$6" legacy_marker="$7"
  local settings_dir lock_dir pre_clone_ok post_clone_ok ts backup_file

  settings_dir="$(dirname "$settings_file")"
  mkdir -p "$settings_dir" 2>/dev/null || {
    echo "install-hooks: $client: cannot create $settings_dir" >&2
    return 1
  }

  # Baseline snapshot BEFORE requesting the lock — see design note 9 above.
  pre_clone_ok=0
  if [ -x "$session_script" ] && [ -x "$post_script" ]; then
    pre_clone_ok=1
  fi

  lock_dir="$settings_file.lockdir"
  # Single, universal mutex for every invocation (design note 1) —
  # deliberately NOT flock-when-available/mkdir-otherwise; mixing the two
  # on the same resource loses mutual exclusion (codex-атк P1). The legacy
  # WIKI_HOOKS_FORCE_MKDIR_LOCK env is retained only for backward-compatible
  # test invocations; it is a no-op since mkdir is always used.
  wiki_lock_acquire "$lock_dir" || fail "$client" "could not acquire lock on $settings_file within ${LOCK_TIMEOUT}s"

  # Test-only seam: hold the lock open for a bit so tests can exercise
  # interrupt/trap-cleanup and vanished-clone behavior deterministically.
  # No-op by default.
  if [ "${WIKI_HOOKS_TEST_SLEEP_AFTER_LOCK:-0}" != "0" ]; then
    sleep "${WIKI_HOOKS_TEST_SLEEP_AFTER_LOCK}"
  fi

  # Re-check under the lock (design note 9 / spec R12).
  post_clone_ok=0
  if [ -x "$session_script" ] && [ -x "$post_script" ]; then
    post_clone_ok=1
  fi
  if [ "$pre_clone_ok" = "1" ] && [ "$post_clone_ok" != "1" ]; then
    echo "install-hooks: $client: skill clone vanished while waiting for lock" >&2
    wiki_lock_release "$lock_dir"
    return 1
  fi

  ts="$(date +%Y%m%d%H%M%S)"
  backup_file="$settings_file.bak-wiki-hooks-$ts"

  if ! python3 - "$client" "$settings_file" "$backup_file" "$MARKER" "$legacy_marker" \
      "$session_script" "$post_script" "$session_matcher" "$post_matcher" <<'PYEOF'
import json
import os
import shutil
import stat
import sys
import tempfile

(
    client,
    settings_file,
    backup_file,
    marker,
    legacy_marker,
    canon_start,
    canon_post,
    session_matcher,
    post_matcher,
) = sys.argv[1:10]


def die(msg):
    sys.stderr.write("install-hooks: %s: %s\n" % (client, msg))
    sys.exit(1)


data = {}
existed = False
mode = None

# TOCTOU-closing open (design note 8 / spec R11): O_NOFOLLOW rejects a
# symlinked settings_file (ELOOP) instead of following it; O_NONBLOCK makes
# opening a FIFO/char-device return immediately instead of hanging forever
# while this call holds the settings lock. The fstat/S_ISREG check on the
# already-open fd is what actually closes the TOCTOU window — a pre-open
# check would still race a swap-to-FIFO landing between the check and the
# open() call. Windows-degradable via getattr(..., 0), same pattern as
# hooks/session-start.sh / hooks/post-tool-use.sh (canonized in
# commit 445180a).
fd = None
try:
    fd = os.open(
        settings_file,
        os.O_RDONLY
        | getattr(os, "O_NOFOLLOW", 0)
        | getattr(os, "O_NONBLOCK", 0),
    )
except FileNotFoundError:
    fd = None
except OSError as exc:
    die("cannot open %s: %s" % (settings_file, exc))

if fd is not None:
    raw = None
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            die(
                "%s is not a regular file — cannot verify, refusing to modify"
                % settings_file
            )
        mode = stat.S_IMODE(st.st_mode)
        with os.fdopen(fd, "r", encoding="utf-8") as fh:
            fd = None  # ownership passed to fh
            raw = fh.read()
    except OSError as exc:
        die("cannot read %s: %s" % (settings_file, exc))
    finally:
        if fd is not None:
            try:
                os.close(fd)
            except OSError:
                pass
    existed = True
    stripped = raw.strip()
    if stripped:
        try:
            data = json.loads(raw)
        except json.JSONDecodeError as exc:
            die("%s is not valid JSON: %s" % (settings_file, exc))
    if not isinstance(data, dict):
        die("%s top-level value is not a JSON object" % settings_file)
    try:
        shutil.copy2(settings_file, backup_file)
    except OSError as exc:
        die("backup failed: %s" % exc)

hooks = data.get("hooks")
if hooks is None:
    hooks = {}
elif not isinstance(hooks, dict):
    die("'hooks' key is not a JSON object")
data["hooks"] = hooks


def has_marker(command):
    command = str(command)
    if marker in command:
        return True
    if legacy_marker and legacy_marker in command:
        return True
    return False


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
                if not (isinstance(h, dict) and has_marker(h.get("command", "")))
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

add_entry("SessionStart", session_matcher, session_cmd)
add_entry("PostToolUse", post_matcher, post_cmd)

dir_name = os.path.dirname(settings_file) or "."
tfd, tmp_path = tempfile.mkstemp(prefix=".settings.json.", dir=dir_name)
try:
    if existed and mode is not None:
        # Preserve the existing file's permissions (design note 7) — an
        # unconditional os.replace would otherwise silently narrow them to
        # whatever mkstemp picked (0600).
        os.chmod(tmp_path, mode)
    with os.fdopen(tfd, "w", encoding="utf-8") as fh:
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
    echo "install-hooks: $client: settings.json merge failed — nothing written" >&2
    wiki_lock_release "$lock_dir"
    return 1
  fi

  echo "install-hooks: $client: SessionStart + PostToolUse зареєстровано в $settings_file" >&2
  wiki_lock_release "$lock_dir"
  return 0
}

register_into claude "$CLAUDE_DIR/settings.json" \
  "$CANON_SESSION_START" "$CANON_POST_TOOL_USE" \
  'startup|clear|compact' 'Read|Edit|Write|MultiEdit' '' || exit 1

exit 0
