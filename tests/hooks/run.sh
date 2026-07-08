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
SESSION_START_HOOK="$ROOT/hooks/session-start.sh"
POST_TOOL_USE_HOOK="$ROOT/hooks/post-tool-use.sh"
INSTALL_HOOKS_SCRIPT="$ROOT/hooks/install-hooks.sh"
UNINSTALL_HOOKS_SCRIPT="$ROOT/hooks/uninstall-hooks.sh"

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

# h. .usage.json is a SYMLINK (to a valid external JSON file) -> neither
#    writable nor bootstrappable (codex-атк P1). Following it on write
#    would slurp external JSON into the repo sidecar via the atomic
#    rename. `-f` alone would pass (it follows the link to a regular
#    file); the `! -L` guard must reject it.
fixture="$(make_fixture)"
wiki="$fixture/docs/wiki"
outside_json="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-outside.XXXXXX")/external.json"
mkdir -p "$(dirname "$outside_json")"
track_tmp "$(dirname "$outside_json")"
printf '{"secret.md": {"view_count": 999}}' >"$outside_json"
rm -f "$wiki/.usage.json"
ln -s "$outside_json" "$wiki/.usage.json"
if wiki_writable "$wiki"; then r=0; else r=1; fi
assert_eq "wiki_writable: .usage.json symlink -> false (no follow/exfil)" "1" "$r"
if wiki_bootstrappable "$wiki"; then r=0; else r=1; fi
assert_eq "wiki_bootstrappable: .usage.json symlink -> false" "1" "$r"

# i. .usage.json is a FIFO -> neither writable nor bootstrappable
#    (codex-атк P1). Old `! -f` bootstrappable test would have declared
#    a FIFO bootstrappable, letting the hook open() it and block forever.
fixture="$(make_fixture)"
wiki="$fixture/docs/wiki"
rm -f "$wiki/.usage.json"
mkfifo "$wiki/.usage.json"
if wiki_writable "$wiki"; then r=0; else r=1; fi
assert_eq "wiki_writable: .usage.json FIFO -> false" "1" "$r"
if wiki_bootstrappable "$wiki"; then r=0; else r=1; fi
assert_eq "wiki_bootstrappable: .usage.json FIFO -> false (never blocks)" "1" "$r"
rm -f "$wiki/.usage.json"

# j. .usage.json is a DANGLING symlink -> not bootstrappable. `-e` is
#    false for a broken link, so a bare `! -e` test would wrongly call it
#    bootstrappable; the `! -L` guard rejects it (TOCTOU: the link target
#    could be created as a FIFO between gate and open).
fixture="$(make_fixture)"
wiki="$fixture/docs/wiki"
rm -f "$wiki/.usage.json"
ln -s "$wiki/does-not-exist-target" "$wiki/.usage.json"
if wiki_writable "$wiki"; then r=0; else r=1; fi
assert_eq "wiki_writable: .usage.json dangling symlink -> false" "1" "$r"
if wiki_bootstrappable "$wiki"; then r=0; else r=1; fi
assert_eq "wiki_bootstrappable: .usage.json dangling symlink -> false" "1" "$r"
rm -f "$wiki/.usage.json"

echo "=== session-start.sh ===" >&2

# session-start.sh is a standalone hook process (it calls `exit` on every
# path, including success) — it must be run as a subprocess, never
# sourced, or `exit` would terminate this test harness itself.

# 1. Happy path: valid wiki -> stable block markers + full index content
#    injected, exit 0.
fixture="$(make_fixture)"
out="$(CLAUDE_PROJECT_DIR="$fixture" bash "$SESSION_START_HOOK" 2>/dev/null)"
rc=$?
assert_eq "session-start: exit 0 on valid wiki" "0" "$rc"
assert_contains "session-start: opens WIKI INDEX block" "$out" "=== WIKI INDEX (hook-injected) ==="
assert_contains "session-start: closes WIKI INDEX block" "$out" "=== END WIKI INDEX ==="
assert_contains "session-start: injects full index.md content" "$out" "Test fixture wiki index."

# 2. Preamble carries the mandatory untrusted-data label — the exact
#    boundary phrase "НЕ інструкції" must appear (plan Task 2 requirement:
#    index.md content is reference data, never trusted instructions).
assert_contains "session-start: preamble has untrusted-data label" "$out" "НЕ інструкції"

# 3. >24 KB index.md is truncated to the cap with a truncation marker; the
#    tail past the cap must NOT appear in the injected block.
fixture="$(make_fixture)"
: >"$fixture/docs/wiki/index.md"
yes "0123456789" | head -c 31000 >>"$fixture/docs/wiki/index.md"
printf 'TAIL_MARKER_BEYOND_CAP' >>"$fixture/docs/wiki/index.md"
out="$(CLAUDE_PROJECT_DIR="$fixture" bash "$SESSION_START_HOOK" 2>/dev/null)"
assert_contains "session-start: >24KB index truncated with marker" "$out" "Індекс обрізано"
assert_not_contains "session-start: truncated tail not leaked past 24KB cap" "$out" "TAIL_MARKER_BEYOND_CAP"

# 4. Heartbeat: session_start_at / hook_version written atomically to
#    .usage.json on a writable (current-schema) wiki.
fixture="$(make_fixture)"
CLAUDE_PROJECT_DIR="$fixture" bash "$SESSION_START_HOOK" >/dev/null 2>&1
sa="$(python3 -c "import json; d=json.load(open('$fixture/docs/wiki/.usage.json')); print(d.get('_hooks',{}).get('session_start_at',''))" 2>/dev/null)"
hv="$(python3 -c "import json; d=json.load(open('$fixture/docs/wiki/.usage.json')); print(d.get('_hooks',{}).get('hook_version',''))" 2>/dev/null)"
if [ -n "$sa" ]; then r=0; else r=1; fi
assert_eq "session-start: heartbeat writes non-empty session_start_at" "0" "$r"
assert_eq "session-start: heartbeat writes hook_version=1" "1" "$hv"
# valid JSON after the write (atomic tmp+rename, never a half-written file).
if python3 -c "import json; json.load(open('$fixture/docs/wiki/.usage.json'))" 2>/dev/null; then r=0; else r=1; fi
assert_eq "session-start: .usage.json still valid JSON after heartbeat" "0" "$r"

# 5. Version gate: legacy/wrong schema version -> index still injected
#    (read-only, safe on any version), but .usage.json is NOT touched.
fixture="$(make_fixture)"
cat >"$fixture/docs/wiki/schema.md" <<'EOF'
---
wiki_version: "3.0"
---

