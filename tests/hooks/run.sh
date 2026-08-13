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
SESSION_START_QWEN_HOOK="$ROOT/hooks/session-start-qwen.sh"
POST_TOOL_USE_HOOK="$ROOT/hooks/post-tool-use.sh"
INSTALL_HOOKS_SCRIPT="$ROOT/hooks/install-hooks.sh"
UNINSTALL_HOOKS_SCRIPT="$ROOT/hooks/uninstall-hooks.sh"
SETTINGS_LOCK_LIB="$ROOT/hooks/lib/settings-lock.sh"

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

# 12d. old one-line pointer format that points directly AT schema.md (the
#      documented old pointer shape, e.g. `knowledge/wiki/schema.md`) must
#      still resolve the containing wiki dir, not be treated as a
#      directory itself (which would look for
#      knowledge/wiki/schema.md/index.md and silently fail, masking a
#      valid non-default/custom wiki — fixwave0-4).
fixture="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-test.XXXXXX")"
track_tmp "$fixture"
( cd "$fixture" && git init -q )
mkdir -p "$fixture/knowledge/wiki"
printf 'custom wiki index' >"$fixture/knowledge/wiki/index.md"
cat >"$fixture/CLAUDE.md" <<'EOF'
## Wiki

Wiki schema at `knowledge/wiki/schema.md`.
EOF
expected="$(real "$fixture/knowledge/wiki")"
out="$(discover_wiki "$fixture" 2>/dev/null)"
assert_eq "old schema.md pointer resolves to its containing wiki dir" "$expected" "$out"

# 12e. same, but the old one-line pointer points directly AT index.md
#      instead of schema.md (e.g. `knowledge/wiki/index.md`) — must also
#      normalize down to the containing dir before appending index.md.
fixture="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-test.XXXXXX")"
track_tmp "$fixture"
( cd "$fixture" && git init -q )
mkdir -p "$fixture/knowledge/wiki"
printf 'custom wiki index' >"$fixture/knowledge/wiki/index.md"
cat >"$fixture/CLAUDE.md" <<'EOF'
## Wiki

Wiki index at `knowledge/wiki/index.md`.
EOF
expected="$(real "$fixture/knowledge/wiki")"
out="$(discover_wiki "$fixture" 2>/dev/null)"
assert_eq "old index.md pointer resolves to its containing wiki dir" "$expected" "$out"

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

# ---- QWEN.md pointer + QWEN_PROJECT_DIR anchor (v4.6.0 Task 1) ----

# 14. QWEN.md only: no CLAUDE.md/AGENTS.md/GEMINI.md present, a pointer in
#     QWEN.md alone must resolve the wiki (QWEN.md appended last, still
#     consulted).
fixture="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-test.XXXXXX")"
track_tmp "$fixture"
( cd "$fixture" && git init -q )
mkdir -p "$fixture/from-qwen/wiki"
printf 'qwen index' >"$fixture/from-qwen/wiki/index.md"
cat >"$fixture/QWEN.md" <<'EOF'
## Wiki

Wiki at `from-qwen/wiki`.
EOF
expected="$(real "$fixture/from-qwen/wiki")"
out="$(discover_wiki "$fixture" 2>/dev/null)"
assert_eq "QWEN.md-only: pointer in QWEN.md alone resolves the wiki" "$expected" "$out"

# 15. CLAUDE.md and QWEN.md both valid but pointing at DIFFERENT wikis:
#     CLAUDE.md wins (higher priority, first in the consult order).
fixture="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-test.XXXXXX")"
track_tmp "$fixture"
( cd "$fixture" && git init -q )
mkdir -p "$fixture/from-claude/wiki" "$fixture/from-qwen/wiki"
printf 'claude index' >"$fixture/from-claude/wiki/index.md"
printf 'qwen index' >"$fixture/from-qwen/wiki/index.md"
cat >"$fixture/CLAUDE.md" <<'EOF'
## Wiki

Wiki at `from-claude/wiki`.
EOF
cat >"$fixture/QWEN.md" <<'EOF'
## Wiki

Wiki at `from-qwen/wiki`.
EOF
expected="$(real "$fixture/from-claude/wiki")"
out="$(discover_wiki "$fixture" 2>/dev/null)"
assert_eq "CLAUDE.md and QWEN.md both valid: CLAUDE.md wins" "$expected" "$out"

# 16. stale/broken pointer in CLAUDE.md must not mask a valid QWEN.md
#     pointer in the same directory (agent-neutral scan continues past a
#     broken higher-priority file, mirrors the AGENTS.md/GEMINI.md case).
fixture="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-test.XXXXXX")"
track_tmp "$fixture"
( cd "$fixture" && git init -q )
mkdir -p "$fixture/from-qwen/wiki"
printf 'qwen index' >"$fixture/from-qwen/wiki/index.md"
cat >"$fixture/CLAUDE.md" <<'EOF'
## Wiki

Wiki at `moved/away/long/ago`.
EOF
cat >"$fixture/QWEN.md" <<'EOF'
## Wiki

Wiki at `from-qwen/wiki`.
EOF
expected="$(real "$fixture/from-qwen/wiki")"
out="$(discover_wiki "$fixture" 2>/dev/null)"
assert_eq "stale CLAUDE.md pointer does not mask valid QWEN.md pointer beside it" "$expected" "$out"

# 17. QWEN_PROJECT_DIR as the start-point anchor when CLAUDE_PROJECT_DIR is
#     unset: run discover_wiki with no start_dir arg from an unrelated cwd,
#     env -u CLAUDE_PROJECT_DIR, QWEN_PROJECT_DIR pointing at the fixture.
fixture="$(make_fixture)"
unrelated_cwd="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-test.XXXXXX")"
track_tmp "$unrelated_cwd"
expected="$(real "$fixture/docs/wiki")"
out="$(
  cd "$unrelated_cwd" && env -u CLAUDE_PROJECT_DIR QWEN_PROJECT_DIR="$fixture" \
    bash -c "source '$DISCOVER_LIB'; discover_wiki" 2>/dev/null
)"
assert_eq "QWEN_PROJECT_DIR anchors discovery when CLAUDE_PROJECT_DIR is unset" "$expected" "$out"

# 18. both CLAUDE_PROJECT_DIR and QWEN_PROJECT_DIR set to DIFFERENT
#     fixtures: CLAUDE_PROJECT_DIR wins (spec edge 11).
claude_fixture="$(make_fixture)"
qwen_fixture="$(make_fixture)"
expected="$(real "$claude_fixture/docs/wiki")"
out="$(
  CLAUDE_PROJECT_DIR="$claude_fixture" QWEN_PROJECT_DIR="$qwen_fixture" \
    bash -c "source '$DISCOVER_LIB'; discover_wiki" 2>/dev/null
)"
assert_eq "CLAUDE_PROJECT_DIR wins over QWEN_PROJECT_DIR when both are set" "$expected" "$out"

# 19. out-of-bounds pointer in QWEN.md: pointer resolves outside the git
#     boundary -> rejected, empty stdout, stderr carries the boundary note
#     (mirrors the existing out-of-bounds CLAUDE.md coverage; boundary-guard
#     itself is untouched by this task).
fixture="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-test.XXXXXX")"
track_tmp "$fixture"
( cd "$fixture" && git init -q )
cat >"$fixture/QWEN.md" <<'EOF'
## Wiki

Wiki at `../../../../../../etc`.
EOF
out="$(discover_wiki "$fixture" 2>/dev/null)"
err="$(discover_wiki "$fixture" 2>&1 >/dev/null)"
assert_eq "out-of-bounds QWEN.md pointer: empty stdout" "" "$out"
assert_contains "out-of-bounds QWEN.md pointer: stderr notes boundary rejection" "$err" "поза межами репо"

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

# k. frontmatter wiki_version "4.1" (a MINOR bump within the current
#    MAJOR) -> writable true. Only an exact-string "4.0" match used to
#    pass; a v4.5-skill-valid "4.1" wiki must gate open the same as
#    "4.0" (fixwave0-3: schema major gate).
fixture="$(make_fixture)"
wiki="$fixture/docs/wiki"
cat >"$wiki/schema.md" <<'EOF'
---
wiki_version: "4.1"
---

# Schema
EOF
if wiki_writable "$wiki"; then r=0; else r=1; fi
assert_eq "wiki_writable: version 4.1 (major 4) -> true" "0" "$r"
if wiki_bootstrappable "$wiki"; then r=0; else r=1; fi
assert_eq "wiki_bootstrappable: version 4.1, .usage.json present -> false" "1" "$r"

# k2. same, but .usage.json absent -> bootstrappable true, mirroring the
#     "4.0" behavior in test b for a "4.1" wiki.
fixture="$(make_fixture)"
wiki="$fixture/docs/wiki"
cat >"$wiki/schema.md" <<'EOF'
---
wiki_version: "4.1"
---

# Schema
EOF
rm -f "$wiki/.usage.json"
if wiki_writable "$wiki"; then r=0; else r=1; fi
assert_eq "wiki_writable: version 4.1, .usage.json absent -> false" "1" "$r"
if wiki_bootstrappable "$wiki"; then r=0; else r=1; fi
assert_eq "wiki_bootstrappable: version 4.1, .usage.json absent -> true" "0" "$r"

