"""PR #15 review regressions; no external CLI credentials or real HOME writes."""
import os
from pathlib import Path
import shlex
import subprocess

from test_release_a import ROOT, Workspace


class ReviewDiscoveryTests(Workspace):
    def candidate(self, path, strict=False):
        # A strict resolver reproduces BSD realpath's absent-target behavior on
        # Linux too; ordinary runs exercise the actual platform realpath.
        script = r'''source "$1"
if [ "$4" = strict ]; then
  _wiki_disc_realpath() { if [ -e "$1" ]; then command realpath "$1" 2>/dev/null || true; fi; }
fi
_wiki_disc_candidate "$2" "$3"
printf '%s\n%s\n' "$WIKI_DISC_REASON" "$WIKI_DISC_CANDIDATE"
'''
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