# Schema
EOF
sha_before="$(_sha "$fixture/docs/wiki/.usage.json")"
out="$(CLAUDE_PROJECT_DIR="$fixture" bash "$SESSION_START_HOOK" 2>/dev/null)"
assert_contains "session-start: legacy schema still injects index (read-only)" "$out" "=== WIKI INDEX (hook-injected) ==="
assert_file_unchanged "session-start: legacy schema -> .usage.json NOT written" "$fixture/docs/wiki/.usage.json" "$sha_before"

# 5b. Version gate: schema.md entirely absent -> same contract (index
#     injected, .usage.json untouched).
fixture="$(make_fixture)"
rm -f "$fixture/docs/wiki/schema.md"
sha_before="$(_sha "$fixture/docs/wiki/.usage.json")"
out="$(CLAUDE_PROJECT_DIR="$fixture" bash "$SESSION_START_HOOK" 2>/dev/null)"
assert_contains "session-start: missing schema.md still injects index" "$out" "=== WIKI INDEX (hook-injected) ==="
assert_file_unchanged "session-start: missing schema.md -> .usage.json NOT written" "$fixture/docs/wiki/.usage.json" "$sha_before"

# 6. Lint reminder: last_lint_at 8 days old -> reminder present.
fixture="$(make_fixture)"
eight_days_ago="$(python3 -c "import time; print(time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(time.time()-8*24*3600)))")"
printf '{"_hooks": {"last_lint_at": "%s"}}' "$eight_days_ago" >"$fixture/docs/wiki/.usage.json"
out="$(CLAUDE_PROJECT_DIR="$fixture" bash "$SESSION_START_HOOK" 2>/dev/null)"
assert_contains "session-start: last_lint_at 8 days old -> reminder present" "$out" "wiki lint"

# 6b. Lint reminder: last_lint_at 2 days old -> no reminder.
fixture="$(make_fixture)"
two_days_ago="$(python3 -c "import time; print(time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(time.time()-2*24*3600)))")"
printf '{"_hooks": {"last_lint_at": "%s"}}' "$two_days_ago" >"$fixture/docs/wiki/.usage.json"
out="$(CLAUDE_PROJECT_DIR="$fixture" bash "$SESSION_START_HOOK" 2>/dev/null)"
assert_not_contains "session-start: last_lint_at 2 days old -> no reminder" "$out" "wiki lint"

# 6c. Lint reminder: last_lint_at absent entirely -> reminder present.
fixture="$(make_fixture)"
out="$(CLAUDE_PROJECT_DIR="$fixture" bash "$SESSION_START_HOOK" 2>/dev/null)"
assert_contains "session-start: last_lint_at absent -> reminder present" "$out" "wiki lint"

# 7. No wiki discoverable -> empty stdout, exit 0 (never blocks startup).
fixture="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-test.XXXXXX")"
track_tmp "$fixture"
( cd "$fixture" && git init -q )
out="$(CLAUDE_PROJECT_DIR="$fixture" bash "$SESSION_START_HOOK" 2>/dev/null)"
rc=$?
assert_eq "session-start: no wiki -> empty stdout" "" "$out"
assert_eq "session-start: no wiki -> exit 0" "0" "$rc"

echo "=== post-tool-use.sh ===" >&2

# post-tool-use.sh is a standalone hook process (it calls `exit` on every
# path) — run as a subprocess, never sourced.

_ptu_stdin() {
  # $1 = tool_name, $2 = file_path. Prints the stdin-JSON shape documented
  # by Claude Code hooks (tool_name, tool_input.file_path).
  printf '{"tool_name":"%s","tool_input":{"file_path":"%s"}}' "$1" "$2"
}

_ptu_field() {
  # $1 = .usage.json path, $2 = key, $3 = field. Empty string if the key or
  # field is absent (missing record, corrupt file, etc.).
  python3 -c "
import json
try:
    d = json.load(open('$1'))
except Exception:
    d = {}
rec = d.get('$2', {})
if not isinstance(rec, dict):
    rec = {}
v = rec.get('$3', '')
print('' if v is None else v)
" 2>/dev/null
}

# 1. Read a wiki page -> view_count + 1, last_viewed_at set.
fixture="$(make_fixture)"
cat >"$fixture/docs/wiki/foo.md" <<'EOF'
# Foo
EOF
_ptu_stdin "Read" "$fixture/docs/wiki/foo.md" | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1
rc=$?
assert_eq "post-tool-use: Read exits 0" "0" "$rc"
vc="$(_ptu_field "$fixture/docs/wiki/.usage.json" "foo.md" "view_count")"
assert_eq "post-tool-use: Read bumps view_count to 1" "1" "$vc"
lva="$(_ptu_field "$fixture/docs/wiki/.usage.json" "foo.md" "last_viewed_at")"
if [ -n "$lva" ]; then r=0; else r=1; fi
assert_eq "post-tool-use: Read sets last_viewed_at" "0" "$r"

# 2. Edit a wiki page -> patch_count + 1, last_patched_at set.
fixture="$(make_fixture)"
cat >"$fixture/docs/wiki/foo.md" <<'EOF'
# Foo
EOF
_ptu_stdin "Edit" "$fixture/docs/wiki/foo.md" | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1
pc="$(_ptu_field "$fixture/docs/wiki/.usage.json" "foo.md" "patch_count")"
assert_eq "post-tool-use: Edit bumps patch_count to 1" "1" "$pc"
lpa="$(_ptu_field "$fixture/docs/wiki/.usage.json" "foo.md" "last_patched_at")"
if [ -n "$lpa" ]; then r=0; else r=1; fi
assert_eq "post-tool-use: Edit sets last_patched_at" "0" "$r"

# 3. Write a brand-new page -> record created with all 10 default fields
#    (nine besides the incremented one, per telemetry.md's ten-field shape).
fixture="$(make_fixture)"
cat >"$fixture/docs/wiki/newpage.md" <<'EOF'
# New Page
EOF
_ptu_stdin "Write" "$fixture/docs/wiki/newpage.md" | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1
field_count="$(python3 -c "
import json
d = json.load(open('$fixture/docs/wiki/.usage.json'))
print(len(d.get('newpage.md', {})))
" 2>/dev/null)"
assert_eq "post-tool-use: Write of new page creates record with 10 fields" "10" "$field_count"
pc="$(_ptu_field "$fixture/docs/wiki/.usage.json" "newpage.md" "patch_count")"
assert_eq "post-tool-use: Write bumps patch_count to 1" "1" "$pc"

