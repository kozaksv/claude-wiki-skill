#!/usr/bin/env bash
# hooks/uninstall-hooks.sh
#
# Removes the wiki skill's two global hooks (SessionStart, PostToolUse) from
# EVERY client settings file install-hooks.sh knows how to register into:
# ~/.claude/settings.json AND ~/.qwen/settings.json
# (docs/superpowers/plans/2026-08-13-v46-qwen.md Task 8).
#
# DESIGN (Task 8, settled decisions s3-s7 in
# docs/superpowers/plans/2026-08-13-v46-qwen-settled.md — do not relitigate
# the mechanisms those decisions forbid):
#
#   Both clients are validated and written by ONE python3 process, invoked
#   ONCE, under BOTH settings locks already held by this bash script (in the
#   global order claude -> qwen; released qwen -> claude via the shared
#   EXIT/INT/TERM trap hooks/lib/settings-lock.sh installs). Inside that one
#   process:
#     phase plan (per client): os.open(O_RDONLY|O_NOFOLLOW|O_NONBLOCK) ->
#       fstat/S_ISREG -> read -> json.loads + "is this an object" -> compute
#       the stripped result. Original bytes and the computed result stay IN
#       MEMORY; nothing touches disk in this phase. State per client:
#       nochange (file absent, or present with nothing to strip) / planned
#       (present, has our marker(s), a write is needed) / error.
#     phase commit (only once NEITHER client is in error): for each
#       "planned" client, in order claude -> qwen: mkstemp beside the target
#       -> fchmod to the source's mode -> write -> close -> backup via
#       os.open(O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW) at
#       "<settings_file>.bak-wiki-hooks-<TS>" (numbered suffix on collision)
#       written from the IN-MEMORY original bytes -> os.replace.
#   One process, not four separate python3 calls (plan x2 + commit x2, as an
#   earlier round of this task built): that used to leave a tmp file sitting
#   on disk for the ENTIRE duration of the second client's plan phase — a
#   window with no purpose other than being racy. Here a tmp file's lifetime
#   is milliseconds, inside the process that created it.
#
#   Locks are taken ONLY for a client whose settings directory already
#   exists (a missing ~/.qwen means a missing settings.json, which is
#   unconditionally nochange — this script never mkdir's ~/.claude or
#   ~/.qwen just to host a lockdir). A client this script did not lock is
#   never opened by the python process either — plan_client short-circuits
#   to nochange for it without touching the filesystem, so there is no
#   window in which this script reads or writes a file it holds no lock on.
#
#   Cleanup on any exit path distinguishes tmp from backup (s7): only tmp
#   files are ever removed by an error/signal branch. ".bak-wiki-hooks-*" is
#   never on that list and is never deleted on any path, success or
#   failure — it is a recovery copy for a human, exactly like install-
#   hooks.sh's backup, and v4.5 has never deleted one either.
#
#   Rollback (s5) applies ONLY to an ordinary failure of the SECOND commit
#   after the first one already succeeded, and restores from the FIRST
#   client's in-memory pre-strip bytes via a fresh mkstemp + os.replace —
#   never by reading the backup file back (a backup file is for humans, not
#   a second source of truth this process trusts). If the rollback write
#   itself fails, this prints the absolute path of that backup and asks for
#   manual recovery.
#
#   Signal (INT/TERM) handling: this script installs its OWN INT/TERM traps
#   (overriding, for those two signals only, the combined EXIT/INT/TERM trap
#   settings-lock.sh installs on the first wiki_lock_acquire call — EXIT
#   stays wired to that shared trap, so lock cleanup on the way out is
#   unaffected) right before launching the python process in the
#   background. Each trap records the honest exit code (130 for INT, 143
#   for TERM) in a variable and forwards the same signal to the python
#   child, then returns; control resumes right after the interrupted `wait`
#   builtin, and the script exits with that RECORDED code explicitly —
#   never by letting the shared trap read a stale `$?` (which could easily
#   be 0 from some earlier successful command and falsely report success to
#   uninstall.sh, which treats exit 0 as permission to delete the clone
#   hosting this very recovery script). No automatic rollback runs on a
#   signal (s4): the trap's job is exactly "clean tmp + locks, report an
#   honest non-zero, ask for a re-run" — nothing more. A signal landing
#   between the two commits leaves the already-committed client committed
#   and the not-yet-committed client untouched; that half-done state is a
#   DECLARED residual, not a bug, because a re-run converges (uninstall is
#   idempotent) and the alternative (an EXIT-trap rollback keyed on a
#   signal) is exactly the extra mechanism s4/s3 forbid re-adding.
#
#   DECLARED RESIDUALS (plan Task 8 point 13 — name them, do not chase
#   them with more mechanism):
#     (a) a signal between the two commits leaves one client done and the
#         other not — a chesny non-zero + "re-run" message, converged by
#         idempotent re-invocation, never an automatic rollback;
#     (b) a third party writing to a settings file between this script's
#         plan and commit phases for that file gets overwritten by the
#         planned result — the same semantics install-hooks.sh already has;
#     (c) a client's directory appearing AFTER this script decided not to
#         lock it (because it was absent at that decision point) is not
#         retroactively locked or reconsidered mid-run;
#     (d) the window between os.close(tmp) and os.replace(tmp, target)
#         inside a single commit is not, and cannot be, closed by any
#         pre-replace check — rename(2) addresses a PATH, not the fd
#         Python already closed, and renameat2/RENAME_NOREPLACE is not
#         available to Python here. A check immediately before replace only
#         moves this window, it does not remove it.
#
# Granularity matches install-hooks.sh: only elements of a matcher-entry's
# nested `hooks[]` array whose `command` contains the `/skills/wiki/hooks/`
# marker (or, for qwen, the legacy `~/.qwen/hooks/wiki-session-start.sh`
# wrapper marker install-hooks.sh also migrates away from) are removed. A
# matcher-entry is dropped once its `hooks[]` is empty; an event array
# (`SessionStart`/`PostToolUse`) is dropped once it holds no entries.
# Everything else in each settings.json is untouched.
#
# Exit-code contract (unchanged from the pre-T8 script; still what
# uninstall.sh's --remove-clones gates clone deletion on): exit 0 only when
# there is verifiably nothing left to do for EVERY client file that exists.
# A settings path that EXISTS but cannot be read as settings JSON (a
# directory, FIFO, dangling symlink, unreadable regular file) is never
# "nothing to do" — it is unverifiable, and unverifiable is fail-closed,
# exactly like "marker still present". Any real failure for ANY client —
# including python3 being unavailable while a marker is present anywhere —
# exits the WHOLE script non-zero, and (per the plan design above) leaves
# EVERY client's settings.json untouched, not just the one that failed.

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
# leaving the legacy entry behind. Claude has no legacy marker.
LEGACY_QWEN_MARKER="/.qwen/hooks/wiki-session-start.sh"

