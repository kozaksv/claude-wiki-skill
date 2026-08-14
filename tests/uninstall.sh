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
  mkdir -p "$HOME_DIR/.claude/skills" "$HOME_DIR/.agents/skills" "$HOME_DIR/.gemini/skills" "$HOME_DIR/.qwen/skills"
  mkdir -p "$HOME_DIR/claude-wiki-skill/.git" "$HOME_DIR/claude-doc-extract-skill/.git"
  ln -s "$HOME_DIR/claude-wiki-skill" "$HOME_DIR/.claude/skills/wiki"
  ln -s "$HOME_DIR/claude-doc-extract-skill" "$HOME_DIR/.claude/skills/doc-extract"
  ln -s "$HOME_DIR/.claude/skills/wiki" "$HOME_DIR/.agents/skills/wiki"
  ln -s "$HOME_DIR/.claude/skills/wiki" "$HOME_DIR/.gemini/skills/wiki"
  ln -s "$HOME_DIR/.claude/skills/wiki" "$HOME_DIR/.qwen/skills/wiki"
  ln -s "$HOME_DIR/.claude/skills/doc-extract" "$HOME_DIR/.agents/skills/doc-extract"
  ln -s "$HOME_DIR/.claude/skills/doc-extract" "$HOME_DIR/.gemini/skills/doc-extract"
  ln -s "$HOME_DIR/.claude/skills/doc-extract" "$HOME_DIR/.qwen/skills/doc-extract"
}

setup_installed_tree
PATH="$BIN_DIR:$PATH" HOME="$HOME_DIR" bash "$ROOT/uninstall.sh" >"$TMP/uninstall-default.log" 2>&1

for path in \
  "$HOME_DIR/.claude/skills/wiki" \
  "$HOME_DIR/.claude/skills/doc-extract" \
  "$HOME_DIR/.agents/skills/wiki" \
  "$HOME_DIR/.gemini/skills/wiki" \
  "$HOME_DIR/.qwen/skills/wiki" \
  "$HOME_DIR/.agents/skills/doc-extract" \
  "$HOME_DIR/.gemini/skills/doc-extract" \
  "$HOME_DIR/.qwen/skills/doc-extract"; do
  expect_missing "$path"
done
expect_exists "$HOME_DIR/.agents"
expect_exists "$HOME_DIR/.gemini"
expect_exists "$HOME_DIR/.qwen"
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

# A foreign canonical symlink ($SKILLS_ROOT/wiki -> attacker dir) whose
# hooks/uninstall-hooks.sh is executable must NEVER be run — the uninstaller
# is invoked through the real clone dir only (codex-атк P1).
setup_installed_tree
mkdir -p "$TMP/evil/hooks"
cat >"$TMP/evil/hooks/uninstall-hooks.sh" <<EVIL
#!/usr/bin/env bash
touch "$TMP/evil-ran"
EVIL
chmod +x "$TMP/evil/hooks/uninstall-hooks.sh"
rm "$HOME_DIR/.claude/skills/wiki"
ln -s "$TMP/evil" "$HOME_DIR/.claude/skills/wiki"
PATH="$BIN_DIR:$PATH" HOME="$HOME_DIR" bash "$ROOT/uninstall.sh" >"$TMP/uninstall-foreign-hook.log" 2>&1
expect_missing "$TMP/evil-ran"

# An UNVERIFIED $SKILL_DIR (exists, carries an executable
# hooks/uninstall-hooks.sh, but is NOT a git clone — stale/unrelated/
# attacker-planted dir at the fixed path) must never have its script run;
# with a lingering hook marker it falls into the orphaned-hooks branch
# instead (codex-кор P1, wave5).
setup_installed_tree
rm -rf "$HOME_DIR/claude-wiki-skill/.git"
mkdir -p "$HOME_DIR/claude-wiki-skill/hooks" "$HOME_DIR/.claude"
cat >"$HOME_DIR/claude-wiki-skill/hooks/uninstall-hooks.sh" <<PLANTED
#!/usr/bin/env bash
touch "$TMP/planted-ran"
PLANTED
chmod +x "$HOME_DIR/claude-wiki-skill/hooks/uninstall-hooks.sh"
printf '{"hooks":{"SessionStart":[{"hooks":[{"command":"x /skills/wiki/hooks/session-start.sh"}]}]}}\n' >"$HOME_DIR/.claude/settings.json"
PATH="$BIN_DIR:$PATH" HOME="$HOME_DIR" bash "$ROOT/uninstall.sh" >"$TMP/uninstall-unverified-clone.log" 2>&1
expect_missing "$TMP/planted-ran"
grep -q "записи hooks лишились" "$TMP/uninstall-unverified-clone.log" || {
  echo "expected unverified-clone case to fall into the orphaned-hooks branch"
  exit 1
}

