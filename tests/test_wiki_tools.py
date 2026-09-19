"""Behavioral tests: real files/CLI/discovery, without network or LLM calls."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("wiki_tools", ROOT / "scripts/wiki.py")
wiki = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wiki)


class WikiTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.write("index.md", "# Wiki\n\nCurated guidance stays here.\n")
        self.write("concepts/topic.md", "# Topic\n\n## Current\nUse the new flow.\n")
        self.wiki = wiki.Wiki(self.root)

    def write(self, path, text):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")

    def cli(self, *args, ok=True):
        process = subprocess.run([sys.executable, str(ROOT / "scripts/wiki.py"), args[0],
                                  "--wiki", str(self.root), *args[1:]], capture_output=True, text=True)
        self.assertEqual(process.returncode, 0 if ok else 1, process.stderr)
        return process

    def test_catalog_discovers_unindexed_nested_and_duplicate_basenames(self):
        self.write("entities/nested/topic.md", "# Other topic\n")
        self.write("history/incident.md", "# Incident\n")
        self.write("schema.md", "Schema")
        self.write("log/old.md", "Log")
        self.write(".cache/ignored.md", "Cache")
        pages = wiki.catalog(self.wiki)["pages"]
        self.assertEqual([p["path"] for p in pages],
                         ["concepts/topic.md", "entities/nested/topic.md", "history/incident.md"])
        self.assertEqual(pages[-1]["kind"], "history")

    def test_blob_hash_matches_git_with_multibyte_text(self):
        self.write("concepts/topic.md", "# Вікі\nПривіт, світе!\n")
        blob = subprocess.check_output(["git", "hash-object", str(self.root / "concepts/topic.md")], text=True).strip()
        page = wiki.catalog(self.wiki)["pages"][0]
        self.assertEqual(page["git_blob_sha1"], blob)
        self.assertEqual(page["bytes"], (self.root / "concepts/topic.md").stat().st_size)

    def test_ranges_ignore_fenced_headings_and_frontmatter(self):
        text = "---\n# not a title\n---\n# Topic\n## Current\n```md\n## Fake\n```\ntext\n## History\nold\n"
        rows = wiki.headings(text)
        self.assertEqual([r["heading"] for r in rows], ["Topic", "Current", "History"])
        self.assertEqual((rows[1]["start_line"], rows[1]["end_line"]), (5, 9))

    def test_catalog_preview_is_read_only_and_write_is_idempotent(self):
        before = (self.root / "index.md").read_bytes()
        self.cli("catalog")
        self.assertFalse((self.root / "catalog.json").exists())
        self.assertEqual(before, (self.root / "index.md").read_bytes())
        self.cli("catalog", "--write")
        generated = (self.root / "index.md").read_bytes()
        self.assertTrue(generated.startswith(before))
        self.cli("catalog", "--write")
        self.assertEqual(generated, (self.root / "index.md").read_bytes())
        self.cli("catalog", "--check")

    def test_check_detects_content_change_addition_and_removal(self):
        for change in ("edit", "add", "remove"):
            with self.subTest(change=change):
                self.write("concepts/topic.md", "# Original\n")
                extra = self.root / "concepts/new.md"
                if extra.exists():
                    extra.unlink()
                self.cli("catalog", "--write")
                if change == "edit":
                    self.write("concepts/topic.md", "# Changed\n")
                elif change == "add":
                    self.write("concepts/new.md", "# New\n")
                else:
                    (self.root / "concepts/topic.md").unlink()
                self.cli("catalog", "--check", ok=False)

    def test_invalid_markers_do_not_clobber_catalog(self):
        self.write("catalog.json", "original")
        self.write("index.md", wiki.START + "\nbroken\n")
        self.cli("catalog", "--write", ok=False)
        self.assertEqual((self.root / "catalog.json").read_text(), "original")

    def test_check_write_flags_conflict(self):
        self.cli("catalog", "--check", "--write", ok=False)
        self.assertFalse((self.root / "catalog.json").exists())

    def test_catalog_encodes_unusual_paths_without_losing_exact_path(self):
        self.write("concepts/дві теми.md", "# [Title] <tag>\n")
        self.cli("catalog", "--write")
        text = (self.root / "index.md").read_text()
        self.assertIn("%20", text)
        self.assertNotIn("<tag>", text)
        self.assertIn("concepts/дві теми.md", (self.root / "catalog.json").read_text())

    def test_symlink_in_inventory_is_not_silently_omitted(self):
        (self.root / "concepts/link.md").symlink_to(self.root / "index.md")
        self.cli("catalog", ok=False)

    def test_symlink_output_is_rejected(self):
        self.write("outside.txt", "keep")
        (self.root / "catalog.json").symlink_to(self.root / "outside.txt")
        self.cli("catalog", "--write", ok=False)
        self.assertEqual((self.root / "outside.txt").read_text(), "keep")

    @unittest.skipUnless(hasattr(os, "mkfifo"), "POSIX FIFO")
    def test_fifo_policy_is_rejected_without_blocking(self):
        os.mkfifo(self.root / "policy.json")
        with self.assertRaises(wiki.WikiError):
            wiki.policy(self.wiki)

    def test_legacy_union_and_migration_preserve_counters(self):
        original = '{"concepts/topic.md":{"pinned":true,"protected":false,"view_count":7}}'
        self.write(".usage.json", original)
        self.assertTrue(wiki.effective_protection(self.wiki, "concepts/topic.md"))
        self.cli("migrate-policy")
        self.assertFalse((self.root / "policy.json").exists())
        self.cli("migrate-policy", "--write")
        self.assertEqual((self.root / ".usage.json").read_text(), original)
        (self.root / ".usage.json").unlink()  # Simulate a fresh clone's absent telemetry.
        self.assertTrue(wiki.effective_protection(self.wiki, "concepts/topic.md"))

    def test_explicit_unprotect_overrides_old_pin(self):
        self.write(".usage.json", '{"concepts/topic.md":{"pinned":true}}')
        self.cli("unprotect", "--page", "concepts/topic.md")
        self.assertFalse(wiki.effective_protection(self.wiki, "concepts/topic.md"))
        self.cli("migrate-policy", "--write")
        self.assertFalse(wiki.effective_protection(self.wiki, "concepts/topic.md"))

    def test_protect_preserves_other_legacy_pins(self):
        self.write("concepts/other.md", "# Other\n")
        self.write(".usage.json", '{"concepts/other.md":{"protected":true}}')
        self.cli("protect", "--page", "concepts/topic.md")
        (self.root / ".usage.json").unlink()
        self.assertTrue(wiki.effective_protection(self.wiki, "concepts/other.md"))

    def test_corrupt_policy_blocks_changes_but_catalog_remains_readable(self):
        for value in ("broken", '{"version":2,"pages":{}}',
                      '{"version":1,"pages":{"concepts/topic.md":{"protected":"false"}}}',
                      '{"version":1,"version":1,"pages":{}}'):
            with self.subTest(value=value):
                self.write("policy.json", value)
                self.cli("protect", "--page", "concepts/topic.md", ok=False)
                self.assertEqual((self.root / "policy.json").read_text(), value)
                self.cli("catalog")

    def test_corrupt_legacy_does_not_erase_pins_or_block_explicit_policy_read(self):
        self.write(".usage.json", "broken")
        self.cli("migrate-policy", "--write", ok=False)
        self.assertFalse((self.root / "policy.json").exists())
        self.write("policy.json", '{"version":1,"pages":{"concepts/topic.md":{"protected":true}}}')
        self.assertTrue(wiki.effective_protection(self.wiki, "concepts/topic.md"))

    def test_path_escape_and_missing_page_are_rejected(self):
        with self.assertRaises(wiki.WikiError):
            wiki.safe_relative("C:escape.md")
        for path in ("../outside.md", "/outside.md", "concepts/../index.md", "missing.md"):
            with self.subTest(path=path):
                self.cli("protect", "--page", path, ok=False)
        self.assertFalse((self.root / "policy.json").exists())

    def history_source(self):
        source = "# Topic\n\n## Current\nUse new.\n\n## History\n2025: Старий досвід.\n\n## Sources\nKeep evidence.\n"
        self.write("concepts/topic.md", source)
        return source

    def test_history_split_preserves_current_sources_and_anchor(self):
        source = self.history_source()
        self.cli("split-history", "--page", "concepts/topic.md", "--heading", "History",
                 "--destination", "history/topic.md")
        self.assertEqual((self.root / "concepts/topic.md").read_text(), source)
        self.cli("split-history", "--page", "concepts/topic.md", "--heading", "History",
                 "--destination", "history/topic.md", "--write")
        current = (self.root / "concepts/topic.md").read_text()
        history = (self.root / "history/topic.md").read_text()
        self.assertIn("## Current\nUse new.", current)
        self.assertIn("## Sources\nKeep evidence.", current)
        self.assertIn("## History\n", current)
        self.assertIn("Старий досвід", history)
        self.assertNotIn("Старий досвід", current)
        self.assertIn("../concepts/topic.md", history)
        self.cli("catalog", "--check")

    def test_history_split_refuses_protection_collision_and_ambiguous_section(self):
        source = self.history_source()
        self.cli("protect", "--page", "concepts/topic.md")
        with self.assertRaises(wiki.WikiError):
            wiki.split_history(self.wiki, "concepts/topic.md", "History", "history/topic.md")
        self.cli("unprotect", "--page", "concepts/topic.md")
        self.write("history/topic.md", "Existing")
        with self.assertRaises(wiki.WikiError):
            wiki.split_history(self.wiki, "concepts/topic.md", "History", "history/topic.md")
        self.write("concepts/topic.md", source + "\n## History\nAgain\n")
        with self.assertRaises(wiki.WikiError):
            wiki.split_history(self.wiki, "concepts/topic.md", "History", "history/other.md")

    def test_history_markdown_links_require_reviewed_relocation(self):
        self.write("concepts/topic.md", "# Topic\n## History\n[relative](other.md)\n")
        with self.assertRaises(wiki.WikiError):
            wiki.split_history(self.wiki, "concepts/topic.md", "History", "history/topic.md")

    def test_batch_write_rolls_back_on_later_failure(self):
        original = (self.root / "index.md").read_bytes()
        real_write = wiki.atomic_write

        def failing(path, data):
            if path.name == "policy.json":
                raise OSError("simulated full disk")
            real_write(path, data)

        with patch.object(wiki, "atomic_write", side_effect=failing):
            with self.assertRaises(OSError):
                wiki.write_batch(self.wiki, {"index.md": b"changed", "policy.json": b"{}"})
        self.assertEqual((self.root / "index.md").read_bytes(), original)


class DiscoveryTests(unittest.TestCase):
    def test_partial_wiki_or_directory_index_is_not_valid_discovery(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q", directory], check=True)
            (root / "docs/wiki").mkdir(parents=True)
            (root / "AGENTS.md").write_text("## Вікі\n`docs/wiki`\n")
            for directory_index in (False, True):
                if directory_index:
                    (root / "docs/wiki/index.md").mkdir()
                result = subprocess.check_output(["bash", str(ROOT / "hooks/lib/discover.sh"), directory],
                                                 stderr=subprocess.DEVNULL, text=True)
                self.assertEqual(result.strip(), "")

    def test_pointer_grammar_in_real_git_checkout(self):
        cases = {
            "## Wiki": True, "## wiki notes": True, "## WIKI (project)": True,
            "## Вікі": True, "## ВІКІ проєкту": True, "## вікі: правила": True,
            "## Wikipedia": False, "### Wiki": False, "# Wiki": False,
            "## Вікіпедія": False,
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q", directory], check=True)
            (root / "knowledge/wiki").mkdir(parents=True)
            (root / "knowledge/wiki/index.md").write_text("# Wiki")
            for heading, valid in cases.items():
                with self.subTest(heading=heading):
                    (root / "AGENTS.md").write_bytes((heading + "\r\nRead `knowledge/wiki/index.md`.\r\n").encode())
                    result = subprocess.run(["bash", str(ROOT / "hooks/lib/discover.sh"), directory],
                                            env={**os.environ, "LC_ALL": "C"}, capture_output=True, text=True, check=True)
                    self.assertEqual(result.stdout.strip(), str(root / "knowledge/wiki") if valid else "")

    def test_fences_h1_boundary_and_active_agent_priority(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q", directory], check=True)
            for name in ("a", "b"):
                (root / name).mkdir()
                (root / name / "index.md").write_text("# Wiki")
            cases = [
                ("```md\n## Wiki\n`b`\n```\n## Wiki\n`a`\n", "a"),
                ("## Wiki\n# Other\n`b`\n", ""),
                ("## Wiki\n~~~\n`b`\n~~~\n`a`\n", "a"),
            ]
            for text, expected in cases:
                (root / "AGENTS.md").write_text(text)
                result = subprocess.check_output(["bash", str(ROOT / "hooks/lib/discover.sh"), directory], stderr=subprocess.DEVNULL, text=True)
                self.assertEqual(result.strip(), str(root / expected) if expected else "")
            (root / "CLAUDE.md").write_text("## Wiki\n`a`\n")
            (root / "AGENTS.md").write_text("## Wiki\n`b`\n")
            result = subprocess.check_output(["bash", str(ROOT / "hooks/lib/discover.sh"), directory],
                                              env={**os.environ, "WIKI_DISCOVERY_AGENT": "codex"}, text=True)
            self.assertEqual(result.strip(), str(root / "b"))


if __name__ == "__main__":
    unittest.main()