# l. frontmatter wiki_version "4.5" -> also writable true (any 4.x is
#    current per the v4.5 skill's versioning contract).
fixture="$(make_fixture)"
wiki="$fixture/docs/wiki"
cat >"$wiki/schema.md" <<'EOF'
---
wiki_version: "4.5"
---

# Schema
EOF
if wiki_writable "$wiki"; then r=0; else r=1; fi
assert_eq "wiki_writable: version 4.5 (major 4) -> true" "0" "$r"

# m. frontmatter wiki_version "4" (bare major, no dot at all) -> also
#    accepted, per "keep it robust to values like '4', '4.1', '4.5'".
fixture="$(make_fixture)"
wiki="$fixture/docs/wiki"
cat >"$wiki/schema.md" <<'EOF'
---
wiki_version: "4"
---

# Schema
EOF
if wiki_writable "$wiki"; then r=0; else r=1; fi
assert_eq "wiki_writable: bare version 4 (no dot) -> true" "0" "$r"

# n. frontmatter wiki_version "40" -> major-only compare must NOT treat
#    this as major 4 via a loose prefix match; "40" is a different major
#    entirely and must stay rejected.
fixture="$(make_fixture)"
wiki="$fixture/docs/wiki"
cat >"$wiki/schema.md" <<'EOF'
---
wiki_version: "40"
---

# Schema
EOF
if wiki_writable "$wiki"; then r=0; else r=1; fi
assert_eq "wiki_writable: version 40 -> false (not major 4 via prefix match)" "1" "$r"

# o. frontmatter wiki_version "5.0" (a genuinely newer major) -> still
#    rejected — the major gate is 4, not "4 or newer".
fixture="$(make_fixture)"
wiki="$fixture/docs/wiki"
cat >"$wiki/schema.md" <<'EOF'
---
wiki_version: "5.0"
---

# Schema
EOF
if wiki_writable "$wiki"; then r=0; else r=1; fi
assert_eq "wiki_writable: version 5.0 -> false (major 5 != current major 4)" "1" "$r"

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

# FIFO .usage.json must NEVER hang Claude Code startup (agy-атк P0, wave3):
# the read is O_NONBLOCK + S_ISREG-guarded, so the hook returns promptly,
# still exits 0, and the read-only index injection still happens.
fixture="$(make_fixture)"
rm -f "$fixture/docs/wiki/.usage.json"
mkfifo "$fixture/docs/wiki/.usage.json"
if command -v timeout >/dev/null 2>&1; then
  _timeout="timeout 10"
elif command -v gtimeout >/dev/null 2>&1; then
  _timeout="gtimeout 10"
else
  _timeout=""
fi
out="$(CLAUDE_PROJECT_DIR="$fixture" $_timeout bash "$SESSION_START_HOOK" 2>/dev/null)"
rc=$?
assert_eq "session-start: FIFO .usage.json -> returns promptly, exit 0 (never blocks startup)" "0" "$rc"
assert_contains "session-start: FIFO .usage.json -> index still injected (read-only degrade)" "$out" "=== WIKI INDEX (hook-injected) ==="
rm -f "$fixture/docs/wiki/.usage.json"

# 8. Fresh checkout: current-schema wiki but .usage.json is entirely ABSENT
#    (gitignored sidecar, never checked out) -> the heartbeat must still be
#    written on this very first session by bootstrapping a minimal valid
#    .usage.json, rather than skipping the write because wiki_writable()
#    requires the file to already exist (fixwave0-8).
fixture="$(make_fixture)"
rm -f "$fixture/docs/wiki/.usage.json"
out="$(CLAUDE_PROJECT_DIR="$fixture" bash "$SESSION_START_HOOK" 2>/dev/null)"
rc=$?
assert_eq "session-start: fresh checkout (no .usage.json) -> exit 0" "0" "$rc"
assert_contains "session-start: fresh checkout -> index still injected" "$out" "=== WIKI INDEX (hook-injected) ==="
if [ -f "$fixture/docs/wiki/.usage.json" ]; then r=0; else r=1; fi
assert_eq "session-start: fresh checkout -> .usage.json bootstrapped" "0" "$r"
sa="$(python3 -c "import json; d=json.load(open('$fixture/docs/wiki/.usage.json')); print(d.get('_hooks',{}).get('session_start_at',''))" 2>/dev/null)"
if [ -n "$sa" ]; then r=0; else r=1; fi
assert_eq "session-start: fresh checkout -> heartbeat written on first session" "0" "$r"
hv="$(python3 -c "import json; d=json.load(open('$fixture/docs/wiki/.usage.json')); print(d.get('_hooks',{}).get('hook_version',''))" 2>/dev/null)"
assert_eq "session-start: fresh checkout -> hook_version=1 written on bootstrap" "1" "$hv"
if python3 -c "import json; json.load(open('$fixture/docs/wiki/.usage.json'))" 2>/dev/null; then r=0; else r=1; fi
assert_eq "session-start: fresh checkout -> bootstrapped .usage.json is valid JSON" "0" "$r"
if [ -L "$fixture/docs/wiki/.usage.json" ]; then r=1; else r=0; fi
assert_eq "session-start: fresh checkout -> bootstrapped .usage.json is a real file, not a symlink" "0" "$r"

# 8b. Fresh checkout + LEGACY schema (not current version) -> the version
#     gate still wins over bootstrap: .usage.json must stay entirely absent.
fixture="$(make_fixture)"
rm -f "$fixture/docs/wiki/.usage.json"
cat >"$fixture/docs/wiki/schema.md" <<'EOF'
---
wiki_version: "3.0"
---

# Schema
EOF
CLAUDE_PROJECT_DIR="$fixture" bash "$SESSION_START_HOOK" >/dev/null 2>&1
if [ -e "$fixture/docs/wiki/.usage.json" ]; then r=0; else r=1; fi
assert_eq "session-start: fresh checkout + legacy schema -> .usage.json NOT created" "1" "$r"

echo "=== session-start-qwen.sh ===" >&2

# session-start-qwen.sh is a standalone hook process (exit on every path)
# — run as a subprocess, never sourced.

# 1. Happy path: valid wiki -> exit 0, stdout is valid single-line JSON
#    wrapping the canonical hook's index injection.
fixture="$(make_fixture)"
out="$(CLAUDE_PROJECT_DIR="$fixture" bash "$SESSION_START_QWEN_HOOK" 2>/dev/null)"
rc=$?
assert_eq "session-start-qwen: exit 0 on valid wiki" "0" "$rc"
if printf '%s' "$out" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then r=0; else r=1; fi
assert_eq "session-start-qwen: stdout parses as JSON" "0" "$r"

# 2. Envelope shape: continue is True; hookEventName == "SessionStart".
cont="$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["continue"])')"
assert_eq "session-start-qwen: continue is True" "True" "$cont"
evt="$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["hookEventName"])')"
assert_eq "session-start-qwen: hookEventName == SessionStart" "SessionStart" "$evt"

# 3. additionalContext carries the canonical hook's WIKI INDEX block and
#    the mandatory untrusted-data label (exact string from
#    hooks/session-start.sh's preamble).
actx="$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])')"
assert_contains "session-start-qwen: additionalContext has WIKI INDEX marker" "$actx" "=== WIKI INDEX (hook-injected) ==="
assert_contains "session-start-qwen: additionalContext has untrusted-data label" "$actx" "НЕ інструкції"

# 4. stdout is EXACTLY one line.
lc="$(printf '%s' "$out" | grep -c '^')"
assert_eq "session-start-qwen: stdout is exactly one line" "1" "$lc"

# 5. No wiki discoverable (git repo, no pointer, no docs/wiki/) -> stdout
#    empty, exit 0.
fixture="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-test.XXXXXX")"
track_tmp "$fixture"
( cd "$fixture" && git init -q )
out="$(CLAUDE_PROJECT_DIR="$fixture" bash "$SESSION_START_QWEN_HOOK" 2>/dev/null)"
rc=$?
assert_eq "session-start-qwen: no wiki -> empty stdout" "" "$out"
assert_eq "session-start-qwen: no wiki -> exit 0" "0" "$rc"

# 6. Non-git directory -> stdout empty, exit 0 (fail-closed inherited from
#    the canonical hook's discovery).
fixture="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-test.XXXXXX")"
track_tmp "$fixture"
out="$(CLAUDE_PROJECT_DIR="$fixture" bash "$SESSION_START_QWEN_HOOK" 2>/dev/null)"
rc=$?
assert_eq "session-start-qwen: non-git dir -> empty stdout" "" "$out"
assert_eq "session-start-qwen: non-git dir -> exit 0" "0" "$rc"

# 7. No python3 on PATH (curated PATH technique, mirrors the post-tool-use
#    "no python3" test) -> stdout empty, exit 0.
fixture="$(make_fixture)"
curated_path_dir="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-nopython.XXXXXX")"
track_tmp "$curated_path_dir"
for _tool in bash dirname basename realpath sed cat git; do
  _tool_src="$(command -v "$_tool" 2>/dev/null)"
  [ -n "$_tool_src" ] && ln -s "$_tool_src" "$curated_path_dir/$_tool"
