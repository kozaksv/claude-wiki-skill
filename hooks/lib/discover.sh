#!/usr/bin/env bash
# hooks/lib/discover.sh
#
# Wiki discovery for hook scripts. Provides `discover_wiki <start_dir>`:
# find the nearest resident `## Wiki` pointer (CLAUDE.md / AGENTS.md /
# GEMINI.md) walking up from <start_dir> to the git-root boundary (or
# $CLAUDE_PROJECT_DIR outside a git repo — NEVER `/`), falling back to
# docs/wiki/ when no pointer resolves. Every candidate is boundary-guarded
# on its RESOLVED index.md so a malicious/broken pointer or a symlink
# escape can never leak content from outside the project root into an
# LLM context (see docs/superpowers/plans/2026-07-08-v45-hooks.md Task 1
# and references/discovery-versioning.md Step 0).
#
# Pure bash, no stdin parsing here — callers (session-start.sh,
# post-tool-use.sh) own the stdin-JSON contract per Claude Code hooks docs.

# ---- internal helpers (prefixed to avoid clashing when sourced alongside
# other hook libs, e.g. version-gate.sh, in the same shell) ----

_wiki_disc_realpath() {
  # $1 = path (may not exist). Always suppress the underlying realpath's
  # own stderr noise for missing paths (spec: "без stderr-шуму").
  realpath "$1" 2>/dev/null
}

_wiki_disc_boundary_ok() {
  # $1 = already-realpath'd absolute path
  # $2 = already-realpath'd absolute boundary root
  case "$1" in
    "$2") return 0 ;;
    "$2"/*) return 0 ;;
    *) return 1 ;;
  esac
}

_wiki_disc_find_config() {
  # $1 = directory to check. Prints the first existing agent instruction
  # file in that directory (CLAUDE.md, then AGENTS.md, then GEMINI.md).
  local dir="$1" name
  for name in CLAUDE.md AGENTS.md GEMINI.md; do
    if [ -f "$dir/$name" ]; then
      printf '%s\n' "$dir/$name"
      return 0
    fi
  done
  return 1
}

_wiki_disc_extract_pointer() {
  # $1 = config file path. Prints the first backtick-quoted token found
  # inside the file's "## Wiki" section (a line that is exactly
  # "## Wiki", up to the next "## " header or EOF). Empty if no such
  # section or no backtick token inside it.
  local file="$1"
  awk '
    /^## Wiki[[:space:]]*$/ { insec=1; next }
    insec && /^## / { insec=0 }
    insec { print }
  ' "$file" | grep -o '`[^`]*`' | head -1 | sed 's/^`//; s/`$//'
}

_wiki_disc_candidate() {
  # $1 = candidate wiki-dir (unvalidated, may be relative-looking or
  #      contain .. segments; not yet realpath'd)
  # $2 = boundary_real (already realpath'd)
  # On success prints the validated absolute wiki dir and returns 0.
  # On failure prints nothing, emits the standard stderr notice, and
  # returns 1. discovery continues (walk-up / fallback) after failure.
  local candidate="$1" boundary_real="$2"
  local idx_real
  idx_real="$(_wiki_disc_realpath "$candidate/index.md")"
  if [ -z "$idx_real" ] || ! _wiki_disc_boundary_ok "$idx_real" "$boundary_real"; then
    echo "[wiki-hook] pointer поза межами репо, ігнорую: $candidate" >&2
    return 1
  fi
  dirname "$idx_real"
  return 0
}

discover_wiki() {
  # $1 = optional start_dir. Fallback: $CLAUDE_PROJECT_DIR, then pwd.
  local start="${1:-}"
  if [ -z "$start" ]; then
    start="${CLAUDE_PROJECT_DIR:-$(pwd)}"
  fi
  [ -d "$start" ] || return 0

  # Walk-up boundary: git toplevel of start; outside a git repo, the
  # boundary is $CLAUDE_PROJECT_DIR (fallback: start itself) — never "/".
  local boundary_input git_top
  boundary_input="${CLAUDE_PROJECT_DIR:-$start}"
  git_top="$(git -C "$start" rev-parse --show-toplevel 2>/dev/null)"
  if [ -n "$git_top" ]; then
    boundary_input="$git_top"
  fi

  local boundary_real start_real
  boundary_real="$(_wiki_disc_realpath "$boundary_input")"
  start_real="$(_wiki_disc_realpath "$start")"
  [ -n "$boundary_real" ] && [ -n "$start_real" ] || return 0

  # Phase 1: walk from start_real up to boundary_real (inclusive) looking
  # for the nearest config file with a "## Wiki" pointer.
  local dir="$start_real" found_config_dir="" pointer_candidate=""
  while :; do
    local cfg
    if cfg="$(_wiki_disc_find_config "$dir")"; then
      local raw
      raw="$(_wiki_disc_extract_pointer "$cfg")"
      if [ -n "$raw" ]; then
        found_config_dir="$dir"
        case "$raw" in
          /*) pointer_candidate="$raw" ;;
          *) pointer_candidate="$dir/$raw" ;;
        esac
        break
      fi
    fi
    [ "$dir" = "$boundary_real" ] && break
    local parent
    parent="$(dirname "$dir")"
    [ "$parent" != "$dir" ] || break
    dir="$parent"
  done

  if [ -n "$pointer_candidate" ]; then
    local wiki_dir
    if wiki_dir="$(_wiki_disc_candidate "$pointer_candidate" "$boundary_real")"; then
      printf '%s\n' "$wiki_dir"
      return 0
    fi
    # broken / out-of-bounds pointer -> fall through to fallback phase
  fi

  # Phase 2: fallback docs/wiki/index.md, tried at (in order, de-duped):
  # the found config file's dir, start_real, boundary_real. Same guard.
  local seen=" " loc
  for loc in "$found_config_dir" "$start_real" "$boundary_real"; do
    [ -n "$loc" ] || continue
    case "$seen" in
      *" $loc "*) continue ;;
    esac
    seen="$seen$loc "
    local wiki_dir
    if wiki_dir="$(_wiki_disc_candidate "$loc/docs/wiki" "$boundary_real")"; then
      printf '%s\n' "$wiki_dir"
      return 0
    fi
  done

  return 0
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  discover_wiki "$@"
fi
