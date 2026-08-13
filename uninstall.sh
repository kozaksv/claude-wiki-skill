#!/usr/bin/env bash
set -euo pipefail

REMOVE_CLONES=0

usage() {
  cat <<'USAGE'
Wiki Skill uninstall

Usage:
  bash uninstall.sh [--remove-clones]

Default behavior removes only skill entrypoint/export symlinks and leaves real
git clone directories intact:
  ~/claude-wiki-skill
  ~/claude-doc-extract-skill

It removes empty */skills subdirectories when possible, but keeps parent
~/.claude, ~/.agents, ~/.gemini, and ~/.qwen directories in place.

Use --remove-clones to remove those clone directories too, but only when each
directory is a git repo and has no local changes.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --remove-clones)
      REMOVE_CLONES=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

SKILLS_ROOT="$HOME/.claude/skills"
AGENTS_SKILLS_ROOT="$HOME/.agents/skills"
GEMINI_SKILLS_ROOT="$HOME/.gemini/skills"
QWEN_SKILLS_ROOT="$HOME/.qwen/skills"

SKILL_DIR="$HOME/claude-wiki-skill"
DOC_EXTRACT_DIR="$HOME/claude-doc-extract-skill"

SKIPPED=0
HOOKS_FAILED=0

remove_symlink_entry() {
  local path="$1" expected_target="$2"
  if [ -L "$path" ]; then
    local current
    current="$(readlink "$path")"
    if [ "$current" != "$expected_target" ]; then
      echo "$path — skipped (symlink points elsewhere: $current; expected → $expected_target)"
      SKIPPED=1
      return 0
    fi
    rm "$path"
    echo "$path — removed symlink (was → $current)"
    return 0
  fi
  if [ -e "$path" ]; then
    echo "$path — skipped (exists and is not a symlink)"
    SKIPPED=1
    return 0
  fi
  echo "$path — already absent"
}

remove_clone_dir() {
  local dir="$1"
  if [ ! -e "$dir" ]; then
    echo "$dir — already absent"
    return 0
  fi
  if [ ! -d "$dir/.git" ]; then
    echo "$dir — skipped (exists but is not a git repo)"
    SKIPPED=1
    return 0
  fi
  if ! command -v git >/dev/null 2>&1; then
    echo "$dir — skipped (git unavailable; cannot check local changes)"
    SKIPPED=1
    return 0
  fi
  if [ -n "$(git -C "$dir" status --porcelain)" ]; then
    echo "$dir — skipped (local changes present)"
    SKIPPED=1
    return 0
  fi
  rm -rf "$dir"
  echo "$dir — removed clone"
}

echo "=== Wiki Skill — uninstall ==="

# Git hooks (best-effort). Runs before --remove-clones deletes $SKILL_DIR
# below. A failure here is non-fatal; the rest of uninstall still proceeds.
#
# The uninstaller is invoked through the REAL clone dir
# ($SKILL_DIR/hooks/uninstall-hooks.sh), NEVER through the canonical symlink
# $SKILLS_ROOT/wiki. That symlink is attacker-influenceable: a foreign link
# (e.g. ~/.claude/skills/wiki -> /tmp/evil, with /tmp/evil/hooks/
# uninstall-hooks.sh executable) would otherwise make us run an
# attacker-controlled script (codex-атк P1). Using $SKILL_DIR also loses no
# legitimate coverage: when $SKILLS_ROOT/wiki correctly points at $SKILL_DIR,
# "$SKILLS_ROOT/wiki/hooks/uninstall-hooks.sh" IS "$SKILL_DIR/hooks/
# uninstall-hooks.sh" — the same file.
#
# The call is additionally gated on $SKILL_DIR being a VERIFIED clone
# (same `.git` check --remove-clones uses below): the path is fixed, so a
# stale, unrelated, or attacker-planted ~/claude-wiki-skill carrying an
# executable hooks/uninstall-hooks.sh must never be executed just because
# it exists (codex-кор P1, wave5). An unverified dir with a lingering hook
# marker falls into the orphaned-hooks branch below instead.
HOOK_UNINSTALLER="$SKILL_DIR/hooks/uninstall-hooks.sh"
HOOK_MARKER="/skills/wiki/hooks/"
# Old qwen wrapper-script path install-hooks.sh registers-then-migrates away
# from. It is a SECOND marker of our own entries, and hooks/
# uninstall-hooks.sh strips it for the qwen client alongside $HOOK_MARKER —
# so the orphan guard here must DETECT it too (codex-атк P1, wave3).
# Scanning only $HOOK_MARKER meant a not-yet-migrated Qwen-only install
# looked marker-free, and --remove-clones happily deleted the clone hosting
# the only script that can ever remove that stranded entry.
# Marker sets are per-client and mirror deregister_from's exactly:
#   claude → $HOOK_MARKER;  qwen → $HOOK_MARKER + $LEGACY_QWEN_MARKER.
LEGACY_QWEN_MARKER="/.qwen/hooks/wiki-session-start.sh"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
QWEN_SETTINGS="$HOME/.qwen/settings.json"
SETTINGS_FILES=("$CLAUDE_SETTINGS" "$QWEN_SETTINGS")

