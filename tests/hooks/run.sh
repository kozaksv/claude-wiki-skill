#!/usr/bin/env bash
# tests/hooks/run.sh
#
# Executable test harness for hooks/lib/*.sh. Not wired into
# tests/skill-contracts.sh yet (that happens in Task 8) — run directly:
#   bash tests/hooks/run.sh
#
# Stdin-JSON shape used by later hook-script test blocks (Tasks 2-3) must
# mirror the official Claude Code hooks docs exactly (hook_event_name,
# session_id, cwd, tool_name, tool_input.file_path; SessionStart's
# `source` in startup|resume|clear|compact) — see plan "Спільні
# інваріанти" note and skill plugin-dev:hook-development. This file has
# no stdin-shaped fixtures yet since Task 1 only covers discover.sh /
# version-gate.sh, neither of which parses stdin.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DISCOVER_LIB="$ROOT/hooks/lib/discover.sh"
VERSION_GATE_LIB="$ROOT/hooks/lib/version-gate.sh"

# shellcheck source=../../hooks/lib/discover.sh
source "$DISCOVER_LIB"
# shellcheck source=../../hooks/lib/version-gate.sh
source "$VERSION_GATE_LIB"

PASS=0
FAIL=0
TMP_DIRS=()

cleanup() {
  local d
  for d in "${TMP_DIRS[@]:-}"; do
    [ -n "$d" ] && [ -d "$d" ] && rm -rf "$d"
  done
}
trap cleanup EXIT

track_tmp() { TMP_DIRS+=("$1"); }

# ---- assertion helpers ----

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $desc" >&2
    echo "  expected: [$expected]" >&2
    echo "  actual:   [$actual]" >&2
  fi
}

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  case "$haystack" in
    *"$needle"*)
      PASS=$((PASS + 1))
      ;;
    *)
      FAIL=$((FAIL + 1))
      echo "FAIL: $desc" >&2
      echo "  expected haystack to contain: [$needle]" >&2
      echo "  haystack was:                 [$haystack]" >&2
      ;;
  esac
}

assert_not_contains() {
  local desc="$1" haystack="$2" needle="$3"
  case "$haystack" in
    *"$needle"*)
      FAIL=$((FAIL + 1))
      echo "FAIL: $desc" >&2
      echo "  expected haystack to NOT contain: [$needle]" >&2
      echo "  haystack was:                      [$haystack]" >&2
      ;;
    *)
      PASS=$((PASS + 1))
      ;;
  esac
}

_sha() {
  shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
}

assert_file_unchanged() {
  # usage: assert_file_unchanged <desc> <file> <sha_before>
  local desc="$1" file="$2" sha_before="$3"
  assert_eq "$desc" "$sha_before" "$(_sha "$file")"
}

real() {
  realpath "$1" 2>/dev/null
}

# ---- fixtures ----

# Standard fixture: git repo with a resolvable pointer + valid wiki.
#   {dir}/CLAUDE.md            -> ## Wiki section, backtick pointer `docs/wiki`
#   {dir}/docs/wiki/index.md
#   {dir}/docs/wiki/schema.md  -> frontmatter wiki_version: "4.0"
#   {dir}/docs/wiki/.usage.json -> {}
make_fixture() {
  local dir
  dir="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-test.XXXXXX")"
  track_tmp "$dir"
  ( cd "$dir" && git init -q )
  cat >"$dir/CLAUDE.md" <<'EOF'
# Test Project

## Wiki

Wiki at `docs/wiki`. Schema -> `docs/wiki/schema.md`. Skill: `wiki`.
EOF
  mkdir -p "$dir/docs/wiki"
  cat >"$dir/docs/wiki/index.md" <<'EOF'
# Wiki Index

Test fixture wiki index.
EOF
  cat >"$dir/docs/wiki/schema.md" <<'EOF'
---
wiki_version: "4.0"
---

# Schema

