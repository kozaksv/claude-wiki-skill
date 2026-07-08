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

# The gate accepts ANY schema MAJOR matching this value (e.g. "4.0",
# "4.1", "4.5" all pass when this is "4") — the v4.5 skill's versioning
# contract treats any 4.x wiki as current, not just the literal "4.0"
# that shipped first (fixwave0-3). Derived from
# WIKI_HOOK_CURRENT_SCHEMA_VERSION's leading integer so there is still a
# single place to bump on a genuine major bump (e.g. to "5.0").
WIKI_HOOK_CURRENT_SCHEMA_MAJOR="${WIKI_HOOK_CURRENT_SCHEMA_VERSION%%.*}"

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
  # anchored `wiki_version: "<N>"` or `wiki_version: "<N>.<...>"` line
  # whose leading integer (the MAJOR component, before the first dot)
  # equals WIKI_HOOK_CURRENT_SCHEMA_MAJOR. Compared by MAJOR only, NOT an
  # exact-string match against WIKI_HOOK_CURRENT_SCHEMA_VERSION — a valid
  # v4 wiki with `wiki_version: "4.1"` (or "4", "4.5", ...) must gate
  # open exactly like "4.0" does, since the v4.5 skill's versioning
  # contract treats any 4.x schema as current (fixwave0-3). A bare
  # numeric prefix with no dot ("4") is also accepted; a value whose
  # leading integer merely starts with the major digit but is a longer
  # number (e.g. "40") is rejected because %%.*  strips only up to the
  # first dot, leaving "40" != "4".
  local wiki_dir="$1"
  local schema="$wiki_dir/schema.md"
  [ -f "$schema" ] || return 1

  local fm
  fm="$(_wiki_ver_frontmatter "$schema")" || return 1
  [ -n "$fm" ] || return 1

  local ver_line ver_value major
  ver_line="$(printf '%s\n' "$fm" | grep -E '^wiki_version:[[:space:]]*"[0-9]+(\.[0-9]+)*"[[:space:]]*$' | head -n1)"
  [ -n "$ver_line" ] || return 1

  ver_value="$(printf '%s\n' "$ver_line" | sed -E 's/^wiki_version:[[:space:]]*"([0-9]+(\.[0-9]+)*)".*/\1/')"
  major="${ver_value%%.*}"

  [ "$major" = "$WIKI_HOOK_CURRENT_SCHEMA_MAJOR" ]
}

wiki_writable() {
  # $1 = wiki dir. exit 0 only if frontmatter version is current AND
  # .usage.json already exists as a REGULAR, NON-SYMLINK file (so the
  # sidecar is only ever mutated, not silently created out of a
  # version-gate write path).
  #
  # The regular-non-symlink requirement is a security invariant shared
  # with hooks/post-tool-use.sh's python read/write path (codex-атк P1):
  # a malicious repo that plants docs/wiki/.usage.json as a SYMLINK (to a
  # valid JSON file elsewhere) or a FIFO / char-device (e.g. /dev/zero)
  # must never be treated as writable — following such a link would
  # exfiltrate outside JSON into the repo sidecar on the next atomic
  # rename, and open()ing a FIFO/char-device would block the hook,
  # violating the "never blocks" invariant. `-L` is checked BEFORE `-f`
  # because `-f` follows symlinks (a symlink-to-regular-file passes `-f`).
  local wiki_dir="$1"
  local usage="$wiki_dir/.usage.json"
  _wiki_ver_schema_ok "$wiki_dir" || return 1
  [ ! -L "$usage" ] || return 1
  [ -f "$usage" ] || return 1
  return 0
}

wiki_bootstrappable() {
  # $1 = wiki dir. true when the schema version is current AND nothing at
  # all sits at the .usage.json path yet — no regular file, no symlink
  # (dangling or not), no FIFO/char-device/directory (fresh-current wiki,
  # sidecar may be created from scratch).
  #
  # "Bootstrappable" means `! -e` AND `! -L`, NOT merely `! -f`
  # (codex-атк P1). A bare `! -f` test is true for a symlink to a
  # char-device, a FIFO, or a dangling symlink — all of which the old
  # code would have declared bootstrappable, letting post-tool-use.sh
  # open() a blocking/exfiltrating sidecar. `! -L` additionally rejects a
  # dangling symlink, for which `-e` is false but `-L` is true.
  local wiki_dir="$1"
  local usage="$wiki_dir/.usage.json"
  _wiki_ver_schema_ok "$wiki_dir" || return 1
  [ ! -e "$usage" ] || return 1
  [ ! -L "$usage" ] || return 1
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
