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
SETTINGS_FILES=("$HOME/.claude/settings.json" "$HOME/.qwen/settings.json")

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
  # Not a regular file (FIFO, socket, directory, device, dangling symlink)
  # — never open it. A FIFO/socket here would otherwise hang grep's open()
  # forever, and this same check runs under two held locks in the
  # follow-up task, so a hang here would starve every parallel installer.
  # WIKI_UNINSTALL_TEST_SKIP_TYPE_CHECK disables ONLY this pre-check, so
  # tests can prove the read-deadline guard below fires on its own.
  if [ -z "${WIKI_UNINSTALL_TEST_SKIP_TYPE_CHECK:-}" ]; then
    [ -f "$f" ] || return 2
  fi
  grep -q "$HOOK_MARKER" "$f" >/dev/null 2>&1 &
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

if [ -d "$SKILL_DIR/.git" ] && [ -f "$HOOK_UNINSTALLER" ]; then
  if ! bash "$HOOK_UNINSTALLER"; then
    echo "Увага: не вдалося прибрати git hooks. Запустіть вручну: bash \"$HOOK_UNINSTALLER\""
    HOOKS_FAILED=1
  fi
elif
  # No usable uninstaller (clone script missing/broken/not executable, or the
  # canonical symlink is dangling/foreign). Check every settings file we
  # know about (Claude, Qwen) for orphaned hook entries — an orphan in
  # EITHER file must block --remove-clones from deleting the clone that
  # hosts the recovery script, which would otherwise strand those entries
  # with no way to clean them up (agy-кор / codex-атк P1, extended in
  # t11-orphan-guard-files to cover ~/.qwen/settings.json too).
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
  [ "${#MARKED_FILES[@]}" -gt 0 ] || [ "${#UNVERIFIED_FILES[@]}" -gt 0 ]
then
  # UNVERIFIED_FILES is treated exactly like a found marker (HOOKS_FAILED=1,
  # $SKILL_DIR kept) — the split between "marker found" and "could not
  # verify" exists only in which warning text prints, never in the outcome.
  # File contents are never printed in either message.
  # "${arr[@]+"${arr[@]}"}" rather than plain "${arr[@]}": under bash 3.2
  # (macOS system /bin/bash), expanding a zero-element array with set -u
  # raises "unbound variable" even though the array was assigned via `()`.
  # The +-guarded form yields zero words for an empty array on every bash.
  for f in "${MARKED_FILES[@]+"${MARKED_FILES[@]}"}"; do
    echo "Увага: скрипт видалення git hooks недоступний ($HOOK_UNINSTALLER), але записи hooks лишились у $f. Відновіть клон і запустіть вручну: bash \"$HOOK_UNINSTALLER\""
  done
  for f in "${UNVERIFIED_FILES[@]+"${UNVERIFIED_FILES[@]}"}"; do
    echo "Увага: не вдалося прочитати $f — перевірити наявність записів hooks неможливо, клон збережено."
  done
  HOOKS_FAILED=1
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
  fi
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