# Missing clone uninstaller + orphaned hook marker in settings.json: the
# clone that hosts the recovery script must be preserved under --remove-clones
# (agy-кор / codex-атк P1 — the "symlink absent / script missing" case).
setup_installed_tree
mkdir -p "$HOME_DIR/.claude"
printf '{"hooks":{"SessionStart":[{"hooks":[{"command":"x /skills/wiki/hooks/session-start.sh"}]}]}}\n' >"$HOME_DIR/.claude/settings.json"
PATH="$BIN_DIR:$PATH" HOME="$HOME_DIR" bash "$ROOT/uninstall.sh" --remove-clones >"$TMP/uninstall-orphan-marker.log" 2>&1
expect_exists "$HOME_DIR/claude-wiki-skill"
expect_missing "$HOME_DIR/claude-doc-extract-skill"
grep -q "git hooks removal failed" "$TMP/uninstall-orphan-marker.log" || {
  echo "expected orphaned-marker clone to be preserved under --remove-clones"
  exit 1
}

# Present, working clone uninstaller is actually invoked via the real clone
# dir, and a successful run does not block clone removal.
setup_installed_tree
mkdir -p "$HOME_DIR/claude-wiki-skill/hooks"
cat >"$HOME_DIR/claude-wiki-skill/hooks/uninstall-hooks.sh" <<HOOK
#!/usr/bin/env bash
touch "$TMP/real-hook-ran"
HOOK
chmod +x "$HOME_DIR/claude-wiki-skill/hooks/uninstall-hooks.sh"
PATH="$BIN_DIR:$PATH" HOME="$HOME_DIR" bash "$ROOT/uninstall.sh" --remove-clones >"$TMP/uninstall-hook-run.log" 2>&1
expect_exists "$TMP/real-hook-ran"
expect_missing "$HOME_DIR/claude-wiki-skill"

# A verified clone (real .git dir) whose uninstall-hooks.sh has LOST its
# executable bit (Windows clone, zip/copy) must still run the cleanup script
# via `bash`, not fall back to the orphaned-hooks warning path.
setup_installed_tree
mkdir -p "$HOME_DIR/claude-wiki-skill/hooks"
cat >"$HOME_DIR/claude-wiki-skill/hooks/uninstall-hooks.sh" <<HOOK
#!/usr/bin/env bash
touch "$TMP/noexec-hook-ran"
HOOK
chmod -x "$HOME_DIR/claude-wiki-skill/hooks/uninstall-hooks.sh"
PATH="$BIN_DIR:$PATH" HOME="$HOME_DIR" bash "$ROOT/uninstall.sh" --remove-clones >"$TMP/uninstall-noexec-hook.log" 2>&1
expect_exists "$TMP/noexec-hook-ran"
expect_missing "$HOME_DIR/claude-wiki-skill"
grep -q "записи hooks лишились" "$TMP/uninstall-noexec-hook.log" && {
  echo "expected non-executable-but-present uninstaller to still run cleanup, not warn about orphaned hooks"
  exit 1
}

# --- t11-orphan-guard-files: orphan-hook guard checks both claude and qwen
# settings files, via the single scan_marker three-state check. -----------

HOOK_MARKER_SNIPPET='{"hooks":{"SessionStart":[{"hooks":[{"command":"x /skills/wiki/hooks/session-start.sh"}]}]}}'
NO_MARKER_SNIPPET='{"hooks":{"SessionStart":[]}}'

# Qwen-only orphan (main regression): marker present ONLY in
# ~/.qwen/settings.json (~/.claude/settings.json has none), hooks/
# uninstall-hooks.sh is absent from the clone (default setup_installed_tree
# state) -> $SKILL_DIR must NOT be removed, and the warning must name the
# qwen file.
setup_installed_tree
printf '%s\n' "$NO_MARKER_SNIPPET" >"$HOME_DIR/.claude/settings.json"
printf '%s\n' "$HOOK_MARKER_SNIPPET" >"$HOME_DIR/.qwen/settings.json"
PATH="$BIN_DIR:$PATH" HOME="$HOME_DIR" bash "$ROOT/uninstall.sh" --remove-clones >"$TMP/uninstall-qwen-orphan.log" 2>&1
expect_exists "$HOME_DIR/claude-wiki-skill"
grep -q "$HOME_DIR/.qwen/settings.json" "$TMP/uninstall-qwen-orphan.log" || {
  echo "expected qwen-only orphan marker to name the qwen settings file"
  exit 1
}
grep -q "записи hooks лишились" "$TMP/uninstall-qwen-orphan.log" || {
  echo "expected qwen-only orphan marker to hit the existing orphaned-hooks message"
  exit 1
}