Test fixture schema.
EOF
  printf '{}' >"$dir/docs/wiki/.usage.json"
  printf '%s' "$dir"
}

echo "=== discover.sh ===" >&2

# 1. pointer-find: discover_wiki finds the wiki via the CLAUDE.md pointer.
fixture="$(make_fixture)"
expected="$(real "$fixture/docs/wiki")"
out="$(discover_wiki "$fixture")"
assert_eq "pointer-find: resolves docs/wiki via CLAUDE.md pointer" "$expected" "$out"

# 2. walk-up from subdir: pointer found at repo root even when start_dir
#    is a nested subdirectory with no config file of its own.
fixture="$(make_fixture)"
mkdir -p "$fixture/src/deep/sub"
expected="$(real "$fixture/docs/wiki")"
out="$(discover_wiki "$fixture/src/deep/sub")"
assert_eq "walk-up: finds pointer at repo root from nested subdir" "$expected" "$out"

# 3. boundary: an outer directory has its own valid wiki pointer, but the
#    inner directory is its own git root with NO pointer/docs/wiki of its
#    own — discover must stop at the inner git boundary and never see the
#    outer wiki, i.e. print nothing.
outer="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-test.XXXXXX")"
track_tmp "$outer"
mkdir -p "$outer/docs/wiki-outer"
printf 'outer index' >"$outer/docs/wiki-outer/index.md"
cat >"$outer/CLAUDE.md" <<'EOF'
## Wiki

Wiki at `docs/wiki-outer`.
EOF
inner="$outer/inner"
mkdir -p "$inner"
( cd "$inner" && git init -q )
out="$(discover_wiki "$inner" 2>/dev/null)"
assert_eq "boundary: inner git root never sees outer wiki pointer" "" "$out"

# 4. missing pointer + no docs/wiki -> silence.
fixture="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-test.XXXXXX")"
track_tmp "$fixture"
( cd "$fixture" && git init -q )
out="$(discover_wiki "$fixture" 2>/dev/null)"
assert_eq "no pointer, no docs/wiki: empty stdout" "" "$out"

# 5. broken pointer + existing docs/wiki -> fallback finds it.
fixture="$(make_fixture)"
cat >"$fixture/CLAUDE.md" <<'EOF'
## Wiki

Wiki at `docs/does-not-exist`.
EOF
expected="$(real "$fixture/docs/wiki")"
out="$(discover_wiki "$fixture" 2>/dev/null)"
assert_eq "broken pointer falls back to docs/wiki" "$expected" "$out"

# 6a. out-of-bounds pointer: relative traversal ../../etc
fixture="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-test.XXXXXX")"
track_tmp "$fixture"
( cd "$fixture" && git init -q )
cat >"$fixture/CLAUDE.md" <<'EOF'
## Wiki

Wiki at `../../etc`.
EOF
out="$(discover_wiki "$fixture" 2>/dev/null)"
assert_eq "out-of-bounds relative pointer (../../etc): empty stdout" "" "$out"
err="$(discover_wiki "$fixture" 2>&1 >/dev/null)"
assert_contains "out-of-bounds relative pointer: stderr notice" "$err" "поза межами репо"

# 6b. out-of-bounds pointer: absolute /etc
fixture="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-test.XXXXXX")"
track_tmp "$fixture"
( cd "$fixture" && git init -q )
cat >"$fixture/CLAUDE.md" <<'EOF'
## Wiki

Wiki at `/etc`.
EOF
out="$(discover_wiki "$fixture" 2>/dev/null)"
assert_eq "out-of-bounds absolute pointer (/etc): empty stdout" "" "$out"