if ! command -v python3 >/dev/null 2>&1; then
  # python3 is required to safely parse/rewrite settings.json. If ANY
  # client's file still carries a wiki hook marker we cannot perform (or
  # verify) removal there, so this is a REAL failure, not a no-op — see the
  # exit-code contract above. grep is a best-effort substring check (not
  # JSON-aware) but that is exactly the same "marker in command string" test
  # the python merge step below uses, so it is precise enough to
  # distinguish "nothing to do" from "removal needed but impossible".
  #
  # Three states, never two (codex-атк P1, wave3): grep exits 0 = found,
  # 1 = read successfully and absent, >=2 = could NOT be read (permissions,
  # I/O error). The old `grep -Fq … 2>/dev/null || …` collapsed >=2 into
  # "absent", so an unreadable settings.json exited 0 = "verifiably nothing
  # to do" — and uninstall.sh trusts that exit code to green-light deleting
  # the clone that hosts THIS recovery script. "Could not verify" must have
  # exactly the same consequence as "found": hard failure.
  marker_present=0
  for f in "$CLAUDE_SETTINGS" "$QWEN_SETTINGS"; do
    # Truly absent (fails BOTH -e and -L) → nothing was ever registered for
    # this client; skip. A dangling symlink, directory or FIFO at the path
    # IS present yet unreadable as settings JSON → unverifiable → fail.
    [ -e "$f" ] || [ -L "$f" ] || continue
    if [ ! -f "$f" ]; then
      fail "python3 not found and $f is not a regular file — cannot verify hook markers"
    fi
    # Marker set is per-client, exactly mirroring what the python merge
    # below would strip for that client (claude: canonical only; qwen:
    # canonical + the legacy wrapper path).
    grep_pats=(-e "$MARKER")
    if [ "$f" = "$QWEN_SETTINGS" ]; then
      grep_pats+=(-e "$LEGACY_QWEN_MARKER")
    fi
    grep_rc=0
    grep -Fq "${grep_pats[@]}" "$f" >/dev/null 2>&1 || grep_rc=$?
    case "$grep_rc" in
      0) marker_present=1 ;;
      1) : ;;
      *) fail "python3 not found and $f could not be read — cannot verify hook markers" ;;
    esac
  done
  if [ "$marker_present" = "1" ]; then
    fail "python3 not found — cannot remove hook entries (marker still present)"
  fi
  echo "uninstall-hooks: python3 not found — no hook markers present, nothing to remove" >&2
  exit 0