# Mirror: marker present ONLY in ~/.claude/settings.json,
# ~/.qwen/settings.json absent entirely -> existing behavior preserved, and
# the collected log carries no "No such file or directory" (the existence
# guard must skip the missing path silently, not abort or leak a stat
# error) and reaches the lines printed after the guard.
setup_installed_tree
printf '%s\n' "$HOOK_MARKER_SNIPPET" >"$HOME_DIR/.claude/settings.json"
PATH="$BIN_DIR:$PATH" HOME="$HOME_DIR" bash "$ROOT/uninstall.sh" --remove-clones >"$TMP/uninstall-claude-orphan.log" 2>&1
expect_exists "$HOME_DIR/claude-wiki-skill"
grep -q "$HOME_DIR/.claude/settings.json" "$TMP/uninstall-claude-orphan.log" || {
  echo "expected claude-only orphan marker to name the claude settings file"
  exit 1
}
grep -q "No such file or directory" "$TMP/uninstall-claude-orphan.log" && {
  echo "expected missing qwen settings.json to be skipped silently, not stat-errored"
  exit 1
}
grep -q "Real clone directories" "$TMP/uninstall-claude-orphan.log" || {
  echo "expected the scan over both settings files to complete and reach the summary section"
  exit 1
}

# Guard is not too wide: both files exist and are readable, neither carries
# the marker -> clone removed as before, and no "could not verify" line
# appears.
setup_installed_tree
printf '%s\n' "$NO_MARKER_SNIPPET" >"$HOME_DIR/.claude/settings.json"
printf '%s\n' "$NO_MARKER_SNIPPET" >"$HOME_DIR/.qwen/settings.json"
PATH="$BIN_DIR:$PATH" HOME="$HOME_DIR" bash "$ROOT/uninstall.sh" --remove-clones >"$TMP/uninstall-no-marker.log" 2>&1
expect_missing "$HOME_DIR/claude-wiki-skill"
grep -q "перевірити наявність записів hooks неможливо" "$TMP/uninstall-no-marker.log" && {
  echo "expected no unverifiable-file line when neither settings file carries the marker"
  exit 1
}

# Both files carry the marker -> both are listed in the warning.
setup_installed_tree
printf '%s\n' "$HOOK_MARKER_SNIPPET" >"$HOME_DIR/.claude/settings.json"
printf '%s\n' "$HOOK_MARKER_SNIPPET" >"$HOME_DIR/.qwen/settings.json"
PATH="$BIN_DIR:$PATH" HOME="$HOME_DIR" bash "$ROOT/uninstall.sh" --remove-clones >"$TMP/uninstall-both-marked.log" 2>&1
expect_exists "$HOME_DIR/claude-wiki-skill"
grep -q "$HOME_DIR/.claude/settings.json" "$TMP/uninstall-both-marked.log" || {
  echo "expected both-marked case to name the claude settings file"
  exit 1
}
grep -q "$HOME_DIR/.qwen/settings.json" "$TMP/uninstall-both-marked.log" || {
  echo "expected both-marked case to name the qwen settings file"
  exit 1
}

# Unreadable settings file = fail-closed (spec invariant "could not verify
# = do NOT delete"): a DIRECTORY sits at ~/.qwen/settings.json (not a
# regular file), no marker in claude's file -> $SKILL_DIR must NOT be
# removed, the output names the qwen path as unverifiable, and the existing
# "git hooks removal failed" substring still appears (relied on by the
# --remove-clones skip message).
setup_installed_tree
printf '%s\n' "$NO_MARKER_SNIPPET" >"$HOME_DIR/.claude/settings.json"
rm -rf "$HOME_DIR/.qwen/settings.json"
mkdir -p "$HOME_DIR/.qwen/settings.json"
PATH="$BIN_DIR:$PATH" HOME="$HOME_DIR" bash "$ROOT/uninstall.sh" --remove-clones >"$TMP/uninstall-unreadable-dir.log" 2>&1
expect_exists "$HOME_DIR/claude-wiki-skill"
grep -q "не вдалося прочитати $HOME_DIR/.qwen/settings.json" "$TMP/uninstall-unreadable-dir.log" || {
  echo "expected directory-at-settings-path to be reported as unverifiable with the qwen path"
  exit 1
}
grep -q "git hooks removal failed" "$TMP/uninstall-unreadable-dir.log" || {
  echo "expected the existing clone-preserved message to still print for the unverified case"
  exit 1
}

# FIFO at the settings path (hang regression): a FIFO with nobody writing to
# it would hang grep's open() forever without the -f pre-check. Wrapped in
# an external timeout as a CI safety net; the real assertion is that
# uninstall.sh itself terminates well within the default read deadline.
if command -v timeout >/dev/null 2>&1; then
  _timeout="timeout 20"
elif command -v gtimeout >/dev/null 2>&1; then
  _timeout="gtimeout 20"
else
  _timeout=""