done
out="$(CLAUDE_PROJECT_DIR="$fixture" PATH="$curated_path_dir" bash "$SESSION_START_QWEN_HOOK" 2>/dev/null)"
rc=$?
assert_eq "session-start-qwen: no python3 -> empty stdout" "" "$out"
assert_eq "session-start-qwen: no python3 -> exit 0" "0" "$rc"

# 8. stderr from the child hook never leaks into stdout: an out-of-bounds
#    CLAUDE.md pointer makes the canonical hook write a
#    "поза межами репо" notice to ITS stderr. The wrapper's stdout must
#    stay either empty or valid JSON, and must never contain that stderr
#    substring.
fixture="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-test.XXXXXX")"
track_tmp "$fixture"
( cd "$fixture" && git init -q )
cat >"$fixture/CLAUDE.md" <<'EOF'
# Test Project

## Wiki

Wiki at `../outside-of-repo/docs/wiki`. Schema -> `../outside-of-repo/docs/wiki/schema.md`. Skill: `wiki`.
EOF
out="$(CLAUDE_PROJECT_DIR="$fixture" bash "$SESSION_START_QWEN_HOOK" 2>/dev/null)"
rc=$?
assert_eq "session-start-qwen: out-of-bounds pointer -> exit 0" "0" "$rc"
if [ -z "$out" ]; then
  r=0
elif printf '%s' "$out" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
  r=0
else
  r=1
fi
assert_eq "session-start-qwen: out-of-bounds pointer -> stdout empty or valid JSON" "0" "$r"
assert_not_contains "session-start-qwen: child stderr does not leak into stdout" "$out" "поза межами репо"

# 9. Wrapper file is executable.
if [ -x "$SESSION_START_QWEN_HOOK" ]; then r=0; else r=1; fi
assert_eq "session-start-qwen: file is executable" "0" "$r"

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

_ptu_keys() {
  # $1 = .usage.json path. Comma-joined sorted list of every non-`_` top
  # level key (i.e. every page record actually present) — proves "no
  # phantom records exist at all", not merely a counter value.
  python3 -c "
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: d={}
print(','.join(sorted(k for k in d if not k.startswith('_'))))
" "$1" 2>/dev/null
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

# 4b. Read an ARCHIVED LOG SHARD under {wiki}/log/ -> excluded, not counted
#     (wiki-structure.md "Out of scope": "Shards are not tracked in
#     {wiki}/.usage.json. Telemetry tracks knowledge pages, not the log
#     substrate."). A shard basename like `2026-01-01_to_2026-01-02.md`
#     passes the *.md filter and is not one of index.md/schema.md/log.md,
#     so without a log/-subtree guard it would get a phantom page record.
fixture="$(make_fixture)"
mkdir -p "$fixture/docs/wiki/log"
cat >"$fixture/docs/wiki/log/2026-01-01_to_2026-01-02.md" <<'EOF'
## [2026-01-01] init | Foo
EOF
sha_before="$(_sha "$fixture/docs/wiki/.usage.json")"
_ptu_stdin "Read" "$fixture/docs/wiki/log/2026-01-01_to_2026-01-02.md" | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1
assert_file_unchanged "post-tool-use: Read archived log shard not counted" "$fixture/docs/wiki/.usage.json" "$sha_before"
key_present="$(python3 -c "
import json
d = json.load(open('$fixture/docs/wiki/.usage.json'))
print(any(k.startswith('log/') for k in d.keys()))
" 2>/dev/null)"
assert_eq "post-tool-use: no log/-prefixed phantom page record created" "False" "$key_present"

# 4c. Write/Edit an archived log shard -> also excluded (not just Read).
fixture="$(make_fixture)"
mkdir -p "$fixture/docs/wiki/log"
cat >"$fixture/docs/wiki/log/2026-02-01_to_2026-02-02.md" <<'EOF'
## [2026-02-01] init | Bar
EOF
sha_before="$(_sha "$fixture/docs/wiki/.usage.json")"
_ptu_stdin "Edit" "$fixture/docs/wiki/log/2026-02-01_to_2026-02-02.md" | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1
assert_file_unchanged "post-tool-use: Edit archived log shard not counted" "$fixture/docs/wiki/.usage.json" "$sha_before"

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

# 9b. Concurrent bumps are serialized by the wiki-dir flock (agy-атк P1,
#     wave3): N overlapping hook invocations on the SAME page must all
#     survive — before the lock, overlapping read-modify-write lost
#     increments (last rename wins). Deterministic with the lock: exactly N.
fixture="$(make_fixture)"
printf 'body\n' >"$fixture/docs/wiki/foo.md"
_ptu_n=6
_ptu_pids=()
for _ in $(seq 1 "$_ptu_n"); do
  _ptu_stdin "Read" "$fixture/docs/wiki/foo.md" | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1 &
  _ptu_pids+=("$!")
done
for _p in "${_ptu_pids[@]}"; do
  wait "$_p" 2>/dev/null || true
done
assert_eq "post-tool-use: $_ptu_n concurrent bumps all survive (flock serializes RMW)" \
  "$_ptu_n" "$(_ptu_field "$fixture/docs/wiki/.usage.json" "foo.md" "view_count")"

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
  "1" "$(_ptu_field "$u" "foo.md" "view_count")"

# 11. MultiEdit with a top-level tool_input.file_path (the Edit/Write-like
#     shape) bumps patch_count same as Edit/Write — this shape already
#     worked before fixwave0-3, kept as a guard against regressing it.
fixture="$(make_fixture)"
printf 'body\n' >"$fixture/docs/wiki/foo.md"
_ptu_stdin "MultiEdit" "$fixture/docs/wiki/foo.md" | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1
assert_eq "post-tool-use: MultiEdit (top-level file_path) bumps patch_count to 1" \
  "1" "$(_ptu_field "$fixture/docs/wiki/.usage.json" "foo.md" "patch_count")"

# 12. fixwave0-3 P1: MultiEdit whose tool_input carries NO top-level
#     file_path at all, only a `edits[]` array where each entry carries its
#     own `file_path` — telemetry must still be bumped (this is the shape
#     that used to be silently skipped entirely).
fixture="$(make_fixture)"
printf 'body\n' >"$fixture/docs/wiki/foo.md"
printf '{"tool_name":"MultiEdit","tool_input":{"edits":[{"file_path":"%s","old_string":"a","new_string":"b"}]}}' \
  "$fixture/docs/wiki/foo.md" | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1
rc=$?
assert_eq "post-tool-use: MultiEdit edits[].file_path (no top-level file_path) exits 0" "0" "$rc"
assert_eq "post-tool-use: MultiEdit edits[].file_path bumps patch_count to 1" \
  "1" "$(_ptu_field "$fixture/docs/wiki/.usage.json" "foo.md" "patch_count")"

# 13. fixwave0-3 P1: a single MultiEdit call whose edits[] touches TWO
#     distinct wiki pages must bump BOTH records — no edit target is
#     dropped just because it isn't the (possibly absent) top-level
#     file_path.
fixture="$(make_fixture)"
printf 'body\n' >"$fixture/docs/wiki/foo.md"
printf 'body\n' >"$fixture/docs/wiki/bar.md"
printf '{"tool_name":"MultiEdit","tool_input":{"edits":[{"file_path":"%s","old_string":"a","new_string":"b"},{"file_path":"%s","old_string":"c","new_string":"d"}]}}' \
  "$fixture/docs/wiki/foo.md" "$fixture/docs/wiki/bar.md" \
  | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1
assert_eq "post-tool-use: MultiEdit multi-file edits[] bumps first file" \
  "1" "$(_ptu_field "$fixture/docs/wiki/.usage.json" "foo.md" "patch_count")"
assert_eq "post-tool-use: MultiEdit multi-file edits[] bumps second file" \
  "1" "$(_ptu_field "$fixture/docs/wiki/.usage.json" "bar.md" "patch_count")"

# 14. fixwave0-3: a path present as BOTH the top-level file_path AND (again)
#     inside edits[] must only be bumped ONCE (de-dup, not double-counted).
fixture="$(make_fixture)"
printf 'body\n' >"$fixture/docs/wiki/foo.md"
printf '{"tool_name":"MultiEdit","tool_input":{"file_path":"%s","edits":[{"file_path":"%s","old_string":"a","new_string":"b"},{"old_string":"c","new_string":"d"}]}}' \
  "$fixture/docs/wiki/foo.md" "$fixture/docs/wiki/foo.md" \
  | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1
assert_eq "post-tool-use: MultiEdit same path in file_path + edits[] bumps once (no double count)" \
  "1" "$(_ptu_field "$fixture/docs/wiki/.usage.json" "foo.md" "patch_count")"

# ---- v46-qwen Task 2: action-gate on Qwen tool names before path
#      extraction, union with Claude's tool names, QWEN_PROJECT_DIR anchor
#      rung. Stdin keys (edits[]/notebook_path/path) are NOT touched here
#      — that is Task 3.

# 16. Qwen `read_file` (absolute tool_input.file_path) bumps view_count
#     same as Claude's Read.
fixture="$(make_fixture)"
printf 'body\n' >"$fixture/docs/wiki/foo.md"
_ptu_stdin "read_file" "$fixture/docs/wiki/foo.md" | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1
rc=$?
assert_eq "post-tool-use: qwen read_file exits 0" "0" "$rc"
assert_eq "post-tool-use: qwen read_file bumps view_count to 1" \
  "1" "$(_ptu_field "$fixture/docs/wiki/.usage.json" "foo.md" "view_count")"

# 17. Qwen `edit`, `write_file`, `replace` each bump patch_count same as
#     Claude's Edit/Write (`replace` is Qwen's legacy alias for `edit`).
for _qwen_tool in edit write_file replace; do
  fixture="$(make_fixture)"
  printf 'body\n' >"$fixture/docs/wiki/foo.md"
  _ptu_stdin "$_qwen_tool" "$fixture/docs/wiki/foo.md" | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1
  assert_eq "post-tool-use: qwen $_qwen_tool bumps patch_count to 1" \
    "1" "$(_ptu_field "$fixture/docs/wiki/.usage.json" "foo.md" "patch_count")"
done

# 18. Qwen `notebook_edit` with a top-level file_path bumps patch_count
#     (the edits[]/notebook_path variant belongs to Task 3).
fixture="$(make_fixture)"
printf 'body\n' >"$fixture/docs/wiki/foo.md"
_ptu_stdin "notebook_edit" "$fixture/docs/wiki/foo.md" | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1
assert_eq "post-tool-use: qwen notebook_edit (file_path) bumps patch_count to 1" \
  "1" "$(_ptu_field "$fixture/docs/wiki/.usage.json" "foo.md" "patch_count")"

# 19. _hooks.post_tool_use_at is stamped after a qwen tool call too, not
#     only Claude ones.
fixture="$(make_fixture)"
printf 'body\n' >"$fixture/docs/wiki/foo.md"
_ptu_stdin "read_file" "$fixture/docs/wiki/foo.md" | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1
pta="$(python3 -c "
import json
d = json.load(open('$fixture/docs/wiki/.usage.json'))
print(d.get('_hooks', {}).get('post_tool_use_at', ''))
" 2>/dev/null)"
if [ -n "$pta" ]; then r=0; else r=1; fi
assert_eq "post-tool-use: _hooks.post_tool_use_at set after qwen call" "0" "$r"

# 20. Relative file_path resolves against QWEN_PROJECT_DIR when
#     CLAUDE_PROJECT_DIR is unset and the hook runs from a subdir (anchor
#     precedence rung 2).
fixture="$(make_fixture)"
printf 'body\n' >"$fixture/docs/wiki/foo.md"
mkdir -p "$fixture/some/other/subdir"
printf '{"tool_name":"read_file","tool_input":{"file_path":"docs/wiki/foo.md"}}' \
  | ( cd "$fixture/some/other/subdir" && env -u CLAUDE_PROJECT_DIR QWEN_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1 )
assert_eq "post-tool-use: relative file_path resolves against QWEN_PROJECT_DIR when CLAUDE_PROJECT_DIR unset" \
  "1" "$(_ptu_field "$fixture/docs/wiki/.usage.json" "foo.md" "view_count")"

# 21. CLAUDE_PROJECT_DIR and QWEN_PROJECT_DIR set to DIFFERENT fixtures ->
#     CLAUDE_PROJECT_DIR wins, only its wiki is bumped.
claude_fixture="$(make_fixture)"
printf 'body\n' >"$claude_fixture/docs/wiki/foo.md"
qwen_fixture="$(make_fixture)"
printf 'body\n' >"$qwen_fixture/docs/wiki/foo.md"
_ptu_stdin "read_file" "$claude_fixture/docs/wiki/foo.md" \
  | CLAUDE_PROJECT_DIR="$claude_fixture" QWEN_PROJECT_DIR="$qwen_fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1
assert_eq "post-tool-use: CLAUDE_PROJECT_DIR wins over QWEN_PROJECT_DIR -> claude wiki bumped" \
  "1" "$(_ptu_field "$claude_fixture/docs/wiki/.usage.json" "foo.md" "view_count")"
assert_eq "post-tool-use: CLAUDE_PROJECT_DIR wins over QWEN_PROJECT_DIR -> qwen wiki untouched" \
  "" "$(_ptu_field "$qwen_fixture/docs/wiki/.usage.json" "foo.md" "view_count")"

# 22. Qwen `run_shell_command` (not in the allowlist) -> exit 0,
#     .usage.json byte-for-byte unchanged.
fixture="$(make_fixture)"
printf 'body\n' >"$fixture/docs/wiki/foo.md"
sha_before="$(_sha "$fixture/docs/wiki/.usage.json")"
printf '{"tool_name":"run_shell_command","tool_input":{"command":"ls"}}' \
  | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1
rc=$?
assert_eq "post-tool-use: qwen run_shell_command exits 0" "0" "$rc"
assert_file_unchanged "post-tool-use: qwen run_shell_command -> .usage.json unchanged" \
  "$fixture/docs/wiki/.usage.json" "$sha_before"

# 23. Action-gate-first regression: tool_name run_shell_command with an
#     EMPTY tool_input (no file_path at all) -> exit 0, empty stdout,
#     .usage.json unchanged — the allowlist gate must fire on tool_name
#     alone, not merely as a side effect of file_paths being empty.
fixture="$(make_fixture)"
sha_before="$(_sha "$fixture/docs/wiki/.usage.json")"
out="$(printf '{"tool_name":"run_shell_command","tool_input":{}}' \
  | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" 2>&1)"