# Shared settings mutex (hooks/lib/settings-lock.sh) — the SAME primitive
# install-hooks.sh and hooks/uninstall-hooks.sh take, which is the only
# reason the critical section below is mutually exclusive with a concurrent
# installer. Sourced from THIS script's own directory: uninstall.sh always
# ships inside the clone, so the lib sits next to it.
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCK_LIB="$SELF_DIR/hooks/lib/settings-lock.sh"
LOCK_LIB_OK=0
if [ -f "$LOCK_LIB" ]; then
  # shellcheck source=hooks/lib/settings-lock.sh
  source "$LOCK_LIB"
  LOCK_LIB_OK=1
fi

# scan_marker: the single three-state check for $HOOK_MARKER inside a
# settings file. Also invoked by the locked recheck in a follow-up task —
# this stays the only implementation of the check.
#   0 — marker found
#   1 — file read successfully, marker absent
#   2 — could not verify (not a regular file, unreadable, or the read
#       deadline below was hit); the caller treats this exactly like "marker
#       found" (fail-closed): an unreadable settings file must never be
#       mistaken for "no orphaned hooks".
MARKER_TIMEOUT="${WIKI_UNINSTALL_MARKER_TIMEOUT:-5}"
scan_marker() {
  local f="$1" gpid wpid rc=0
  local -a pats
  # Not a regular file (FIFO, socket, directory, device, dangling symlink)
  # — never open it. A FIFO/socket here would otherwise hang grep's open()
  # forever, and this same check runs under two held locks in the
  # follow-up task, so a hang here would starve every parallel installer.
  # WIKI_UNINSTALL_TEST_SKIP_TYPE_CHECK disables ONLY this pre-check, so
  # tests can prove the read-deadline guard below fires on its own.
  if [ -z "${WIKI_UNINSTALL_TEST_SKIP_TYPE_CHECK:-}" ]; then
    [ -f "$f" ] || return 2
  fi
  # Per-client marker set, identical to what hooks/uninstall-hooks.sh would
  # strip for that client. -F (fixed strings): $LEGACY_QWEN_MARKER contains
  # regex metacharacters (`.`), so a basic-regex match would be both wider
  # than intended and misleading.
  pats=(-e "$HOOK_MARKER")
  if [ "$f" = "$QWEN_SETTINGS" ]; then
    pats+=(-e "$LEGACY_QWEN_MARKER")
  fi
  grep -Fq "${pats[@]}" "$f" >/dev/null 2>&1 &
  gpid=$!
  ( sleep "$MARKER_TIMEOUT"; kill -TERM "$gpid" 2>/dev/null || true ) &
  wpid=$!
  wait "$gpid" || rc=$?
  kill -TERM "$wpid" 2>/dev/null || true
  wait "$wpid" 2>/dev/null || true
  # grep has THREE exit statuses: 0 found, 1 not found, >=2 read error
  # (permissions, I/O failure, deadline guard killed it with rc=143).
  # Treating >=2 as "not found" would let an unreadable settings file
  # green-light deleting $SKILL_DIR while entries may still be there.
  case "$rc" in
    0) return 0 ;;
    1) return 1 ;;
    *) return 2 ;;
  esac
}

# Step 1 (OUTSIDE the locks below): run the clone's own hook uninstaller.
# It takes both settings locks itself, so calling it inside the critical
# section would be a guaranteed self-deadlock.
UNINSTALLER_RAN=0
if [ -d "$SKILL_DIR/.git" ] && [ -f "$HOOK_UNINSTALLER" ]; then
  UNINSTALLER_RAN=1
  if ! bash "$HOOK_UNINSTALLER"; then
    echo "Увага: не вдалося прибрати git hooks. Запустіть вручну: bash \"$HOOK_UNINSTALLER\""
    HOOKS_FAILED=1
  fi
fi