# 4. Read index.md -> excluded, not counted (service-navigation page).
fixture="$(make_fixture)"
sha_before="$(_sha "$fixture/docs/wiki/.usage.json")"
_ptu_stdin "Read" "$fixture/docs/wiki/index.md" | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1
assert_file_unchanged "post-tool-use: Read index.md not counted" "$fixture/docs/wiki/.usage.json" "$sha_before"

# 5. Read a file OUTSIDE the wiki -> no change at all.
fixture="$(make_fixture)"
mkdir -p "$fixture/src"
cat >"$fixture/src/outside.md" <<'EOF'
# Outside
EOF
sha_before="$(_sha "$fixture/docs/wiki/.usage.json")"
_ptu_stdin "Read" "$fixture/src/outside.md" | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1
rc=$?
assert_eq "post-tool-use: Read outside wiki exits 0" "0" "$rc"
assert_file_unchanged "post-tool-use: Read outside wiki -> .usage.json unchanged" "$fixture/docs/wiki/.usage.json" "$sha_before"

# 6. Corrupt .usage.json -> recovered to {} + fresh record written.
fixture="$(make_fixture)"
cat >"$fixture/docs/wiki/foo.md" <<'EOF'
# Foo
EOF
printf '{not valid json' >"$fixture/docs/wiki/.usage.json"
_ptu_stdin "Read" "$fixture/docs/wiki/foo.md" | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1
if python3 -c "import json; json.load(open('$fixture/docs/wiki/.usage.json'))" 2>/dev/null; then r=0; else r=1; fi
assert_eq "post-tool-use: corrupt .usage.json recovered to valid JSON" "0" "$r"
vc="$(_ptu_field "$fixture/docs/wiki/.usage.json" "foo.md" "view_count")"
assert_eq "post-tool-use: corrupt .usage.json -> fresh record written (view_count 1)" "1" "$vc"

# 7. No python3 on PATH -> exit 0, .usage.json untouched. A curated PATH
#    dir carries symlinks to every OTHER external tool the hook needs
#    (bash, dirname, basename, realpath, sed, cat, git) but deliberately
#    omits python3 — an outright-empty PATH would also break command
#    lookup for `bash` itself (both bash and zsh resolve the invoked
#    command's name against the OVERRIDDEN PATH of a `VAR=val cmd`
#    prefix, not the caller's), giving a false "no python3" signal for
#    the wrong reason (127 from a missing `bash`, not the hook's own
#    python3 guard).
fixture="$(make_fixture)"
cat >"$fixture/docs/wiki/foo.md" <<'EOF'
# Foo
EOF
sha_before="$(_sha "$fixture/docs/wiki/.usage.json")"
curated_path_dir="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-nopython.XXXXXX")"
track_tmp "$curated_path_dir"
for _tool in bash dirname basename realpath sed cat git; do
  _tool_src="$(command -v "$_tool" 2>/dev/null)"
  [ -n "$_tool_src" ] && ln -s "$_tool_src" "$curated_path_dir/$_tool"
done
out="$(_ptu_stdin "Read" "$fixture/docs/wiki/foo.md" | CLAUDE_PROJECT_DIR="$fixture" PATH="$curated_path_dir" bash "$POST_TOOL_USE_HOOK" 2>/dev/null)"
rc=$?
assert_eq "post-tool-use: no python3 -> exit 0" "0" "$rc"
assert_file_unchanged "post-tool-use: no python3 -> .usage.json untouched" "$fixture/docs/wiki/.usage.json" "$sha_before"

# 8. file_path resolution: a RELATIVE file_path (as Claude Code sends it)
#    must resolve against $CLAUDE_PROJECT_DIR, not the hook process's own
#    cwd — invoke from an unrelated subdirectory of the fixture.
fixture="$(make_fixture)"
cat >"$fixture/docs/wiki/foo.md" <<'EOF'
# Foo
EOF
mkdir -p "$fixture/other/subdir"
( cd "$fixture/other/subdir" && _ptu_stdin "Read" "docs/wiki/foo.md" | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1 )
vc="$(_ptu_field "$fixture/docs/wiki/.usage.json" "foo.md" "view_count")"
assert_eq "post-tool-use: relative file_path resolves against CLAUDE_PROJECT_DIR (not hook cwd)" "1" "$vc"

# 9. Version gate: legacy schema.md (not 4.0) -> .usage.json NOT touched.
fixture="$(make_fixture)"
cat >"$fixture/docs/wiki/foo.md" <<'EOF'
# Foo
EOF
cat >"$fixture/docs/wiki/schema.md" <<'EOF'
---
wiki_version: "3.0"
---
EOF
sha_before="$(_sha "$fixture/docs/wiki/.usage.json")"
_ptu_stdin "Edit" "$fixture/docs/wiki/foo.md" | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1
assert_file_unchanged "post-tool-use: legacy schema.md -> .usage.json untouched" "$fixture/docs/wiki/.usage.json" "$sha_before"

# 9b. Version gate: schema.md entirely absent -> same contract.
fixture="$(make_fixture)"
cat >"$fixture/docs/wiki/foo.md" <<'EOF'
# Foo
EOF
rm -f "$fixture/docs/wiki/schema.md"
sha_before="$(_sha "$fixture/docs/wiki/.usage.json")"
_ptu_stdin "Edit" "$fixture/docs/wiki/foo.md" | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1
assert_file_unchanged "post-tool-use: missing schema.md -> .usage.json untouched" "$fixture/docs/wiki/.usage.json" "$sha_before"

# 10. Version gate: schema 4.0 but .usage.json absent -> sidecar creation
#     allowed (wiki_bootstrappable path).
fixture="$(make_fixture)"
cat >"$fixture/docs/wiki/foo.md" <<'EOF'
# Foo
EOF
rm -f "$fixture/docs/wiki/.usage.json"
_ptu_stdin "Read" "$fixture/docs/wiki/foo.md" | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1
if [ -f "$fixture/docs/wiki/.usage.json" ]; then r=0; else r=1; fi
assert_eq "post-tool-use: current schema + missing .usage.json -> sidecar created" "0" "$r"
vc="$(_ptu_field "$fixture/docs/wiki/.usage.json" "foo.md" "view_count")"
assert_eq "post-tool-use: bootstrapped sidecar has fresh view_count 1" "1" "$vc"