rc=$?
assert_eq "post-tool-use: action-gate-first regression exits 0" "0" "$rc"
assert_eq "post-tool-use: action-gate-first regression -> empty stdout" "" "$out"
assert_file_unchanged "post-tool-use: action-gate-first regression -> .usage.json unchanged" \
  "$fixture/docs/wiki/.usage.json" "$sha_before"

# 24. Qwen read_file outside the wiki -> .usage.json unchanged
#     (boundary-guard, same posture as Claude's Read).
fixture="$(make_fixture)"
mkdir -p "$fixture/src"
printf 'body\n' >"$fixture/src/outside.md"
sha_before="$(_sha "$fixture/docs/wiki/.usage.json")"
_ptu_stdin "read_file" "$fixture/src/outside.md" | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1
assert_file_unchanged "post-tool-use: qwen read_file out-of-wiki -> .usage.json unchanged" \
  "$fixture/docs/wiki/.usage.json" "$sha_before"

# 25. Legacy schema (wiki_version 3.0) + qwen `edit` -> .usage.json
#     untouched (version-gate, same posture as Claude's Edit).
fixture="$(make_fixture)"
cat >"$fixture/docs/wiki/schema.md" <<'EOF'
---
wiki_version: "3.0"
---

# Schema
EOF
printf 'body\n' >"$fixture/docs/wiki/foo.md"
sha_before="$(_sha "$fixture/docs/wiki/.usage.json")"
_ptu_stdin "edit" "$fixture/docs/wiki/foo.md" | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1
assert_file_unchanged "post-tool-use: legacy schema + qwen edit -> .usage.json unchanged" \
  "$fixture/docs/wiki/.usage.json" "$sha_before"

# ---- v46-qwen Task 3: first-match-wins scalar chain
#      (file_path -> notebook_path -> path), BATCH_TOOLS-gated edits[]
#      union.

# 26. Qwen `notebook_edit` with tool_input.notebook_path (NO file_path) ->
#     patch_count = 1.
fixture="$(make_fixture)"
printf 'body\n' >"$fixture/docs/wiki/foo.md"
printf '{"tool_name":"notebook_edit","tool_input":{"notebook_path":"%s"}}' \
  "$fixture/docs/wiki/foo.md" \
  | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1
assert_eq "post-tool-use: qwen notebook_edit (notebook_path only) bumps patch_count to 1" \
  "1" "$(_ptu_field "$fixture/docs/wiki/.usage.json" "foo.md" "patch_count")"

# 27. Qwen `read_file` with a relative tool_input.path (NO file_path/
#     notebook_path) + QWEN_PROJECT_DIR anchor, CLAUDE_PROJECT_DIR unset ->
#     view_count = 1.
fixture="$(make_fixture)"
printf 'body\n' >"$fixture/docs/wiki/foo.md"
printf '{"tool_name":"read_file","tool_input":{"path":"docs/wiki/foo.md"}}' \
  | env -u CLAUDE_PROJECT_DIR QWEN_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1
assert_eq "post-tool-use: qwen read_file (relative path only) bumps view_count to 1" \
  "1" "$(_ptu_field "$fixture/docs/wiki/.usage.json" "foo.md" "view_count")"

# 28. First-match-wins guard (required): a single read_file call whose
#     tool_input carries file_path AND notebook_path AND path — three
#     DIFFERENT existing wiki pages -> _ptu_keys is exactly the file_path
#     page's name; the other two keys never appear in .usage.json at all.
fixture="$(make_fixture)"
printf 'body\n' >"$fixture/docs/wiki/foo.md"
printf 'body\n' >"$fixture/docs/wiki/bar.md"
printf 'body\n' >"$fixture/docs/wiki/baz.md"
printf '{"tool_name":"read_file","tool_input":{"file_path":"%s","notebook_path":"%s","path":"%s"}}' \
  "$fixture/docs/wiki/foo.md" "$fixture/docs/wiki/bar.md" "$fixture/docs/wiki/baz.md" \
  | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1
