"""Safety regressions for history splitting and real Claude/Qwen hook dispatch."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("review_wiki_tools", ROOT / "scripts/wiki.py")
wiki = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wiki)


class HistorySafetyTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.write("index.md", "# Wiki\n")
        self.write("concepts/topic.md", "# Topic\n## History\nOld incident.\n")

    def write(self, name, text):
        target = self.root / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(text.encode("utf-8"))

    def snapshot(self):
        return {p.relative_to(self.root).as_posix(): p.read_bytes()
                for p in self.root.rglob("*") if p.is_file()}

    def cli(self, *arguments):
        return subprocess.run([sys.executable, str(ROOT / "scripts/wiki.py"), *arguments],
                              capture_output=True, text=True, timeout=10)

    def split(self, *arguments, heading="History"):
        return self.cli("split-history", "--wiki", str(self.root), "--page", "concepts/topic.md",
                        "--heading", heading, "--destination", "history/topic.md", *arguments)

    def assert_refused_without_changes(self, heading="History"):
        before = self.snapshot()
        for flags in ((), ("--write",)):
            with self.subTest(flags=flags):
                result = self.split(*flags, heading=heading)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn("reviewed Split", result.stderr)
                self.assertEqual(before, self.snapshot())

    def test_setext_boundaries_fail_closed_in_preview_and_write(self):
        for underline in ("=", "---", "  =====  ", "   --\t"):
            for newline in ("\n", "\r\n"):
                with self.subTest(underline=underline, newline=repr(newline)):
                    source = ("# Topic\n\n## History\nOld incident.\n\n"
                              "Current rules\n" + underline + "\nKeep the current rule.\n")
                    self.write("concepts/topic.md", source.replace("\n", newline))
                    self.assert_refused_without_changes()

    def test_setext_anywhere_in_source_requires_review(self):
        self.write("concepts/topic.md", "Topic\n=====\n\n## History\nOld incident.\n")
        self.assert_refused_without_changes()

    def test_ambiguous_thematic_break_is_conservatively_refused(self):
        self.write("concepts/topic.md", "# Topic\n## History\nOld incident.\n\n---\n")
        self.assert_refused_without_changes()

    def test_simple_split_preserves_current_rules_and_sources(self):
        source = ("# Topic\n## History\nOld incident.\n\n## Current\nKeep the current rule.\n"
                  "\n## Sources\n[report]: evidence.md\n")
        self.write("concepts/topic.md", source)
        preview = self.split()
        self.assertEqual(preview.returncode, 0, preview.stderr)
        self.assertEqual(source, (self.root / "concepts/topic.md").read_text())
        result = self.split("--write")
        self.assertEqual(result.returncode, 0, result.stderr)
        current = (self.root / "concepts/topic.md").read_text()
        historical = (self.root / "history/topic.md").read_text()
        self.assertIn("## Current\nKeep the current rule.", current)
        self.assertIn("[report]: evidence.md", current)
        self.assertNotIn("Old incident.", current)
        self.assertIn("Old incident.", historical)
        checked = self.cli("catalog", "--wiki", str(self.root), "--check")
        self.assertEqual(checked.returncode, 0, checked.stderr)

    def test_yaml_and_fenced_underlines_remain_supported(self):
        for fence in ("```", "~~~~"):
            with self.subTest(fence=fence):
                source = ("---\ntitle: Topic\n---\n# Topic\n## History\nOld incident.\n"
                          + fence + "text\nExample\n---\n## Not a boundary\n" + fence
                          + "\n\n## Current\nKeep the current rule.\n")
                self.write("concepts/topic.md", source)
                result = self.split()
                self.assertEqual(result.returncode, 0, result.stderr)
                changes = json.loads(result.stdout)
                self.assertIn("Keep the current rule.", changes["concepts/topic.md"])
                self.assertIn("Example\n---\n## Not a boundary", changes["history/topic.md"])

    def test_reference_inline_image_and_html_links_require_review(self):
        examples = ("See [incident][report].", "See [report][].", "See [report].",
                    "See [incident]\n[report].", "![incident][report]", "[incident](evidence.md)",
                    "[[topic#History]]", '<a href="evidence.md">report</a>',
                    "See [nested [incident]][report].")
        for body in examples:
            with self.subTest(body=body):
                self.write("concepts/topic.md", "# Topic\n## History\n" + body
                           + "\n\n## Sources\n[report]: evidence.md\n")
                self.assert_refused_without_changes()

    def test_link_in_history_heading_also_requires_review(self):
        heading = "History [report]"
        self.write("concepts/topic.md", "# Topic\n## " + heading
                   + "\nOld incident.\n\n## Sources\n[report]: evidence.md\n")
        self.assert_refused_without_changes(heading)

    def test_catalog_still_reads_setext_documents(self):
        self.write("concepts/topic.md", "Topic\n=====\nCurrent rules\n-------------\nKeep.\n")
        result = self.cli("catalog", "--wiki", str(self.root))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([p["path"] for p in json.loads(result.stdout)["pages"]], ["concepts/topic.md"])


class HookProtectionTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.repo = Path(temporary.name)
        subprocess.run(["git", "init", "-q", str(self.repo)], check=True, timeout=10)
        (self.repo / "CLAUDE.md").write_text("## Wiki\n`docs/wiki`\n")
        self.root = self.repo / "docs/wiki"
        (self.root / "concepts").mkdir(parents=True)
        (self.root / "index.md").write_text("# Wiki\n")
        (self.root / "schema.md").write_text('---\nwiki_version: "4.0"\n---\n')
        for name in ("topic", "critical"):
            (self.root / "concepts" / (name + ".md")).write_text("# " + name + "\n")
        self.usage = self.root / ".usage.json"
        self.env = {**os.environ, "CLAUDE_PROJECT_DIR": str(self.repo),
                    "QWEN_PROJECT_DIR": str(self.repo), "WIKI_DISCOVERY_AGENT": "",
                    "WIKI_HOOK_CLIENT": ""}

    def hook(self, tool):
        if tool == "SessionStart":
            filename = "session-start.sh"
            payload = {"hook_event_name": "SessionStart", "source": "startup", "cwd": str(self.repo)}
        else:
            filename = "post-tool-use.sh"
            payload = {"hook_event_name": "PostToolUse", "cwd": str(self.repo), "tool_name": tool,
                       "tool_input": {"file_path": str(self.root / "concepts/topic.md")}}
        result = subprocess.run(["bash", str(ROOT / "hooks" / filename)],
                                input=json.dumps(payload), capture_output=True, text=True,
                                env=self.env, cwd=self.repo, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_both_hooks_preserve_corrupt_legacy_protection_byte_for_byte(self):
        examples = ('{"concepts/critical.md":{"protected":true},}', "[]", "null",
                    '{"concepts/critical.md":{"protected":true,"protected":false}}',
                    '{"concepts/critical.md":{"protected":true},"concepts/critical.md":{}}',
                    '{"concepts/critical.md":[]}',
                    '{"concepts/critical.md":{"pinned":"true"}}')
        for original in examples:
            for tool in ("SessionStart", "Read", "Edit", "read_file", "write_file"):
                with self.subTest(original=original, tool=tool):
                    self.usage.write_bytes(original.encode())
                    self.hook(tool)
                    self.assertEqual(self.usage.read_bytes(), original.encode())
                    with self.assertRaises(wiki.WikiError):
                        wiki.effective_protection(wiki.Wiki(self.root), "concepts/critical.md")
                    with self.assertRaises(wiki.WikiError):
                        wiki.migrate_policy(wiki.Wiki(self.root))

    def test_missing_sidecar_still_bootstraps(self):
        for tool, field in (("Read", "view_count"), ("Edit", "patch_count"),
                            ("read_file", "view_count"), ("write_file", "patch_count")):
            with self.subTest(tool=tool):
                if self.usage.exists():
                    self.usage.unlink()
                self.hook(tool)
                data = json.loads(self.usage.read_text())
                self.assertEqual(data["concepts/topic.md"][field], 1)
                self.assertIn("post_tool_use_at", data["_hooks"])
        self.usage.unlink()
        self.hook("SessionStart")
        self.assertIn("session_start_at", json.loads(self.usage.read_text())["_hooks"])

    def test_valid_legacy_union_and_other_pins_survive_real_hooks(self):
        original = {"concepts/topic.md": {"pinned": True, "protected": False, "view_count": 7},
                    "concepts/critical.md": {"protected": True, "view_count": 3}}
        self.usage.write_text(json.dumps(original))
        self.hook("SessionStart")
        self.hook("Read")
        data = json.loads(self.usage.read_text())
        self.assertEqual(data["concepts/topic.md"]["view_count"], 8)
        self.assertTrue(data["concepts/topic.md"]["protected"])
        self.assertNotIn("pinned", data["concepts/topic.md"])
        self.assertEqual(data["concepts/critical.md"], original["concepts/critical.md"])
        migrated = wiki.migrate_policy(wiki.Wiki(self.root))
        self.assertTrue(migrated["pages"]["concepts/topic.md"]["protected"])
        self.assertTrue(migrated["pages"]["concepts/critical.md"]["protected"])


if __name__ == "__main__":
    unittest.main()