fi

# shellcheck source=lib/settings-lock.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/settings-lock.sh"

# Locks are acquired ONLY for a client whose settings directory already
# exists (plan point 9): a missing ~/.qwen means a missing settings.json,
# unconditionally nochange, and this script never creates ~/.claude or
# ~/.qwen just to host a lockdir. Order is claude -> qwen textually and at
# runtime (static-assert test in tests/hooks/run.sh greps for this).
CLAUDE_LOCKED=0
if [ -d "$CLAUDE_DIR" ]; then
  wiki_lock_acquire "$CLAUDE_SETTINGS.lockdir" || fail "claude: could not acquire lock on $CLAUDE_SETTINGS within ${LOCK_TIMEOUT}s"
  CLAUDE_LOCKED=1
fi

QWEN_LOCKED=0
if [ -d "$QWEN_DIR" ]; then
  if ! wiki_lock_acquire "$QWEN_SETTINGS.lockdir"; then
    # First lock already held -> release it before failing (plan point 10).
    [ "$CLAUDE_LOCKED" = "1" ] && wiki_lock_release "$CLAUDE_SETTINGS.lockdir"
    fail "qwen: could not acquire lock on $QWEN_SETTINGS within ${LOCK_TIMEOUT}s"
  fi
  QWEN_LOCKED=1
fi

# ---------------------------------------------------------------------------
# Signal handling for the window this single python invocation spans.
#
# settings-lock.sh's wiki_lock_acquire above already installed a combined
# `trap _wiki_lock_release_all EXIT INT TERM` (on its first call). That
# handler reads a STALE `$?` on INT/TERM — whatever the last command
# happened to return, not "were we interrupted" — and re-`exit`s with it,
# which could easily be 0. uninstall.sh treats exit 0 as permission to
# delete the clone hosting this very script, so a signal must never be
# allowed to masquerade as success.
#
# Overriding INT and TERM here (deliberately NOT EXIT, which stays wired to
# the shared lock-cleanup trap) makes each of our handlers record the
# HONEST code for the signal it caught and forward that same signal to the
# python child so it can die promptly instead of finishing an unrelated
# amount of work first. The handler does not itself `exit` — it returns,
# the interrupted `wait` builtin resumes, and the script below explicitly
# `exit`s with the recorded code, which is what finally fires the shared
# EXIT trap and releases both locks.
_UNINSTALL_SIG_CODE=""
_UNINSTALL_PY_PID=""