assert_eq "post-tool-use: first-match-wins -> only file_path page bumped" \
  "foo.md" "$(_ptu_keys "$fixture/docs/wiki/.usage.json")"

# 29. Mirror case: notebook_path + path without file_path -> bumps only
#     the notebook_path page.
fixture="$(make_fixture)"
printf 'body\n' >"$fixture/docs/wiki/bar.md"
printf 'body\n' >"$fixture/docs/wiki/baz.md"
printf '{"tool_name":"notebook_edit","tool_input":{"notebook_path":"%s","path":"%s"}}' \
  "$fixture/docs/wiki/bar.md" "$fixture/docs/wiki/baz.md" \
  | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1
assert_eq "post-tool-use: notebook_path + path (no file_path) -> only notebook_path page bumped" \
  "bar.md" "$(_ptu_keys "$fixture/docs/wiki/.usage.json")"

# 30. Batch-only guard for edits[] (required): a `write_file` payload with
#     a valid top-level file_path PLUS tool_input.edits[] pointing at two
#     other existing wiki pages -> _ptu_keys contains exactly the primary
#     page (write_file is not in BATCH_TOOLS, so edits[] is never read).
#     Mirrored for `edit`.
for _qwen_tool in write_file edit; do
  fixture="$(make_fixture)"
  printf 'body\n' >"$fixture/docs/wiki/foo.md"
  printf 'body\n' >"$fixture/docs/wiki/bar.md"
  printf 'body\n' >"$fixture/docs/wiki/baz.md"
  printf '{"tool_name":"%s","tool_input":{"file_path":"%s","edits":[{"file_path":"%s","old_string":"a","new_string":"b"},{"file_path":"%s","old_string":"c","new_string":"d"}]}}' \
    "$_qwen_tool" "$fixture/docs/wiki/foo.md" "$fixture/docs/wiki/bar.md" "$fixture/docs/wiki/baz.md" \
    | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1
  assert_eq "post-tool-use: $_qwen_tool + edits[] -> edits[] ignored (batch-only), only primary bumped" \
    "foo.md" "$(_ptu_keys "$fixture/docs/wiki/.usage.json")"
done

# 31. Positive control: the SAME payload shape as #30 under tool_name
#     MultiEdit -> three records (primary + the two from edits[]) — proves
#     the guard in #30 rejects the non-batch tool NAME, not the edits[]
#     branch itself.
fixture="$(make_fixture)"
printf 'body\n' >"$fixture/docs/wiki/foo.md"
printf 'body\n' >"$fixture/docs/wiki/bar.md"
printf 'body\n' >"$fixture/docs/wiki/baz.md"
printf '{"tool_name":"MultiEdit","tool_input":{"file_path":"%s","edits":[{"file_path":"%s","old_string":"a","new_string":"b"},{"file_path":"%s","old_string":"c","new_string":"d"}]}}' \
  "$fixture/docs/wiki/foo.md" "$fixture/docs/wiki/bar.md" "$fixture/docs/wiki/baz.md" \
  | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" >/dev/null 2>&1
assert_eq "post-tool-use: MultiEdit positive control -> all three pages bumped" \
  "bar.md,baz.md,foo.md" "$(_ptu_keys "$fixture/docs/wiki/.usage.json")"

# 32. Guard for non-matched Claude instruments (required): a Grep payload
#     and a Glob payload, each with tool_input.path pointing at an
#     existing wiki page -> .usage.json byte-for-byte unchanged, empty
#     stdout, exit 0. Grep/Glob DO carry a `path` key in real Claude Code
#     tool_input, so this proves the action-gate rejects the tool NAME
#     before the scalar chain ever reads `path` for them.
for _claude_tool in Grep Glob; do
  fixture="$(make_fixture)"
  printf 'body\n' >"$fixture/docs/wiki/foo.md"
  sha_before="$(_sha "$fixture/docs/wiki/.usage.json")"
  out="$(printf '{"tool_name":"%s","tool_input":{"path":"%s"}}' \
    "$_claude_tool" "$fixture/docs/wiki/foo.md" \
    | CLAUDE_PROJECT_DIR="$fixture" bash "$POST_TOOL_USE_HOOK" 2>&1)"
  rc=$?
  assert_eq "post-tool-use: $_claude_tool exits 0" "0" "$rc"
  assert_eq "post-tool-use: $_claude_tool -> empty stdout" "" "$out"
  assert_file_unchanged "post-tool-use: $_claude_tool (tool_input.path) -> .usage.json unchanged" \
    "$fixture/docs/wiki/.usage.json" "$sha_before"
done

# 33. Regression: post-tool-use.sh MUST be committed executable. install
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

# 6c. fixwave0-4 P2: no python3 on PATH at uninstall time.
#     6c1: settings.json still carries the wiki hook marker -> removal can
#     neither be performed NOR verified, so this MUST be a non-zero exit
#     (not the old "skip and exit 0"), and settings.json must be left
#     byte-identical — a caller (uninstall.sh) that gates --remove-clones on
#     this exit code must refuse to delete the clone hosting the recovery
#     script. Curated PATH mirrors the "no python3" technique used for
#     post-tool-use.sh above: symlink every OTHER tool uninstall-hooks.sh's
#     early-exit path needs (bash, grep) but omit python3, so the failure is
#     provably the script's own python3 guard and not a missing-tool 127.
curated_path_dir="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-nopython-uninstall.XXXXXX")"
track_tmp "$curated_path_dir"
for _tool in bash grep; do
  _tool_src="$(command -v "$_tool" 2>/dev/null)"
  [ -n "$_tool_src" ] && ln -s "$_tool_src" "$curated_path_dir/$_tool"
done
home="$(make_fake_home)"
f="$home/.claude/settings.json"
env "${WH_ENV[@]}" HOME="$home" PATH="$curated_path_dir:$PATH" bash "$INSTALL_HOOKS_SCRIPT" >/dev/null 2>&1
sha_before="$(_sha "$f")"
err="$(env WIKI_HOOKS_FORCE_MKDIR_LOCK=1 WIKI_HOOKS_LOCK_TIMEOUT=3 WIKI_HOOKS_LOCK_POLL=0.1 HOME="$home" PATH="$curated_path_dir" bash "$UNINSTALL_HOOKS_SCRIPT" 2>&1 >/dev/null)"
rc=$?
assert_eq "uninstall: no python3 + marker present -> non-zero exit" "1" "$rc"
assert_file_unchanged "uninstall: no python3 + marker present -> settings.json byte-identical" "$f" "$sha_before"
assert_contains "uninstall: no python3 + marker present -> stderr mentions python3" "$err" "python3"

#     6c2: no python3 AND no wiki marker present (nothing installed) ->
#     genuinely nothing to do, must still exit 0.
home="$(make_fake_home)"
f="$home/.claude/settings.json"
cat >"$f" <<'EOF'
{
  "hooks": {
    "Stop": [{"matcher": "*", "hooks": [{"type": "command", "command": "/foreign/stop.sh"}]}]
  }
}
EOF
sha_before="$(_sha "$f")"
env WIKI_HOOKS_FORCE_MKDIR_LOCK=1 WIKI_HOOKS_LOCK_TIMEOUT=3 WIKI_HOOKS_LOCK_POLL=0.1 HOME="$home" PATH="$curated_path_dir" bash "$UNINSTALL_HOOKS_SCRIPT" >/dev/null 2>&1
rc=$?
assert_eq "uninstall: no python3 + no marker -> exit 0 (nothing to do)" "0" "$rc"
assert_file_unchanged "uninstall: no python3 + no marker -> settings.json untouched" "$f" "$sha_before"

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
# install-hooks.sh sources its sibling hooks/lib/settings-lock.sh
# (t5-settings-lock-lib) via a BASH_SOURCE-relative path, exactly as it
# ships in this repo — a "clone" of the installer must carry that lib
# alongside it too, or the copy is not a faithful clone.
mkdir -p "$clone_a/lib" "$clone_b/lib"
cp "$SETTINGS_LOCK_LIB" "$clone_a/lib/settings-lock.sh"
cp "$SETTINGS_LOCK_LIB" "$clone_b/lib/settings-lock.sh"
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

# 11c. dir_age_seconds portability (P2): on GNU/Linux, `stat -f %m "$d"`
#      doesn't mean "print mtime" — `-f` is GNU stat's unrelated
#      --file-system flag — so it emits non-numeric filesystem-status
#      text instead of failing cleanly. A fake `stat` shim ahead of PATH
#      reproduces exactly that: `-f` yields non-numeric non-empty
#      output, `-c %Y` yields the real mtime (GNU-only path). Without
#      validating the `-f` output is numeric before trusting it, the
#      stale mkdir-fallback lock (no pid file, old mtime) is never
#      detected as stale and the competing install hangs to its own
#      timeout instead of reclaiming it.
fake_stat_dir="$(mktemp -d "${TMPDIR:-/tmp}/wiki-hook-fakestat.XXXXXX")"
track_tmp "$fake_stat_dir"
cat >"$fake_stat_dir/stat" <<'FAKESTAT'
#!/usr/bin/env bash
# Simulates GNU coreutils stat's behavior for `-f %m FILE`: -f is the
# unrelated --file-system flag, so it does NOT print an mtime and does
# NOT fail cleanly — it prints non-numeric filesystem-status text and
# exits 0. `-c %Y FILE` behaves like the real GNU stat mtime query.
if [ "$1" = "-f" ]; then
  echo "not-a-number-filesystem-status"
  exit 0
