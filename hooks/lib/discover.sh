#!/usr/bin/env bash
# hooks/lib/discover.sh
#
# Wiki discovery for hook scripts. Provides `discover_wiki <start_dir>`:
# find the nearest resident `## Wiki` pointer walking up from <start_dir>
# to the git-root boundary, falling back to docs/wiki/ when no pointer
# resolves. In each directory ALL agent instruction files (CLAUDE.md,
# AGENTS.md, GEMINI.md) are consulted and the first pointer that actually
# VALIDATES (resolved index.md inside the boundary) wins — agent-neutral
# discovery. A stale/broken pointer never stops the search: the remaining
# files of the same directory are still tried, and the walk-up continues
# to higher directories, so a stale nested CLAUDE.md can mask neither a
# valid AGENTS.md/GEMINI.md pointer beside it nor a valid root-level one. Discovery is FAIL-CLOSED without git: with no git toplevel we
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

_wiki_disc_dir_pointers() {
  # $1 = directory. Agent-neutral pointer lookup: consult ALL instruction
  # files in priority order (CLAUDE.md, AGENTS.md, GEMINI.md) and print
  # EVERY `## Wiki` backtick pointer found, one per line, in that order.
  # A file with no pointer contributes nothing but does NOT stop the scan
  # (codex-атк P1). Printing ALL pointers (not just the first) lets the
  # caller validate each one, so a stale-but-present CLAUDE.md pointer
  # cannot mask a valid AGENTS.md/GEMINI.md pointer in the same directory
  # (agy-атк P1 follow-up). Always exits 0; empty output = no pointers.
  local dir="$1" name raw
  for name in CLAUDE.md AGENTS.md GEMINI.md; do
    [ -f "$dir/$name" ] || continue
    raw="$(_wiki_disc_extract_pointer "$dir/$name")"
    [ -n "$raw" ] && printf '%s\n' "$raw"
  done
  return 0
}

_wiki_disc_normalize_pointer() {
  # $1 = raw pointer string extracted from a "## Wiki" section. The
  # documented OLD one-line pointer format points directly AT the wiki's
  # schema or index file (e.g. `knowledge/wiki/schema.md`), not at its
  # containing directory. Downstream code (_wiki_disc_candidate) always
  # appends "/index.md" to build the file it validates, so a pointer that
  # already ends in schema.md/index.md must first be stripped down to its
  # containing dir — otherwise the appended index.md lands under
  # .../schema.md/index.md (schema.md treated as a directory) and the
  # pointer never resolves, silently masking a valid non-default/custom
  # wiki (fixwave0-4). Only the TRAILING filename is stripped so a
  # directory that merely contains "schema.md"/"index.md" as a path
  # segment elsewhere is left untouched.
  local p="$1"
  case "$p" in
    */schema.md) printf '%s' "${p%/schema.md}" ;;
    */index.md) printf '%s' "${p%/index.md}" ;;
    schema.md | index.md) printf '%s' "." ;;
    *) printf '%s' "$p" ;;
  esac
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

  # Phase 1: walk from start_real up to boundary_real (inclusive). In each
  # directory validate EVERY pointer found there immediately; the first
  # pointer whose resolved index.md passes the boundary guard wins. A
  # stale/broken/out-of-bounds pointer never stops the search — remaining
  # pointers in the same directory are tried, then the walk continues
  # upward (agy-атк P1: a stale nested pointer must not mask a valid
  # root-level custom-path pointer). found_config_dir remembers the
  # NEAREST directory that carried any pointer at all — Phase 2 uses it
  # as the first fallback anchor regardless of pointer validity.
  local dir="$start_real" found_config_dir="" wiki_dir="" raws raw candidate
  while :; do
    raws="$(_wiki_disc_dir_pointers "$dir")"
    if [ -n "$raws" ]; then
      [ -n "$found_config_dir" ] || found_config_dir="$dir"
      while IFS= read -r raw; do
        [ -n "$raw" ] || continue
        raw="$(_wiki_disc_normalize_pointer "$raw")"
        case "$raw" in
          /*) candidate="$raw" ;;
          *) candidate="$dir/$raw" ;;
        esac
        if wiki_dir="$(_wiki_disc_candidate "$candidate" "$boundary_real")"; then
          printf '%s\n' "$wiki_dir"
          return 0
        fi
        # broken / out-of-bounds pointer -> try the next one / keep walking
      done <<<"$raws"
    fi
    [ "$dir" = "$boundary_real" ] && break
    local parent
    parent="$(dirname "$dir")"
    [ "$parent" != "$dir" ] || break
    dir="$parent"
  done

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