_uninstall_on_term() {
  _UNINSTALL_SIG_CODE=143
  [ -n "$_UNINSTALL_PY_PID" ] && kill -TERM "$_UNINSTALL_PY_PID" 2>/dev/null
  true
}

_uninstall_on_int() {
  _UNINSTALL_SIG_CODE=130
  [ -n "$_UNINSTALL_PY_PID" ] && kill -INT "$_UNINSTALL_PY_PID" 2>/dev/null
  true
}

trap _uninstall_on_term TERM
trap _uninstall_on_int INT

# Test-only seam (plan Task 8 point 4/13a): sleep AFTER the first planned
# client's commit has fully landed and BEFORE the second one starts, so a
# signal delivered in that window lands where the "signal between commits"
# residual is (no tmp file is ever open at that exact point — the first
# client's tmp was already replaced, the second client's tmp does not exist
# yet). No-op by default (0).
UNINSTALL_SEAM="${WIKI_HOOKS_TEST_SLEEP_BETWEEN_COMMITS:-0}"

# run_uninstall_py <marker> <seam> <client1> <settings1> <legacy1> <locked1>
#                   <client2> <settings2> <legacy2> <locked2>
#
# The ENTIRE two-phase, two-client protocol lives in this one python3
# process (s5): plan(client1) -> plan(client2) -> [any error => exit 1,
# nothing written] -> commit(planned clients, in argv order). A client
# whose <lockedN> is "0" is never opened at all — this script holds no
# lock on it, so nothing about it may be read or written (plan point 9).
run_uninstall_py() {
  python3 - "$@" <<'PYEOF'
import errno
import json
import os
import stat
import sys
import tempfile
import time

# How many "$settings_file.bak-wiki-hooks-$TS[-N]" candidates the exclusive
# backup create below probes before giving up — same bound, same reason as
# install-hooks.sh (see its long note on this).
BACKUP_NAME_ATTEMPTS = 64


def has_marker(command, marker, legacy_marker):
    command = str(command)
    if marker in command:
        return True
    if legacy_marker and legacy_marker in command:
        return True
    return False


def strip_markers(data, marker, legacy_marker):
    """Return (new_data, changed) — new_data is a fresh top-level dict with
    the wiki entries stripped out of hooks['SessionStart']/['PostToolUse'];
    `data` itself is never mutated, so callers may keep it around as the
    pristine pre-strip value (used for the backup and for rollback)."""
    hooks = data.get("hooks")
    if not isinstance(hooks, dict):
        return data, False

    hooks = dict(hooks)
    changed = [False]

    def strip_event(event_name):
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
                    if not (isinstance(h, dict) and has_marker(h.get("command", ""), marker, legacy_marker))
                ]
                if len(filtered) == 0:
                    # Whole entry was ours alone -> drop the entry.
                    changed[0] = True
                    continue
                if len(filtered) != len(inner):
                    changed[0] = True
                    entry = dict(entry)
                    entry["hooks"] = filtered
            kept.append(entry)
        if kept:
            hooks[event_name] = kept
        elif event_name in hooks:
            changed[0] = True
            hooks.pop(event_name, None)

    strip_event("SessionStart")
    strip_event("PostToolUse")

    new_data = dict(data)
    if hooks:
        new_data["hooks"] = hooks
    else:
        if "hooks" in new_data:
            changed[0] = True
        new_data.pop("hooks", None)

    return new_data, changed[0]