elif [ "$1" = "-c" ]; then
  fmt="$2"; file="$3"
  if command /usr/bin/stat -f %m "$file" >/dev/null 2>&1; then
    command /usr/bin/stat -f %m "$file"
  else
    command /usr/bin/stat -c %Y "$file"
  fi
  exit 0
fi
exit 1
FAKESTAT
chmod +x "$fake_stat_dir/stat"
home="$(make_fake_home)"
f="$home/.claude/settings.json"
lockdir="$home/.claude/settings.json.lockdir"
mkdir -p "$lockdir"
python3 -c "import os,time; os.utime('$lockdir', (time.time()-300, time.time()-300))"
rc=0
env PATH="$fake_stat_dir:$PATH" WIKI_HOOKS_FORCE_MKDIR_LOCK=1 WIKI_HOOKS_LOCK_TIMEOUT=3 WIKI_HOOKS_LOCK_POLL=0.1 HOME="$home" bash "$INSTALL_HOOKS_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "dir_age_seconds portability: GNU-style non-numeric 'stat -f' still reclaims stale lock (install)" "0" "$rc"
assert_eq "dir_age_seconds portability: install succeeded despite fake stat" "1" "$(json_get "$f" "len(d['hooks']['SessionStart'])")"

home="$(make_fake_home)"
f="$home/.claude/settings.json"
lockdir="$home/.claude/settings.json.lockdir"
env PATH="$fake_stat_dir:$PATH" WIKI_HOOKS_FORCE_MKDIR_LOCK=1 WIKI_HOOKS_LOCK_TIMEOUT=3 WIKI_HOOKS_LOCK_POLL=0.1 HOME="$home" bash "$INSTALL_HOOKS_SCRIPT" >/dev/null 2>&1
mkdir -p "$lockdir"
python3 -c "import os,time; os.utime('$lockdir', (time.time()-300, time.time()-300))"
rc=0
env PATH="$fake_stat_dir:$PATH" WIKI_HOOKS_FORCE_MKDIR_LOCK=1 WIKI_HOOKS_LOCK_TIMEOUT=3 WIKI_HOOKS_LOCK_POLL=0.1 HOME="$home" bash "$UNINSTALL_HOOKS_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "dir_age_seconds portability: GNU-style non-numeric 'stat -f' still reclaims stale lock (uninstall)" "0" "$rc"

# 11c. PID-recycle deadlock guard (P1, fixwave0-2): a lock dir whose pid
#      file names a process that IS currently alive (simulating an OS
#      having recycled the crashed original holder's pid onto some
#      unrelated long-running process) must still be force-reclaimed once
#      its mtime exceeds WIKI_HOOKS_LOCK_MAX_AGE — liveness of a recycled
#      pid can never be trusted to gate reclamation forever, or every
#      future install/uninstall would deadlock permanently. A small
#      WIKI_HOOKS_LOCK_MAX_AGE keeps this deterministic and fast without
#      waiting a real hour.
home="$(make_fake_home)"
f="$home/.claude/settings.json"
lockdir="$home/.claude/settings.json.lockdir"
mkdir -p "$lockdir"
( sleep 30 ) &
recycled_pid=$!
echo "$recycled_pid" >"$lockdir/pid"
# Age the lock well past WIKI_HOOKS_LOCK_MAX_AGE below, but still safely
# inside the overall LOCK_TIMEOUT wait budget so a passing run is fast.
python3 -c "import os,time; os.utime('$lockdir', (time.time()-100, time.time()-100))"
rc=0
env WIKI_HOOKS_FORCE_MKDIR_LOCK=1 WIKI_HOOKS_LOCK_TIMEOUT=5 WIKI_HOOKS_LOCK_POLL=0.1 WIKI_HOOKS_LOCK_MAX_AGE=10 HOME="$home" bash "$INSTALL_HOOKS_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "pid-recycle guard: install succeeds despite recorded pid being alive" "0" "$rc"
assert_eq "pid-recycle guard: SessionStart has 1 entry" "1" "$(json_get "$f" "len(d['hooks']['SessionStart'])")"
[ -d "$lockdir" ] && FAIL=$((FAIL + 1)) && echo "FAIL: pid-recycle guard: lock dir cleaned up" >&2 || PASS=$((PASS + 1))
kill "$recycled_pid" 2>/dev/null || true
wait "$recycled_pid" 2>/dev/null || true

# 11d. PID-recycle guard must NOT weaken normal live-owner protection: a
#      lock whose mtime is old but still WELL WITHIN WIKI_HOOKS_LOCK_MAX_AGE
#      (default far larger than any single install run) must still block a
#      competing install exactly like test 10 above — the age ceiling is a
#      last-resort safety net, not a general license to steal live locks.
home="$(make_fake_home)"
f="$home/.claude/settings.json"
sha_before="$(_sha "$f" 2>/dev/null || true)"
lockdir="$home/.claude/settings.json.lockdir"
mkdir -p "$lockdir"
( sleep 30 ) &
live_pid=$!
echo "$live_pid" >"$lockdir/pid"
python3 -c "import os,time; os.utime('$lockdir', (time.time()-5, time.time()-5))"
rc=0
err="$(env WIKI_HOOKS_FORCE_MKDIR_LOCK=1 WIKI_HOOKS_LOCK_TIMEOUT=1 WIKI_HOOKS_LOCK_POLL=0.1 WIKI_HOOKS_LOCK_MAX_AGE=3600 HOME="$home" bash "$INSTALL_HOOKS_SCRIPT" 2>&1 >/dev/null)" || rc=$?
assert_eq "pid-recycle guard: age well within LOCK_MAX_AGE -> still does not steal a live lock" "1" "$rc"
kill "$live_pid" 2>/dev/null || true
wait "$live_pid" 2>/dev/null || true
rm -rf "$lockdir"

# 12. Interrupt while holding the mkdir-fallback lock: the EXIT/INT/TERM
#     trap must remove the lock dir completely, never leaving a deadlock
#     for the next run. WIKI_HOOKS_TEST_SLEEP_AFTER_LOCK holds the lock
#     open long enough to reliably deliver SIGTERM mid-critical-section.
home="$(make_fake_home)"
f="$home/.claude/settings.json"
lockdir="$home/.claude/settings.json.lockdir"
env WIKI_HOOKS_FORCE_MKDIR_LOCK=1 WIKI_HOOKS_TEST_SLEEP_AFTER_LOCK=5 HOME="$home" bash "$INSTALL_HOOKS_SCRIPT" >/dev/null 2>&1 &
interrupted_pid=$!
# Poll for OWNERSHIP (a non-empty pid file), not merely for the lock dir to
# exist, and never a fixed sleep — so this isn't racy under slow/loaded CI.
# The bare `-d` check used to fire during the holder's mkdir->pid-write
# window, where the lock dir exists but nothing records an owner yet; a
# SIGTERM delivered there is NOT "interrupted mid-critical-section" (what
# this case is about) and the trap deliberately leaves such an empty-pid dir
# alone (agy-атк P0, wave4 — deleting it could destroy a new owner's lock),
# so the assertion below intermittently saw a legitimately-retained dir.
# Waiting for the pid file makes the interrupt land where the comment says
# it does; the empty-pid window's own behaviour is covered by U5.
wait_start="$(date +%s)"
while [ ! -s "$lockdir/pid" ]; do
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
# not exclude each other. Assert statically that neither script (nor the
# shared lock lib itself) makes an `flock -w` call, that both installers
# acquire the mkdir lock unconditionally via the shared
# hooks/lib/settings-lock.sh, and that no second mutex implementation
# (`acquire_mkdir`) remains in either installer (t5-settings-lock-lib).
for sc in "$INSTALL_HOOKS_SCRIPT" "$UNINSTALL_HOOKS_SCRIPT" "$SETTINGS_LOCK_LIB"; do
  n="$(basename "$sc")"
  assert_eq "lock-unify: $n makes no flock -w call" "0" "$(grep -c 'flock -w' "$sc")"
done
for sc in "$INSTALL_HOOKS_SCRIPT" "$UNINSTALL_HOOKS_SCRIPT"; do
  n="$(basename "$sc")"
  assert_eq "lock-unify: $n acquires the mkdir lock unconditionally" "yes" \
    "$(grep -qE 'wiki_lock_acquire [^|]*\|\| *fail' "$sc" && echo yes || echo no)"
  assert_eq "lock-unify: $n sources the shared lock lib" "yes" \
    "$(grep -q 'lib/settings-lock.sh' "$sc" && echo yes || echo no)"
  assert_eq "lock-unify: $n carries no second mutex implementation" "0" "$(grep -c 'acquire_mkdir' "$sc")"
