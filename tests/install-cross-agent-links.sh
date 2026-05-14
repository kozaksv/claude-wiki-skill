#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

HOME_DIR="$TMP/home"
BIN_DIR="$TMP/bin"
mkdir -p "$HOME_DIR" "$BIN_DIR"

cat >"$BIN_DIR/git" <<'FAKE_GIT'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-C" ]]; then
  dir="$2"
  shift 2
  case "${1:-}" in
    fetch|pull)
      exit 0
      ;;
    checkout)
      if [[ "$dir" == *"claude-doc-extract-skill"* && "${2:-}" != "main" ]]; then
        echo "doc-extract must be checked out at main in this fixture" >&2
        exit 1
      fi
      exit 0
      ;;
    symbolic-ref)
      exit 0
      ;;
  esac
fi

if [[ "${1:-}" == "clone" ]]; then
  repo="$2"
  dir="$3"
  if [[ "${FAIL_DOC_EXTRACT_CLONE:-0}" == "1" && "$repo" == *"doc-extract"* ]]; then
    echo "simulated doc-extract clone failure" >&2
    exit 2
  fi
  mkdir -p "$dir/.git"
  if [[ "$repo" == *"doc-extract"* ]]; then
    cat >"$dir/SKILL.md" <<'DOC'
---
name: doc-extract
description: Test fixture.
---
DOC
    mkdir -p "$dir/bin"
    touch "$dir/bin/install-deps.sh" "$dir/bin/doctor.sh"
  else
    cat >"$dir/SKILL.md" <<'WIKI'
---
name: wiki
description: Test fixture.
---
WIKI
  fi
  exit 0
fi

echo "unexpected git invocation: $*" >&2
exit 1
FAKE_GIT
chmod +x "$BIN_DIR/git"

CLAUDE_WIKI="$HOME_DIR/.claude/skills/wiki"
CLAUDE_DOC_EXTRACT="$HOME_DIR/.claude/skills/doc-extract"
AGENTS_WIKI="$HOME_DIR/.agents/skills/wiki"
AGENTS_DOC_EXTRACT="$HOME_DIR/.agents/skills/doc-extract"
GEMINI_WIKI="$HOME_DIR/.gemini/skills/wiki"
GEMINI_DOC_EXTRACT="$HOME_DIR/.gemini/skills/doc-extract"
LOG="$TMP/install.log"

run_install() {
  PATH="$BIN_DIR:$PATH" HOME="$HOME_DIR" bash "$ROOT/install.sh" >>"$LOG"
}

expect_link_target() {
  local link="$1"
  local target="$2"
  [[ -L "$link" ]] || { echo "expected symlink: $link"; exit 1; }
  [[ "$(readlink "$link")" == "$target" ]] || {
    echo "expected $link to point at $target, got $(readlink "$link")"
    exit 1
  }
}

run_install

[[ -L "$CLAUDE_WIKI" ]] || { echo "expected Claude wiki symlink"; exit 1; }
[[ -L "$AGENTS_WIKI" ]] || { echo "expected .agents wiki symlink"; exit 1; }
[[ -L "$GEMINI_WIKI" ]] || { echo "expected Gemini wiki symlink"; exit 1; }
[[ -L "$AGENTS_DOC_EXTRACT" ]] || { echo "expected .agents doc-extract symlink"; exit 1; }
[[ -L "$GEMINI_DOC_EXTRACT" ]] || { echo "expected Gemini doc-extract symlink"; exit 1; }

expect_link_target "$AGENTS_WIKI" "$CLAUDE_WIKI"
expect_link_target "$GEMINI_WIKI" "$CLAUDE_WIKI"
expect_link_target "$AGENTS_DOC_EXTRACT" "$CLAUDE_DOC_EXTRACT"
expect_link_target "$GEMINI_DOC_EXTRACT" "$CLAUDE_DOC_EXTRACT"

grep -q '^name: wiki$' "$AGENTS_WIKI/SKILL.md" || {
  echo "expected wiki SKILL.md reachable through .agents export"
  exit 1
}

grep -q '^name: doc-extract$' "$GEMINI_DOC_EXTRACT/SKILL.md" || {
  echo "expected doc-extract SKILL.md reachable through Gemini export"
  exit 1
}

run_install
expect_link_target "$AGENTS_WIKI" "$CLAUDE_WIKI"
expect_link_target "$GEMINI_WIKI" "$CLAUDE_WIKI"

rm "$AGENTS_WIKI"
ln -s "$HOME_DIR/missing-wiki-target" "$AGENTS_WIKI"
run_install
expect_link_target "$AGENTS_WIKI" "$CLAUDE_WIKI"

OTHER_TARGET="$TMP/other-wiki"
mkdir -p "$OTHER_TARGET"
rm "$GEMINI_WIKI"
ln -s "$OTHER_TARGET" "$GEMINI_WIKI"
run_install
expect_link_target "$GEMINI_WIKI" "$OTHER_TARGET"

rm "$AGENTS_DOC_EXTRACT"
printf 'do not replace\n' >"$AGENTS_DOC_EXTRACT"
run_install
[[ ! -L "$AGENTS_DOC_EXTRACT" ]] || {
  echo "expected non-symlink export conflict to be preserved"
  exit 1
}
grep -q 'do not replace' "$AGENTS_DOC_EXTRACT" || {
  echo "expected non-symlink export file content to be preserved"
  exit 1
}

HOME_FAIL="$TMP/home-fail"
mkdir -p "$HOME_FAIL"
FAIL_DOC_EXTRACT_CLONE=1 PATH="$BIN_DIR:$PATH" HOME="$HOME_FAIL" bash "$ROOT/install.sh" >"$TMP/install-fail-doc.log" 2>&1
[[ -L "$HOME_FAIL/.agents/skills/wiki" ]] || {
  echo "expected wiki export even when optional doc-extract install fails"
  exit 1
}
[[ ! -e "$HOME_FAIL/.agents/skills/doc-extract" ]] || {
  echo "did not expect doc-extract export when optional install fails"
  exit 1
}

HOME_CONFLICT="$TMP/home-conflict"
mkdir -p "$HOME_CONFLICT/.claude/skills/wiki"
if PATH="$BIN_DIR:$PATH" HOME="$HOME_CONFLICT" bash "$ROOT/install.sh" >"$TMP/install-conflict.log" 2>&1; then
  echo "expected install to fail when canonical wiki entrypoint is a real directory"
  exit 1
fi
grep -q 'не є symlink' "$TMP/install-conflict.log" || {
  echo "expected clear non-symlink canonical conflict message"
  exit 1
}

echo "install cross-agent links: ok"