# 10b. Fixture without .usage.json AND legacy schema.md -> no file created
#      at all (neither wiki_writable nor wiki_bootstrappable).
fixture="$(make_fixture)"
cat >"$fixture/docs/wiki/foo.md" <<'EOF'
# Foo
EOF
rm -f "$fixture/docs/wiki/.usage.json"
cat >"$fixture/docs/wiki/schema.md" <<'EOF'
---
wiki_version: "3.0"
---
EOF
_ptu_stdin "Read" "$fixture/docs/wiki/foo.md" | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1
if [ -f "$fixture/docs/wiki/.usage.json" ]; then r=0; else r=1; fi
assert_eq "post-tool-use: legacy schema + missing .usage.json -> sidecar NOT created" "1" "$r"

# 11. Legacy `pinned` field -> migrated to `protected` on write, old key
#     dropped (telemetry.md "Field-rename compat", v4.0.0 -> v4.0.x).
fixture="$(make_fixture)"
cat >"$fixture/docs/wiki/foo.md" <<'EOF'
# Foo
EOF
python3 -c "
import json
d = {'foo.md': {
    'view_count': 3, 'use_count': 0, 'patch_count': 1,
    'last_viewed_at': None, 'last_used_at': None, 'last_patched_at': None,
    'created_at': '2026-01-01T00:00:00Z', 'state': 'active',
    'pinned': True, 'archived_at': None,
}}
json.dump(d, open('$fixture/docs/wiki/.usage.json', 'w'))
"
_ptu_stdin "Read" "$fixture/docs/wiki/foo.md" | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1
prot="$(_ptu_field "$fixture/docs/wiki/.usage.json" "foo.md" "protected")"
assert_eq "post-tool-use: legacy pinned:true migrated to protected" "True" "$prot"
has_pinned="$(python3 -c "
import json
d = json.load(open('$fixture/docs/wiki/.usage.json'))
print('pinned' in d.get('foo.md', {}))
")"
assert_eq "post-tool-use: legacy pinned key dropped after migration" "False" "$has_pinned"
vc="$(_ptu_field "$fixture/docs/wiki/.usage.json" "foo.md" "view_count")"
assert_eq "post-tool-use: pinned-migration write still bumps view_count" "4" "$vc"

# 12. Existing record missing newer v4 fields (state/protected/archived_at)
#     -> backfilled with defaults on write, existing fields left untouched
#     (telemetry.md "Backfill missing keys silently").
fixture="$(make_fixture)"
cat >"$fixture/docs/wiki/foo.md" <<'EOF'
# Foo
EOF
python3 -c "
import json
d = {'foo.md': {'view_count': 2, 'use_count': 0, 'patch_count': 0,
    'last_viewed_at': None, 'last_used_at': None, 'last_patched_at': None,
    'created_at': '2026-01-01T00:00:00Z'}}
json.dump(d, open('$fixture/docs/wiki/.usage.json', 'w'))
"
_ptu_stdin "Read" "$fixture/docs/wiki/foo.md" | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1
field_count="$(python3 -c "
import json
d = json.load(open('$fixture/docs/wiki/.usage.json'))
print(len(d.get('foo.md', {})))
")"
assert_eq "post-tool-use: legacy record backfilled to 10 fields" "10" "$field_count"
state="$(_ptu_field "$fixture/docs/wiki/.usage.json" "foo.md" "state")"
assert_eq "post-tool-use: backfilled state defaults to active" "active" "$state"
created="$(_ptu_field "$fixture/docs/wiki/.usage.json" "foo.md" "created_at")"
assert_eq "post-tool-use: backfill leaves existing created_at untouched" "2026-01-01T00:00:00Z" "$created"
vc="$(_ptu_field "$fixture/docs/wiki/.usage.json" "foo.md" "view_count")"
assert_eq "post-tool-use: backfill write bumps pre-existing view_count" "3" "$vc"

# 13. pinned/protected union (codex-атк P1): a record carrying BOTH
#     {"protected": true, "pinned": false} must stay protected after the
#     migration write — the legacy `pinned:false` must NOT clobber the
#     live `protected:true`, or a protected page would silently become
#     cleanup-eligible. Old key dropped, protected stays true.
fixture="$(make_fixture)"
cat >"$fixture/docs/wiki/foo.md" <<'EOF'
# Foo
EOF
python3 -c "
import json
d = {'foo.md': {
    'view_count': 1, 'use_count': 0, 'patch_count': 0,
    'last_viewed_at': None, 'last_used_at': None, 'last_patched_at': None,
    'created_at': '2026-01-01T00:00:00Z', 'state': 'active',
    'protected': True, 'pinned': False, 'archived_at': None,
}}
json.dump(d, open('$fixture/docs/wiki/.usage.json', 'w'))
"
_ptu_stdin "Read" "$fixture/docs/wiki/foo.md" | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1
prot="$(_ptu_field "$fixture/docs/wiki/.usage.json" "foo.md" "protected")"
assert_eq "post-tool-use: protected:true survives pinned:false migration (union)" "True" "$prot"
has_pinned="$(python3 -c "
import json
d = json.load(open('$fixture/docs/wiki/.usage.json'))
print('pinned' in d.get('foo.md', {}))
")"
assert_eq "post-tool-use: legacy pinned key dropped even in union case" "False" "$has_pinned"

# 13b. Reverse direction: {"protected": false, "pinned": true} -> union
#      keeps it protected (either name truthy).
fixture="$(make_fixture)"
cat >"$fixture/docs/wiki/foo.md" <<'EOF'
# Foo
EOF
python3 -c "
import json
d = {'foo.md': {
    'view_count': 1, 'use_count': 0, 'patch_count': 0,
    'last_viewed_at': None, 'last_used_at': None, 'last_patched_at': None,
    'created_at': '2026-01-01T00:00:00Z', 'state': 'active',
    'protected': False, 'pinned': True, 'archived_at': None,
}}
json.dump(d, open('$fixture/docs/wiki/.usage.json', 'w'))
"
_ptu_stdin "Read" "$fixture/docs/wiki/foo.md" | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1
prot="$(_ptu_field "$fixture/docs/wiki/.usage.json" "foo.md" "protected")"
assert_eq "post-tool-use: pinned:true promotes protected:false via union" "True" "$prot"

