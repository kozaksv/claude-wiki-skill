#!/usr/bin/env bash
# One local pointer parser for hooks and the read-only instruction audit.
# AGENTS first *within* the nearest valid level; legacy remains readable.
# Default interface: path on stdout, or empty on absent/error. Conflict returns
# 3 with no path: callers must not write telemetry to an ambiguous wiki.
# --records is a NUL-delimited internal transport for scripts/instructions.py.

_wiki_disc_realpath() { realpath "$1" 2>/dev/null || true; }
_wiki_disc_boundary_ok() { case "$1" in "$2"/*) return 0 ;; *) return 1 ;; esac; }

_wiki_disc_extract_pointer() {
  local out
  out="$(awk '
    { sub(/\r$/, "") }
    {
      line=$0; sub(/^ ? ? ?/, "", line)
      if (line ~ /^(```|~~~)/) {
        c=substr(line,1,1); n=0
        while (substr(line,n+1,1)==c) n++
        rest=substr(line,n+1)
        if (!fence) { fence=c; fence_len=n }
        else if (fence==c && n>=fence_len && rest ~ /^[[:space:]]*$/) fence=""
        next
      }
      if (fence) next
      if (line ~ /^##[[:space:]]+([Ww][Ii][Kk][Ii]|(В|в)(І|і)(К|к)(І|і))([[:space:][:punct:]]|$)/) {
        insec=1; next
      }
      if (line ~ /^##?[[:space:]]/) insec=0
      if (insec && match(line, /`[^`]+`/)) {
        print substr(line,RSTART+1,RLENGTH-2); exit
      }
    }
  ' "$1")" || true
  printf '%s' "$out"
}

_wiki_disc_normalize_pointer() {
  case "$1" in
    */schema.md) printf '%s' "${1%/schema.md}" ;;
    */index.md) printf '%s' "${1%/index.md}" ;;
    schema.md|index.md) printf '.' ;;
    *) printf '%s' "$1" ;;
  esac
}

_wiki_disc_exact_file() {
  # A direct -f test is case-insensitive on common macOS filesystems.
  local entry
  for entry in "$1"/*; do
    [ "${entry##*/}" = "$2" ] && [ -f "$entry" ] && return 0
  done
  return 1
}

_wiki_disc_candidate() {
  # Sets result/reason in this shell; never opens index.md or an external wiki.
  local candidate="$1" boundary="$2" index_real dir_real
  WIKI_DISC_CANDIDATE=""; WIKI_DISC_REASON="missing"
  dir_real="$(_wiki_disc_realpath "$candidate")"
  if [ -n "$dir_real" ] && [ "$dir_real" != "$boundary" ] && ! _wiki_disc_boundary_ok "$dir_real" "$boundary"; then
    WIKI_DISC_REASON=outside_boundary; return 0
  fi
  index_real="$(_wiki_disc_realpath "$candidate/index.md")"
  if [ -n "$index_real" ] && ! _wiki_disc_boundary_ok "$index_real" "$boundary"; then
    WIKI_DISC_REASON=symlink_escape; return 0
  fi
  if [ -d "$candidate" ]; then WIKI_DISC_REASON=no_index; fi
  [ -n "$index_real" ] && [ -f "$candidate/index.md" ] || return 0
  WIKI_DISC_CANDIDATE="$(dirname "$index_real")"
  WIKI_DISC_REASON=valid
}

_wiki_disc_record() {
  # source, raw pointer, resolved wiki (or empty), reason. NUL framing is
  # applied at the transport boundary, never eval'ed or split on whitespace.
  WIKI_DISC_RECORDS+=("$1" "$2" "$3" "$4")
  case "$4" in
    outside_boundary|symlink_escape)
      printf '[wiki-hook] pointer поза межами репо, ігнорую: %s\n' "${1:-$2}" >&2 ;;
  esac
}