fi
setup_installed_tree
printf '%s\n' "$NO_MARKER_SNIPPET" >"$HOME_DIR/.claude/settings.json"
rm -f "$HOME_DIR/.qwen/settings.json"
mkfifo "$HOME_DIR/.qwen/settings.json"
_t0=$(date +%s)
PATH="$BIN_DIR:$PATH" HOME="$HOME_DIR" $_timeout bash "$ROOT/uninstall.sh" --remove-clones >"$TMP/uninstall-fifo.log" 2>&1
_rc=$?
_t1=$(date +%s)
[ "$_rc" -ne 124 ] || {
  echo "expected uninstall.sh to terminate on its own, not be killed by the external timeout wrapper"
  exit 1
}
[ $((_t1 - _t0)) -le 15 ] || {
  echo "expected uninstall.sh to finish near the default read deadline, took $((_t1 - _t0))s"
  exit 1
}
expect_exists "$HOME_DIR/claude-wiki-skill"
grep -q "не вдалося прочитати $HOME_DIR/.qwen/settings.json" "$TMP/uninstall-fifo.log" || {
  echo "expected FIFO-at-settings-path to be reported as unverifiable with the qwen path"
  exit 1
}

# Read deadline fires (direct test of the second line of defense, not the
# -f pre-check): the pre-check is disabled via the test seam, so grep
# genuinely blocks in open() on the FIFO, and the sleep-guard must kill it.
setup_installed_tree
printf '%s\n' "$NO_MARKER_SNIPPET" >"$HOME_DIR/.claude/settings.json"
rm -f "$HOME_DIR/.qwen/settings.json"
mkfifo "$HOME_DIR/.qwen/settings.json"
_t0=$(date +%s)
PATH="$BIN_DIR:$PATH" HOME="$HOME_DIR" WIKI_UNINSTALL_TEST_SKIP_TYPE_CHECK=1 WIKI_UNINSTALL_MARKER_TIMEOUT=1 \
  bash "$ROOT/uninstall.sh" --remove-clones >"$TMP/uninstall-fifo-deadline.log" 2>&1
_t1=$(date +%s)
[ $((_t1 - _t0)) -le 8 ] || {
  echo "expected the read-deadline guard to fire within a few seconds, took $((_t1 - _t0))s"
  exit 1
}
expect_exists "$HOME_DIR/claude-wiki-skill"

# Mirror for permissions: an unreadable (chmod 000) regular file hits the
# same fail-closed branch via grep's own read-error exit status (>=2), not
# the -f pre-check. Skipped (not failed) under root, which ignores 000.
if [ "$(id -u)" != "0" ]; then
  setup_installed_tree
  printf '%s\n' "$NO_MARKER_SNIPPET" >"$HOME_DIR/.claude/settings.json"
  printf '%s\n' "$NO_MARKER_SNIPPET" >"$HOME_DIR/.qwen/settings.json"
  chmod 000 "$HOME_DIR/.qwen/settings.json"
  PATH="$BIN_DIR:$PATH" HOME="$HOME_DIR" bash "$ROOT/uninstall.sh" --remove-clones >"$TMP/uninstall-chmod000.log" 2>&1
  chmod 644 "$HOME_DIR/.qwen/settings.json" 2>/dev/null || true
  expect_exists "$HOME_DIR/claude-wiki-skill"
  grep -q "не вдалося прочитати $HOME_DIR/.qwen/settings.json" "$TMP/uninstall-chmod000.log" || {
    echo "expected chmod-000 settings file to be reported as unverifiable"
    exit 1
  }
else
  echo "uninstall: skipping chmod-000 unreadable-file case (running as root)"
fi

# --- wave3: legacy Qwen wrapper marker is ALSO an orphan marker (codex-атк
# P1). hooks/uninstall-hooks.sh strips `/.qwen/hooks/wiki-session-start.sh`
# for the qwen client alongside the canonical marker, so a not-yet-migrated
# Qwen-only install must block --remove-clones exactly like a canonical one.
LEGACY_QWEN_SNIPPET='{"hooks":{"SessionStart":[{"hooks":[{"command":"test -x \"/home/u/.qwen/hooks/wiki-session-start.sh\" && \"/home/u/.qwen/hooks/wiki-session-start.sh\" || exit 0"}]}]}}'

setup_installed_tree
printf '%s\n' "$NO_MARKER_SNIPPET" >"$HOME_DIR/.claude/settings.json"
printf '%s\n' "$LEGACY_QWEN_SNIPPET" >"$HOME_DIR/.qwen/settings.json"
PATH="$BIN_DIR:$PATH" HOME="$HOME_DIR" bash "$ROOT/uninstall.sh" --remove-clones >"$TMP/uninstall-legacy-qwen.log" 2>&1
expect_exists "$HOME_DIR/claude-wiki-skill"
grep -q "$HOME_DIR/.qwen/settings.json" "$TMP/uninstall-legacy-qwen.log" || {
  echo "expected legacy qwen wrapper marker to be detected as an orphan in the qwen settings file"
  exit 1
}
grep -q "git hooks removal failed" "$TMP/uninstall-legacy-qwen.log" || {
  echo "expected legacy qwen wrapper marker to preserve the clone under --remove-clones"
  exit 1
}