# 14. .usage.json is a SYMLINK to an external JSON file (codex-атк P1):
#     the hook must NOT read the external file's contents into the repo
#     sidecar, and the external file must remain byte-for-byte unchanged.
#     Version gate rejects the symlink, so nothing is written at all.
fixture="$(make_fixture)"
cat >"$fixture/docs/wiki/foo.md" <<'EOF'
# Foo
EOF
outside_json="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-outside.XXXXXX")/external.json"
mkdir -p "$(dirname "$outside_json")"
track_tmp "$(dirname "$outside_json")"
printf '{"SECRET_EXTERNAL_KEY": {"view_count": 999}}' >"$outside_json"
outside_sha_before="$(_sha "$outside_json")"
rm -f "$fixture/docs/wiki/.usage.json"
ln -s "$outside_json" "$fixture/docs/wiki/.usage.json"
out="$(_ptu_stdin "Read" "$fixture/docs/wiki/foo.md" | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" 2>&1)"
rc=$?
assert_eq "post-tool-use: symlink .usage.json -> exit 0" "0" "$rc"
assert_file_unchanged "post-tool-use: symlink .usage.json -> external file untouched" "$outside_json" "$outside_sha_before"
# The gate blocks the symlinked sidecar entirely, so the hook writes
# nothing: the path must STILL be a symlink (never replaced by a repo
# regular file materializing the external JSON). If a regression let the
# write through, os.replace would have converted it to a regular file
# carrying SECRET_EXTERNAL_KEY committed inside the repo tree.
if [ -L "$fixture/docs/wiki/.usage.json" ]; then r=0; else r=1; fi
assert_eq "post-tool-use: symlink .usage.json left untouched (no exfil write)" "0" "$r"
if [ -f "$fixture/docs/wiki/.usage.json" ] && [ ! -L "$fixture/docs/wiki/.usage.json" ]; then r=0; else r=1; fi
assert_eq "post-tool-use: sidecar not materialized as a regular repo file" "1" "$r"
rm -f "$fixture/docs/wiki/.usage.json"

# 15. .usage.json is a FIFO (codex-атк P1): the hook must return promptly
#     (never block on open()) and exit 0. Run with a hard timeout so a
#     regression that blocks fails loudly instead of hanging the suite.
fixture="$(make_fixture)"
cat >"$fixture/docs/wiki/foo.md" <<'EOF'
# Foo
EOF
rm -f "$fixture/docs/wiki/.usage.json"
mkfifo "$fixture/docs/wiki/.usage.json"
if command -v timeout >/dev/null 2>&1; then
  _timeout="timeout 10"
elif command -v gtimeout >/dev/null 2>&1; then
  _timeout="gtimeout 10"
else
  _timeout=""
fi
_ptu_stdin "Read" "$fixture/docs/wiki/foo.md" | CLAUDE_PROJECT_DIR="$fixture" $_timeout bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1
rc=$?
assert_eq "post-tool-use: FIFO .usage.json -> returns promptly, exit 0 (never blocks)" "0" "$rc"
rm -f "$fixture/docs/wiki/.usage.json"

# 10. Relative file_path resolves against the documented stdin `cwd` when
#     $CLAUDE_PROJECT_DIR is UNSET and the hook runs from a subdir. Without
#     parsing stdin cwd the anchor falls back to pwd (the subdir), the
#     in-wiki guard mis-resolves, and telemetry silently vanishes on a real
#     Claude Code invocation that doesn't export CLAUDE_PROJECT_DIR
#     (codex-атк P1).
fixture="$(make_fixture)"
u="$fixture/docs/wiki/.usage.json"
printf 'body\n' >"$fixture/docs/wiki/foo.md"
mkdir -p "$fixture/some/other/subdir"
echo '{"tool_name":"Read","cwd":"'"$fixture"'","tool_input":{"file_path":"docs/wiki/foo.md"}}' \
  | ( cd "$fixture/some/other/subdir" && env -u CLAUDE_PROJECT_DIR bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1 )
assert_eq "post-tool-use: relative file_path resolves against stdin cwd when CLAUDE_PROJECT_DIR unset" \
  "1" "$(ptu_field "$u" "d['foo.md']['view_count']")"

# 11. Regression: post-tool-use.sh MUST be committed executable. install
#     registers `test -x <canonical> && <canonical> || exit 0`, so a
#     non-executable file (git mode 100644) makes the installed hook a silent
#     no-op — PostToolUse telemetry never fires (codex-атк P1). The blocks
#     above all run it via `bash`, bypassing the -x guard, so assert the git
#     index mode + on-disk bit explicitly.
mode="$(git -C "$ROOT" ls-files -s -- hooks/post-tool-use.sh 2>/dev/null | awk '{print $1}')"
assert_eq "post-tool-use: committed with executable git mode (100755)" "100755" "$mode"
assert_eq "post-tool-use: executable bit set on disk" "yes" \
  "$([ -x "$POST_TOOL_USE_HOOK" ] && echo yes || echo no)"

echo "=== install-hooks.sh / uninstall-hooks.sh ===" >&2

# install-hooks.sh / uninstall-hooks.sh are standalone processes (they
# `exit` on every path) and mutate a GLOBAL-shaped ~/.claude/settings.json
# — every invocation below points HOME at a throwaway tmp dir so the real
# ~/.claude is never touched (plan Task 4 test-fixture requirement).
#
# WIKI_HOOKS_FORCE_MKDIR_LOCK=1 pins every call to the mkdir-fallback lock
# path so these tests are deterministic regardless of whether the host
# happens to have `flock` installed (stock macOS does not; some Linux CI
# images do) — the plan's crash/interrupt-recovery and stale-lock
# requirements are specifically about that fallback. WIKI_HOOKS_LOCK_TIMEOUT
# / WIKI_HOOKS_LOCK_POLL are kept small so the deliberately-slow scenarios
# below stay fast.

make_fake_home() {
  local dir
  dir="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-home.XXXXXX")"
  track_tmp "$dir"
  mkdir -p "$dir/.claude"
  printf '%s' "$dir"
}

# json_get <file> <python-expr-on-loaded-dict-d> -> prints repr(eval(expr))
# or __ERR__ if the file is missing/invalid or the expr raises.
#
# eval() here is safe: <python-expr> is always a literal string hardcoded
# in THIS test file below (e.g. "len(d['hooks']['SessionStart'])"), never
# data read from the JSON fixture or any other untrusted source — `d` is
# the only external input and it only flows in via json.load(), not eval.
json_get() {
  python3 -c "
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print(eval(sys.argv[2]))
except Exception:
    print('__ERR__')
" "$1" "$2" 2>/dev/null
}

WH_ENV=(WIKI_HOOKS_FORCE_MKDIR_LOCK=1 WIKI_HOOKS_LOCK_TIMEOUT=3 WIKI_HOOKS_LOCK_POLL=0.1)