_wiki_disc_run() {
  local start="${1:-}" all_levels="${2:-0}" git_top dir parent name raw file_real candidate
  local level_first level_conflict seen loc old duplicate
  WIKI_DISC_ROOT=""; WIKI_DISC_SELECTED=""; WIKI_DISC_LEVEL=""
  WIKI_DISC_CONFLICT=0; WIKI_DISC_NEAREST_POINTER=""; WIKI_DISC_RECORDS=()
  if [ -z "$start" ]; then
    if [ "${WIKI_HOOK_CLIENT:-}" = qwen ]; then
      start="${QWEN_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-}}"
    else
      start="${CLAUDE_PROJECT_DIR:-${QWEN_PROJECT_DIR:-}}"
    fi
    [ -n "$start" ] || start="$(pwd)"
  fi
  [ -d "$start" ] || return 0
  git_top="$(git -C "$start" rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$git_top" ] || return 0
  WIKI_DISC_ROOT="$(_wiki_disc_realpath "$git_top")"
  start="$(_wiki_disc_realpath "$start")"
  [ -n "$start" ] && [ -n "$WIKI_DISC_ROOT" ] || return 0
  if [ "$start" != "$WIKI_DISC_ROOT" ] && ! _wiki_disc_boundary_ok "$start" "$WIKI_DISC_ROOT"; then return 0; fi
  dir="$start"
  while :; do
    level_first=""; level_conflict=0
    for name in AGENTS.md CLAUDE.md GEMINI.md QWEN.md; do
      _wiki_disc_exact_file "$dir" "$name" || continue
      file_real="$(_wiki_disc_realpath "$dir/$name")"
      if ! _wiki_disc_boundary_ok "$file_real" "$WIKI_DISC_ROOT"; then
        _wiki_disc_record "$dir/$name" "" "" symlink_escape
        continue
      fi
      raw="$(_wiki_disc_extract_pointer "$dir/$name")"
      [ -n "$raw" ] || continue
      [ -n "$WIKI_DISC_NEAREST_POINTER" ] || WIKI_DISC_NEAREST_POINTER="$dir"
      candidate="$(_wiki_disc_normalize_pointer "$raw")"
      case "$candidate" in
        *$'\n'*|*$'\r'*|*://*) _wiki_disc_record "$dir/$name" "$raw" "" invalid_pointer; continue ;;
        /*) : ;;
        *) candidate="$dir/$candidate" ;;
      esac
      _wiki_disc_candidate "$candidate" "$WIKI_DISC_ROOT"
      _wiki_disc_record "$dir/$name" "$raw" "$WIKI_DISC_CANDIDATE" "$WIKI_DISC_REASON"
      if [ -n "$WIKI_DISC_CANDIDATE" ]; then
        if [ -z "$level_first" ]; then level_first="$WIKI_DISC_CANDIDATE"
        elif [ "$level_first" != "$WIKI_DISC_CANDIDATE" ]; then level_conflict=1
        fi
      fi
    done
    if [ -n "$level_first" ] && [ -z "$WIKI_DISC_SELECTED" ]; then
      WIKI_DISC_SELECTED="$level_first"; WIKI_DISC_LEVEL="$dir"; WIKI_DISC_CONFLICT="$level_conflict"
      [ "$all_levels" = 1 ] || return 0
    fi
    [ "$dir" != "$WIKI_DISC_ROOT" ] || break
    parent="$(dirname "$dir")"; [ "$parent" != "$dir" ] || break
    dir="$parent"
  done
  [ -z "$WIKI_DISC_SELECTED" ] || return 0
  local -a tried=()
  for loc in "$WIKI_DISC_NEAREST_POINTER" "$start" "$WIKI_DISC_ROOT"; do
    [ -n "$loc" ] || continue
    duplicate=0
    for old in ${tried[@]+"${tried[@]}"}; do [ "$loc" != "$old" ] || duplicate=1; done
    [ "$duplicate" = 0 ] || continue
    tried+=("$loc")
    _wiki_disc_candidate "$loc/docs/wiki" "$WIKI_DISC_ROOT"
    _wiki_disc_record "" "$loc/docs/wiki" "$WIKI_DISC_CANDIDATE" "$WIKI_DISC_REASON"
    if [ -n "$WIKI_DISC_CANDIDATE" ]; then
      WIKI_DISC_SELECTED="$WIKI_DISC_CANDIDATE"; WIKI_DISC_LEVEL="$loc"
      return 0
    fi
  done
  return 0
}

discover_wiki() {
  _wiki_disc_run "${1:-}" 0
  if [ "$WIKI_DISC_CONFLICT" = 1 ]; then
    printf '%s\n' 'wiki: same-level pointer conflict; no telemetry writes' >&2
    return 3
  fi
  [ -z "$WIKI_DISC_SELECTED" ] || printf '%s\n' "$WIKI_DISC_SELECTED"
  return 0
}

wiki_discovery_records() {
  _wiki_disc_run "${1:-}" 1
  printf '%s\0' "$WIKI_DISC_ROOT" "$WIKI_DISC_SELECTED" "$WIKI_DISC_LEVEL" "$WIKI_DISC_CONFLICT"
  if [ "${#WIKI_DISC_RECORDS[@]}" -gt 0 ]; then printf '%s\0' "${WIKI_DISC_RECORDS[@]}"; fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  if [ "${1:-}" = --records ]; then shift; wiki_discovery_records "${1:-}"
  else discover_wiki "${1:-}"
  fi
fi
