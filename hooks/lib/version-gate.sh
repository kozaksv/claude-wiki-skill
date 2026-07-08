#!/usr/bin/env bash
# hooks/lib/version-gate.sh
#
# Gates hook writes to {wiki} on schema version + sidecar presence.
# `wiki_version` is parsed ONLY from the FIRST YAML frontmatter block of
# {wiki}/schema.md — never a substring match against the whole file — so a
# legacy/corrupt schema.md that merely *mentions* `wiki_version: "4.0"` in
# prose, an example, or a migration-log entry below the frontmatter can
# never pass the gate (docs/superpowers/plans/2026-07-08-v45-hooks.md
# Task 1; mirrors references/discovery-versioning.md's version-compare
# section).

# Single source of truth for the current on-disk schema version. Bump
# here only.
WIKI_HOOK_CURRENT_SCHEMA_VERSION="4.0"

_wiki_ver_frontmatter() {
  # $1 = file. Prints the body of the FIRST YAML frontmatter block (the
  # lines strictly between the first "---" line and the next "---"
  # line). Fails (empty output, non-zero exit) if line 1 isn't "---" or
  # no closing "---" is ever found.
  # CRLF-safe: every line is stripped of a trailing \r BEFORE any
  # comparison/print, so a CRLF-checked-out schema.md (agy-атк P1) still
  # matches the "---" delimiters and the caller's anchored version grep —
  # otherwise the gate would silently fail-closed and block all hook
  # writes on such repos.
  local file="$1"
  awk '
    { sub(/\r$/, "") }
    NR == 1 {
      if ($0 != "---") { exit 1 }
      next
    }
    $0 == "---" { closed = 1; exit }
    { print }
    END { if (!closed) exit 1 }
  ' "$file"
}

_wiki_ver_schema_ok() {
  # $1 = wiki dir. 0 iff {wiki}/schema.md's frontmatter contains an
  # anchored `wiki_version: "<current>"` line.
  local wiki_dir="$1"
  local schema="$wiki_dir/schema.md"
  [ -f "$schema" ] || return 1

  local fm
  fm="$(_wiki_ver_frontmatter "$schema")" || return 1
  [ -n "$fm" ] || return 1

  local ver_re
  ver_re="$(printf '%s' "$WIKI_HOOK_CURRENT_SCHEMA_VERSION" | sed 's/\./\\./g')"
  printf '%s\n' "$fm" | grep -qE '^wiki_version:[[:space:]]*"'"$ver_re"'"[[:space:]]*$'
}

wiki_writable() {
  # $1 = wiki dir. exit 0 only if frontmatter version is current AND
  # .usage.json already exists (so the sidecar is only ever mutated, not
  # silently created out of a version-gate write path).
  local wiki_dir="$1"
  _wiki_ver_schema_ok "$wiki_dir" || return 1
  [ -f "$wiki_dir/.usage.json" ] || return 1
  return 0
}

wiki_bootstrappable() {
  # $1 = wiki dir. true when the schema version is current but
  # .usage.json does not exist yet (fresh-current wiki, sidecar may be
  # created from scratch).
  local wiki_dir="$1"
  _wiki_ver_schema_ok "$wiki_dir" || return 1
  [ ! -f "$wiki_dir/.usage.json" ] || return 1
  return 0
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  cmd="${1:-}"
  shift || true
  case "$cmd" in
    wiki_writable|wiki_bootstrappable) "$cmd" "$@" ;;
    *) echo "usage: version-gate.sh {wiki_writable|wiki_bootstrappable} <wiki_dir>" >&2; exit 2 ;;
  esac
fi