# 1. Empty settings.json (no file at all) -> install adds exactly 2 records
#    (one SessionStart entry, one PostToolUse entry), valid JSON, exit 0.
home="$(make_fake_home)"
out="$(env "${WH_ENV[@]}" HOME="$home" bash "$INSTALL_HOOKS_SCRIPT" 2>&1)"
rc=$?
assert_eq "install: empty settings -> exit 0" "0" "$rc"
f="$home/.claude/settings.json"
assert_eq "install: empty settings -> SessionStart has 1 entry" "1" "$(json_get "$f" "len(d['hooks']['SessionStart'])")"
assert_eq "install: empty settings -> PostToolUse has 1 entry" "1" "$(json_get "$f" "len(d['hooks']['PostToolUse'])")"
assert_eq "install: registered SessionStart matcher" "startup|clear|compact" "$(json_get "$f" "d['hooks']['SessionStart'][0]['matcher']")"
assert_eq "install: registered PostToolUse matcher" "Read|Edit|Write|MultiEdit" "$(json_get "$f" "d['hooks']['PostToolUse'][0]['matcher']")"
assert_contains "install: SessionStart command carries canonical marker" \
  "$(json_get "$f" "d['hooks']['SessionStart'][0]['hooks'][0]['command']")" "/skills/wiki/hooks/"

# 2. Foreign hooks/keys are preserved unchanged (structurally, value-for-
#    value — the only mutation allowed is inside the wiki-owned entries).
home="$(make_fake_home)"
f="$home/.claude/settings.json"
cat >"$f" <<'EOF'
{
  "otherTopLevelKey": {"nested": true, "n": 3},
  "hooks": {
    "Stop": [
      {"matcher": "*", "hooks": [{"type": "command", "command": "/foreign/stop.sh"}]}
    ],
    "SessionStart": [
      {"matcher": "custom-matcher", "hooks": [{"type": "command", "command": "/foreign/session.sh"}]}
    ]
  }
}
EOF
env "${WH_ENV[@]}" HOME="$home" bash "$INSTALL_HOOKS_SCRIPT" >/dev/null 2>&1
assert_eq "install: foreign top-level key preserved" "{'nested': True, 'n': 3}" "$(json_get "$f" "d['otherTopLevelKey']")"
assert_eq "install: foreign Stop event untouched" "/foreign/stop.sh" "$(json_get "$f" "d['hooks']['Stop'][0]['hooks'][0]['command']")"
assert_eq "install: foreign SessionStart matcher-entry untouched" "/foreign/session.sh" "$(json_get "$f" "d['hooks']['SessionStart'][0]['hooks'][0]['command']")"
assert_eq "install: foreign SessionStart entry count unchanged + 1 wiki entry" "2" "$(json_get "$f" "len(d['hooks']['SessionStart'])")"

# 3. Repeated install -> idempotent, no duplicate wiki entries.
env "${WH_ENV[@]}" HOME="$home" bash "$INSTALL_HOOKS_SCRIPT" >/dev/null 2>&1
env "${WH_ENV[@]}" HOME="$home" bash "$INSTALL_HOOKS_SCRIPT" >/dev/null 2>&1
assert_eq "install: repeat runs stay idempotent (still 1 foreign + 1 wiki)" "2" "$(json_get "$f" "len(d['hooks']['SessionStart'])")"
assert_eq "install: repeat runs -> PostToolUse still exactly 1 entry" "1" "$(json_get "$f" "len(d['hooks']['PostToolUse'])")"

# 4. Corrupt JSON -> refuse, file left byte-identical, non-zero exit.
home="$(make_fake_home)"
f="$home/.claude/settings.json"
printf '{ this is not valid json' >"$f"
sha_before="$(_sha "$f")"
err="$(env "${WH_ENV[@]}" HOME="$home" bash "$INSTALL_HOOKS_SCRIPT" 2>&1 >/dev/null)"
rc=$?
assert_eq "install: corrupt JSON -> non-zero exit" "1" "$rc"
assert_file_unchanged "install: corrupt JSON -> settings.json byte-identical" "$f" "$sha_before"
assert_contains "install: corrupt JSON -> stderr mentions failure" "$err" "install-hooks"

# 5. uninstall removes wiki entries, leaves foreign hooks intact.
home="$(make_fake_home)"
f="$home/.claude/settings.json"
cat >"$f" <<'EOF'
{
  "hooks": {
    "Stop": [{"matcher": "*", "hooks": [{"type": "command", "command": "/foreign/stop.sh"}]}]
  }
}
EOF
env "${WH_ENV[@]}" HOME="$home" bash "$INSTALL_HOOKS_SCRIPT" >/dev/null 2>&1
assert_eq "uninstall-fixture: install left foreign Stop hook alone" "/foreign/stop.sh" "$(json_get "$f" "d['hooks']['Stop'][0]['hooks'][0]['command']")"
env "${WH_ENV[@]}" HOME="$home" bash "$UNINSTALL_HOOKS_SCRIPT" >/dev/null 2>&1
rc=$?
assert_eq "uninstall: exit 0" "0" "$rc"
assert_eq "uninstall: SessionStart event removed entirely (empty after strip)" "False" "$(json_get "$f" "'SessionStart' in d.get('hooks', {})")"
assert_eq "uninstall: PostToolUse event removed entirely (empty after strip)" "False" "$(json_get "$f" "'PostToolUse' in d.get('hooks', {})")"
assert_eq "uninstall: foreign Stop hook survives" "/foreign/stop.sh" "$(json_get "$f" "d['hooks']['Stop'][0]['hooks'][0]['command']")"

# 6. Mixed-entry granular removal: one matcher-entry's nested hooks[] holds
#    BOTH a wiki command (bearing the marker) and an unrelated user
#    command. install/uninstall must strip only the wiki command, keep the
#    user command, and must NOT delete the parent matcher-entry (its
#    hooks[] is not empty).
home="$(make_fake_home)"
f="$home/.claude/settings.json"
cat >"$f" <<'EOF'
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|clear|compact",
        "hooks": [
          {"type": "command", "command": "test -x \"/old/clone/.claude/skills/wiki/hooks/session-start.sh\" && \"/old/clone/.claude/skills/wiki/hooks/session-start.sh\" || exit 0"},
          {"type": "command", "command": "/my/custom-hook.sh"}
        ]
      }
    ]
  }
}
EOF
env "${WH_ENV[@]}" HOME="$home" bash "$INSTALL_HOOKS_SCRIPT" >/dev/null 2>&1
assert_eq "mixed-entry install: old wiki command replaced (marker still present exactly once per event)" \
  "1" "$(json_get "$f" "sum(1 for e in d['hooks']['SessionStart'] for h in e['hooks'] if '/skills/wiki/hooks/' in h['command'])")"
assert_eq "mixed-entry install: user command survives" "True" \
  "$(json_get "$f" "any(h['command'] == '/my/custom-hook.sh' for e in d['hooks']['SessionStart'] for h in e['hooks'])")"