def plan_client(client, settings_file, marker, legacy_marker, locked):
    """Phase 1: read + validate + compute the stripped result, entirely in
    memory. Returns a dict with state in {"nochange", "planned", "error"}.
    Never touches a client this script did not lock (plan point 9)."""
    result = {
        "client": client,
        "settings_file": settings_file,
        "state": "nochange",
        "raw": None,
        "mode": None,
        "data": None,
    }
    if not locked:
        return result

    def fail(msg):
        sys.stderr.write("uninstall-hooks: %s: %s\n" % (client, msg))
        result["state"] = "error"
        return result

    # TOCTOU-closing open (same guard as install-hooks.sh's register_into,
    # plan point 5 — NOT an `-f` pre-check): O_NOFOLLOW refuses a symlinked
    # settings_file outright (ELOOP), O_NONBLOCK keeps opening a
    # FIFO/char-device from hanging forever while this call holds the lock,
    # and fstat/S_ISREG on the already-open fd closes the window a
    # pre-open check could not.
    fd = None
    try:
        fd = os.open(
            settings_file,
            os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0),
        )
    except FileNotFoundError:
        return result
    except OSError as exc:
        if exc.errno in (errno.ELOOP,):
            return fail("%s is not a regular file — cannot verify hook markers" % settings_file)
        return fail("cannot open %s: %s" % (settings_file, exc))

    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            return fail("%s is not a regular file — cannot verify hook markers" % settings_file)
        mode = stat.S_IMODE(st.st_mode)
        with os.fdopen(fd, "r", encoding="utf-8") as fh:
            fd = None  # ownership passed to fh
            raw = fh.read()
    except OSError as exc:
        return fail("cannot read %s: %s" % (settings_file, exc))
    finally:
        if fd is not None:
            try:
                os.close(fd)
            except OSError:
                pass

    data = {}
    stripped_text = raw.strip()
    if stripped_text:
        try:
            data = json.loads(raw)
        except json.JSONDecodeError as exc:
            return fail("%s is not valid JSON: %s" % (settings_file, exc))
    if not isinstance(data, dict):
        return fail("%s top-level value is not a JSON object" % settings_file)

    new_data, changed = strip_markers(data, marker, legacy_marker)
    result["raw"] = raw
    result["mode"] = mode
    if changed:
        result["state"] = "planned"
        result["data"] = new_data
    return result


def commit_client(p, ts):
    """Phase 2, one client: mkstemp -> fchmod -> write -> close -> backup
    (from IN-MEMORY pre-strip bytes) -> os.replace. Returns True/False;
    always cleans up its own tmp file on any failure."""
    client = p["client"]
    settings_file = p["settings_file"]
    dir_name = os.path.dirname(settings_file) or "."

    tfd, tmp_path = tempfile.mkstemp(prefix=".settings.json.", dir=dir_name)
    try:
        if p["mode"] is not None and hasattr(os, "fchmod"):
            os.fchmod(tfd, p["mode"])
        with os.fdopen(tfd, "w", encoding="utf-8") as fh:
            tfd = None  # ownership passed to fh
            json.dump(p["data"], fh, indent=2, ensure_ascii=False)
            fh.write("\n")
    except OSError as exc:
        if tfd is not None:
            try:
                os.close(tfd)
            except OSError:
                pass
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        sys.stderr.write("uninstall-hooks: %s: write failed: %s\n" % (client, exc))
        return False

    # Predictable backup path -> CREATED, never opened (codex-атк P1): a
    # symlink pre-planted at this exact name gets refused by O_EXCL
    # (POSIX: fails on a symlink, dangling or not) instead of followed and
    # truncated. Content comes from p["raw"], the bytes already read in the
    # plan phase — never a re-read of settings_file by path.
    backup_file = "%s.bak-wiki-hooks-%s" % (settings_file, ts)
    bfd = None
    backup_path = None
    for attempt in range(BACKUP_NAME_ATTEMPTS):
        candidate = backup_file if attempt == 0 else "%s-%d" % (backup_file, attempt)
        try:
            bfd = os.open(
                candidate,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0),
                0o600,
            )
        except OSError as exc:
            if exc.errno in (errno.EEXIST, errno.ELOOP):
                continue
            sys.stderr.write("uninstall-hooks: %s: backup failed: %s\n" % (client, exc))
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
            return False
        backup_path = candidate
        break
    if bfd is None:
        sys.stderr.write(
            "uninstall-hooks: %s: backup failed: no free backup name beside %s\n" % (client, settings_file)
        )
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        return False
    try:
        if p["mode"] is not None and hasattr(os, "fchmod"):
            os.fchmod(bfd, p["mode"])
        with os.fdopen(bfd, "w", encoding="utf-8") as bf:
            bfd = None  # ownership passed to bf
            bf.write(p["raw"])
    except OSError as exc:
        if bfd is not None:
            try:
                os.close(bfd)
            except OSError:
                pass
        sys.stderr.write("uninstall-hooks: %s: backup failed: %s\n" % (client, exc))
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        return False

    try:
        os.replace(tmp_path, settings_file)
    except OSError as exc:
        sys.stderr.write("uninstall-hooks: %s: replace failed: %s\n" % (client, exc))
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        return False

    p["backup_abs_path"] = os.path.abspath(backup_path)
    return True


