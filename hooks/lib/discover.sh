#!/usr/bin/env bash
# hooks/lib/discover.sh
#
# Wiki discovery for hook scripts. Provides `discover_wiki <start_dir>`:
# find the nearest resident `## Wiki` pointer walking up from <start_dir>
# to the git-root boundary, falling back to docs/wiki/ when no pointer
# resolves. In each directory ALL agent instruction files (CLAUDE.md,
# AGENTS.md, GEMINI.md) are consulted and the FIRST that carries a valid
# `## Wiki` pointer wins — agent-neutral discovery, so a stale/broken
# CLAUDE.md can never mask a valid AGENTS.md/GEMINI.md pointer in the same
# directory. Discovery is FAIL-CLOSED without git: with no git toplevel we
# refuse to establish a boundary and resolve nothing (Session-Start
# Contract requires a git marker; an orphan / non-git tree must not resolve
# or mutate a wiki). Every candidate is boundary-guarded on its RESOLVED
# index.md so a malicious/broken pointer or a symlink escape can never leak
# content from outside the project root into an LLM context (see
# docs/superpowers/plans/2026-07-08-v45-hooks.md Task 1 and
# references/discovery-versioning.md Step 0).
#
# set -euo pipefail safety: this lib is sourced by hook scripts that may
# run under `set -euo pipefail`. Every internal command-substitution here
# is written so it NEVER propagates a non-zero status into the caller's
# assignment (which set -e would treat as fatal): realpath/git/awk-pipe
# failures are swallowed to empty output + exit 0, and callers branch on
# emptiness instead of exit status.
#
# Pure bash, no stdin parsing here — callers (session-start.sh,
# post-tool-use.sh) own the stdin-JSON contract per Claude Code hooks docs.

# ---- internal helpers (prefixed to avoid clashing when sourced alongside
# other hook libs, e.g. version-gate.sh, in the same shell) ----

_wiki_disc_realpath() {
  # $1 = path (may not exist). Always suppress the underlying realpath's
  # own stderr noise for missing paths (spec: "без stderr-шуму"). The
  # trailing `|| true` keeps this at exit 0 for a missing path so a
  # `x="$(_wiki_disc_realpath ...)"` assignment can never trip a set -e
  # caller; callers already branch on empty output.
  realpath "$1" 2>/dev/null || true
}

_wiki_disc_boundary_ok() {
  # $1 = already-realpath'd absolute path (in practice always a resolved
  #      index.md FILE, never the boundary dir itself)
  # $2 = already-realpath'd absolute boundary root
  # Must be STRICTLY inside $2, never equal to it. An exact match means
  # index.md resolved (e.g. via a symlink) to the boundary root itself;
  # the caller then does `dirname` on that, which yields the boundary's
  # PARENT — an escape outside the project. See
  # references/discovery-versioning.md Step 0 symlink-escape note.
  case "$1" in
    "$2"/*) return 0 ;;
    *) return 1 ;;
  esac
}

_wiki_disc_extract_pointer() {
  # $1 = config file path. Prints the first backtick-quoted token found
  # inside the file's "## Wiki" section (a line that is exactly
  # "## Wiki", up to the next "## " header or EOF). Empty if no such
  # section or no backtick token inside it.
  #
  # The awk|grep|head|sed pipe returns non-zero when the "## Wiki" section
  # exists but has NO backtick token (grep -o matches nothing -> exit 1;
  # head closing the pipe early can also SIGPIPE grep). Capturing into a
  # local with a trailing `|| true` swallows that so this function always
  # exits 0 — otherwise a `raw="$(_wiki_disc_extract_pointer ...)"`
  # assignment would abort a set -e caller on the perfectly-normal
  # "section present, no pointer" case (codex-атк P1).
  local file="$1" out
  out="$(
    awk '
      /^## Wiki[[:space:]]*$/ { insec=1; next }
      insec && /^## / { insec=0 }
      insec { print }
    ' "$file" | grep -o '`[^`]*`' | head -1 | sed 's/^`//; s/`$//'
  )" || true
  printf '%s' "$out"
}

_wiki_disc_dir_pointer() {
  # $1 = directory. Agent-neutral pointer lookup: consult ALL instruction
  # files in priority order (CLAUDE.md, AGENTS.md, GEMINI.md) and print the
  # first VALID `## Wiki` backtick pointer found in ANY of them. A file that
  # exists but has no pointer (stale / broken / no "## Wiki" section) does
  # NOT stop the search — the next file in the same dir is still tried
  # (codex-атк P1: previously only the first existing file was read, so a
  # stale CLAUDE.md masked a valid AGENTS.md/GEMINI.md pointer). Empty
  # output + return 1 when no file in the dir yields a pointer.
  local dir="$1" name raw
  for name in CLAUDE.md AGENTS.md GEMINI.md; do
    [ -f "$dir/$name" ] || continue
    raw="$(_wiki_disc_extract_pointer "$dir/$name")"
    if [ -n "$raw" ]; then
      printf '%s\n' "$raw"
      return 0
    fi
  done
  return 1
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

  # Walk-up boundary: the git toplevel of start. FAIL-CLOSED — with no git
  # toplevel we resolve nothing at all. Wiki discovery is git-backed (the
  # Session-Start Contract requires a git marker); legalizing a boundary at
  # $CLAUDE_PROJECT_DIR for an orphan / non-git tree would let hook writes
  # create or mutate a wiki (.usage.json) in a state Step 0 must block
  # (codex-атк P1). The `|| true` keeps the failing rev-parse from aborting
  # a set -e caller before we can fail-closed on empty output.
  local git_top
  git_top="$(git -C "$start" rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$git_top" ] || return 0

  local boundary_real start_real
  boundary_real="$(_wiki_disc_realpath "$git_top")"
  start_real="$(_wiki_disc_realpath "$start")"
  [ -n "$boundary_real" ] && [ -n "$start_real" ] || return 0

  # Phase 1: walk from start_real up to boundary_real (inclusive) looking
  # for the nearest config file with a "## Wiki" pointer.
  local dir="$start_real" found_config_dir="" pointer_candidate=""
  while :; do
    local raw
    if raw="$(_wiki_disc_dir_pointer "$dir")" && [ -n "$raw" ]; then
      found_config_dir="$dir"
      case "$raw" in
        /*) pointer_candidate="$raw" ;;
        *) pointer_candidate="$dir/$raw" ;;
      esac
      break
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