# NOTE: deliberately compares fields rather than a `[{'k': 'v', ...}]`
# dict-literal expression here — bash 3.2 (stock macOS /bin/bash)
# misparses a comma-separated `{a,b}`-shaped literal as brace expansion
# when it's nested two levels of double-quoting deep inside `$(...)`,
# even though it is fully quoted at the shell level (harmless in this
# specific nesting shape, but avoided outright to keep the assertion
# portable across bash versions).
assert_eq "mixed-entry install: user-only matcher-entry not deleted (hooks[] non-empty)" "True" \
  "$(json_get "$f" "any(len(e['hooks']) == 1 and e['hooks'][0]['command'] == '/my/custom-hook.sh' for e in d['hooks']['SessionStart'])")"
env "${WH_ENV[@]}" HOME="$home" bash "$UNINSTALL_HOOKS_SCRIPT" >/dev/null 2>&1
assert_eq "mixed-entry uninstall: wiki command gone" "0" \
  "$(json_get "$f" "sum(1 for e in d['hooks'].get('SessionStart', []) for h in e['hooks'] if '/skills/wiki/hooks/' in h['command'])")"
assert_eq "mixed-entry uninstall: user command still present" "True" \
  "$(json_get "$f" "any(h['command'] == '/my/custom-hook.sh' for e in d['hooks']['SessionStart'] for h in e['hooks'])")"
assert_eq "mixed-entry uninstall: user-only matcher-entry NOT removed" "1" "$(json_get "$f" "len(d['hooks']['SessionStart'])")"

# 6b. Entry containing ONLY the wiki command -> after uninstall the entry
#     itself is removed entirely (not left behind as an empty hooks[]).
home="$(make_fake_home)"
f="$home/.claude/settings.json"
env "${WH_ENV[@]}" HOME="$home" bash "$INSTALL_HOOKS_SCRIPT" >/dev/null 2>&1
assert_eq "wiki-only entry: install produced exactly 1 SessionStart entry" "1" "$(json_get "$f" "len(d['hooks']['SessionStart'])")"
env "${WH_ENV[@]}" HOME="$home" bash "$UNINSTALL_HOOKS_SCRIPT" >/dev/null 2>&1
assert_eq "wiki-only entry: uninstall removes matcher-entry entirely, no empty leftovers" "False" \
  "$(json_get "$f" "'SessionStart' in d.get('hooks', {})")"

# 7. Fail-open: the registered command wraps the canonical script in
#    `test -x ... && ... || exit 0`. Once that script is missing (as it
#    always is under a throwaway fake HOME with no real skill clone),
#    running the command must exit 0 with no stderr noise.
home="$(make_fake_home)"
f="$home/.claude/settings.json"
env "${WH_ENV[@]}" HOME="$home" bash "$INSTALL_HOOKS_SCRIPT" >/dev/null 2>&1
cmd="$(json_get "$f" "d['hooks']['SessionStart'][0]['hooks'][0]['command']")"
assert_contains "fail-open: registered command uses test -x guard" "$cmd" "test -x"
fo_err="$(bash -c "$cmd" 2>&1 >/dev/null)"
fo_rc=$?
assert_eq "fail-open: missing canonical script -> exit 0" "0" "$fo_rc"
assert_eq "fail-open: missing canonical script -> no stderr" "" "$fo_err"

# 8. Canonical path: the registered command always targets
#    $HOME/.claude/skills/wiki/hooks/*.sh literally — never the physical
#    location install-hooks.sh itself was run from. Copy the script to two
#    different fake "clone" locations and confirm both produce the exact
#    same command, and a rerun from the second clone does not duplicate.
home="$(make_fake_home)"
f="$home/.claude/settings.json"
clone_a="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-clone.XXXXXX")"
track_tmp "$clone_a"
clone_b="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-clone.XXXXXX")"
track_tmp "$clone_b"
cp "$INSTALL_HOOKS_SCRIPT" "$clone_a/install-hooks.sh"
cp "$INSTALL_HOOKS_SCRIPT" "$clone_b/install-hooks.sh"
env "${WH_ENV[@]}" HOME="$home" bash "$clone_a/install-hooks.sh" >/dev/null 2>&1
cmd_a="$(json_get "$f" "d['hooks']['SessionStart'][0]['hooks'][0]['command']")"
expected_canon="$home/.claude/skills/wiki/hooks/session-start.sh"
assert_contains "canonical path: command targets \$HOME/.claude/skills/wiki/hooks/ literally" "$cmd_a" "$expected_canon"
env "${WH_ENV[@]}" HOME="$home" bash "$clone_b/install-hooks.sh" >/dev/null 2>&1
cmd_b="$(json_get "$f" "d['hooks']['SessionStart'][0]['hooks'][0]['command']")"
assert_eq "canonical path: identical command from a different clone location" "$cmd_a" "$cmd_b"
assert_eq "canonical path: rerun from different clone -> still no duplicate SessionStart entries" "1" "$(json_get "$f" "len(d['hooks']['SessionStart'])")"

# 9. Serialized read-modify-write: two installs racing on the same
#    settings.json must both land, no lost update, valid JSON at the end.
home="$(make_fake_home)"
f="$home/.claude/settings.json"
env "${WH_ENV[@]}" HOME="$home" bash "$INSTALL_HOOKS_SCRIPT" >/dev/null 2>&1 &
p1=$!
env "${WH_ENV[@]}" HOME="$home" bash "$INSTALL_HOOKS_SCRIPT" >/dev/null 2>&1 &
p2=$!
rc1=0; rc2=0
wait "$p1" || rc1=$?
wait "$p2" || rc2=$?
assert_eq "serialized RMW: first parallel install exit 0" "0" "$rc1"
assert_eq "serialized RMW: second parallel install exit 0" "0" "$rc2"
assert_eq "serialized RMW: settings.json still valid JSON" "dict" "$(json_get "$f" "type(d).__name__")"
assert_eq "serialized RMW: SessionStart has exactly 1 entry (no lost update, no duplicate)" "1" "$(json_get "$f" "len(d['hooks']['SessionStart'])")"
assert_eq "serialized RMW: PostToolUse has exactly 1 entry" "1" "$(json_get "$f" "len(d['hooks']['PostToolUse'])")"

