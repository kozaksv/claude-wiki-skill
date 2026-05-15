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
    fetch)
      exit 0
      ;;
    pull)
      if [[ "${FAIL_PULL:-0}" == "1" ]]; then
        echo "simulated pull failure" >&2
        exit 2
      fi
      exit 0
      ;;
    checkout)
      expected_doc_ref="${DOC_EXTRACT_EXPECTED_REF:-main}"
      if [[ "$dir" == *"claude-doc-extract-skill"* && "${2:-}" != "$expected_doc_ref" ]]; then
        echo "doc-extract must be checked out at $expected_doc_ref in this fixture" >&2
        exit 1
      fi
      exit 0
      ;;
    rev-parse)
      expected_doc_ref="${DOC_EXTRACT_EXPECTED_REF:-main}"
      ref="${@: -1}"
      case "$ref" in
        master*|origin/master*|main*|origin/main*|v4.2.0*|origin/v4.2.0*|"$expected_doc_ref"*|"origin/$expected_doc_ref"*)
          exit 0
          ;;
        *)
          exit 1
          ;;
      esac
      ;;
    symbolic-ref)
      exit 0
      ;;
    status)
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
CONFLICT_LOG="$TMP/install-export-conflict.log"
PATH="$BIN_DIR:$PATH" HOME="$HOME_DIR" bash "$ROOT/install.sh" >"$CONFLICT_LOG" 2>&1
expect_link_target "$GEMINI_WIKI" "$OTHER_TARGET"
grep -q 'пропущено' "$CONFLICT_LOG" || {
  echo "expected install summary to mark conflicting export as skipped"
  exit 1
}
grep -q "$GEMINI_WIKI → $OTHER_TARGET" "$CONFLICT_LOG" || {
  echo "expected conflict summary to show the real current target"
  exit 1
}
grep -q 'частину exports пропущено' "$CONFLICT_LOG" || {
  echo "expected install summary to surface aggregate skip warning"
  exit 1
}

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