# Remove exports first so canonical links do not become dangling during a
# partial uninstall.
remove_symlink_entry "$AGENTS_SKILLS_ROOT/wiki" "$SKILLS_ROOT/wiki"
remove_symlink_entry "$GEMINI_SKILLS_ROOT/wiki" "$SKILLS_ROOT/wiki"
remove_symlink_entry "$QWEN_SKILLS_ROOT/wiki" "$SKILLS_ROOT/wiki"
remove_symlink_entry "$AGENTS_SKILLS_ROOT/doc-extract" "$SKILLS_ROOT/doc-extract"
remove_symlink_entry "$GEMINI_SKILLS_ROOT/doc-extract" "$SKILLS_ROOT/doc-extract"
remove_symlink_entry "$QWEN_SKILLS_ROOT/doc-extract" "$SKILLS_ROOT/doc-extract"
remove_symlink_entry "$SKILLS_ROOT/wiki" "$SKILL_DIR"
remove_symlink_entry "$SKILLS_ROOT/doc-extract" "$DOC_EXTRACT_DIR"

rmdir "$AGENTS_SKILLS_ROOT" 2>/dev/null || true
rmdir "$GEMINI_SKILLS_ROOT" 2>/dev/null || true
rmdir "$QWEN_SKILLS_ROOT" 2>/dev/null || true
rmdir "$SKILLS_ROOT" 2>/dev/null || true

# ---------------------------------------------------------------------------
# CRITICAL SECTION (t12-orphan-guard-locks / codex-атк P1, wave3)
#
# The orphan-marker recheck and the $SKILL_DIR deletion that depends on it
# must be ONE atomic decision. Previously the scan ran up top, then export
# removal and rmdir ran, then the clone was deleted — a wide TOCTOU window
# in which a concurrent install-hooks.sh could write hook entries into a
# settings file already scanned as clean, leaving them stranded the moment
# the clone (and with it the recovery script) disappeared.
#
# Both locks are held simultaneously, always in the global order
# claude → qwen — the SAME order hooks/uninstall-hooks.sh takes them in, and
# install-hooks.sh only ever holds ONE at a time, so no wait cycle can exist
# in any pair of processes. Do not "tidy" the order in one place only.
#
# Locks are taken only for clients whose parent directory already exists: a
# missing ~/.qwen means no settings file to protect, and creating the dir
# just to host a lockdir would turn every Claude-only machine into a
# permanent fail-closed.
HELD_LOCKS=()
GUARD_LOCKED=0
RERUN_FLAG=""
if [ "$REMOVE_CLONES" -eq 1 ]; then
  RERUN_FLAG=" --remove-clones"
fi
if [ "$LOCK_LIB_OK" -eq 1 ]; then
  GUARD_LOCKED=1
  for f in "${SETTINGS_FILES[@]}"; do
    if [ ! -d "$(dirname "$f")" ]; then
      continue
    fi
    if wiki_lock_acquire "$f.lockdir"; then
      HELD_LOCKS+=("$f.lockdir")
    else
      # "Could not take the lock" is never read as "nothing to protect".
      echo "Увага: не вдалося взяти лок на $f за ${WIKI_HOOKS_LOCK_TIMEOUT:-10}с — перевірити записи hooks неможливо, клон збережено. Повторіть пізніше: bash \"$SELF_DIR/uninstall.sh\"$RERUN_FLAG"
      GUARD_LOCKED=0
      HOOKS_FAILED=1
      break
    fi
  done
else
  # Script running detached from its clone (copied elsewhere): the shared
  # mutex is unavailable, so a locked recheck is impossible. Conservative
  # skip rather than an unsynchronized check.
  echo "Увага: $LOCK_LIB недоступний — перевірити записи hooks під локом неможливо, клон збережено."
  HOOKS_FAILED=1
fi

