#!/usr/bin/env bash
# Canonical registry. Records: id, relative user skill root, entrypoint kind.
# Runtime loading is NOT inferred from these filesystem registrations.
# agy CLI 1.2.16 loads global skills from ~/.gemini/config/skills (runtime probe,
# PR #15); ~/.gemini/antigravity-cli/skills was not scanned despite web docs.
wiki_harness_records() {
  printf '%s\n' \
    'claude|.claude/skills|canonical' \
    'codex|.agents/skills|export' \
    'agy|.gemini/config/skills|export' \
    'qwen|.qwen/skills|export'
}

wiki_export_parent_safe() {
  # Do not follow a project/user-controlled parent link into another tree.
  # HOME itself may be the user's normal symlinked home; descendants may not.
  local probe
  case "$1" in "$HOME"/*) ;; *) return 1 ;; esac
  probe="$(dirname "$1")"
  while [ "$probe" != "$HOME" ]; do
    [ ! -L "$probe" ] || return 1
    if [ -e "$probe" ] && [ ! -d "$probe" ]; then return 1; fi
    [ "$probe" != / ] || return 1
    probe="$(dirname "$probe")"
  done
  return 0
}

wiki_ensure_export() {
  local skill="$1" source="$2" link="$3" current
  if ! wiki_export_parent_safe "$link"; then
    echo "[$skill] export пропущено (unsafe parent): $link"; return 2
  fi
  if [ ! -f "$source/SKILL.md" ]; then
    echo "[$skill] canonical SKILL.md unavailable: $source"; return 2
  fi
  if [ -L "$link" ]; then
    current="$(readlink "$link")"
    if [ "$current" = "$source" ] && [ -f "$link/SKILL.md" ]; then
      echo "[$skill] export already present: $link → $source"; return 0
    fi
    # A dangling link pointing elsewhere is still not ours.
    echo "[$skill] export пропущено (conflict, preserved): $link → $current"; return 2
  fi
  if [ -e "$link" ]; then
    echo "[$skill] export пропущено (not a symlink, preserved): $link"; return 2
  fi
  if ! mkdir -p "$(dirname "$link")" || ! wiki_export_parent_safe "$link"; then
    echo "[$skill] export пропущено (directory unavailable): $link"; return 2
  fi
  # No -f: a concurrent creator is a conflict, never permission to overwrite.
  if ln -s "$source" "$link" && [ "$(readlink "$link")" = "$source" ] && [ -f "$link/SKILL.md" ]; then
    echo "[$skill] export: $link → $source"; return 0
  fi
  echo "[$skill] export incomplete: $link"; return 2
}

wiki_retire_gemini_export() {
  local skill="$1" source="$HOME/.claude/skills/$1"
  local old="$HOME/.gemini/skills/$1" replacement="$HOME/.gemini/config/skills/$1"
  [ -e "$old" ] || [ -L "$old" ] || return 0
  if ! wiki_export_parent_safe "$old" || [ ! -L "$old" ] || [ "$(readlink "$old")" != "$source" ]; then
    echo "[$skill] retired export conflict (preserved): $old"; return 2
  fi
  if ! wiki_export_parent_safe "$replacement" || [ ! -L "$replacement" ] ||
     [ "$(readlink "$replacement")" != "$source" ] || [ ! -f "$replacement/SKILL.md" ]; then
    echo "[$skill] retired export present; agy export missing/unverified: $old"; return 2
  fi
  # Exact ownership and replacement verified again immediately before unlink.
  if wiki_export_parent_safe "$old" && [ -L "$old" ] && [ "$(readlink "$old")" = "$source" ]; then
    if rm -- "$old"; then echo "[$skill] removed owned retired Gemini export: $old"; return 0; fi
  fi
  echo "[$skill] retired export cleanup incomplete: $old"; return 2
}

wiki_reconcile_exports() {
  local skill id relative kind source rc=0 export_rc
  [ -L "$HOME/.claude/skills/wiki" ] && [ -f "$HOME/.claude/skills/wiki/SKILL.md" ] || {
    echo 'wiki: canonical entrypoint must be a valid symlink containing SKILL.md' >&2
    return 1
  }
  for skill in wiki doc-extract; do
    source="$HOME/.claude/skills/$skill"
    if [ -f "$source/SKILL.md" ]; then
      while IFS='|' read -r id relative kind; do
        [ "$kind" = export ] || continue
        wiki_ensure_export "$skill" "$source" "$HOME/$relative/$skill" || rc=2
      done < <(wiki_harness_records)
    else
      echo "[$skill] optional canonical absent; no new exports created"
    fi
    # Retirement is pairwise, and can only run after agy's replacement exists.
    wiki_retire_gemini_export "$skill" || rc=2
  done
  return "$rc"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    --list) wiki_harness_records ;;
    --repair) wiki_reconcile_exports ;;
    *) echo 'usage: harnesses.sh --list | --repair' >&2; exit 2 ;;
  esac
fi