HOME_DOC_REF="$TMP/home-doc-ref"
mkdir -p "$HOME_DOC_REF"
DOC_EXTRACT_EXPECTED_REF=stable-doc WIKI_DOC_EXTRACT_REF=stable-doc PATH="$BIN_DIR:$PATH" HOME="$HOME_DOC_REF" bash "$ROOT/install.sh" >"$TMP/install-doc-ref.log" 2>&1
expect_link_target "$HOME_DOC_REF/.agents/skills/doc-extract" "$HOME_DOC_REF/.claude/skills/doc-extract"
expect_link_target "$HOME_DOC_REF/.gemini/skills/doc-extract" "$HOME_DOC_REF/.claude/skills/doc-extract"
grep -q "doc-extract.*(@ stable-doc)" "$TMP/install-doc-ref.log" || {
  echo "expected doc-extract summary to show env-selected ref"
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

HOME_FOREIGN="$TMP/home-foreign"
mkdir -p "$HOME_FOREIGN/.claude/skills" "$TMP/foreign-wiki"
ln -s "$TMP/foreign-wiki" "$HOME_FOREIGN/.claude/skills/wiki"
if PATH="$BIN_DIR:$PATH" HOME="$HOME_FOREIGN" bash "$ROOT/install.sh" >"$TMP/install-foreign.log" 2>&1; then
  echo "expected install to fail when canonical wiki symlink points at a foreign target"
  exit 1
fi
[[ "$(readlink "$HOME_FOREIGN/.claude/skills/wiki")" == "$TMP/foreign-wiki" ]] || {
  echo "expected foreign canonical symlink to be preserved"
  exit 1
}
grep -q 'не перезаписую canonical link' "$TMP/install-foreign.log" || {
  echo "expected clear foreign canonical symlink message"
  exit 1
}

HOME_CANONICAL_BROKEN="$TMP/home-canonical-broken"
mkdir -p "$HOME_CANONICAL_BROKEN/.claude/skills"
ln -s "$HOME_CANONICAL_BROKEN/missing-canonical-target" "$HOME_CANONICAL_BROKEN/.claude/skills/wiki"
PATH="$BIN_DIR:$PATH" HOME="$HOME_CANONICAL_BROKEN" bash "$ROOT/install.sh" >"$TMP/install-canonical-broken.log" 2>&1
expect_link_target "$HOME_CANONICAL_BROKEN/.claude/skills/wiki" "$HOME_CANONICAL_BROKEN/claude-wiki-skill"
grep -q 'замінюю битий canonical link' "$TMP/install-canonical-broken.log" || {
  echo "expected broken canonical symlink replacement message"
  exit 1
}

HOME_CANONICAL_FILE="$TMP/home-canonical-file"
mkdir -p "$HOME_CANONICAL_FILE/.claude/skills"
printf 'do not replace\n' >"$HOME_CANONICAL_FILE/.claude/skills/wiki"
if PATH="$BIN_DIR:$PATH" HOME="$HOME_CANONICAL_FILE" bash "$ROOT/install.sh" >"$TMP/install-canonical-file.log" 2>&1; then
  echo "expected install to fail when canonical wiki entrypoint is a plain file"
  exit 1
fi
grep -q 'не є symlink' "$TMP/install-canonical-file.log" || {
  echo "expected clear plain-file canonical conflict message"
  exit 1
}

HOME_TAG_REF="$TMP/home-tag-ref"
mkdir -p "$HOME_TAG_REF"
PATH="$BIN_DIR:$PATH" HOME="$HOME_TAG_REF" bash "$ROOT/install.sh" v4.2.0 >"$TMP/install-tag-ref.log" 2>&1
grep -q "wiki.*(@ v4.2.0)" "$TMP/install-tag-ref.log" || {
  echo "expected v4.2.0 to be an installable ref"
  exit 1
}

HOME_BAD_REF="$TMP/home-bad-ref"
mkdir -p "$HOME_BAD_REF"
if PATH="$BIN_DIR:$PATH" HOME="$HOME_BAD_REF" bash "$ROOT/install.sh" v9.9.9 >"$TMP/install-bad-ref.log" 2>&1; then
  echo "expected install to fail with a friendly message for missing ref"
  exit 1
fi
grep -q "ref 'v9.9.9' не знайдено" "$TMP/install-bad-ref.log" || {
  echo "expected clear missing ref message"
  exit 1
}

HOME_INVALID_REF="$TMP/home-invalid-ref"
mkdir -p "$HOME_INVALID_REF"
if PATH="$BIN_DIR:$PATH" HOME="$HOME_INVALID_REF" bash "$ROOT/install.sh" 'bad;ref' >"$TMP/install-invalid-ref.log" 2>&1; then
  echo "expected install to fail before git for invalid ref syntax"
  exit 1
fi
grep -q "invalid install ref" "$TMP/install-invalid-ref.log" || {
  echo "expected clear invalid ref syntax message"
  exit 1
}

HOME_PULL_FAIL="$TMP/home-pull-fail"
mkdir -p "$HOME_PULL_FAIL/claude-wiki-skill/.git"
if FAIL_PULL=1 PATH="$BIN_DIR:$PATH" HOME="$HOME_PULL_FAIL" bash "$ROOT/install.sh" >"$TMP/install-pull-fail.log" 2>&1; then
  echo "expected install to fail with a friendly message when git pull fails"
  exit 1
fi
grep -q "неможливо оновити $HOME_PULL_FAIL/claude-wiki-skill" "$TMP/install-pull-fail.log" || {
  echo "expected clear git pull failure message"
  exit 1
}

HOME_BLOCKED_EXPORT="$TMP/home-blocked-export"
mkdir -p "$HOME_BLOCKED_EXPORT"
printf 'blocking file\n' >"$HOME_BLOCKED_EXPORT/.agents"
PATH="$BIN_DIR:$PATH" HOME="$HOME_BLOCKED_EXPORT" bash "$ROOT/install.sh" >"$TMP/install-blocked-export.log" 2>&1
[[ -L "$HOME_BLOCKED_EXPORT/.claude/skills/wiki" ]] || {
  echo "expected canonical wiki link even when .agents export root is blocked"
  exit 1
}
[[ ! -e "$HOME_BLOCKED_EXPORT/.agents/skills/wiki" ]] || {
  echo "did not expect .agents wiki export when .agents is a plain file"
  exit 1
}
grep -q "$HOME_BLOCKED_EXPORT/.agents існує і не є директорією" "$TMP/install-blocked-export.log" || {
  echo "expected blocked export root file-vs-directory conflict to be reported"
  exit 1
}
grep -q "$HOME_BLOCKED_EXPORT/.agents/skills/wiki .*пропущено" "$TMP/install-blocked-export.log" || {
  echo "expected blocked .agents wiki export to be marked skipped in summary"
  exit 1
}
if grep -q "export: $HOME_BLOCKED_EXPORT/.agents/skills/wiki" "$TMP/install-blocked-export.log"; then
  echo "blocked .agents wiki export was falsely reported as created"
  exit 1
fi

HOME_ROUNDTRIP="$TMP/home-roundtrip"
mkdir -p "$HOME_ROUNDTRIP"
PATH="$BIN_DIR:$PATH" HOME="$HOME_ROUNDTRIP" bash "$ROOT/install.sh" >"$TMP/install-roundtrip-1.log" 2>&1
PATH="$BIN_DIR:$PATH" HOME="$HOME_ROUNDTRIP" bash "$ROOT/uninstall.sh" >"$TMP/uninstall-roundtrip.log" 2>&1
for link in \
  "$HOME_ROUNDTRIP/.claude/skills/wiki" \
  "$HOME_ROUNDTRIP/.claude/skills/doc-extract" \
  "$HOME_ROUNDTRIP/.agents/skills/wiki" \
  "$HOME_ROUNDTRIP/.gemini/skills/wiki" \
  "$HOME_ROUNDTRIP/.agents/skills/doc-extract" \
  "$HOME_ROUNDTRIP/.gemini/skills/doc-extract"; do
  [ ! -e "$link" ] && [ ! -L "$link" ] || {
    echo "expected uninstall to remove round-trip symlink: $link"
    exit 1
  }
done
PATH="$BIN_DIR:$PATH" HOME="$HOME_ROUNDTRIP" bash "$ROOT/install.sh" >"$TMP/install-roundtrip-2.log" 2>&1
expect_link_target "$HOME_ROUNDTRIP/.agents/skills/wiki" "$HOME_ROUNDTRIP/.claude/skills/wiki"
expect_link_target "$HOME_ROUNDTRIP/.gemini/skills/doc-extract" "$HOME_ROUNDTRIP/.claude/skills/doc-extract"

echo "install cross-agent links: ok"