# 6c. out-of-bounds pointer: symlink {repo}/w -> /tmp/outside (real
#     index.md exists on the far side, proving the guard rejects a
#     genuinely-resolving out-of-bounds target, not just a missing one).
fixture="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-test.XXXXXX")"
track_tmp "$fixture"
( cd "$fixture" && git init -q )
outside="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-outside.XXXXXX")"
track_tmp "$outside"
printf 'outside index' >"$outside/index.md"
ln -s "$outside" "$fixture/w"
cat >"$fixture/CLAUDE.md" <<'EOF'
## Wiki

Wiki at `w`.
EOF
out="$(discover_wiki "$fixture" 2>/dev/null)"
assert_eq "out-of-bounds symlink pointer (w -> /tmp/outside): empty stdout" "" "$out"

# 7. symlink-escape via index.md itself: docs/wiki/ is a real in-bounds
#    directory (passes any dir-level check) but index.md inside it is a
#    symlink to an out-of-bounds file. The guard must canonicalize the
#    RESOLVED index.md, not just the candidate directory.
fixture="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-test.XXXXXX")"
track_tmp "$fixture"
( cd "$fixture" && git init -q )
outside_file="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-outside.XXXXXX")/secret.md"
mkdir -p "$(dirname "$outside_file")"
track_tmp "$(dirname "$outside_file")"
printf 'secret' >"$outside_file"
mkdir -p "$fixture/docs/wiki"
ln -s "$outside_file" "$fixture/docs/wiki/index.md"
cat >"$fixture/CLAUDE.md" <<'EOF'
## Wiki

Wiki at `docs/wiki`.
EOF
out="$(discover_wiki "$fixture" 2>/dev/null)"
assert_eq "symlink-escape via index.md itself: empty stdout" "" "$out"
assert_not_contains "symlink-escape via index.md itself: no leaked path" "$out" "secret"

# 8. symlink-escape via fallback dir: no pointer at all, docs/wiki is
#    itself a symlink to an out-of-bounds directory containing index.md.
fixture="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-test.XXXXXX")"
track_tmp "$fixture"
( cd "$fixture" && git init -q )
outside="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-outside.XXXXXX")"
track_tmp "$outside"
printf 'outside index' >"$outside/index.md"
mkdir -p "$fixture/docs"
ln -s "$outside" "$fixture/docs/wiki"
out="$(discover_wiki "$fixture" 2>/dev/null)"
assert_eq "symlink-escape via fallback dir (docs/wiki -> outside): empty stdout" "" "$out"

# 8b. symlink-escape via index.md resolving to the boundary root itself:
#     docs/wiki/index.md is a symlink whose resolved path IS boundary_real
#     (not merely outside it). A naive exact-match boundary check would
#     accept this, then dirname() on boundary_real yields the boundary's
#     PARENT, escaping outside the project entirely. The guard must
#     require the resolved index.md to be STRICTLY inside the boundary,
#     never equal to it.
fixture="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-test.XXXXXX")"
track_tmp "$fixture"
( cd "$fixture" && git init -q )
boundary_real="$(real "$fixture")"
mkdir -p "$fixture/docs/wiki"
ln -s "$boundary_real" "$fixture/docs/wiki/index.md"
out="$(discover_wiki "$fixture" 2>/dev/null)"
assert_eq "symlink-escape via index.md == boundary root itself: empty stdout" "" "$out"
parent_of_boundary="$(dirname "$boundary_real")"
assert_not_contains "symlink-escape via index.md == boundary root: no boundary-parent leak" "$out" "$parent_of_boundary"

# 9. relative pointer + subdir: pointer resolves against the config
#    file's directory, not against start_dir or the git root.
fixture="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-test.XXXXXX")"
track_tmp "$fixture"
( cd "$fixture" && git init -q )
mkdir -p "$fixture/level1/level2/level3"
mkdir -p "$fixture/level1/sub/docs/wiki"
printf 'nested index' >"$fixture/level1/sub/docs/wiki/index.md"
cat >"$fixture/level1/CLAUDE.md" <<'EOF'
## Wiki