done

# ---- hooks/lib/settings-lock.sh: direct unit tests (t5-settings-lock-lib) ----
#
# Each scenario sources the lib inside its OWN bash process (never in this
# harness's own process) because wiki_lock_acquire installs an EXIT/INT/TERM
# trap in whatever shell calls it — sourcing it in-process here would
# clobber this harness's own `trap cleanup EXIT` (line 42).

# U1. Acquire on a free lockdir -> 0, dir exists, recorded pid is the
#     acquiring process's own pid.
home="$(make_fake_home)"
lockdir="$home/u1.lockdir"
bash -c '
  set -uo pipefail
  source "'"$SETTINGS_LOCK_LIB"'"
  wiki_lock_acquire "'"$lockdir"'" || exit 1
  sleep 5
' &
u1_pid=$!
wait_start="$(date +%s)"
while [ ! -s "$lockdir/pid" ]; do
  now="$(date +%s)"
  if [ $((now - wait_start)) -ge 5 ]; then
    break
  fi
done
assert_eq "settings-lock lib: U1 acquire creates the lock dir" "yes" "$([ -d "$lockdir" ] && echo yes || echo no)"
assert_eq "settings-lock lib: U1 recorded pid is the acquiring process" "$u1_pid" "$(cat "$lockdir/pid" 2>/dev/null)"
kill -TERM "$u1_pid" 2>/dev/null || true
wait "$u1_pid" 2>/dev/null || true
assert_eq "settings-lock lib: U1 trap removes the lock dir on exit" "" "$([ -d "$lockdir" ] && echo present)"

# U2. A second process racing for the SAME lockdir with a short
#     WIKI_HOOKS_LOCK_TIMEOUT times out (1) while the live owner's lockdir
#     is left untouched.
home="$(make_fake_home)"
lockdir="$home/u2.lockdir"
bash -c '
  set -uo pipefail
  source "'"$SETTINGS_LOCK_LIB"'"
  wiki_lock_acquire "'"$lockdir"'" || exit 1
  sleep 5
' &
u2_owner_pid=$!
wait_start="$(date +%s)"
while [ ! -s "$lockdir/pid" ]; do
  now="$(date +%s)"
  if [ $((now - wait_start)) -ge 5 ]; then
    break
  fi
done
owner_pid_recorded="$(cat "$lockdir/pid" 2>/dev/null)"
rc=0
env WIKI_HOOKS_LOCK_TIMEOUT=1 WIKI_HOOKS_LOCK_POLL=0.1 bash -c '
  set -uo pipefail
  source "'"$SETTINGS_LOCK_LIB"'"
  wiki_lock_acquire "'"$lockdir"'"
' || rc=$?
assert_eq "settings-lock lib: U2 contender times out (1) on a live foreign lock" "1" "$rc"
assert_eq "settings-lock lib: U2 foreign lockdir survives the timed-out contender" "yes" "$([ -d "$lockdir" ] && echo yes || echo no)"
assert_eq "settings-lock lib: U2 foreign lockdir pid unchanged" "$owner_pid_recorded" "$(cat "$lockdir/pid" 2>/dev/null)"
kill -TERM "$u2_owner_pid" 2>/dev/null || true
wait "$u2_owner_pid" 2>/dev/null || true

# U3. wiki_lock_release removes a lock dir ONLY when its recorded pid is
#     the caller's own ($$) — a lockdir whose pid file was rewritten to a
#     foreign pid (simulating a race the caller must defensively tolerate)
#     is left in place.
home="$(make_fake_home)"
lockdir="$home/u3.lockdir"
release_out="$(bash -c '
  set -uo pipefail
  source "'"$SETTINGS_LOCK_LIB"'"
  wiki_lock_acquire "'"$lockdir"'" || exit 1
  echo 999999 >"'"$lockdir"'/pid"
  wiki_lock_release "'"$lockdir"'"
  [ -d "'"$lockdir"'" ] && echo STILL_PRESENT || echo REMOVED
  rm -f "'"$lockdir"'/pid" 2>/dev/null
  rmdir "'"$lockdir"'" 2>/dev/null
' 2>&1)"
assert_eq "settings-lock lib: U3 release refuses to remove a foreign-owned lock dir" "STILL_PRESENT" "$release_out"

# U4. Two different lockdirs held at once by the SAME process -> both
#     acquired successfully, and after the process exits (trap) NEITHER
#     remains (T8/T12 rely on exactly this: claude+qwen or two clients
#     locked concurrently within one script run).
home="$(make_fake_home)"
lockdir_a="$home/u4-a.lockdir"
lockdir_b="$home/u4-b.lockdir"
out="$(bash -c '
  set -uo pipefail
  source "'"$SETTINGS_LOCK_LIB"'"
  wiki_lock_acquire "'"$lockdir_a"'" || exit 1
  wiki_lock_acquire "'"$lockdir_b"'" || exit 1
  echo BOTH_ACQUIRED
' 2>&1)"
assert_eq "settings-lock lib: U4 both distinct lockdirs acquired in one process" "BOTH_ACQUIRED" "$out"
assert_eq "settings-lock lib: U4 first lockdir removed after exit" "" "$([ -d "$lockdir_a" ] && echo present)"
assert_eq "settings-lock lib: U4 second lockdir removed after exit" "" "$([ -d "$lockdir_b" ] && echo present)"

# U5. pid-write failure is a FAILED acquisition, never a silent warning
#     (codex-атк P1). Simulated with a `mkdir` shell function that creates
#     the lock dir and immediately strips its write bit, so the very next
#     `>"$lockdir/pid"` fails with EACCES exactly like a read-only fs /
#     ENOSPC / quota would. wiki_lock_acquire must return non-zero (both
#     installers do `wiki_lock_acquire … || fail`, so the caller never runs
#     its settings.json read-modify-write under a lock dir that no guard can
#     attribute to an owner), and the abandoned empty-pid dir must stay
#     put — removing it is what would steal a live foreign lock — so a later
#     contender still self-heals through the mtime-age fallback.
home="$(make_fake_home)"
lockdir="$home/u5.lockdir"
u5_out="$(bash -c '
  set -uo pipefail
  source "'"$SETTINGS_LOCK_LIB"'"
  mkdir() { command mkdir "$@" && chmod 500 "$1"; }
  if wiki_lock_acquire "'"$lockdir"'"; then echo ACQUIRED; else echo REFUSED; fi
' 2>/dev/null)"
assert_eq "settings-lock lib: U5 unwritable pid file makes acquire fail, not succeed" "REFUSED" "$u5_out"
assert_eq "settings-lock lib: U5 recorded owner pid is absent/empty (nothing claims ownership)" "" "$(cat "$lockdir/pid" 2>/dev/null)"
assert_eq "settings-lock lib: U5 abandoned lock dir is left for the age fallback, not stolen back" "yes" "$([ -d "$lockdir" ] && echo yes || echo no)"
# Backdate the abandoned dir instead of waiting out lock_timeout in real
# time, so this assertion tests the reclaim path itself rather than the
# scheduler: the contender must reclaim on its very first iteration.
touch -t 202001010000 "$lockdir" 2>/dev/null || true
u5_next="$(env WIKI_HOOKS_LOCK_TIMEOUT=1 WIKI_HOOKS_LOCK_POLL=0.1 bash -c '
  set -uo pipefail
  source "'"$SETTINGS_LOCK_LIB"'"
  if wiki_lock_acquire "'"$lockdir"'"; then echo ACQUIRED_AFTER; else echo TIMED_OUT; fi
' 2>/dev/null)"
assert_eq "settings-lock lib: U5 next client reclaims the abandoned empty-pid lock (self-healing)" "ACQUIRED_AFTER" "$u5_next"
chmod -R u+rwX "$home" 2>/dev/null || true

# ---- t6-register-into: hooks/install-hooks.sh parameterized into
#      register_into(client) (docs/superpowers/plans/2026-08-13-v46-qwen.md
#      Task 6). All tests above this point exercise the pre-T6 behavior
#      unmodified and stay green byte-for-byte — that is the identity proof
#      that the claude branch through register_into is unchanged. The
#      cases below cover what's NEW in T6: per-existing-file permission
#      preservation, the client-prefixed messages, the read-under-lock
#      TOCTOU guard (FIFO), and the re-check-under-lock vanished-clone
#      guard (spec R12). ----

# t6_stat_mode <file> -> octal permission bits, portable BSD (`stat -f
# %OLp`) first with a GNU (`stat -c %a`) fallback — mirrors the
# _wiki_lock_dir_age_seconds BSD/GNU dance in hooks/lib/settings-lock.sh
# (GNU coreutils' `-f` is the unrelated --file-system flag and emits
# non-numeric text instead of failing cleanly, so the BSD-form output must
# be validated as pure octal digits before being trusted).
t6_stat_mode() {
  local f="$1" m
  m="$(stat -f %OLp "$f" 2>/dev/null || true)"
  case "$m" in
    ''|*[!0-7]*) m="" ;;
  esac
  if [ -z "$m" ]; then
    m="$(stat -c %a "$f" 2>/dev/null || true)"
    case "$m" in
      ''|*[!0-7]*) m="" ;;
    esac
  fi
  echo "$m"
}

