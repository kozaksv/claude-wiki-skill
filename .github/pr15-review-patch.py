from pathlib import Path
import subprocess


def replace(path, before, after, count=1):
    p = Path(path)
    text = p.read_text()
    found = text.count(before)
    if found != count:
        raise RuntimeError(f'{path}: expected {count} matches, found {found}: {before!r}')
    p.write_text(text.replace(before, after))


replace('hooks/lib/discover.sh', '_wiki_disc_realpath() { realpath "$1" 2>/dev/null || true; }', '''_wiki_disc_realpath() { realpath "$1" 2>/dev/null || true; }

_wiki_disc_lexical_path() {
  # Absolute dot-segment normalization without requiring the target to exist.
  # Keep this separate from physical resolution: a symlink followed by /..
  # can have different semantics, so successful candidates still need realpath.
  local rest="$1" part normalized=""
  case "$rest" in /*) ;; *) return 1 ;; esac
  while [ -n "$rest" ]; do
    part="${rest%%/*}"
    case "$rest" in */*) rest="${rest#*/}" ;; *) rest="" ;; esac
    case "$part" in
      ""|.) : ;;
      ..) normalized="${normalized%/*}" ;;
      *) normalized="$normalized/$part" ;;
    esac
  done
  printf '%s' "${normalized:-/}"
}''')
replace('hooks/lib/discover.sh', '''  local candidate="$1" boundary="$2" index_real dir_real
  WIKI_DISC_CANDIDATE=""; WIKI_DISC_REASON="missing"
  dir_real="$(_wiki_disc_realpath "$candidate")"
  if [ -n "$dir_real" ] && [ "$dir_real" != "$boundary" ] && ! _wiki_disc_boundary_ok "$dir_real" "$boundary"; then
    WIKI_DISC_REASON=outside_boundary; return 0
  fi''', '''  local candidate="$1" boundary="$2" index_real dir_real lexical lexical_inside=0
  WIKI_DISC_CANDIDATE=""; WIKI_DISC_REASON="missing"
  lexical="$(_wiki_disc_lexical_path "$candidate")" || {
    WIKI_DISC_REASON=invalid_pointer; return 0;
  }
  if [ "$lexical" = "$boundary" ] || _wiki_disc_boundary_ok "$lexical" "$boundary"; then
    lexical_inside=1
  fi
  dir_real="$(_wiki_disc_realpath "$candidate")"
  if [ "$lexical_inside" = 0 ]; then
    # Outside remains outside even when BSD realpath cannot resolve a missing
    # target. Preserve validated local absolute aliases (/var -> /private/var)
    # only when their physical target is actually inside this repository.
    if [ -z "$dir_real" ] || { [ "$dir_real" != "$boundary" ] && ! _wiki_disc_boundary_ok "$dir_real" "$boundary"; }; then
      WIKI_DISC_REASON=outside_boundary; return 0
    fi
  elif [ -n "$dir_real" ] && [ "$dir_real" != "$boundary" ] && ! _wiki_disc_boundary_ok "$dir_real" "$boundary"; then
    WIKI_DISC_REASON=symlink_escape; return 0
  fi''')

# Normalize fixture roots, not actual results or deliberate fixture symlinks.
for file in ('tests/test_release_a.py', 'tests/test_wiki_tools.py', 'tests/test_hook_upgrade.py'):
    p = Path(file)
    text = p.read_text()
    changed = text
    for expression in ('Path(self.tmp.name)', 'Path(self.temp.name)', 'Path(tmp)'):
        changed = changed.replace(expression, expression + '.resolve()')
    if changed == text:
        raise RuntimeError('No fixture root found: ' + file)
    p.write_text(changed)
replace('tests/hooks/run.sh', 'set -uo pipefail\n', '''set -uo pipefail

# macOS can expose TMPDIR as /var while discovery returns /private/var.
# Normalize only the shared fixture root, preserving intentional test symlinks.
TMPDIR="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
export TMPDIR
''')

