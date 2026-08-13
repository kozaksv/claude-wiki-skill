# hooks/lib/settings-lock.sh
#
# Single, shared mutex implementation for every script that
# read-modify-writes a Claude/Qwen settings.json under a lock directory
# (hooks/install-hooks.sh, hooks/uninstall-hooks.sh, and the top-level
# uninstall.sh). Extracted verbatim (moved, not rewritten) from
# hooks/install-hooks.sh:118-233 (docs/superpowers/plans/2026-08-13-v46-qwen.md
# Task 5) — the comments below reproduce the hard-won invariants
# (PID-recycle, empty-pid race window, atomic claim-then-destroy) that were
# fixed one at a time in earlier waves; do not "clean them up" away.
#
# Design (mirrors install-hooks.sh's former header, see plan Task 4/5 for
# full rationale):
#   Serialized read-modify-write under ONE exclusive mutex: an atomic
#   `mkdir` lock-directory. A single primitive is used for EVERY
#   invocation — never flock-when-available / mkdir-otherwise — because
#   two different primitives guarding the same resource are not mutually
#   exclusive: an flock holder and a concurrent mkdir holder would both
#   enter the critical section and corrupt settings.json (codex-атк P1).
#   The mkdir lock records its own PID inside the lock dir and installs an
#   EXIT/INT/TERM trap plus pid-liveness + mtime-age reclaim, so a crash or
#   interrupt while holding the lock can never deadlock a future run.
#   PID liveness is NEVER trusted on its own: an operating system recycles
#   PIDs, so if the original lock holder crashed and its PID was later
#   reassigned to an unrelated long-running process, `kill -0 $pid` would
#   report "alive" forever and a liveness-only check would deadlock every
#   future run permanently. To close that hole, lock age is the ultimate
#   authority: a lock older than WIKI_HOOKS_LOCK_MAX_AGE is ALWAYS
#   force-reclaimed regardless of what kill -0 says about the recorded pid
#   (P1, fixwave0-2) — liveness only ever extends the wait, it never
#   blocks reclamation forever.
#
# Public API (the only functions callers should use):
#   wiki_lock_acquire <lockdir>  -> 0 = acquired, 1 = timed out.
#                                    Installs the shared EXIT/INT/TERM trap
#                                    on its first-ever call.
#   wiki_lock_release <lockdir>  -> idempotent; removes the lock dir only
#                                    if its recorded pid is our own ($$).
#
# State is PER-CALL, not a single global scalar: an internal array of
# currently-held lock dirs (_WIKI_LOCK_HELD), because a caller (uninstall.sh,
# Task 12) holds TWO lock dirs open at the same time (claude's and qwen's).
# wiki_lock_acquire appends to it; wiki_lock_release removes from it.
#
# The trap is installed exactly ONCE (guarded by _WIKI_LOCK_TRAP_INSTALLED)
# and, on exit, releases EVERY still-held lock in the reverse order it was
# acquired, then preserves and re-raises the original exit code — exactly
# like the on_exit this replaces.
#
# Env knobs — UNCHANGED names and defaults, read fresh on every
# wiki_lock_acquire call (so a caller may vary them per invocation):
#   WIKI_HOOKS_LOCK_TIMEOUT   (10)   — max seconds a call blocks waiting.
#   WIKI_HOOKS_LOCK_POLL      (0.2)  — poll interval while waiting.
#   WIKI_HOOKS_LOCK_MAX_AGE   (3600) — absolute reclaim ceiling, see above.
#   WIKI_HOOKS_FORCE_MKDIR_LOCK      — legacy, compatible no-op: mkdir is
#     always the mutex now, so this switch does nothing; it is kept only so
#     existing test invocations that still set it keep working unchanged.
# The lockdir PATH itself is the caller's to construct (typically
# "<settings_file>.lockdir") — this lib never invents or defaults one.
#
# Safety under `set -e`: this file is sourced by callers running under
# `set -euo pipefail` (the top-level uninstall.sh). No function here may
# leave a non-zero exit status as the last command on a successful path,
# and every internal grep/kill -0/stat/cat/rm/rmdir call that can fail for
# ordinary, expected reasons (missing file, dead pid, race with another
# holder) is guarded with `|| true` or placed inside an `if`/`elif` test so
# it can never itself trip `set -e`.
#
# There is deliberately no second implementation of this mutex anywhere in
# the tree — two different primitives guarding the same resource is not
# mutual exclusion.

