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

# ---- summary ----
echo "" >&2
echo "pass: $PASS  fail: $FAIL" >&2
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