# T6a. Existing settings.json with mode 0644 -> install preserves 0644
# (an unconditional os.replace would otherwise silently narrow it to
# whatever mkstemp picked, 0600).
home="$(make_fake_home)"
f="$home/.claude/settings.json"
printf '{}' >"$f"
chmod 644 "$f"
env "${WH_ENV[@]}" HOME="$home" bash "$INSTALL_HOOKS_SCRIPT" >/dev/null 2>&1
assert_eq "t6: existing 0644 settings.json keeps 0644 after install" "644" "$(t6_stat_mode "$f")"

# T6b. Brand-new settings.json (no file at all beforehand) -> 0600 (these
# files can carry secrets under other keys, e.g. env/mcpServers).
home="$(make_fake_home)"
f="$home/.claude/settings.json"
env "${WH_ENV[@]}" HOME="$home" bash "$INSTALL_HOOKS_SCRIPT" >/dev/null 2>&1
assert_eq "t6: freshly-created settings.json is 0600" "600" "$(t6_stat_mode "$f")"

# T6c. Success message on stderr carries the client prefix.
home="$(make_fake_home)"
f="$home/.claude/settings.json"
err="$(env "${WH_ENV[@]}" HOME="$home" bash "$INSTALL_HOOKS_SCRIPT" 2>&1 >/dev/null)"
assert_contains "t6: success stderr carries client prefix" "$err" "install-hooks: claude:"

# T6d. Corrupt JSON -> non-zero, file byte-identical, client-prefixed
# stderr (distinct from test 4 above, which only asserts a bare
# "install-hooks" substring — this checks the new "<client>:" segment).
home="$(make_fake_home)"
f="$home/.claude/settings.json"
printf '{ not valid json' >"$f"
sha_before="$(_sha "$f")"
err="$(env "${WH_ENV[@]}" HOME="$home" bash "$INSTALL_HOOKS_SCRIPT" 2>&1 >/dev/null)"
rc=$?
assert_eq "t6: corrupt JSON -> non-zero exit" "1" "$rc"
assert_file_unchanged "t6: corrupt JSON -> settings.json byte-identical" "$f" "$sha_before"
assert_contains "t6: corrupt JSON -> stderr carries client prefix" "$err" "install-hooks: claude:"

# T6e. FIFO in place of settings.json -> refused without hanging (the
# read-under-lock TOCTOU guard: os.open(O_RDONLY|O_NOFOLLOW|O_NONBLOCK) +
# fstat/S_ISREG), and the lockdir is not left behind. A background watchdog
# kills the installer if it is still alive past a generous bound so a
# regression here fails this assertion instead of wedging the whole suite
# forever — that bound is also the wall-clock assertion itself.
if command -v mkfifo >/dev/null 2>&1; then
  home="$(make_fake_home)"
  f="$home/.claude/settings.json"
  rm -f "$f"
  mkfifo "$f"
  start_ts="$(date +%s)"
  env "${WH_ENV[@]}" HOME="$home" bash "$INSTALL_HOOKS_SCRIPT" >/dev/null 2>&1 &
  fifo_pid=$!
  (
    waited=0
    while kill -0 "$fifo_pid" 2>/dev/null; do
      sleep 1
      waited=$((waited + 1))
      if [ "$waited" -ge 8 ]; then
        kill -TERM "$fifo_pid" 2>/dev/null
        break
      fi
    done
  ) &
  watchdog_pid=$!
  rc=0
  wait "$fifo_pid" || rc=$?
  end_ts="$(date +%s)"
  kill "$watchdog_pid" 2>/dev/null || true
  wait "$watchdog_pid" 2>/dev/null || true
  elapsed=$((end_ts - start_ts))
  assert_eq "t6: FIFO settings.json -> non-zero exit (no hang)" "1" "$rc"
  if [ "$elapsed" -lt 8 ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: t6: FIFO settings.json -> wall-clock too slow (${elapsed}s, suspected hang)" >&2
  fi
  assert_eq "t6: FIFO settings.json -> no lockdir left" "" "$([ -d "$f.lockdir" ] && echo present)"
  rm -f "$f" 2>/dev/null || true
fi

# T6f. Clone vanished while waiting for the lock (spec R12): a settings.json
# with our canonical scripts present+executable, a lockdir pre-held by a
# genuinely live foreign process so this install blocks waiting for it;
# while it waits, the canonical scripts are deleted (simulating
# `uninstall.sh --remove-clones` tearing down $SKILL_DIR mid-wait); the
# foreign lock is then released. The waiting installer must re-check under
# its own lock, see the scripts gone, and refuse -> non-zero with "skill
# clone vanished", settings.json left byte-identical, no lockdir leftover.
home="$(make_fake_home)"
f="$home/.claude/settings.json"
printf '{}' >"$f"
sha_before="$(_sha "$f")"
skill_hooks_dir="$home/.claude/skills/wiki/hooks"
mkdir -p "$skill_hooks_dir"
printf '#!/usr/bin/env bash\nexit 0\n' >"$skill_hooks_dir/session-start.sh"
printf '#!/usr/bin/env bash\nexit 0\n' >"$skill_hooks_dir/post-tool-use.sh"
chmod +x "$skill_hooks_dir/session-start.sh" "$skill_hooks_dir/post-tool-use.sh"

lockdir="$f.lockdir"
( sleep 30 ) &
foreign_pid=$!
mkdir -p "$lockdir"
echo "$foreign_pid" >"$lockdir/pid"

env WIKI_HOOKS_FORCE_MKDIR_LOCK=1 WIKI_HOOKS_LOCK_TIMEOUT=8 WIKI_HOOKS_LOCK_POLL=0.1 HOME="$home" bash "$INSTALL_HOOKS_SCRIPT" >/dev/null 2>"t6f_err.$$" &
waiter_pid=$!

sleep 0.5
rm -f "$skill_hooks_dir/session-start.sh" "$skill_hooks_dir/post-tool-use.sh"
rm -rf "$lockdir"

rc=0
wait "$waiter_pid" || rc=$?
kill "$foreign_pid" 2>/dev/null || true
wait "$foreign_pid" 2>/dev/null || true

t6f_err="$(cat "t6f_err.$$" 2>/dev/null)"
rm -f "t6f_err.$$"
assert_eq "t6: clone vanished under lock -> non-zero exit" "1" "$rc"
assert_contains "t6: clone vanished under lock -> stderr mentions vanished clone" "$t6f_err" "skill clone vanished"
assert_file_unchanged "t6: clone vanished under lock -> settings.json byte-identical" "$f" "$sha_before"
assert_eq "t6: clone vanished under lock -> no lockdir left" "" "$([ -d "$lockdir" ] && echo present)"

# T6g. Pre-planted symlink at the predictable backup path must NOT be
# written through (codex-атк P1). The backup name is
# "$settings_file.bak-wiki-hooks-$(date +%Y%m%d%H%M%S)" — fully guessable by
# anyone who can write into the settings dir — so the installer creates it
# with O_CREAT|O_EXCL|O_NOFOLLOW and steps to the next numbered candidate
# instead of following a symlink and truncating + chmod-ing the victim.
# The exact second the installer picks is racy from out here, so every
# candidate name in a 3-second window is booby-trapped; the install below
# runs far inside that window.
home="$(make_fake_home)"
f="$home/.claude/settings.json"
printf '{}' >"$f"
victim="$home/victim.txt"
printf 'DO-NOT-TOUCH\n' >"$victim"
chmod 600 "$victim"
victim_sha="$(_sha "$victim")"
for off in 0 1 2 3; do
  planted_ts="$(python3 -c "
import sys, time
print(time.strftime('%Y%m%d%H%M%S', time.localtime(time.time() + int(sys.argv[1]))))
" "$off")"
  ln -s "$victim" "$f.bak-wiki-hooks-$planted_ts" 2>/dev/null || true
done
rc=0
env "${WH_ENV[@]}" HOME="$home" bash "$INSTALL_HOOKS_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "t6: planted backup symlink -> victim file byte-identical" "$victim_sha" "$(_sha "$victim")"
assert_eq "t6: planted backup symlink -> victim keeps 0600" "600" "$(t6_stat_mode "$victim")"
assert_eq "t6: planted backup symlink -> install still succeeds" "0" "$rc"
assert_eq "t6: planted backup symlink -> hooks still registered" "1" "$(json_get "$f" "len(d['hooks']['SessionStart'])")"
# The real backup landed on a sidestepped name and is a regular file, not
# one of the planted symlinks.
real_backup=""
for cand in "$home/.claude/"*.bak-wiki-hooks-*; do
  [ -e "$cand" ] || continue
  if [ ! -L "$cand" ] && [ -f "$cand" ]; then
    real_backup="$cand"
    break
  fi
done
assert_eq "t6: planted backup symlink -> a real (non-symlink) backup was created" "1" "$([ -n "$real_backup" ] && echo 1 || echo 0)"
assert_eq "t6: planted backup symlink -> real backup holds the pre-merge settings" "{}" "$(cat "$real_backup" 2>/dev/null)"

# ---- summary ----
echo "" >&2
echo "pass: $PASS  fail: $FAIL" >&2
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