Wiki at `sub/docs/wiki`.
EOF
expected="$(real "$fixture/level1/sub/docs/wiki")"
out="$(discover_wiki "$fixture/level1/level2/level3" 2>/dev/null)"
assert_eq "relative pointer resolves against config-file dir, not start_dir" "$expected" "$out"

# 10. outside a git repo: FAIL-CLOSED. Even a perfectly valid, in-bounds
#     pointer + real docs/wiki/index.md must resolve to NOTHING when there
#     is no git toplevel — discovery is git-backed and must never legalize
#     a boundary for an orphan / non-git tree (codex-атк P1).
fixture="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-test.XXXXXX")"
track_tmp "$fixture"
# deliberately no `git init`
mkdir -p "$fixture/docs/wiki"
printf 'valid index' >"$fixture/docs/wiki/index.md"
cat >"$fixture/CLAUDE.md" <<'EOF'
## Wiki

Wiki at `docs/wiki`.
EOF
out="$(CLAUDE_PROJECT_DIR="$fixture" discover_wiki 2>/dev/null)"
assert_eq "outside git repo: fail-closed, valid in-bounds pointer still resolves nothing" "" "$out"

# 10b. outside a git repo: out-of-bounds pointer also yields nothing and
#      never leaks /etc/passwd (fail-closed short-circuits before any
#      pointer resolution).
fixture="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-test.XXXXXX")"
track_tmp "$fixture"
# deliberately no `git init`
cat >"$fixture/CLAUDE.md" <<'EOF'
## Wiki

Wiki at `../../etc/passwd`.
EOF
out="$(CLAUDE_PROJECT_DIR="$fixture" discover_wiki 2>/dev/null)"
assert_eq "outside git repo: out-of-bounds pointer rejected (fail-closed)" "" "$out"
assert_not_contains "outside git repo: no /etc/passwd leakage" "$out" "root:"

# 11. no realpath stderr noise for nonexistent paths.
fixture="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-test.XXXXXX")"
track_tmp "$fixture"
( cd "$fixture" && git init -q )
cat >"$fixture/CLAUDE.md" <<'EOF'
## Wiki

Wiki at `does/not/exist/anywhere`.
EOF
err="$(discover_wiki "$fixture" 2>&1 >/dev/null)"
assert_not_contains "no raw realpath stderr noise" "$err" "No such file or directory"

# 12. agent-neutral discovery: a stale/pointerless CLAUDE.md must NOT mask
#     a valid pointer in AGENTS.md sitting in the SAME directory. Previously
#     only the first existing instruction file was read, so this fell into
#     the wrong fallback / "no wiki" (codex-атк P1).
fixture="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-test.XXXXXX")"
track_tmp "$fixture"
( cd "$fixture" && git init -q )
mkdir -p "$fixture/from-agents/wiki"
printf 'agents index' >"$fixture/from-agents/wiki/index.md"
# CLAUDE.md exists but its "## Wiki" section carries NO backtick pointer.
cat >"$fixture/CLAUDE.md" <<'EOF'
## Wiki

See the team handbook for where the wiki lives.
EOF
cat >"$fixture/AGENTS.md" <<'EOF'
## Wiki

Wiki at `from-agents/wiki`.
EOF
expected="$(real "$fixture/from-agents/wiki")"
out="$(discover_wiki "$fixture" 2>/dev/null)"
assert_eq "agent-neutral: stale CLAUDE.md does not mask valid AGENTS.md pointer" "$expected" "$out"

# 12b. agent-neutral, stale-but-PRESENT pointer: CLAUDE.md carries a broken
#      backtick pointer (non-empty, resolves nowhere) while AGENTS.md in the
#      SAME directory has a valid one. The broken pointer must be validated
#      and skipped, not returned (agy-атк P1 follow-up).
fixture="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-test.XXXXXX")"
track_tmp "$fixture"
( cd "$fixture" && git init -q )
mkdir -p "$fixture/from-agents/wiki"
printf 'agents index' >"$fixture/from-agents/wiki/index.md"
cat >"$fixture/CLAUDE.md" <<'EOF'
## Wiki

