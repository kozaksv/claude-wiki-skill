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
~/.claude, ~/.agents, and ~/.gemini directories in place.

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
SETTINGS_JSON="$HOME/.claude/settings.json"
if [ -d "$SKILL_DIR/.git" ] && [ -f "$HOOK_UNINSTALLER" ]; then
  if ! bash "$HOOK_UNINSTALLER"; then
    echo "Увага: не вдалося прибрати git hooks. Запустіть вручну: bash \"$HOOK_UNINSTALLER\""
    HOOKS_FAILED=1
  fi
elif [ -f "$SETTINGS_JSON" ] && grep -q "$HOOK_MARKER" "$SETTINGS_JSON" 2>/dev/null; then
  # No usable uninstaller (clone script missing/broken/not executable, or the
  # canonical symlink is dangling/foreign), yet settings.json still carries
  # our hook marker — the global hooks are orphaned. Flag HOOKS_FAILED so
  # --remove-clones does NOT delete the clone that hosts the recovery script,
  # which would strand those entries with no way to clean them up (agy-кор /
  # codex-атк P1: the "symlink absent / script missing" case, not just the
  # "script exits non-zero" case).
  echo "Увага: скрипт видалення git hooks недоступний ($HOOK_UNINSTALLER), але записи hooks лишились у $SETTINGS_JSON. Відновіть клон і запустіть вручну: bash \"$HOOK_UNINSTALLER\""
  HOOKS_FAILED=1
fi

# Remove exports first so canonical links do not become dangling during a
# partial uninstall.
remove_symlink_entry "$AGENTS_SKILLS_ROOT/wiki" "$SKILLS_ROOT/wiki"
remove_symlink_entry "$GEMINI_SKILLS_ROOT/wiki" "$SKILLS_ROOT/wiki"
remove_symlink_entry "$AGENTS_SKILLS_ROOT/doc-extract" "$SKILLS_ROOT/doc-extract"
remove_symlink_entry "$GEMINI_SKILLS_ROOT/doc-extract" "$SKILLS_ROOT/doc-extract"
remove_symlink_entry "$SKILLS_ROOT/wiki" "$SKILL_DIR"
remove_symlink_entry "$SKILLS_ROOT/doc-extract" "$DOC_EXTRACT_DIR"

rmdir "$AGENTS_SKILLS_ROOT" 2>/dev/null || true
rmdir "$GEMINI_SKILLS_ROOT" 2>/dev/null || true
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