_WIKI_LOCK_HELD=()
_WIKI_LOCK_TRAP_INSTALLED=0

_wiki_lock_is_pid_alive() {
  [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null
}

_wiki_lock_dir_age_seconds() {
  local d="$1" mtime now
  # BSD `stat -f %m` (macOS) vs GNU `stat -c %Y` (Linux) are mutually
  # rejected by each other's stat — EXCEPT GNU stat also accepts `-f`
  # (its own, unrelated --file-system flag) without erroring, so
  # `stat -f %m "$d"` on Linux does not fail cleanly: it silently emits
  # non-numeric filesystem-status text instead of an mtime. Validate each
  # candidate's output is a plain integer before trusting it, rather than
  # trusting "non-empty" as if it meant "correct".
  mtime="$(stat -f %m "$d" 2>/dev/null || true)"
  case "$mtime" in
    ''|*[!0-9]*) mtime="" ;;
  esac
  if [ -z "$mtime" ]; then
    mtime="$(stat -c %Y "$d" 2>/dev/null || true)"
    case "$mtime" in
      ''|*[!0-9]*) mtime="" ;;
    esac
  fi
  [ -z "$mtime" ] && return 1
  now="$(date +%s)"
  echo $((now - mtime))
}

_wiki_lock_reclaim() {
  # Atomically CLAIM the stale lock before destroying it (fixwave0-1 P0,
  # TOCTOU): with a naive `rm pid; rmdir`, two contenders that BOTH judged
  # the lock stale race each other — A clears and re-mkdirs, then B (acting
  # on its own earlier staleness verdict) clears A's freshly acquired live
  # lock, and a third process enters concurrently. rename(2) is atomic:
  # exactly ONE claimer wins the `mv`; losers fail and simply re-loop. The
  # claimed dir is then destroyed under a private name nobody else races.
  local lockdir="$1" claim="$1.claim.$$"
  if mv "$lockdir" "$claim" 2>/dev/null; then
    rm -rf "$claim" 2>/dev/null || true
  fi
  return 0
}

# Shared EXIT/INT/TERM trap handler, installed exactly once (see
# wiki_lock_acquire). Tears down EVERY still-held lock, most-recently
# acquired first, and preserves the process's real exit code.
_wiki_lock_release_all() {
  local ec=$?
  local idxs=("${!_WIKI_LOCK_HELD[@]}")
  local n="${#idxs[@]}"
  local i j lockdir owner
  for (( i = n - 1; i >= 0; i-- )); do
    j="${idxs[$i]}"
    lockdir="${_WIKI_LOCK_HELD[$j]}"
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
    owner="$(cat "$lockdir/pid" 2>/dev/null || true)"
    if [ "$owner" = "$$" ]; then
      rm -f "$lockdir/pid" 2>/dev/null || true
      rmdir "$lockdir" 2>/dev/null || true
    fi
  done
  _WIKI_LOCK_HELD=()
  exit "$ec"
}