replace('install.sh', '''    echo "Помилка: битий canonical wiki symlink: $SKILL_LINK → $(readlink "$SKILL_LINK")"
    echo "Запустіть повну інсталяцію: bash install.sh"''', '''    echo "Помилка: битий canonical wiki symlink: $SKILL_LINK → $(readlink "$SKILL_LINK")"
    echo "Перевірте шлях і target вручну. Installer не замінює цей link автоматично."
    printf 'Після перевірки видаліть лише сам битий symlink (без -r): rm -- %q\\n' "$SKILL_LINK"
    echo "Потім запустіть повну інсталяцію зі свіжого installer: bash install.sh"''')
replace('references/operation-ingest-binary.md', 'Gemini direct export', 'agy CLI direct export')
replace('references/operation-ingest-binary.md', "Gemini's direct user-skill path", "agy CLI's direct user-skill path")
replace('references/operation-ingest-binary.md', '"$HOME/.gemini/skills/doc-extract"', '"$HOME/.gemini/antigravity-cli/skills/doc-extract"')
replace('.github/workflows/wiki-contracts.yml', '    runs-on: ubuntu-latest\n', '''    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, macos-latest]
    runs-on: ${{ matrix.os }}
''')

new_tests = r'''"""PR #15 review regressions; no external CLI credentials or real HOME writes."""
import os
from pathlib import Path
import shlex
import subprocess

from test_release_a import ROOT, Workspace


class ReviewDiscoveryTests(Workspace):
    def candidate(self, path, strict=False):
        # A strict resolver reproduces BSD realpath's absent-target behavior on
        # Linux too; ordinary runs exercise the actual platform realpath.
        script = r\'''source "$1"
if [ "$4" = strict ]; then
  _wiki_disc_realpath() { if [ -e "$1" ]; then command realpath "$1" 2>/dev/null || true; fi; }
fi
_wiki_disc_candidate "$2" "$3"
printf '%s\n%s\n' "$WIKI_DISC_REASON" "$WIKI_DISC_CANDIDATE"
\'''
        result = subprocess.run(
            ["bash", "-eu", "-c", script, "bash", str(ROOT / "hooks/lib/discover.sh"),
             str(path), str(self.repo), "strict" if strict else "native"],
            env=self.env, text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.splitlines()

    def test_missing_outside_has_stable_reason(self):
        for strict in (False, True):
            with self.subTest(strict=strict):
                reason, selected = self.candidate(str(self.repo) + "/./../absent/../outside-missing", strict)
                self.assertEqual(reason, "outside_boundary")
                self.assertEqual(selected, "")
                reason, selected = self.candidate(self.repo / "missing", strict)
                self.assertEqual(reason, "missing")
                self.assertEqual(selected, "")

    def test_inside_dot_segments_and_no_index(self):
        expected = self.wiki("knowledge/wiki")
        for strict in (False, True):
            with self.subTest(strict=strict):
                reason, selected = self.candidate(str(self.repo) + "/knowledge/./wiki/../wiki", strict)
                self.assertEqual((reason, selected), ("valid", str(expected)))
                (self.repo / "empty").mkdir(exist_ok=True)
                self.assertEqual(self.candidate(self.repo / "empty", strict)[0], "no_index")

    def test_directory_symlink_escape_is_still_rejected(self):
        outside = self.home / "outside"
        self.write(outside / "index.md", "must not be read")
        (self.repo / "link").symlink_to(outside, target_is_directory=True)
        self.assertEqual(self.candidate(self.repo / "link"), ["symlink_escape", ""])

    def test_absolute_alias_to_same_repository_is_valid(self):
        expected = self.wiki("knowledge/wiki")
        alias = self.home / "project-alias"
        alias.symlink_to(self.repo, target_is_directory=True)
        self.write(self.repo / "AGENTS.md", "## Wiki\n`" + str(alias / "knowledge/wiki") + "`\n")
        self.assertEqual(self.discover().stdout.strip(), str(expected))
        self.assertEqual(self.candidate(alias / "knowledge/wiki", True), ["valid", str(expected)])

    def test_symlink_then_parent_uses_physical_boundary(self):
        external = self.home / "outside/deep"
        external.mkdir(parents=True)
        self.write(external.parent / "wiki/index.md", "outside")
        (self.repo / "link").symlink_to(external, target_is_directory=True)
        # Lexically repo/wiki, physically home/outside/wiki. Never normalize
        # away /.. before validating the actual filesystem resolution.
        self.assertEqual(self.candidate(str(self.repo) + "/link/../wiki"), ["symlink_escape", ""])


class ReviewRecoveryTests(Workspace):
    def test_dangling_canonical_repair_has_actionable_safe_message(self):
        canonical = self.home / ".claude/skills/wiki"
        canonical.parent.mkdir(parents=True)
        missing = self.home / "missing-checkout"
        canonical.symlink_to(missing)
        result = subprocess.run(["bash", str(ROOT / "install.sh"), "--repair-exports"],
                                cwd=self.repo, env=self.env, text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertTrue(canonical.is_symlink())
        self.assertEqual(os.readlink(canonical), str(missing))
        self.assertIn("без -r", result.stdout)
        command = next(line.split("rm -- ", 1)[1] for line in result.stdout.splitlines() if "rm -- " in line)
        self.assertEqual(shlex.split("rm -- " + command), ["rm", "--", str(canonical)])
        self.assertIn("Потім", result.stdout)
        self.assertFalse(missing.exists())

    def test_binary_example_uses_agy_not_retired_export(self):
        text = (ROOT / "references/operation-ingest-binary.md").read_text()
        self.assertIn('"$HOME/.gemini/antigravity-cli/skills/doc-extract"', text)
        self.assertNotIn('"$HOME/.gemini/skills/doc-extract"', text)
        self.assertNotIn("Gemini's direct", text)
'''.replace("r\\'''", "r'''").replace("\\'''", "'''")
compile(new_tests, 'tests/test_pr15_review.py', 'exec')
Path('tests/test_pr15_review.py').write_text(new_tests)