# Marker sets are PER CLIENT, mirroring deregister_from: the legacy qwen
# wrapper path in ~/.claude/settings.json is not a claude marker (uninstall-
# hooks.sh would never strip it there), so it must NOT block removal forever.
setup_installed_tree
printf '%s\n' "$LEGACY_QWEN_SNIPPET" >"$HOME_DIR/.claude/settings.json"
printf '%s\n' "$NO_MARKER_SNIPPET" >"$HOME_DIR/.qwen/settings.json"
PATH="$BIN_DIR:$PATH" HOME="$HOME_DIR" bash "$ROOT/uninstall.sh" --remove-clones >"$TMP/uninstall-legacy-in-claude.log" 2>&1
expect_missing "$HOME_DIR/claude-wiki-skill"

# --- wave3 / t12: marker recheck + clone deletion run under the SAME
# settings locks install-hooks.sh takes (codex-атк P1). -------------------

# Locks are released on the way out — no lockdir may survive any run.
expect_no_lockdirs() {
  local label="$1" leftover
  leftover="$(find "$HOME_DIR" -maxdepth 3 -name '*.lockdir' 2>/dev/null | head -1)"
  [ -z "$leftover" ] || {
    echo "$label: expected no leftover settings lockdir, found $leftover"
    exit 1
  }
}
expect_no_lockdirs "no-marker run"

# A. TOCTOU regression, the main proof: install-hooks.sh takes the locks
#    FIRST and writes its entries while uninstall.sh waits. Without a shared
#    mutex the guard's scan would run before those writes, see a clean file,
#    and delete the clone with live entries left behind — exactly the orphan
#    this closes. Deterministic: uninstall can only acquire each lock after
#    install has written that client's file and released it.
if command -v python3 >/dev/null 2>&1; then
  setup_installed_tree
  printf '{}\n' >"$HOME_DIR/.claude/settings.json"
  printf '{}\n' >"$HOME_DIR/.qwen/settings.json"
  ( HOME="$HOME_DIR" WIKI_HOOKS_TEST_SLEEP_AFTER_LOCK=2 WIKI_HOOKS_LOCK_TIMEOUT=20 WIKI_HOOKS_LOCK_POLL=0.1 \
      bash "$ROOT/hooks/install-hooks.sh" >"$TMP/toctou-install.log" 2>&1 ) &
  _install_pid=$!
  sleep 0.3
  PATH="$BIN_DIR:$PATH" HOME="$HOME_DIR" WIKI_HOOKS_LOCK_TIMEOUT=20 WIKI_HOOKS_LOCK_POLL=0.1 \
    bash "$ROOT/uninstall.sh" --remove-clones >"$TMP/toctou-uninstall.log" 2>&1
  wait "$_install_pid" || true
  expect_exists "$HOME_DIR/claude-wiki-skill"
  grep -q "git hooks removal failed" "$TMP/toctou-uninstall.log" || {
    echo "expected concurrently-written hook entries to preserve the clone"
    exit 1
  }
  # Asserted on the claude file only, deliberately: the claude lock handoff
  # is deterministic (uninstall can only take it after install wrote and
  # released it), whereas which process wins the qwen lock afterwards is
  # scheduler-dependent — and the mutex does not promise an order there.
  grep -q '/skills/wiki/hooks/' "$HOME_DIR/.claude/settings.json" || {
    echo "expected the concurrent installer to have written its marker into the claude settings file"
    exit 1
  }
  grep -q "$HOME_DIR/.claude/settings.json" "$TMP/toctou-uninstall.log" || {
    echo "expected the locked recheck to report the orphan marker in the claude settings file"
    exit 1
  }
  grep -q "не вдалося взяти лок" "$TMP/toctou-uninstall.log" && {
    echo "expected honest lock waiting, not a lock-acquisition failure"
    exit 1
  }
  grep -q "could not acquire lock" "$TMP/toctou-install.log" && {
    echo "expected the installer not to be starved by the uninstall guard"
    exit 1
  }
  expect_no_lockdirs "toctou scenario"
else
  echo "uninstall: skipping lock TOCTOU case (python3 unavailable)"
fi