# 10. Stale-lock, LIVE owner: a leftover lock dir owned by a genuinely
#     alive process, with an mtime well past the timeout, must NOT be
#     stolen. The competing install waits and then fails by its own
#     overall timeout; the settings.json from the prior successful install
#     above must be completely untouched by the failed attempt.
home="$(make_fake_home)"
f="$home/.claude/settings.json"
env "${WH_ENV[@]}" HOME="$home" bash "$INSTALL_HOOKS_SCRIPT" >/dev/null 2>&1
sha_before="$(_sha "$f")"
( sleep 30 ) &
live_pid=$!
lockdir="$home/.claude/settings.json.lockdir"
mkdir -p "$lockdir"
echo "$live_pid" >"$lockdir/pid"
python3 -c "import os,time; os.utime('$lockdir', (time.time()-300, time.time()-300))"
rc=0
err="$(env WIKI_HOOKS_FORCE_MKDIR_LOCK=1 WIKI_HOOKS_LOCK_TIMEOUT=1 WIKI_HOOKS_LOCK_POLL=0.1 HOME="$home" bash "$INSTALL_HOOKS_SCRIPT" 2>&1 >/dev/null)" || rc=$?
assert_eq "stale-lock live-owner: competing install fails by overall timeout (does not steal)" "1" "$rc"
assert_file_unchanged "stale-lock live-owner: settings.json untouched by the failed attempt" "$f" "$sha_before"
kill "$live_pid" 2>/dev/null || true
wait "$live_pid" 2>/dev/null || true
rm -rf "$lockdir"

# 11. Stale-lock recovery, mkdir-fallback, DEAD pid: a leftover lock dir
#     whose pid file names a process that no longer exists must be forced
#     clear immediately (no deadlock), and the install proceeds to
#     completion.
home="$(make_fake_home)"
f="$home/.claude/settings.json"
lockdir="$home/.claude/settings.json.lockdir"
mkdir -p "$lockdir"
echo 999999 >"$lockdir/pid" # astronomically unlikely to be a live pid
rc=0
env WIKI_HOOKS_FORCE_MKDIR_LOCK=1 WIKI_HOOKS_LOCK_TIMEOUT=3 WIKI_HOOKS_LOCK_POLL=0.1 HOME="$home" bash "$INSTALL_HOOKS_SCRIPT" >/dev/null 2>err.$$ || rc=$?
dead_pid_err="$(cat "err.$$" 2>/dev/null)"; rm -f "err.$$"
assert_eq "stale-lock recovery (dead pid): install still succeeds" "0" "$rc"
assert_eq "stale-lock recovery (dead pid): SessionStart has 1 entry" "1" "$(json_get "$f" "len(d['hooks']['SessionStart'])")"
[ -d "$lockdir" ] && FAIL=$((FAIL + 1)) && echo "FAIL: stale-lock recovery (dead pid): lock dir cleaned up" >&2 || PASS=$((PASS + 1))

# 11b. Stale-lock recovery, mkdir-fallback, NO pid file at all (crash
#      between mkdir and pid write) + mtime older than timeout -> forced
#      clear, install proceeds.
home="$(make_fake_home)"
f="$home/.claude/settings.json"
lockdir="$home/.claude/settings.json.lockdir"
mkdir -p "$lockdir"
python3 -c "import os,time; os.utime('$lockdir', (time.time()-300, time.time()-300))"
rc=0
env WIKI_HOOKS_FORCE_MKDIR_LOCK=1 WIKI_HOOKS_LOCK_TIMEOUT=3 WIKI_HOOKS_LOCK_POLL=0.1 HOME="$home" bash "$INSTALL_HOOKS_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "stale-lock recovery (no pid file, old mtime): install still succeeds" "0" "$rc"
assert_eq "stale-lock recovery (no pid file, old mtime): SessionStart has 1 entry" "1" "$(json_get "$f" "len(d['hooks']['SessionStart'])")"

# 12. Interrupt while holding the mkdir-fallback lock: the EXIT/INT/TERM
#     trap must remove the lock dir completely, never leaving a deadlock
#     for the next run. WIKI_HOOKS_TEST_SLEEP_AFTER_LOCK holds the lock
#     open long enough to reliably deliver SIGTERM mid-critical-section.
home="$(make_fake_home)"
f="$home/.claude/settings.json"
lockdir="$home/.claude/settings.json.lockdir"
env WIKI_HOOKS_FORCE_MKDIR_LOCK=1 WIKI_HOOKS_TEST_SLEEP_AFTER_LOCK=5 HOME="$home" bash "$INSTALL_HOOKS_SCRIPT" >/dev/null 2>&1 &
interrupted_pid=$!
# Poll for the lock dir to appear instead of a fixed sleep, so this isn't
# racy under slow/loaded CI.
wait_start="$(date +%s)"
while [ ! -d "$lockdir" ]; do
  now="$(date +%s)"
  if [ $((now - wait_start)) -ge 5 ]; then
    break
  fi
done
kill -TERM "$interrupted_pid" 2>/dev/null || true
wait "$interrupted_pid" 2>/dev/null || true
assert_eq "interrupt-under-lock: trap removes lock dir, no deadlock leftover" "" "$([ -d "$lockdir" ] && echo present)"
rc=0
env WIKI_HOOKS_FORCE_MKDIR_LOCK=1 WIKI_HOOKS_LOCK_TIMEOUT=3 WIKI_HOOKS_LOCK_POLL=0.1 HOME="$home" bash "$INSTALL_HOOKS_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "interrupt-under-lock: next install proceeds normally (not deadlocked)" "0" "$rc"
assert_eq "interrupt-under-lock: settings.json ends up valid with 1 SessionStart entry" "1" "$(json_get "$f" "len(d['hooks']['SessionStart'])")"

# Lock-primitive unification (codex-атк P1): install and uninstall must guard
# settings.json with ONE shared mutex (the mkdir lock-directory), never a
# flock-when-available / mkdir-otherwise split — an flock holder and a
# concurrent mkdir holder (missing flock, or WIKI_HOOKS_FORCE_MKDIR_LOCK) do
# not exclude each other. Assert statically that neither script makes an
# `flock -w` call and that both acquire the mkdir lock unconditionally.
for sc in "$INSTALL_HOOKS_SCRIPT" "$UNINSTALL_HOOKS_SCRIPT"; do
  n="$(basename "$sc")"
  assert_eq "lock-unify: $n makes no flock -w call" "0" "$(grep -c 'flock -w' "$sc")"
  assert_eq "lock-unify: $n acquires the mkdir lock unconditionally" "yes" \
    "$(grep -qE '^acquire_mkdir \|\| fail' "$sc" && echo yes || echo no)"
done

# ---- summary ----
echo "" >&2
echo "pass: $PASS  fail: $FAIL" >&2
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