def rollback_client(p):
    """Restore a previously-committed client from its IN-MEMORY pre-strip
    bytes (never from the backup file — that is a recovery copy for a
    human, not a second source of truth this process trusts). Only called
    for an ORDINARY commit failure of the OTHER client, never for a
    signal (s4/s5)."""
    settings_file = p["settings_file"]
    dir_name = os.path.dirname(settings_file) or "."
    try:
        tfd, tmp_path = tempfile.mkstemp(prefix=".settings.json.", dir=dir_name)
    except OSError:
        return False
    try:
        if p["mode"] is not None and hasattr(os, "fchmod"):
            os.fchmod(tfd, p["mode"])
        with os.fdopen(tfd, "w", encoding="utf-8") as fh:
            tfd = None  # ownership passed to fh
            fh.write(p["raw"])
        os.replace(tmp_path, settings_file)
        return True
    except OSError:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        return False


def main():
    marker = sys.argv[1]
    seam = float(sys.argv[2])
    rest = sys.argv[3:]
    clients = [tuple(rest[i:i + 4]) for i in range(0, len(rest), 4)]

    plans = [
        plan_client(client, settings_file, marker, legacy_marker, locked == "1")
        for (client, settings_file, legacy_marker, locked) in clients
    ]

    # No write for ANYONE until every client has planned cleanly (plan
    # point 3): any single error refuses the whole run.
    if any(p["state"] == "error" for p in plans):
        sys.exit(1)

    planned = [p for p in plans if p["state"] == "planned"]
    ts = time.strftime("%Y%m%d%H%M%S")
    committed = []
    for idx, p in enumerate(planned):
        if idx == 1 and seam > 0:
            time.sleep(seam)
        if commit_client(p, ts):
            committed.append(p)
            continue
        # This commit failed. If an earlier client in THIS run already
        # committed, roll it back from memory (s5) — never automatically
        # on a signal (that path never reaches here: a signal kills this
        # process directly, see the bash wrapper).
        if committed:
            prev = committed[-1]
            if rollback_client(prev):
                sys.stderr.write(
                    "uninstall-hooks: %s: rolled back after %s failed to commit\n" % (prev["client"], p["client"])
                )
            else:
                sys.stderr.write(
                    "uninstall-hooks: %s: rollback FAILED after %s failed to commit — "
                    "restore manually from %s\n"
                    % (prev["client"], p["client"], prev.get("backup_abs_path", "<unknown>"))
                )
        sys.exit(1)

    sys.exit(0)


main()
PYEOF
}

run_uninstall_py "$MARKER" "$UNINSTALL_SEAM" \
  claude "$CLAUDE_SETTINGS" "" "$CLAUDE_LOCKED" \
  qwen "$QWEN_SETTINGS" "$LEGACY_QWEN_MARKER" "$QWEN_LOCKED" &
_UNINSTALL_PY_PID=$!
wait "$_UNINSTALL_PY_PID"
PY_RC=$?

# A caught signal always wins over whatever python's own exit status
# happened to be — see the signal-handling note above.
if [ -n "$_UNINSTALL_SIG_CODE" ]; then
  echo "uninstall-hooks: interrupted — please re-run bash uninstall-hooks.sh" >&2
  exit "$_UNINSTALL_SIG_CODE"
fi

exit "$PY_RC"