# B. A foreign holder of either lock is never bypassed: the guard cannot
#    verify, so the clone stays. The qwen variant also proves the FIRST
#    (claude) lock is released before bailing out.
_hold_lock_and_run() {
  local lockdir="$1" log="$2"
  sleep 30 &
  local sleeper=$!
  mkdir -p "$lockdir"
  printf '%s\n' "$sleeper" >"$lockdir/pid"
  PATH="$BIN_DIR:$PATH" HOME="$HOME_DIR" WIKI_HOOKS_LOCK_TIMEOUT=1 WIKI_HOOKS_LOCK_POLL=0.1 \
    bash "$ROOT/uninstall.sh" --remove-clones >"$log" 2>&1
  kill "$sleeper" 2>/dev/null || true
  wait "$sleeper" 2>/dev/null || true
  rm -rf "$lockdir"
}

setup_installed_tree
printf '%s\n' "$NO_MARKER_SNIPPET" >"$HOME_DIR/.claude/settings.json"
printf '%s\n' "$NO_MARKER_SNIPPET" >"$HOME_DIR/.qwen/settings.json"
_hold_lock_and_run "$HOME_DIR/.claude/settings.json.lockdir" "$TMP/uninstall-locked-claude.log"
expect_exists "$HOME_DIR/claude-wiki-skill"
grep -q "не вдалося взяти лок на $HOME_DIR/.claude/settings.json" "$TMP/uninstall-locked-claude.log" || {
  echo "expected a held claude lock to be reported and the clone preserved"
  exit 1
}

setup_installed_tree
printf '%s\n' "$NO_MARKER_SNIPPET" >"$HOME_DIR/.claude/settings.json"
printf '%s\n' "$NO_MARKER_SNIPPET" >"$HOME_DIR/.qwen/settings.json"
_hold_lock_and_run "$HOME_DIR/.qwen/settings.json.lockdir" "$TMP/uninstall-locked-qwen.log"
expect_exists "$HOME_DIR/claude-wiki-skill"
grep -q "не вдалося взяти лок на $HOME_DIR/.qwen/settings.json" "$TMP/uninstall-locked-qwen.log" || {
  echo "expected a held qwen lock to be reported and the clone preserved"
  exit 1
}
expect_missing "$HOME_DIR/.claude/settings.json.lockdir"

# C. Lock lib unavailable (script copied out of its clone) -> the locked
#    recheck is impossible, so the clone is conservatively kept.
setup_installed_tree
mkdir -p "$TMP/detached"
cp "$ROOT/uninstall.sh" "$TMP/detached/uninstall.sh"
printf '%s\n' "$NO_MARKER_SNIPPET" >"$HOME_DIR/.claude/settings.json"
PATH="$BIN_DIR:$PATH" HOME="$HOME_DIR" bash "$TMP/detached/uninstall.sh" --remove-clones >"$TMP/uninstall-nolib.log" 2>&1
expect_exists "$HOME_DIR/claude-wiki-skill"
grep -q "перевірити записи hooks під локом неможливо" "$TMP/uninstall-nolib.log" || {
  echo "expected a missing settings-lock lib to be reported as an explicit conservative skip"
  exit 1
}

# D. Claude-only machine: no ~/.qwen at all -> only the claude lock is
#    taken, ~/.qwen is NOT created just to host a lockdir, and the clean
#    clone is still removed.
setup_installed_tree
rm -rf "$HOME_DIR/.qwen"
printf '%s\n' "$NO_MARKER_SNIPPET" >"$HOME_DIR/.claude/settings.json"
PATH="$BIN_DIR:$PATH" HOME="$HOME_DIR" bash "$ROOT/uninstall.sh" --remove-clones >"$TMP/uninstall-claude-only.log" 2>&1
expect_missing "$HOME_DIR/claude-wiki-skill"
expect_missing "$HOME_DIR/.qwen"
grep -q "не вдалося взяти лок" "$TMP/uninstall-claude-only.log" && {
  echo "expected no lock failure on a claude-only machine"
  exit 1
}
expect_no_lockdirs "claude-only run"

# D-2. Mirror of D: qwen-only machine, no ~/.claude at all -> only the qwen
#      lock is taken, ~/.claude is NOT created just to host a lockdir, and
#      the clean clone is still removed.
setup_installed_tree
rm -rf "$HOME_DIR/.claude"
printf '%s\n' "$NO_MARKER_SNIPPET" >"$HOME_DIR/.qwen/settings.json"
PATH="$BIN_DIR:$PATH" HOME="$HOME_DIR" bash "$ROOT/uninstall.sh" --remove-clones >"$TMP/uninstall-qwen-only.log" 2>&1
expect_missing "$HOME_DIR/claude-wiki-skill"
expect_missing "$HOME_DIR/.claude"
grep -q "не вдалося взяти лок" "$TMP/uninstall-qwen-only.log" && {
  echo "expected no lock failure on a qwen-only machine"
  exit 1
}
expect_no_lockdirs "qwen-only run"