Wiki at `moved/away/long/ago`.
EOF
cat >"$fixture/AGENTS.md" <<'EOF'
## Wiki

Wiki at `from-agents/wiki`.
EOF
expected="$(real "$fixture/from-agents/wiki")"
out="$(discover_wiki "$fixture" 2>/dev/null)"
assert_eq "stale CLAUDE.md pointer does not mask valid AGENTS.md pointer beside it" "$expected" "$out"

# 12c. stale NESTED pointer must not mask a valid root-level custom-path
#      pointer: sub/CLAUDE.md has a broken pointer, the repo root's
#      CLAUDE.md points at a custom (non-docs/wiki) location. The walk-up
#      must skip the invalid nested candidate and keep climbing
#      (agy-атк P1). Custom path on purpose: the docs/wiki fallback could
#      otherwise mask a broken Phase 1.
fixture="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-test.XXXXXX")"
track_tmp "$fixture"
( cd "$fixture" && git init -q )
mkdir -p "$fixture/sub" "$fixture/knowledge/wiki"
printf 'root custom index' >"$fixture/knowledge/wiki/index.md"
cat >"$fixture/sub/CLAUDE.md" <<'EOF'
## Wiki

Wiki at `does/not/exist/here`.
EOF
cat >"$fixture/CLAUDE.md" <<'EOF'
## Wiki

Wiki at `knowledge/wiki`.
EOF
expected="$(real "$fixture/knowledge/wiki")"
out="$(discover_wiki "$fixture/sub" 2>/dev/null)"
assert_eq "stale nested pointer does not mask valid root custom-path pointer" "$expected" "$out"

# 13. set -euo pipefail safety: a "## Wiki" section that exists but has NO
#     backtick token makes the awk|grep|head|sed pipe exit non-zero. Sourced
#     under `set -euo pipefail`, discover_wiki must NOT abort the caller on
#     that assignment — it must fall through cleanly (codex-атк P1).
fixture="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-test.XXXXXX")"
track_tmp "$fixture"
( cd "$fixture" && git init -q )
cat >"$fixture/CLAUDE.md" <<'EOF'
## Wiki

Section present, but no backtick pointer anywhere in it.
EOF
# Run in a fresh subshell that turns on the strict flags BEFORE sourcing,
# so we observe the exact abort behavior a strict hook caller would.
set_e_rc=0
set_e_out="$(
  set -euo pipefail
  source "$DISCOVER_LIB"
  discover_wiki "$fixture"
  printf 'REACHED_END'
)" || set_e_rc=$?
assert_eq "set -euo pipefail: discover_wiki returns 0 on pointerless section" "0" "$set_e_rc"
assert_contains "set -euo pipefail: caller runs to completion (not aborted)" "$set_e_out" "REACHED_END"

# ---- assert_file_unchanged sanity: discover_wiki is read-only ----
fixture="$(make_fixture)"
sha_before="$(_sha "$fixture/docs/wiki/index.md")"
discover_wiki "$fixture" >/dev/null
assert_file_unchanged "discover_wiki does not modify index.md" "$fixture/docs/wiki/index.md" "$sha_before"

echo "=== version-gate.sh ===" >&2

# a. frontmatter 4.0 + .usage.json exists -> writable true, bootstrappable false.
fixture="$(make_fixture)"
wiki="$fixture/docs/wiki"
if wiki_writable "$wiki"; then r=0; else r=1; fi
assert_eq "wiki_writable: current version + .usage.json present -> true" "0" "$r"
if wiki_bootstrappable "$wiki"; then r=0; else r=1; fi
assert_eq "wiki_bootstrappable: .usage.json present -> false" "1" "$r"

