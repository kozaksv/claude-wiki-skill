"""Issue #5: verified upgrades, scoped migrations and bounded session context."""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "hooks/lib" / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


config = load("config_audit")
health = load("session_health")


def handler(command, event="SessionStart", matcher="startup|clear|compact"):
    return {"hooks": {event: [{"matcher": matcher, "hooks": [{"type": "command", "command": command}]}]}}


class UpgradeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="wiki-upgrade-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.home = self.base / "home"
        self.home.mkdir()
        (self.home / ".claude/skills").mkdir(parents=True)
        (self.home / ".claude/skills/wiki").symlink_to(ROOT, target_is_directory=True)
        self.project = self.base / "project with spaces"
        self.project.mkdir()
        subprocess.run(["git", "init", "-q", str(self.project)], check=True)
        self.env = dict(os.environ, HOME=str(self.home))
        self.env.pop("CLAUDE_PROJECT_DIR", None)
        self.env.pop("QWEN_PROJECT_DIR", None)
        self.env.pop("WIKI_HOOK_CLIENT", None)
        self.local = self.project / ".claude/settings.local.json"
        self.local.parent.mkdir()
        self.global_settings = self.home / ".claude/settings.json"
        self.command = str(self.home / ".claude/skills/wiki/hooks/session-start.sh")

    def install(self, *args):
        return subprocess.run(["bash", str(ROOT / "hooks/install-hooks.sh"), *args],
                              env=self.env, text=True, capture_output=True, timeout=30)

    def test_standalone_ownership_not_inline_text(self):
        self.assertEqual(config.classify(self.command), "owned")
        self.assertEqual(config.classify(config.expected_command(Path(self.command))), "owned")
        self.assertEqual(config.classify('bash "' + str(self.home / "claude-wiki-skill/hooks/session-start.sh") + '"'), "owned")
        self.assertEqual(config.classify('echo "WIKI INDEX (hook-injected)"; cat docs/wiki/index.md'), "suspect")
        self.assertEqual(config.classify('echo "' + self.command + '"'), "suspect")
        self.assertEqual(config.classify(self.command + '; touch /tmp/never'), "suspect")
        self.assertEqual(config.classify('echo other'), "foreign")

    def test_global_and_project_duplicates_migrate_once(self):
        data = handler(self.command)
        data["hooks"]["SessionStart"][0]["hooks"].append({"type": "command", "command": "echo keep-me"})
        data["unrelated"] = {"preserve": True}
        self.local.write_text(json.dumps(data))
        os.chmod(self.local, 0o640)
        result = self.install("--verify", "--project", str(self.project))
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        updated = json.loads(self.local.read_text())
        self.assertEqual(updated["unrelated"], data["unrelated"])
        self.assertEqual(updated["hooks"]["SessionStart"][0]["hooks"], [{"type": "command", "command": "echo keep-me"}])
        self.assertEqual(self.local.stat().st_mode & 0o777, 0o640)
        self.assertTrue(list(self.local.parent.glob("settings.local.json.bak-wiki-hooks-*")))
        before = self.local.read_bytes()
        second = self.install("--verify", "--project", str(self.project), "--project", str(self.project))
        self.assertEqual(second.returncode, 0, second.stderr + second.stdout)
        self.assertEqual(self.local.read_bytes(), before)
        self.assertIn("wiki hooks: verified", second.stdout)
        global_data = json.loads(self.global_settings.read_text())
        self.assertEqual(len(global_data["hooks"]["SessionStart"]), 1)
        self.assertEqual(len(global_data["hooks"]["PostToolUse"]), 1)

    def test_unknown_inline_hook_preserved_and_upgrade_incomplete(self):
        raw = json.dumps(handler('echo "WIKI INDEX (hook-injected)"; cat docs/wiki/index.md'))
        self.local.write_text(raw)
        result = self.install("--verify", "--project", str(self.project))
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        self.assertEqual(self.local.read_text(), raw)
        self.assertIn("ambiguous", result.stdout)
        self.assertNotIn("wiki hooks: verified", result.stdout)

    def test_other_checkout_not_touched(self):
        other = self.base / "other/.claude/settings.json"
        other.parent.mkdir(parents=True)
        other.write_text(json.dumps(handler(self.command)))
        raw = other.read_bytes()
        result = self.install("--verify", "--project", str(self.project))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(other.read_bytes(), raw)

    def test_project_qwen_migration_creates_global_qwen_pair(self):
        local_qwen = self.project / ".qwen/settings.json"
        local_qwen.parent.mkdir()
        local_qwen.write_text(json.dumps(handler(str(self.home / ".qwen/hooks/wiki-session-start.sh"))))
        result = self.install("--verify", "--project", str(self.project))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(local_qwen.read_text())["hooks"]["SessionStart"], [])
        self.assertTrue((self.home / ".qwen/settings.json").exists())

    def test_global_json_duplicate_keys_preserved(self):
        raw = '{"hooks":{},"hooks":{"SessionStart":[]}}'
        self.global_settings.write_text(raw)
        result = self.install("--verify")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.global_settings.read_text(), raw)

    def test_project_symlink_cannot_redirect_migration(self):
        self.global_settings.write_text(json.dumps(handler(self.command)))
        self.local.symlink_to(self.global_settings)
        raw = self.global_settings.read_bytes()
        result = self.install("--verify", "--project", str(self.project))
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.local.is_symlink())
        self.assertEqual(self.global_settings.read_bytes(), raw)

    def test_project_directory_symlink_rejected(self):
        shutil.rmtree(self.local.parent)
        self.local.parent.symlink_to(self.home / ".claude", target_is_directory=True)
        result = self.install("--verify", "--project", str(self.project))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.global_settings.exists())

    def test_no_python_is_not_reported_as_success(self):
        empty_path = self.base / "empty-path"
        empty_path.mkdir()
        env = dict(self.env, PATH=str(empty_path))
        result = subprocess.run([shutil.which("bash"), str(ROOT / "hooks/install-hooks.sh")],
                                env=env, text=True, capture_output=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.global_settings.exists())
        self.assertIn("python3", result.stderr)

    def test_doctor_read_only_and_disabled_hooks_are_reported(self):
        self.assertEqual(self.install().returncode, 0)
        data = json.loads(self.global_settings.read_text())
        data["disableAllHooks"] = True
        self.global_settings.write_text(json.dumps(data))
        raw = self.global_settings.read_bytes()
        result = subprocess.run(["bash", str(ROOT / "hooks/doctor.sh"), "--project", str(self.project)],
                                env=self.env, text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 3)
        self.assertIn("disableAllHooks", result.stdout)
        self.assertEqual(self.global_settings.read_bytes(), raw)

    def test_concurrent_migrations_keep_foreign_global_hook(self):
        self.global_settings.write_text(json.dumps(handler("echo foreign")))
        self.local.write_text(json.dumps(handler(self.command)))
        cmd = ["bash", str(ROOT / "hooks/install-hooks.sh"), "--verify", "--project", str(self.project)]
        a = subprocess.Popen(cmd, env=self.env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        b = subprocess.Popen(cmd, env=self.env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        for process in (a, b):
            out, err = process.communicate(timeout=40)
            self.assertEqual(process.returncode, 0, out + err)
        text = self.global_settings.read_text()
        self.assertIn("echo foreign", text)
        self.assertEqual(text.count('"matcher": "startup|clear|compact"'), 2)


class SessionHealthTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="wiki-health-")
        self.addCleanup(self.temp.cleanup)
        self.project = Path(self.temp.name)
        subprocess.run(["git", "init", "-q", str(self.project)], check=True)
        self.wiki = self.project / "docs/wiki"
        (self.wiki / "concepts").mkdir(parents=True)
        (self.wiki / "index.md").write_text("# Index\n\nunique-index-body\n")
        (self.wiki / "schema.md").write_text('---\nwiki_version: "4.0"\n---\n')
        (self.wiki / "concepts/a.md").write_text("# A\ncontent\n")
        self.usage = self.wiki / ".usage.json"
        self.env = dict(os.environ, CLAUDE_PROJECT_DIR=str(self.project))
        self.env.pop("QWEN_PROJECT_DIR", None)
        self.env.pop("WIKI_HOOK_CLIENT", None)

    def invoke(self, source="startup", qwen=False):
        script = "session-start-qwen.sh" if qwen else "session-start.sh"
        result = subprocess.run(["bash", str(ROOT / "hooks" / script)], env=self.env,
                                input=json.dumps({"source": source, "cwd": str(self.project)}),
                                text=True, capture_output=True, timeout=8)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)["hookSpecificOutput"]["additionalContext"] if qwen else result.stdout

    def test_compact_clear_resume_no_maintenance_or_index(self):
        for source in ("compact", "clear"):
            out = self.invoke(source)
            self.assertIn("WIKI DISCOVERY", out)
            self.assertNotIn("wiki lint", out)
            self.assertNotIn("unique-index-body", out)
            self.assertEqual(len(out.splitlines()), 1)
        self.assertEqual(self.invoke("resume"), "")

    def test_same_state_reminded_once_then_changed_deleted_renamed(self):
        self.assertIn("wiki lint", self.invoke())
        self.assertNotIn("wiki lint", self.invoke())
        page = self.wiki / "concepts/a.md"
        page.write_text("# Changed\n")
        self.assertIn("wiki lint", self.invoke())
        page.rename(page.with_name("b.md"))
        self.assertIn("wiki lint", self.invoke())
        page.with_name("b.md").unlink()
        self.assertIn("wiki lint", self.invoke())

    def test_log_and_telemetry_changes_do_not_change_fingerprint(self):
        initial = health.fingerprint(self.wiki)
        self.invoke()
        (self.wiki / "log.md").write_text("new entry\n")
        (self.wiki / "log").mkdir()
        (self.wiki / "log/old.md").write_text("archive\n")
        self.assertEqual(initial, health.fingerprint(self.wiki))
        self.assertNotIn("wiki lint", self.invoke())

    def test_old_full_lint_unchanged_no_reminder(self):
        digest = health.fingerprint(self.wiki)
        self.usage.write_text(json.dumps({"_hooks": {"last_lint_at": "2000-01-01T00:00:00Z", "last_lint_fingerprint": digest}}))
        self.assertNotIn("wiki lint", self.invoke())

    def test_partial_lint_does_not_stamp_full_fingerprint(self):
        health.mark_lint(self.wiki, "partial")
        meta = json.loads(self.usage.read_text())["_hooks"]
        self.assertIn("last_partial_lint_at", meta)
        self.assertNotIn("last_lint_fingerprint", meta)
        self.assertIn("wiki lint", self.invoke())
        health.mark_lint(self.wiki, "full")
        self.assertNotIn("wiki lint", self.invoke())

    def test_stale_telemetry_is_unconfirmed_not_dead_and_deduplicated(self):
        self.usage.write_text(json.dumps({"_hooks": {"post_tool_use_at": "2000-01-01T00:00:00Z"}}))
        out = self.invoke()
        self.assertIn("телеметрія не підтверджена", out)
        self.assertNotIn("мертва", out)
        self.assertNotIn("телеметрія не підтверджена", self.invoke())

    def test_corrupt_protection_is_preserved(self):
        for raw in ('not json', '[]', '{"concepts/a.md":{"protected":"true"}}', '{"x":{},"x":{}}'):
            self.usage.write_text(raw)
            self.assertIn("телеметрія недоступна", self.invoke())
            self.assertEqual(self.usage.read_text(), raw)

    def test_fifo_and_symlink_do_not_block_or_overwrite(self):
        if hasattr(os, "mkfifo"):
            os.mkfifo(self.usage)
            self.invoke()
            self.usage.unlink()
        target = self.project / "private.json"
        target.write_text('{"keep":true}')
        self.usage.symlink_to(target)
        self.invoke()
        self.assertTrue(self.usage.is_symlink())
        self.assertEqual(target.read_text(), '{"keep":true}')

    def test_future_schema_remains_read_only(self):
        (self.wiki / "schema.md").write_text('---\nwiki_version: "5.0"\n---\n')
        self.invoke()
        self.assertFalse(self.usage.exists())

    def test_qwen_preserves_source_and_envelope(self):
        out = self.invoke("compact", qwen=True)
        self.assertIn("WIKI DISCOVERY", out)
        self.assertNotIn("wiki lint", out)
        self.assertEqual(len(out.splitlines()), 1)

    def test_large_index_does_not_grow_compact_notice(self):
        before = self.invoke("compact")
        (self.wiki / "index.md").write_text("sensitive-body " * 30000)
        after = self.invoke("compact")
        self.assertEqual(before, after)
        self.assertLess(len(after.encode()), 700)

    def test_compact_does_not_scan_fingerprint(self):
        with patch.object(health, "fingerprint", side_effect=AssertionError("should not scan")):
            self.assertEqual(health.session(self.wiki, True, "compact"), [])

    def test_stdin_cwd_fallback(self):
        self.env.pop("CLAUDE_PROJECT_DIR", None)
        self.assertIn(str(self.wiki / "index.md"), self.invoke("compact"))

    def test_helper_version_matches_skill(self):
        self.invoke("compact")
        meta = json.loads(self.usage.read_text())["_hooks"]
        self.assertEqual(meta["hook_version"], health.hook_version())
        self.assertNotEqual(meta["hook_version"], "1")


if __name__ == "__main__":
    unittest.main()