# E. No lock nesting (self-deadlock regression). The REAL hooks/
#    uninstall-hooks.sh (T8) — which takes the SAME two settings locks
#    itself — is present in the verified clone. Step 1 of uninstall.sh calls
#    it OUTSIDE the critical section, so it must acquire, use, and fully
#    release both locks before the critical section ever asks for them
#    again. If that call were ever moved inside the critical section, this
#    run would block for the full timeout and fail with "could not acquire
#    lock".
if command -v python3 >/dev/null 2>&1; then
  setup_installed_tree
  mkdir -p "$HOME_DIR/claude-wiki-skill/hooks/lib"
  cp "$ROOT/hooks/uninstall-hooks.sh" "$HOME_DIR/claude-wiki-skill/hooks/uninstall-hooks.sh"
  cp "$ROOT/hooks/lib/settings-lock.sh" "$HOME_DIR/claude-wiki-skill/hooks/lib/settings-lock.sh"
  chmod +x "$HOME_DIR/claude-wiki-skill/hooks/uninstall-hooks.sh"
  printf '%s\n' "$NO_MARKER_SNIPPET" >"$HOME_DIR/.claude/settings.json"
  printf '%s\n' "$NO_MARKER_SNIPPET" >"$HOME_DIR/.qwen/settings.json"
  _t0=$(date +%s)
  PATH="$BIN_DIR:$PATH" HOME="$HOME_DIR" WIKI_HOOKS_LOCK_TIMEOUT=6 WIKI_HOOKS_LOCK_POLL=0.1 \
    bash "$ROOT/uninstall.sh" --remove-clones >"$TMP/uninstall-selfdeadlock.log" 2>&1
  _t1=$(date +%s)
  grep -q "could not acquire lock" "$TMP/uninstall-selfdeadlock.log" && {
    echo "expected no self-deadlock between uninstall.sh and its own hooks/uninstall-hooks.sh"
    exit 1
  }
  [ $((_t1 - _t0)) -le 4 ] || {
    echo "expected the self-deadlock case to finish noticeably faster than the 6s timeout, took $((_t1 - _t0))s"
    exit 1
  }
  expect_missing "$HOME_DIR/claude-wiki-skill"
  expect_no_lockdirs "self-deadlock run"
else
  echo "uninstall: skipping self-deadlock case (python3 unavailable)"
fi

# F. A non-regular file inside the critical section does not starve the
#    locks: once the guard finishes (unverifiable -> fail-closed), BOTH
#    lockdirs are released and a parallel installer can acquire them right
#    after, without "could not acquire lock".
setup_installed_tree
printf '%s\n' "$NO_MARKER_SNIPPET" >"$HOME_DIR/.claude/settings.json"
rm -f "$HOME_DIR/.qwen/settings.json"
mkfifo "$HOME_DIR/.qwen/settings.json"
PATH="$BIN_DIR:$PATH" HOME="$HOME_DIR" bash "$ROOT/uninstall.sh" --remove-clones >"$TMP/uninstall-fifo-locks.log" 2>&1
expect_exists "$HOME_DIR/claude-wiki-skill"
expect_no_lockdirs "fifo-in-section run"
grep -q "не вдалося прочитати $HOME_DIR/.qwen/settings.json" "$TMP/uninstall-fifo-locks.log" || {
  echo "expected the fifo-in-section case to still report the qwen file as unverifiable"
  exit 1
}
rm -f "$HOME_DIR/.qwen/settings.json"
printf '%s\n' "$NO_MARKER_SNIPPET" >"$HOME_DIR/.qwen/settings.json"
if command -v python3 >/dev/null 2>&1; then
  HOME="$HOME_DIR" WIKI_HOOKS_LOCK_TIMEOUT=5 WIKI_HOOKS_LOCK_POLL=0.1 \
    bash "$ROOT/hooks/install-hooks.sh" >"$TMP/uninstall-fifo-followup-install.log" 2>&1
  grep -q "could not acquire lock" "$TMP/uninstall-fifo-followup-install.log" && {
    echo "expected the installer to acquire both locks freely after the fifo-in-section guard released them"
    exit 1
  }
fi

# G/G-2. Race, second half: uninstall.sh takes BOTH locks FIRST (doc plan
#    scenario B — proof the window is hermetic) and, once it releases them,
#    a concurrent installer's entries written afterward are inert (scenario
#    B-2 — machine-checked boundary of the invariant, not just prose).
if command -v python3 >/dev/null 2>&1; then
  _assert_inert_entries() {
    local settings="$1" label="$2" cmd out err_file
    err_file="$TMP/inert-stderr-$$"
    while IFS= read -r cmd; do
      [ -n "$cmd" ] || continue
      case "$cmd" in
        "test -x "*) : ;;
        *)
          echo "$label: expected orphaned entry to start with 'test -x ', got: $cmd"
          exit 1
          ;;
      esac
      out="$(bash -c "$cmd" </dev/null 2>"$err_file")" || {
        echo "$label: expected inert entry to exit 0, got $? for: $cmd"
        exit 1
      }
      [ -z "$out" ] || {
        echo "$label: expected empty stdout from inert entry, got: $out"
        exit 1
      }
      [ ! -s "$err_file" ] || {
        echo "$label: expected empty stderr from inert entry, got: $(cat "$err_file")"
        exit 1
      }
      rm -f "$err_file"
    done < <(python3 - "$settings" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)
