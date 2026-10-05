"""Release A regression tests; synthetic HOME/CLI fixtures, never paid sessions."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("instructions", ROOT / "scripts/instructions.py")
AUDIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIT)


class Workspace(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name) / "home with spaces"
        self.home.mkdir()
        self.repo = self.home / "project"
        self.repo.mkdir()
        self.env = dict(os.environ, HOME=str(self.home), GIT_CONFIG_NOSYSTEM="1",
                        GIT_CONFIG_GLOBAL=os.devnull, CODEX_HOME=str(self.home / ".codex"))
        for key in ("CLAUDE_PROJECT_DIR", "QWEN_PROJECT_DIR", "WIKI_HOOK_CLIENT", "WIKI_DISCOVERY_AGENT"):
            self.env.pop(key, None)
        subprocess.run(["git", "init", "-q", str(self.repo)], check=True, env=self.env)

    def write(self, path, content=""):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def wiki(self, name):
        path = self.repo / name
        self.write(path / "index.md", "# Wiki\n")
        self.write(path / "schema.md", '---\nwiki_version: "4.0"\n---\n')
        return path

    def discover(self, cwd=None, **env):
        return subprocess.run(["bash", str(ROOT / "hooks/lib/discover.sh"), str(cwd or self.repo)],
                              env=dict(self.env, **env), text=True, capture_output=True, timeout=10)

    def audit(self, cwd=None):
        with patch.dict(os.environ, self.env, clear=True):
            return AUDIT.audit([str(cwd or self.repo)])


class DiscoveryTests(Workspace):
    def test_same_level_conflict_all_harnesses(self):
        self.wiki("one"); self.wiki("two")
        self.write(self.repo / "AGENTS.md", "## Wiki\n`one/schema.md`\n")
        self.write(self.repo / "CLAUDE.md", "## Wiki\n`two/index.md`\n")
        for agent in ("claude", "codex", "qwen", "agy", ""):
            result = self.discover(WIKI_DISCOVERY_AGENT=agent)
            self.assertEqual(result.returncode, 3)
            self.assertEqual(result.stdout, "")
        selection = self.audit()["projects"][0]["discovery"]
        self.assertEqual(selection["selected"], str(self.repo / "one"))
        self.assertTrue(selection["same_level_conflict"])

    def test_nearest_level_is_not_conflict(self):
        self.wiki("rootwiki"); expected = self.wiki("component/wiki")
        self.write(self.repo / "CLAUDE.md", "## Wiki\n`rootwiki`\n")
        self.write(self.repo / "component/AGENTS.md", "## Wiki\n`wiki`\n")
        result = self.discover(self.repo / "component", WIKI_DISCOVERY_AGENT="claude")
        self.assertEqual(result.stdout.strip(), str(expected))
        self.assertEqual(result.returncode, 0)
        report = self.audit(self.repo / "component")["projects"][0]
        self.assertFalse(report["discovery"]["same_level_conflict"])
        self.assertTrue(any("cross-level" in w for w in report["warnings"]))

    def test_stale_and_duplicate_pointers(self):
        expected = self.wiki("knowledge/wiki")
        self.write(self.repo / "AGENTS.md", "## Wiki\n`missing`\n")
        self.write(self.repo / "CLAUDE.md", "## Вікі проєкту\n`knowledge/wiki/schema.md`\n")
        self.write(self.repo / "GEMINI.md", "## Wiki\n`knowledge/wiki/index.md`\n")
        self.assertEqual(self.discover().stdout.strip(), str(expected))
        self.assertEqual(self.discover().returncode, 0)
        reasons = [p["reason"] for p in self.audit()["projects"][0]["discovery"]["candidates"]]
        self.assertIn("missing", reasons)
        self.assertNotIn("outside_boundary", reasons)

    def test_exact_case_and_fences(self):
        expected = self.wiki("docs/wiki"); self.wiki("other")
        self.write(self.repo / "agents.md", "## Wiki\n`other`\n")
        self.write(self.repo / "CLAUDE.md", "```md\n## Wiki\n`other`\n```\n# End\n")
        self.assertEqual(self.discover().stdout.strip(), str(expected))
        self.assertFalse(self.audit()["projects"][0]["preflight"]["allow_create_agents"])

    def test_no_external_instruction_read(self):
        outside = self.write(self.home / "outside.md", "## Wiki\n`project/other`\n")
        (self.repo / "AGENTS.md").symlink_to(outside)
        expected = self.wiki("docs/wiki")
        self.assertEqual(self.discover().stdout.strip(), str(expected))
        report = self.audit()["projects"][0]["discovery"]
        self.assertEqual(report["candidates"][0]["reason"], "symlink_escape")

    def test_index_escape_rejected(self):
        outside = self.write(self.home / "index.md", "private")
        (self.repo / "evil").mkdir()
        (self.repo / "evil/index.md").symlink_to(outside)
        self.write(self.repo / "AGENTS.md", "## Wiki\n`evil`\n")
        self.assertEqual(self.discover().stdout, "")

    def test_no_git_and_set_e(self):
        other = self.home / "notgit"; other.mkdir()
        proc = subprocess.run(["bash", "-euc", 'source "$1"; x="$(discover_wiki "$2")"; echo ok',
                               "bash", str(ROOT / "hooks/lib/discover.sh"), str(other)],
                              env=self.env, capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(proc.stdout, "ok\n")

    def test_worktree(self):
        subprocess.run(["git", "-C", str(self.repo), "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                        "commit", "--allow-empty", "-qm", "base"], check=True, env=self.env)
        work = self.home / "worktree"
        subprocess.run(["git", "-C", str(self.repo), "worktree", "add", "--detach", str(work)],
                       check=True, env=self.env, capture_output=True)
        self.write(work / "docs/wiki/index.md", "# Wiki")
        self.assertEqual(self.discover(work).stdout.strip(), str(work / "docs/wiki"))

    def test_shared_fixtures(self):
        cases = json.loads((ROOT / "references/discovery-cases.json").read_text())
        for case in cases:
            with self.subTest(case=case["id"]), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                subprocess.run(["git", "init", "-q", str(root)], check=True, env=self.env)
                for path, text in case["files"].items(): self.write(root / path, text)
                cwd = root / case.get("cwd", "."); cwd.mkdir(exist_ok=True, parents=True)
                with patch.dict(os.environ, self.env, clear=True): result = AUDIT.discovery(cwd)
                expected = str(root / case["selected"]) if case["selected"] else None
                self.assertEqual(result["selected"], expected)
                self.assertEqual(result["same_level_conflict"], case["conflict"])


class AuditTests(Workspace):
    def test_presence_not_content_or_version(self):
        self.write(self.repo / "CLAUDE.md", "must not be read by presence probe")
        self.write(self.home / ".claude/CLAUDE.md", "user exception")
        self.write(self.repo / ".claude/rules/local.md", "rules exception")
        self.write(self.home / "CLAUDE.local.md", "ancestor blocker")
        nested = self.repo / "nested"; nested.mkdir()
        self.write(nested / ".claude/CLAUDE.md", "nested blocker")
        with patch.object(Path, "read_text", side_effect=AssertionError("content opened")), patch.object(AUDIT, "command", side_effect=AssertionError("process launched")):
            blockers = AUDIT.claude_blockers(nested, self.home)
            root_blockers = AUDIT.claude_blockers(self.repo, self.home)
        self.assertIn(str(self.home / "CLAUDE.local.md"), blockers)
        self.assertIn(str(nested / ".claude/CLAUDE.md"), blockers)
        self.assertNotIn(str(nested / ".claude/CLAUDE.md"), root_blockers)
        self.assertNotIn(str(self.home / ".claude/CLAUDE.md"), blockers)
        self.assertFalse(any("rules" in p for p in blockers))

    def test_fresh_unknown_config_and_existing_fallback(self):
        self.write(self.home / ".codex/config.toml", "[not valid")
        self.assertTrue(self.audit()["projects"][0]["preflight"]["allow_create_agents"])
        self.write(self.home / ".codex/config.toml", 'project_doc_fallback_filenames = ["TEAM.md"]\n')
        self.write(self.repo / "TEAM.md", "important")
        self.assertFalse(self.audit()["projects"][0]["preflight"]["allow_create_agents"])

    def test_inventory_is_reusable_and_noop(self):
        self.write(self.repo / "AGENTS.md", "# Rules\n")
        self.write(self.repo / ".qwen/QWEN.local.md", "private\n")
        before = {str(p.relative_to(self.repo)): p.read_bytes() for p in self.repo.rglob("*") if p.is_file()}
        report = self.audit()
        self.assertEqual(report["schema_version"], 1)
        self.assertEqual(report["projects"][0]["preflight"]["state"], "canonical_present")
        self.assertTrue(any(p["private"] for p in report["projects"][0]["inventory"]))
        after = {str(p.relative_to(self.repo)): p.read_bytes() for p in self.repo.rglob("*") if p.is_file()}
        self.assertEqual(before, after)
        self.assertNotIn("private\n", json.dumps(report))

    def test_canonical_alias_is_not_updateable(self):
        self.write(self.repo / "CLAUDE.md", "# Important")
        (self.repo / "AGENTS.md").symlink_to("CLAUDE.md")
        preflight = self.audit()["projects"][0]["preflight"]
        self.assertFalse(preflight["allow_update_agents"])
        self.assertEqual(preflight["state"], "consolidation_required")


class ExportTests(Workspace):
    def setUp(self):
        super().setUp()
        self.write(self.home / "checkout/SKILL.md", "# wiki")
        canonical = self.home / ".claude/skills/wiki"
        canonical.parent.mkdir(parents=True)
        canonical.symlink_to(self.home / "checkout")

    def repair(self):
        return subprocess.run(["bash", str(ROOT / "lib/harnesses.sh"), "--repair"],
                              env=self.env, text=True, capture_output=True, timeout=10)

    def old_link(self, target=None):
        path = self.home / ".gemini/skills/wiki"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.symlink_to(target or self.home / ".claude/skills/wiki")
        return path

    def test_repair_retirement_and_idempotence(self):
        old = self.old_link()
        foreign = self.home / ".gemini/skills/foreign"
        foreign.symlink_to("/nonexistent/foreign")
        self.assertEqual(self.repair().returncode, 0)
        self.assertFalse(old.is_symlink())
        for relative in (".agents/skills", ".qwen/skills", ".gemini/antigravity-cli/skills"):
            self.assertEqual(os.readlink(self.home / relative / "wiki"), str(self.home / ".claude/skills/wiki"))
        self.assertTrue(foreign.is_symlink())
        self.assertEqual(self.repair().returncode, 0)
        self.assertTrue((self.home / ".gemini/skills").is_dir())

    def test_new_conflict_preserves_old(self):
        old = self.old_link()
        self.write(self.home / ".gemini/antigravity-cli/skills/wiki", "foreign")
        self.assertEqual(self.repair().returncode, 2)
        self.assertTrue(old.is_symlink())

    def test_foreign_dangling_preserved(self):
        old = self.old_link("/no/such/foreign")
        target = self.home / ".agents/skills/wiki"
        target.parent.mkdir(parents=True)
        target.symlink_to("/another/foreign")
        self.assertEqual(self.repair().returncode, 2)
        self.assertEqual(os.readlink(old), "/no/such/foreign")
        self.assertEqual(os.readlink(target), "/another/foreign")

    def test_unsafe_parent_preserved(self):
        old = self.old_link()
        external = self.home / "external"; external.mkdir()
        (self.home / ".gemini/antigravity-cli").symlink_to(external)
        self.assertEqual(self.repair().returncode, 2)
        self.assertTrue(old.is_symlink())
        self.assertEqual(list(external.iterdir()), [])

    def test_optional_missing_retirement_deferred(self):
        old = self.home / ".gemini/skills/doc-extract"
        old.parent.mkdir(parents=True)
        old.symlink_to(self.home / ".claude/skills/doc-extract")
        self.assertEqual(self.repair().returncode, 2)
        self.assertTrue(old.is_symlink())
        self.assertTrue((self.home / ".gemini/antigravity-cli/skills/wiki/SKILL.md").is_file())


class HookConflictTests(Workspace):
    def test_hooks_do_not_write_on_conflict(self):
        for name in ("one", "two"):
            wiki = self.wiki(name)
            self.write(wiki / "concepts/page.md", "# Page")
            self.write(wiki / ".usage.json", "{}\n")
        self.write(self.repo / "AGENTS.md", "## Wiki\n`one`\n")
        self.write(self.repo / "CLAUDE.md", "## Wiki\n`two`\n")
        before = [(self.repo / name / ".usage.json").read_bytes() for name in ("one", "two")]
        for script, payload in (
            ("session-start.sh", {"source": "startup", "cwd": str(self.repo)}),
            ("post-tool-use.sh", {"tool_name": "Read", "cwd": str(self.repo),
                                  "tool_input": {"file_path": "one/concepts/page.md"}}),
        ):
            result = subprocess.run(["bash", str(ROOT / "hooks" / script)], input=json.dumps(payload),
                                    env=self.env, text=True, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0)
            if script == "session-start.sh": self.assertIn("conflict", result.stdout)
        after = [(self.repo / name / ".usage.json").read_bytes() for name in ("one", "two")]
        self.assertEqual(before, after)


if __name__ == "__main__":
    unittest.main()