if [ "$GUARD_LOCKED" -eq 1 ]; then
  # Test-only seam (mirrors WIKI_HOOKS_TEST_SLEEP_AFTER_LOCK): hold both
  # locks open inside the section so tests can prove a concurrent installer
  # cannot write during the window. No-op by default.
  if [ "${WIKI_UNINSTALL_TEST_SLEEP_IN_GUARD:-0}" != "0" ]; then
    sleep "${WIKI_UNINSTALL_TEST_SLEEP_IN_GUARD}"
  fi

  # Recheck every settings file we know about (Claude, Qwen) for orphaned
  # hook entries — an orphan in EITHER file must block --remove-clones from
  # deleting the clone that hosts the recovery script, which would otherwise
  # strand those entries with no way to clean them up (agy-кор / codex-атк
  # P1, t11-orphan-guard-files). Same single scan_marker three-state check
  # as ever; the -f pre-check and read deadline inside it matter doubly here
  # — a grep hung on a FIFO would hold BOTH locks forever and starve every
  # parallel installer.
  MARKED_FILES=()
  UNVERIFIED_FILES=()
  for f in "${SETTINGS_FILES[@]}"; do
    # Path absent → no marker here, not an error; keep scanning the rest.
    # A broken symlink IS present (fails -e, passes -L) — that is "could
    # not verify", not "absent", so it still goes through scan_marker.
    [ -e "$f" ] || [ -L "$f" ] || continue
    rc=0
    scan_marker "$f" || rc=$?
    case "$rc" in
      0) MARKED_FILES+=("$f") ;;
      1) : ;;
      *) UNVERIFIED_FILES+=("$f") ;;
    esac
  done

  # UNVERIFIED_FILES is treated exactly like a found marker (HOOKS_FAILED=1,
  # $SKILL_DIR kept) — the split between "marker found" and "could not
  # verify" exists only in which warning text prints, never in the outcome.
  # File contents are never printed in either message.
  # "${arr[@]+"${arr[@]}"}" rather than plain "${arr[@]}": under bash 3.2
  # (macOS system /bin/bash), expanding a zero-element array with set -u
  # raises "unbound variable" even though the array was assigned via `()`.
  # The +-guarded form yields zero words for an empty array on every bash.
  for f in "${MARKED_FILES[@]+"${MARKED_FILES[@]}"}"; do
    if [ "$UNINSTALLER_RAN" -eq 1 ]; then
      echo "Увага: після запуску $HOOK_UNINSTALLER записи hooks усе ще лишились у $f. Запустіть вручну: bash \"$HOOK_UNINSTALLER\""
    else
      echo "Увага: скрипт видалення git hooks недоступний ($HOOK_UNINSTALLER), але записи hooks лишились у $f. Відновіть клон і запустіть вручну: bash \"$HOOK_UNINSTALLER\""
    fi
    HOOKS_FAILED=1
  done
  for f in "${UNVERIFIED_FILES[@]+"${UNVERIFIED_FILES[@]}"}"; do
    echo "Увага: не вдалося прочитати $f — перевірити наявність записів hooks неможливо, клон збережено."
    HOOKS_FAILED=1
  done
fi

if [ "$REMOVE_CLONES" -eq 1 ]; then
  echo ""
  echo "Real clone directories:"
  if [ "$HOOKS_FAILED" -eq 1 ]; then
    # Keep the clone dir that hosts uninstall-hooks.sh so the recovery
    # command printed above still exists to run. Removing it here would
    # delete the only remaining path that can ever clean up the orphaned
    # hook entries left in settings.json (agy-атк P1).
    echo "$SKILL_DIR — skipped (git hooks removal failed; run the command above first, then re-run --remove-clones)"
    SKIPPED=1
  else
    remove_clone_dir "$SKILL_DIR"
    if [ ! -e "$SKILL_DIR" ]; then
      # Boundary of the invariant, stated where it is enforced: the locks
      # guarantee no entry existed at deletion time. They do NOT guarantee
      # none appears afterwards — an installer that was waiting for the lock
      # gets it right after release and legitimately writes its entries.
      # That is the mutex working, not a race. Such entries are inert by
      # construction (`test -x "…" && "…" || exit 0` exits 0 silently once
      # the canonical path is gone). Widening the section to "wait them out"
      # would mean holding both locks indefinitely — forbidden.
      echo "Примітка: паралельний інсталер міг дописати записи hooks уже після видалення клону. Вони інертні; приберіть їх запуском hooks/uninstall-hooks.sh з репозиторію або переінстальованого скіла."
    fi
  fi
fi

# Release in reverse acquisition order (qwen → claude). Everything below is
# outside the critical section.
for (( _i = ${#HELD_LOCKS[@]} - 1; _i >= 0; _i-- )); do
  wiki_lock_release "${HELD_LOCKS[$_i]}"
done
# ---------------------------------------------------------------------------

if [ "$REMOVE_CLONES" -eq 1 ]; then
  remove_clone_dir "$DOC_EXTRACT_DIR"
else
  echo ""
  echo "Real clone directories kept (default):"
  echo "  $SKILL_DIR"
  echo "  $DOC_EXTRACT_DIR"
  echo "Run with --remove-clones to remove clean git clones too."
fi

echo ""
if [ "$SKIPPED" -eq 1 ]; then
  echo "Done with skipped entries. Review the lines marked skipped above."
else
  echo "Done."
fi