# wiki_lock_acquire <lockdir> -> 0 acquired, 1 timed out.
#
# mkdir-based lock: atomic `mkdir` as the mutex. Crash/interrupt recovery
# relies on the shared EXIT/INT/TERM trap (installed below on first call)
# — the pid file is written FIRST, the directory removed SECOND, so a bare
# `rmdir` on a nonempty dir never hangs a cleanup.
wiki_lock_acquire() {
  local lockdir="$1"
  local lock_timeout="${WIKI_HOOKS_LOCK_TIMEOUT:-10}"
  local lock_poll="${WIKI_HOOKS_LOCK_POLL:-0.2}"
  # Absolute ceiling on lock age (P1, fixwave0-2 — PID-recycle deadlock
  # guard): once a lock dir is older than this, it is ALWAYS
  # force-reclaimed regardless of whether the recorded pid currently looks
  # alive. Deliberately much larger than lock_timeout (which only governs
  # how long a *waiting* invocation blocks on a live-looking owner) — it
  # exists purely so a crashed holder whose pid gets reassigned to some
  # unrelated long-running process can never wedge the lock forever.
  local lock_max_age="${WIKI_HOOKS_LOCK_MAX_AGE:-3600}"
  local start elapsed pid age now

  if [ "$_WIKI_LOCK_TRAP_INSTALLED" != "1" ]; then
    trap _wiki_lock_release_all EXIT INT TERM
    _WIKI_LOCK_TRAP_INSTALLED=1
  fi

  start="$(date +%s)"
  while true; do
    if mkdir "$lockdir" 2>/dev/null; then
      # Record the held lock BEFORE writing the pid file: if a signal
      # lands in the narrow window between `mkdir` succeeding and the pid
      # write below, the trap must still know it owns (and must remove)
      # this lock dir, even pid-less.
      _WIKI_LOCK_HELD+=("$lockdir")
      echo $$ >"$lockdir/pid" 2>/dev/null || true
      return 0
    fi
    if [ -f "$lockdir/pid" ]; then
      pid="$(cat "$lockdir/pid" 2>/dev/null || true)"
    else
      pid=""
    fi
    if [ -n "$pid" ]; then
      # PID-recycle deadlock guard (P1, fixwave0-2): liveness of a stored
      # pid is NEVER, on its own, sufficient grounds to keep waiting
      # forever. If the original holder crashed and the OS later recycled
      # its pid onto an unrelated long-running process, `kill -0 $pid`
      # would report "alive" indefinitely and this lock could never be
      # reclaimed by liveness alone. So age is checked FIRST and wins
      # unconditionally: once the lock is older than lock_max_age it is
      # force-cleared no matter what kill -0 says.
      age="$(_wiki_lock_dir_age_seconds "$lockdir" 2>/dev/null || true)"
      if [ -n "${age:-}" ] && [ "$age" -gt "$lock_max_age" ]; then
        _wiki_lock_reclaim "$lockdir"
        continue
      elif _wiki_lock_is_pid_alive "$pid"; then
        : # live owner within the max-age bound — never steal, just wait.
      else
        # Non-empty pid naming a dead/unreadable process -> genuinely
        # stale lock; atomically claim + destroy and retry immediately (no
        # need to wait out lock_max_age when the pid is verifiably dead).
        _wiki_lock_reclaim "$lockdir"
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
      # (atomic claim-then-destroy — see _wiki_lock_reclaim).
      age="$(_wiki_lock_dir_age_seconds "$lockdir" 2>/dev/null || true)"
      if [ -n "${age:-}" ] && [ "$age" -gt "$lock_timeout" ]; then
        _wiki_lock_reclaim "$lockdir"
        continue
      fi
    fi
    now="$(date +%s)"
    elapsed=$((now - start))
    if [ "$elapsed" -ge "$lock_timeout" ]; then
      return 1
    fi
    sleep "$lock_poll"
  done
}

# wiki_lock_release <lockdir> -> idempotent. Removes the lock dir only if
# it is currently held by this call (present in _WIKI_LOCK_HELD) AND its
# recorded pid is our own ($$) — a lockdir some other pid owns is left
# untouched. Safe to call more than once for the same lockdir, and safe to
# call for a lockdir this process never acquired (no-op).
wiki_lock_release() {
  local lockdir="$1" owner i idx=""
  for i in "${!_WIKI_LOCK_HELD[@]}"; do
    if [ "${_WIKI_LOCK_HELD[$i]}" = "$lockdir" ]; then
      idx="$i"
      break
    fi
  done
  if [ -z "$idx" ]; then
    return 0
  fi
  owner="$(cat "$lockdir/pid" 2>/dev/null || true)"
  if [ "$owner" = "$$" ]; then
    rm -f "$lockdir/pid" 2>/dev/null || true
    rmdir "$lockdir" 2>/dev/null || true
  fi
  unset "_WIKI_LOCK_HELD[$idx]"
  return 0
}