# b. .usage.json absent -> writable false, bootstrappable true.
fixture="$(make_fixture)"
wiki="$fixture/docs/wiki"
rm -f "$wiki/.usage.json"
if wiki_writable "$wiki"; then r=0; else r=1; fi
assert_eq "wiki_writable: .usage.json absent -> false" "1" "$r"
if wiki_bootstrappable "$wiki"; then r=0; else r=1; fi
assert_eq "wiki_bootstrappable: current version + .usage.json absent -> true" "0" "$r"

# c. frontmatter version not 4.0 -> both false.
fixture="$(make_fixture)"
wiki="$fixture/docs/wiki"
cat >"$wiki/schema.md" <<'EOF'
---
wiki_version: "3.0"
---

# Schema
EOF
if wiki_writable "$wiki"; then r=0; else r=1; fi
assert_eq "wiki_writable: version 3.0 -> false" "1" "$r"
if wiki_bootstrappable "$wiki"; then r=0; else r=1; fi
assert_eq "wiki_bootstrappable: version 3.0 -> false" "1" "$r"

# d. schema.md absent -> both false.
fixture="$(make_fixture)"
wiki="$fixture/docs/wiki"
rm -f "$wiki/schema.md"
if wiki_writable "$wiki"; then r=0; else r=1; fi
assert_eq "wiki_writable: schema.md absent -> false" "1" "$r"
if wiki_bootstrappable "$wiki"; then r=0; else r=1; fi
assert_eq "wiki_bootstrappable: schema.md absent -> false" "1" "$r"

# e. frontmatter-only match: wiki_version: "4.0" appears in the BODY
#    (below the closing ---), not in the frontmatter -> both false.
fixture="$(make_fixture)"
wiki="$fixture/docs/wiki"
cat >"$wiki/schema.md" <<'EOF'
---
title: "Schema"
---

# Schema

Migration log: previously bumped to wiki_version: "4.0" on 2026-01-01.
EOF
if wiki_writable "$wiki"; then r=0; else r=1; fi
assert_eq "wiki_writable: wiki_version 4.0 only in body -> false (no substring match)" "1" "$r"
if wiki_bootstrappable "$wiki"; then r=0; else r=1; fi
assert_eq "wiki_bootstrappable: wiki_version 4.0 only in body -> false" "1" "$r"

# f. schema.md with no frontmatter block at all (no closing ---) -> both false.
fixture="$(make_fixture)"
wiki="$fixture/docs/wiki"
cat >"$wiki/schema.md" <<'EOF'
# Schema

No frontmatter here at all, just prose mentioning wiki_version: "4.0".
EOF
if wiki_writable "$wiki"; then r=0; else r=1; fi
assert_eq "wiki_writable: no frontmatter block -> false" "1" "$r"
if wiki_bootstrappable "$wiki"; then r=0; else r=1; fi
assert_eq "wiki_bootstrappable: no frontmatter block -> false" "1" "$r"

# g. CRLF line endings: a schema.md checked out with \r\n must still pass
#    the gate — the parser strips \r before comparing delimiters and the
#    version line (agy-атк P1; fail direction was fail-closed: all hook
#    writes silently blocked on CRLF repos).
fixture="$(make_fixture)"
wiki="$fixture/docs/wiki"
printf -- '---\r\nwiki_version: "4.0"\r\n---\r\n\r\n# Schema\r\n' >"$wiki/schema.md"
if wiki_writable "$wiki"; then r=0; else r=1; fi
assert_eq "wiki_writable: CRLF schema.md, current version -> true" "0" "$r"
printf -- '---\r\nwiki_version: "3.0"\r\n---\r\n' >"$wiki/schema.md"
if wiki_writable "$wiki"; then r=0; else r=1; fi
assert_eq "wiki_writable: CRLF schema.md, old version -> still false" "1" "$r"

# ---- summary ----
echo "" >&2
echo "pass: $PASS  fail: $FAIL" >&2
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