receipt = '''\n## Reviewer receipts on `9737036` — 2026-10-05\n\nSource: [review and native receipts](https://github.com/kozaksv/claude-wiki-skill/pull/15#issuecomment-5994628035).\nThe reviewer found no code blockers; these are reviewer-observed runs on the\noriginal PR commit, not reruns by the editing agent and not blanket validation\nof subsequent commits. The real HOME was not changed.\n\n| Surface | Observed evidence | Remaining acceptance work |\n|---|---|---|\n| Claude | Root/nested AGENTS with tools disabled; local blocker control; compact; wiki query using PR skill and PR hook | `/memory` interactive view not run; behavioral evidence is recorded, not a fabricated UI receipt |\n| Codex | Root/nested and fallback control passed | Wiki query used the global **master** skill; rerun with the PR skill for #9 |\n| agy | Root/nested and wiki query using workspace PR skill passed | Global CLI export runtime not run; temporary-HOME filesystem check is not equivalent |\n| Qwen | No completed model runs | API 403 `Access to model denied`; query and duplicate-skill check remain unverified |\n| GitHub agent | Not run on the reviewer's stand | Connector scenario receipt still required |\n\nThe reviewer also reproduced macOS fixture path mismatches (`/var` versus\n`/private/var`). The follow-up normalizes test fixture roots, makes missing\noutside-pointer reasons independent of `realpath` behavior, preserves safe\nphysical aliases, and adds Ubuntu/macOS CI. Native model receipts remain\nseparate from these deterministic regression tests.\n'''
p = Path('docs/release-a-validation.md')
p.write_text(p.read_text() + receipt)
subprocess.run(['python3', 'scripts/build_skill.py'], check=True)
subprocess.run(['git', 'diff', '--check'], check=True)