for event in ("SessionStart", "PostToolUse"):
    for entry in data.get("hooks", {}).get(event, []) or []:
        for h in entry.get("hooks", []) or []:
            cmd = h.get("command", "")
            if "/skills/wiki/hooks/" in cmd:
                print(cmd)
PY
)
  }

  setup_installed_tree
  printf '%s\n' "$NO_MARKER_SNIPPET" >"$HOME_DIR/.claude/settings.json"
  printf '%s\n' "$NO_MARKER_SNIPPET" >"$HOME_DIR/.qwen/settings.json"
  _claude_before="$(cat "$HOME_DIR/.claude/settings.json")"
  _qwen_before="$(cat "$HOME_DIR/.qwen/settings.json")"

  ( PATH="$BIN_DIR:$PATH" HOME="$HOME_DIR" WIKI_UNINSTALL_TEST_SLEEP_IN_GUARD=2 \
      WIKI_HOOKS_LOCK_TIMEOUT=20 WIKI_HOOKS_LOCK_POLL=0.1 \
      bash "$ROOT/uninstall.sh" --remove-clones >"$TMP/window-uninstall.log" 2>&1 ) &
  _uninstall_pid=$!
  sleep 0.3
  # No sleep-seam here on purpose: this installer races the guard's window
  # for real, not on a scheduled delay.
  ( HOME="$HOME_DIR" WIKI_HOOKS_LOCK_TIMEOUT=20 WIKI_HOOKS_LOCK_POLL=0.1 \
      bash "$ROOT/hooks/install-hooks.sh" >"$TMP/window-install.log" 2>&1 ) &
  _install_pid=$!
  sleep 0.7

  # Inside the window (~1s after the guard started, well before its 2s
  # sleep-seam ends): both locks are still held, so nothing may have
  # changed either settings file yet.
  [ "$(cat "$HOME_DIR/.claude/settings.json")" = "$_claude_before" ] || {
    echo "expected the claude settings file to be untouched while the guard holds both locks"
    exit 1
  }
  [ "$(cat "$HOME_DIR/.qwen/settings.json")" = "$_qwen_before" ] || {
    echo "expected the qwen settings file to be untouched while the guard holds both locks"
    exit 1
  }
  grep -q '/skills/wiki/hooks/' "$HOME_DIR/.claude/settings.json" && {
    echo "expected no marker in the claude settings file inside the guard window"
    exit 1
  }
  grep -q '/skills/wiki/hooks/' "$HOME_DIR/.qwen/settings.json" && {
    echo "expected no marker in the qwen settings file inside the guard window"
    exit 1
  }

  _urc=0
  wait "$_uninstall_pid" || _urc=$?
  _irc=0
  wait "$_install_pid" || _irc=$?
  [ "$_urc" -eq 0 ] || {
    echo "expected uninstall.sh to exit 0 in the hermetic-window race, got $_urc"
    exit 1
  }
  [ "$_irc" -eq 0 ] || {
    echo "expected install-hooks.sh to exit 0 once it got the locks after the window, got $_irc"
    exit 1
  }
  expect_missing "$HOME_DIR/claude-wiki-skill"
  expect_no_lockdirs "hermetic-window race"

  # G-2: the installer that unblocked right after the clone vanished wrote
  # fresh entries pointing at a canonical path that no longer resolves.
  # Prove those entries are inert (fail open, touch nothing), then prove a
  # normal uninstall-hooks.sh run from the working tree sweeps them to zero.
  _assert_inert_entries "$HOME_DIR/.claude/settings.json" "claude (post-window)"
  _assert_inert_entries "$HOME_DIR/.qwen/settings.json" "qwen (post-window)"

  HOME="$HOME_DIR" WIKI_HOOKS_LOCK_TIMEOUT=10 bash "$ROOT/hooks/uninstall-hooks.sh" \
    >"$TMP/window-cleanup.log" 2>&1
  grep -q '/skills/wiki/hooks/' "$HOME_DIR/.claude/settings.json" && {
    echo "expected the post-window claude entry to be swept by hooks/uninstall-hooks.sh"
    exit 1
  }
  grep -q '/skills/wiki/hooks/' "$HOME_DIR/.qwen/settings.json" && {
    echo "expected the post-window qwen entry to be swept by hooks/uninstall-hooks.sh"
    exit 1
  }
else
  echo "uninstall: skipping hermetic-window race + inert-entries case (python3 unavailable)"
fi

echo "uninstall: ok"
