"""Release B regression tests: consolidation plan/check/apply/commit/rollback and private flow."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("migrate", ROOT / "scripts/migrate.py")
M = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(M)

STUB = ("# Project\n\n## Wiki\n\nWiki at `docs/wiki/`. Schema → `docs/wiki/schema.md`. Skill: `wiki`.\n\n"
        "**ОБОВ'ЯЗКОВО на старті сесії:** прочитай `docs/wiki/index.md` ДО\n"
        "будь-якої project-specific відповіді (як налаштувати X / де лежить Y / як працює Z /\n"
        "«пам'ятаєш як ми...»). Кожна така відповідь МАЄ містити `[[page-name]]` цитати на\n"
        "сторінки вікі. Без цитат — баг, переробити. Memory-first заборонено: якщо вікі\n"
        "суперечить пам'яті — вікі виграє.\n\nДля пошуку викликай скіл `wiki` (operation: query).\n")
RULES = "# Project\n\n## Rules\n\n- Never push to main directly.\n- Run `make test` before commit.\n\n## Wiki\n\nWiki schema and operations → `docs/wiki/schema.md`. Skill: `wiki`.\n"


class Repo(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name).resolve() / "home"
        self.home.mkdir()
        self.repo = self.home / "project"
        self.repo.mkdir()
        self.env = dict(os.environ, HOME=str(self.home), GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull,
                        CODEX_HOME=str(self.home / ".codex"), GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t",
                        GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")
        for key in ("CLAUDE_PROJECT_DIR", "QWEN_PROJECT_DIR", "WIKI_HOOK_CLIENT", "WIKI_DISCOVERY_AGENT"):
            self.env.pop(key, None)
        self.patcher = patch.dict(os.environ, self.env, clear=True)
        self.patcher.start(); self.addCleanup(self.patcher.stop)
        self.git("init", "-q")
        self.write("docs/wiki/index.md", "# Index\n")
        self.write("docs/wiki/schema.md", '---\nwiki_version: "4.0"\n---\n')

    def git(self, *args):
        return subprocess.run(["git", "-C", str(self.repo), *args], check=True, capture_output=True, text=True).stdout

    def write(self, rel, text):
        path = self.repo / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def commit_all(self):
        self.git("add", "-A"); self.git("commit", "-qm", "base")

    def plan(self, cwd=None):
        return M.build_plan(cwd or self.repo)

    def approve_all(self, plan):
        for entry in plan["coverage"]: entry["approved"] = True
        plan["status"] = M.plan_status(plan)
        return plan


class PlanTests(Repo):
    def test_identical_copies_are_deterministic(self):
        for name in ("AGENTS.md", "CLAUDE.md", "GEMINI.md", "QWEN.md"): self.write(name, RULES)
        self.commit_all()
        plan = self.plan()
        self.assertEqual(plan["status"], "ready")
        self.assertEqual(plan["outputs"], [])
        self.assertEqual(sorted(d["path"] for d in plan["deletes"]), ["CLAUDE.md", "GEMINI.md", "QWEN.md"])
        self.assertTrue(M.check(plan, self.repo)["ok"])

    def test_title_only_difference_is_duplicate(self):
        self.write("AGENTS.md", RULES.replace("# Project", "# Project — Agent Instructions"))
        self.write("CLAUDE.md", RULES.replace("# Project", "# Project — Claude Instructions"))
        self.commit_all()
        self.assertEqual(self.plan()["status"], "ready")

    def test_rules_in_claude_with_stubs(self):
        self.write("CLAUDE.md", RULES); self.write("AGENTS.md", STUB); self.write("GEMINI.md", STUB)
        self.commit_all()
        plan = self.plan()
        self.assertEqual(plan["status"], "needs-decision")
        out = plan["outputs"][0]
        self.assertEqual(out["path"], "AGENTS.md")
        self.assertIn("Never push to main directly.", out["content"])
        classes = {f["source"]: f["class"] for f in plan["fragments"] if f["kind"] == "pointer"}
        self.assertEqual(classes["GEMINI.md"], "generated-pointer-stub")
        self.assertFalse(M.check(plan, self.repo)["ok"])
        self.assertTrue(M.check(self.approve_all(plan), self.repo)["ok"])

    def test_same_heading_different_body_is_conflict(self):
        self.write("AGENTS.md", "# P\n\n## Build\n\nUse make.\n")
        self.write("CLAUDE.md", "# P\n\n## Build\n\nUse ninja.\n")
        self.commit_all()
        plan = self.plan()
        self.assertIn("conflict-or-unknown", {f["class"] for f in plan["fragments"]})
        self.assertEqual(plan["status"], "needs-decision")

    def test_same_bytes_different_scope_not_deduped(self):
        self.write("CLAUDE.md", "# Root\n\n## Shared\n\n- Keep it.\n")
        self.write("pkg/CLAUDE.md", "# Root\n\n## Shared\n\n- Keep it.\n")
        self.commit_all()
        plan = self.plan()
        self.assertEqual(sorted(o["path"] for o in plan["outputs"]), ["AGENTS.md", "pkg/AGENTS.md"])

    def test_stub_with_extra_text_is_not_stub(self):
        self.write("AGENTS.md", STUB)
        self.write("CLAUDE.md", STUB.replace("Для пошуку", "- Never edit generated files.\n\nДля пошуку"))
        self.commit_all()
        plan = self.plan()
        pointer = [f for f in plan["fragments"] if f["source"] == "CLAUDE.md" and f["kind"] == "pointer"][0]
        self.assertEqual(pointer["class"], "unique")
        self.assertIn("Never edit generated files.", plan["outputs"][0]["content"])

    def test_every_line_is_covered(self):
        text = "---\nx: 1\n---\nintro line\n# Title\n```\n## not a heading\n```\n### Sub\nbody\n### Sub\nagain\n"
        frags = M.fragments("CLAUDE.md", text, ".")
        covered = set()
        for f in frags: covered.update(range(f["start"], f["end"] + 1))
        for number, line in enumerate(text.splitlines(), 1):
            if line.strip(): self.assertIn(number, covered, line)
        self.assertNotIn("## not a heading", [f["heading"] for f in frags])

    def test_canonical_only_is_noop(self):
        self.write("AGENTS.md", RULES); self.commit_all()
        plan = self.plan()
        self.assertEqual((plan["outputs"], plan["deletes"], plan["status"]), ([], [], "ready"))
        self.assertEqual(M.apply(plan, self.repo, write=True)["status"], "noop")
        self.assertEqual(M.commit(plan, self.repo, "x")["status"], "noop")

    def test_same_level_wiki_conflict_blocks(self):
        self.write("other/index.md", "# o\n")
        self.write("AGENTS.md", "## Wiki\n`docs/wiki`\n"); self.write("CLAUDE.md", "## Wiki\n`other`\n")
        self.commit_all()
        self.assertEqual(self.plan()["status"], "blocked")

    def test_custom_wiki_pointer_rewritten_relative(self):
        self.write("knowledge/wiki/index.md", "# k\n")
        self.write("pkg/CLAUDE.md", "# Pkg\n\n## Wiki\n\nWiki schema and operations → `../knowledge/wiki/schema.md`. Skill: `wiki`.\n")
        self.write("CLAUDE.md", f"# R\n\n## Wiki\n\nWiki at `{self.repo}/knowledge/wiki`. Schema → `x`. Skill: `wiki`.\n")
        self.commit_all()
        plan = self.plan()
        contents = {o["path"]: o["content"] for o in plan["outputs"]}
        self.assertIn("Wiki at `knowledge/wiki`", contents["AGENTS.md"])
        self.assertIn("Wiki at `../knowledge/wiki`", contents["pkg/AGENTS.md"])
        self.assertNotIn(str(self.repo), contents["AGENTS.md"])
        self.assertTrue(M.check(self.approve_all(plan), self.repo)["ok"])
        bad = json.loads(json.dumps(plan))
        bad["outputs"][0]["content"] = bad["outputs"][0]["content"].replace("knowledge/wiki", "nowhere")
        self.assertTrue(any("future tree" in e for e in M.check(bad, self.repo)["errors"]))

    def test_aliases(self):
        self.write("CLAUDE.md", RULES); os.symlink("CLAUDE.md", self.repo / "AGENTS.md")
        self.commit_all()
        plan = self.plan()
        self.assertEqual(plan["outputs"][0]["action"], "materialize")
        self.assertEqual(plan["deletes"][0]["path"], "CLAUDE.md")
        self.assertTrue(M.check(plan, self.repo)["ok"], M.check(plan, self.repo))

        (self.repo / "AGENTS.md").unlink(); self.write("AGENTS.md", RULES); (self.repo / "CLAUDE.md").unlink()
        os.symlink("AGENTS.md", self.repo / "CLAUDE.md"); self.commit_all()
        plan = self.plan()
        self.assertEqual(plan["outputs"], [])
        self.assertEqual(plan["deletes"], [{"path": "CLAUDE.md", "kind": "symlink", "link_target": "AGENTS.md", "reason": "alias of canonical"}])

    def test_import_redirect_is_duplicate_not_dangling(self):
        self.write("CLAUDE.md", RULES); self.write("QWEN.md", "@CLAUDE.md\n"); self.commit_all()
        plan = self.approve_all(self.plan())
        self.assertNotIn("@CLAUDE.md", plan["outputs"][0]["content"])
        self.assertTrue(M.check(plan, self.repo)["ok"], M.check(plan, self.repo))
        plan["outputs"][0]["content"] += "\n@CLAUDE.md\n"
        self.assertTrue(any("deleted legacy file" in e for e in M.check(plan, self.repo)["errors"]))

    def test_redirect_prose_keeps_text_drops_dangling_import(self):
        self.write("CLAUDE.md", RULES); self.write("QWEN.md", "# Q\n\nRules live in CLAUDE.md.\n\n@CLAUDE.md\n"); self.commit_all()
        plan = self.approve_all(self.plan())
        content = plan["outputs"][0]["content"]
        self.assertIn("Rules live in CLAUDE.md.", content)
        self.assertNotIn("@CLAUDE.md", content)
        self.assertTrue(M.check(plan, self.repo)["ok"], M.check(plan, self.repo))

    def test_private_and_override_reported_not_touched(self):
        self.write("AGENTS.md", RULES); self.write("CLAUDE.local.md", "secret\n"); self.write("AGENTS.override.md", "x\n")
        plan = self.plan()
        codes = {f["code"] for f in plan["findings"]}
        self.assertTrue({"claude_private_blocker", "native_file_untouched"} <= codes)
        self.assertNotIn("CLAUDE.local.md", [d["path"] for d in plan["deletes"]])


class CheckTests(Repo):
    def ready_plan(self):
        self.write("CLAUDE.md", RULES); self.write("AGENTS.md", STUB); self.commit_all()
        return self.approve_all(self.plan())

    def test_missing_coverage_and_stale_hash(self):
        plan = self.ready_plan()
        broken = json.loads(json.dumps(plan)); broken["coverage"].pop()
        self.assertTrue(any("exactly once" in e for e in M.check(broken, self.repo)["errors"]))
        self.write("CLAUDE.md", RULES + "\n- extra\n")
        self.assertTrue(any("stale source" in e for e in M.check(plan, self.repo)["errors"]))

    def test_critical_rule_dropped(self):
        plan = self.ready_plan()
        plan["outputs"][0]["content"] = plan["outputs"][0]["content"].replace("- Never push to main directly.\n", "")
        for c in plan["coverage"]: c["rewritten"] = True
        errors = M.check(plan, self.repo)["errors"]
        self.assertTrue(any("critical rule missing" in e for e in errors), errors)

    def test_placed_text_absent(self):
        plan = self.ready_plan()
        plan["outputs"][0]["content"] = plan["outputs"][0]["content"].replace("Run `make test` before commit.", "Run tests.")
        self.assertTrue(any("placed text not found" in e for e in M.check(plan, self.repo)["errors"]))

    def test_budgets_includes_and_agy_rules(self):
        plan = self.ready_plan()
        plan["outputs"][0]["content"] += "x" * 40000 + "\n@docs/extra.md\n"
        result = M.check(plan, self.repo)
        self.assertTrue(any("agy" in e for e in result["errors"]))
        self.assertTrue(any("Codex chain" in e for e in result["errors"]))
        self.assertTrue(any("includes" in d for d in result["decisions_needed"]))
        self.assertTrue(M.agy_rule_errors(".agents/rules/a.md", "---\ntrigger: alwaysOn\n---\nx\n"))
        self.assertFalse(M.agy_rule_errors(".agents/rules/a.md", "---\ntrigger: always_on\n---\nx\n"))

    def test_snapshot_mode_without_git(self):
        plan = self.ready_plan()
        snap = Path(self.tmp.name) / "snap"; snap.mkdir()
        for rel in ("CLAUDE.md", "AGENTS.md", "docs/wiki/index.md", "docs/wiki/schema.md"):
            (snap / rel).parent.mkdir(parents=True, exist_ok=True)
            (snap / rel).write_bytes((self.repo / rel).read_bytes())
        self.assertTrue(M.check(plan, snap, snapshot=True)["ok"])


class ApplyTests(Repo):
    def test_apply_commit_preserves_unrelated_staging(self):
        self.write("CLAUDE.md", RULES); self.write("GEMINI.md", STUB); self.write("notes.txt", "a\n"); self.commit_all()
        self.write("notes.txt", "b\n"); self.git("add", "notes.txt")
        plan = self.approve_all(self.plan())
        result = M.apply(plan, self.repo, write=True)
        self.assertEqual(result["status"], "applied-uncommitted")
        self.assertFalse((self.repo / "CLAUDE.md").exists())
        self.assertIn("Never push to main directly.", (self.repo / "AGENTS.md").read_text())
        done = M.commit(plan, self.repo, "consolidate")
        self.assertEqual(set(done["paths"]), {"AGENTS.md", "CLAUDE.md", "GEMINI.md"})
        self.assertIn("M  notes.txt", self.git("status", "--porcelain"))
        self.assertNotIn("notes.txt", self.git("show", "--name-only", "--format=", "HEAD"))

    def test_rollback_restores_tracked_untracked_and_new(self):
        self.write("CLAUDE.md", RULES); self.commit_all()
        self.write("GEMINI.md", "# G\n\n## Extra\n\n- Always lint.\n")  # untracked legacy
        plan = self.approve_all(self.plan())
        M.apply(plan, self.repo, write=True)
        self.assertFalse((self.repo / "GEMINI.md").exists())
        M.rollback(plan, self.repo, write=True)
        self.assertEqual((self.repo / "CLAUDE.md").read_text(), RULES)
        self.assertIn("Always lint", (self.repo / "GEMINI.md").read_text())
        self.assertFalse((self.repo / "AGENTS.md").exists())

    def test_untracked_canonical_is_backed_up(self):
        self.write("CLAUDE.md", RULES); self.commit_all(); self.write("AGENTS.md", "# P\n\n## Local\n\n- Keep me.\n")
        plan = self.approve_all(self.plan())
        M.apply(plan, self.repo, write=True)
        self.assertIn("Keep me.", (self.repo / "AGENTS.md").read_text())
        M.rollback(plan, self.repo, write=True)
        self.assertEqual((self.repo / "AGENTS.md").read_text(), "# P\n\n## Local\n\n- Keep me.\n")

    def test_alias_materialized_before_target_delete(self):
        self.write("CLAUDE.md", RULES); os.symlink("CLAUDE.md", self.repo / "AGENTS.md"); self.commit_all()
        M.apply(self.plan(), self.repo, write=True)
        self.assertFalse((self.repo / "AGENTS.md").is_symlink())
        self.assertIn("Never push", (self.repo / "AGENTS.md").read_text())
        self.assertFalse(os.path.lexists(self.repo / "CLAUDE.md"))

    def test_link_unlinked_not_target(self):
        self.write("AGENTS.md", RULES); os.symlink("AGENTS.md", self.repo / "CLAUDE.md"); self.commit_all()
        M.apply(self.plan(), self.repo, write=True)
        self.assertEqual((self.repo / "AGENTS.md").read_text(), RULES)
        self.assertFalse(os.path.lexists(self.repo / "CLAUDE.md"))

    def test_concurrent_edit_stops(self):
        self.write("CLAUDE.md", RULES); self.commit_all()
        plan = self.approve_all(self.plan())
        self.write("CLAUDE.md", RULES + "- new\n")
        with self.assertRaises(M.MigrationError): M.apply(plan, self.repo, write=True)
        self.assertTrue((self.repo / "CLAUDE.md").exists())

    def test_custom_wiki_survives_and_no_second_wiki(self):
        self.write("knowledge/wiki/index.md", "# k\n")
        (self.repo / "docs/wiki/index.md").unlink(); (self.repo / "docs/wiki/schema.md").unlink()
        self.write("CLAUDE.md", "# R\n\n## Wiki\n\nWiki schema and operations → `knowledge/wiki/schema.md`. Skill: `wiki`.\n")
        self.commit_all()
        plan = self.approve_all(self.plan())
        M.apply(plan, self.repo, write=True)
        found = M.AUDIT.discovery(self.repo)
        self.assertEqual(M.rel_or_none(found["selected"], self.repo), "knowledge/wiki")


class PrivateTests(Repo):
    def setUp(self):
        super().setUp()
        self.write("AGENTS.md", RULES); self.commit_all()
        self.write("CLAUDE.local.md", "- My sandbox is http://localhost:9\n@notes/me.md\n")

    def test_state_machine_and_exclude(self):
        with self.assertRaises(M.MigrationError): M.private_switch(self.repo, "CLAUDE.local.md", True)
        state = M.private_prepare(self.repo, "CLAUDE.local.md", "local", True)
        dest = self.repo / state["destination"]
        self.assertTrue(dest.exists())
        self.assertIn("@../../notes/me.md", dest.read_text())
        self.assertEqual(subprocess.run(["git", "-C", str(self.repo), "check-ignore", "-q", state["destination"]]).returncode, 0)
        self.assertTrue((self.repo / "CLAUDE.local.md").exists())
        with self.assertRaises(M.MigrationError): M.private_switch(self.repo, "CLAUDE.local.md", True)
        with self.assertRaises(M.MigrationError): M.private_confirm(self.repo, "CLAUDE.local.md", 2)
        M.private_confirm(self.repo, "CLAUDE.local.md", 1)
        M.private_switch(self.repo, "CLAUDE.local.md", True)
        self.assertFalse((self.repo / "CLAUDE.local.md").exists())
        self.assertEqual(M.private_state(self.repo, "CLAUDE.local.md")["status"], "switched")
        self.assertEqual(M.private_confirm(self.repo, "CLAUDE.local.md", 2)["status"], "completed")
        self.assertNotIn(".claude/rules/local.md", self.git("status", "--porcelain"))

    def test_recover_and_tracked_private_refused(self):
        M.private_prepare(self.repo, "CLAUDE.local.md", "local", True)
        M.private_confirm(self.repo, "CLAUDE.local.md", 1)
        M.private_switch(self.repo, "CLAUDE.local.md", True)
        M.private_recover(self.repo, "CLAUDE.local.md", True)
        self.assertTrue((self.repo / "CLAUDE.local.md").exists())
        self.assertFalse((self.repo / ".claude/rules/local.md").exists())
        self.git("add", "-f", "CLAUDE.local.md")
        with self.assertRaises(M.MigrationError): M.private_prepare(self.repo, "CLAUDE.local.md", "other", True)


class ReviewRegressionTests(Repo):
    def migrate(self, message="m"):
        plan = self.approve_all(self.plan())
        M.apply(plan, self.repo, write=True)
        return plan, M.commit(plan, self.repo, message)

    def test_commit_rename_unicode_and_spaces(self):
        self.write("CLAUDE.md", "# P\n\n## X\n\n- extra\n")
        self.write("документи/CLAUDE.md", "# Д\n\n## Y\n\n- y\n")
        self.write("my docs/CLAUDE.md", "# S\n\n## Z\n\n- z\n")
        self.commit_all()
        plan, done = self.migrate()
        self.assertEqual(done["status"], "committed")
        state = json.loads((M.migration_dir(self.repo, plan["id"]) / "state.json").read_text())
        self.assertEqual(state["status"], "committed")

    def test_revert_preview_and_untracked_restore(self):
        self.git("commit", "--allow-empty", "-qm", "base")
        self.write("CLAUDE.md", "# P\n\n## X\n\n- keep\n")
        plan = self.approve_all(self.plan())
        M.apply(plan, self.repo, write=True); M.commit(plan, self.repo, "m")
        head = self.git("rev-parse", "HEAD")
        self.assertEqual(M.rollback(plan, self.repo, write=False, revert=True)["status"], "preview")
        self.assertEqual(self.git("rev-parse", "HEAD"), head)
        result = M.rollback(plan, self.repo, write=True, revert=True)
        self.assertEqual(result["status"], "reverted")
        self.assertIn("keep", (self.repo / "CLAUDE.md").read_text())

    def test_partial_output_failure_is_recoverable(self):
        for d in ("a", "b"):
            self.write(f"{d}/AGENTS.md", f"# {d}\n"); self.write(f"{d}/CLAUDE.md", f"# {d}\n\n## R\n\n- rule {d}\n")
        self.commit_all()
        plan = self.approve_all(self.plan())
        os.chmod(self.repo / "b", 0o555); self.addCleanup(os.chmod, self.repo / "b", 0o755)
        with self.assertRaises(OSError): M.apply(plan, self.repo, write=True)
        result = M.rollback(plan, self.repo, write=True)
        self.assertEqual((self.repo / "a/AGENTS.md").read_text(), "# a\n")
        self.assertEqual(result["skipped"], [])

    def test_custom_title_in_stub_is_not_dropped(self):
        stub = "# Acme: ALWAYS run make lint before commit\n\n## Wiki\n\nWiki schema and operations → `docs/wiki/schema.md`. Skill: `wiki`.\n"
        self.write("CLAUDE.md", stub); self.commit_all()
        plan = self.plan()
        self.assertIn("ALWAYS run make lint", plan["outputs"][0]["content"])
        self.write("AGENTS.md", "# Other\n"); self.commit_all()
        plan = self.approve_all(self.plan())
        self.assertFalse(M.check(plan, self.repo)["ok"])  # dropped title carries a critical rule

    def test_relocated_and_inline_imports(self):
        self.write(".claude/rules/style.md", "x\n")
        self.write(".claude/CLAUDE.md", "# C\n\n## Style\n\n@rules/style.md\n")
        self.write("GEMINI.md", "# G\n\n## More\n\nSee @QWEN.md for details.\n"); self.write("QWEN.md", "# Q\n\n## Q\n\n- q\n")
        self.commit_all()
        plan = self.approve_all(self.plan())
        content = plan["outputs"][0]["content"]
        self.assertIn("@.claude/rules/style.md", content)
        plan["decisions"]["includes_approved"] = True
        self.assertTrue(any("@QWEN.md" in e for e in M.check(plan, self.repo)["errors"]))
        plan["outputs"][0]["content"] += "\nUse @testing-library/react and ping @alice.\n"
        self.assertFalse(any("testing-library" in d or "alice" in d for d in M.check(plan, self.repo)["decisions_needed"]))

    def test_commit_refuses_preexisting_untracked_canonical(self):
        self.write("CLAUDE.md", RULES); self.commit_all(); self.write("AGENTS.md", "# P\n\n- my private wip\n")
        plan = self.approve_all(self.plan())
        M.apply(plan, self.repo, write=True)
        with self.assertRaises(M.MigrationError): M.commit(plan, self.repo, "m")

    def test_wiki_notes_heading_and_distinct_title(self):
        self.write("AGENTS.md", "# Title A\n\n## Rules\n\n- ok\n")
        self.write("CLAUDE.md", "# Title B\n\n## Rules\n\n- ok\n\n## Wiki conventions\n\n- Use kebab-case page names.\n")
        self.commit_all()
        plan = self.plan()
        content = plan["outputs"][0]["content"]
        self.assertIn("## Notes from the CLAUDE.md wiki section\n\n- Use kebab-case page names.", content)
        h1 = [c for c in plan["coverage"] if c["fragment"] == "CLAUDE.md#1"][0]
        self.assertFalse(h1["approved"])

    def test_private_name_validated_and_crlf_preserved(self):
        self.write("AGENTS.md", "# P\r\n\r\n## R\r\n\r\n- a\r\n")
        self.write("CLAUDE.md", "# P\r\n\r\n## S\r\n\r\n- b\r\n"); self.commit_all()
        plan = self.approve_all(self.plan())
        self.assertIn("- a\r\n", plan["outputs"][0]["content"])
        self.assertNotIn("\n", plan["outputs"][0]["content"].replace("\r\n", ""))
        self.write("CLAUDE.local.md", "x\n")
        exclude = self.repo / ".git/info/exclude"
        before = exclude.read_text() if exclude.exists() else ""
        with self.assertRaises(M.MigrationError): M.private_prepare(self.repo, "CLAUDE.local.md", "../../../esc", True)
        self.assertEqual(exclude.read_text() if exclude.exists() else "", before)


if __name__ == "__main__":
    unittest.main()
