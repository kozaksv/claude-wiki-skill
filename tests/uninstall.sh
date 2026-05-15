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

if [[ "${1:-}" == "-C" && "${3:-}" == "status" && "${4:-}" == "--porcelain" ]]; then
  dir="$2"
  if [[ -e "$dir/DIRTY" ]]; then
    echo " M DIRTY"
  fi
  exit 0
fi

echo "unexpected git invocation: $*" >&2
exit 1
FAKE_GIT
chmod +x "$BIN_DIR/git"

expect_missing() {
  local path="$1"
  [ ! -e "$path" ] && [ ! -L "$path" ] || {
    echo "expected missing: $path"
    exit 1
  }
}

expect_exists() {
  local path="$1"
  [ -e "$path" ] || {
    echo "expected existing: $path"
    exit 1
  }
}

expect_link_target() {
  local link="$1"
  local target="$2"
  [ -L "$link" ] || {
    echo "expected symlink: $link"
    exit 1
  }
  [ "$(readlink "$link")" = "$target" ] || {
    echo "expected $link to point at $target, got $(readlink "$link")"
    exit 1
  }
}

setup_installed_tree() {
  rm -rf "$HOME_DIR"
  mkdir -p "$HOME_DIR/.claude/skills" "$HOME_DIR/.agents/skills" "$HOME_DIR/.gemini/skills"
  mkdir -p "$HOME_DIR/claude-wiki-skill/.git" "$HOME_DIR/claude-doc-extract-skill/.git"
  ln -s "$HOME_DIR/claude-wiki-skill" "$HOME_DIR/.claude/skills/wiki"
  ln -s "$HOME_DIR/claude-doc-extract-skill" "$HOME_DIR/.claude/skills/doc-extract"
  ln -s "$HOME_DIR/.claude/skills/wiki" "$HOME_DIR/.agents/skills/wiki"
  ln -s "$HOME_DIR/.claude/skills/wiki" "$HOME_DIR/.gemini/skills/wiki"
  ln -s "$HOME_DIR/.claude/skills/doc-extract" "$HOME_DIR/.agents/skills/doc-extract"
  ln -s "$HOME_DIR/.claude/skills/doc-extract" "$HOME_DIR/.gemini/skills/doc-extract"
}

setup_installed_tree
PATH="$BIN_DIR:$PATH" HOME="$HOME_DIR" bash "$ROOT/uninstall.sh" >"$TMP/uninstall-default.log" 2>&1

for path in \
  "$HOME_DIR/.claude/skills/wiki" \
  "$HOME_DIR/.claude/skills/doc-extract" \
  "$HOME_DIR/.agents/skills/wiki" \
  "$HOME_DIR/.gemini/skills/wiki" \
  "$HOME_DIR/.agents/skills/doc-extract" \
  "$HOME_DIR/.gemini/skills/doc-extract"; do
  expect_missing "$path"
done
expect_exists "$HOME_DIR/.agents"
expect_exists "$HOME_DIR/.gemini"
expect_exists "$HOME_DIR/claude-wiki-skill"
expect_exists "$HOME_DIR/claude-doc-extract-skill"
grep -q 'Real clone directories kept' "$TMP/uninstall-default.log" || {
  echo "expected default uninstall to keep real clone directories"
  exit 1
}

PATH="$BIN_DIR:$PATH" HOME="$HOME_DIR" bash "$ROOT/uninstall.sh" >"$TMP/uninstall-rerun.log" 2>&1
grep -q 'already absent' "$TMP/uninstall-rerun.log" || {
  echo "expected idempotent already-absent reporting"
  exit 1
}

setup_installed_tree
rm "$HOME_DIR/.agents/skills/wiki"
printf 'do not remove\n' >"$HOME_DIR/.agents/skills/wiki"
rm "$HOME_DIR/.claude/skills/doc-extract"
mkdir -p "$HOME_DIR/.claude/skills/doc-extract"
PATH="$BIN_DIR:$PATH" HOME="$HOME_DIR" bash "$ROOT/uninstall.sh" >"$TMP/uninstall-conflict.log" 2>&1
grep -q "$HOME_DIR/.agents/skills/wiki .*skipped" "$TMP/uninstall-conflict.log" || {
  echo "expected plain-file export to be skipped"
  exit 1
}
grep -q "$HOME_DIR/.claude/skills/doc-extract .*skipped" "$TMP/uninstall-conflict.log" || {
  echo "expected real canonical directory to be skipped"
  exit 1
}
grep -q 'do not remove' "$HOME_DIR/.agents/skills/wiki" || {
  echo "expected plain-file export content to be preserved"
  exit 1
}
expect_exists "$HOME_DIR/.claude/skills/doc-extract"

setup_installed_tree
mkdir -p "$TMP/foreign-wiki" "$TMP/foreign-doc-extract"
rm "$HOME_DIR/.agents/skills/wiki" "$HOME_DIR/.claude/skills/doc-extract"
ln -s "$TMP/foreign-wiki" "$HOME_DIR/.agents/skills/wiki"
ln -s "$TMP/foreign-doc-extract" "$HOME_DIR/.claude/skills/doc-extract"
PATH="$BIN_DIR:$PATH" HOME="$HOME_DIR" bash "$ROOT/uninstall.sh" >"$TMP/uninstall-foreign-symlink.log" 2>&1
expect_link_target "$HOME_DIR/.agents/skills/wiki" "$TMP/foreign-wiki"
expect_link_target "$HOME_DIR/.claude/skills/doc-extract" "$TMP/foreign-doc-extract"
grep -q "$HOME_DIR/.agents/skills/wiki .*skipped.*points elsewhere" "$TMP/uninstall-foreign-symlink.log" || {
  echo "expected foreign export symlink to be skipped"
  exit 1
}
grep -q "$HOME_DIR/.claude/skills/doc-extract .*skipped.*points elsewhere" "$TMP/uninstall-foreign-symlink.log" || {
  echo "expected foreign canonical symlink to be skipped"
  exit 1
}

setup_installed_tree
touch "$HOME_DIR/claude-doc-extract-skill/DIRTY"
PATH="$BIN_DIR:$PATH" HOME="$HOME_DIR" bash "$ROOT/uninstall.sh" --remove-clones >"$TMP/uninstall-clones.log" 2>&1
expect_missing "$HOME_DIR/claude-wiki-skill"
expect_exists "$HOME_DIR/claude-doc-extract-skill"
grep -q "$HOME_DIR/claude-doc-extract-skill .*local changes" "$TMP/uninstall-clones.log" || {
  echo "expected dirty clone to be preserved"
  exit 1
}

echo "uninstall: ok"
