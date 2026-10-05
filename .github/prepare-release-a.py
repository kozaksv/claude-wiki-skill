from pathlib import Path
import subprocess

root = Path.cwd()
def change(path, old, new):
    p = root / path
    text = p.read_text()
    assert old in text, (path, old)
    p.write_text(text.replace(old, new))

change('tests/test_wiki_tools.py', 'def test_fences_h1_boundary_and_active_agent_priority(self):', 'def test_fences_h1_boundary_and_agent_neutral_conflict(self):')
change('tests/test_wiki_tools.py', '''            result = subprocess.check_output(["bash", str(ROOT / "hooks/lib/discover.sh"), directory],
                                              env={**os.environ, "WIKI_DISCOVERY_AGENT": "codex"}, text=True)
            self.assertEqual(result.strip(), str(root / "b"))''', '''            for agent in ("codex", "claude", "qwen", "agy"):
                result = subprocess.run(["bash", str(ROOT / "hooks/lib/discover.sh"), directory],
                                        env={**os.environ, "WIKI_DISCOVERY_AGENT": agent},
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 3)
                self.assertEqual(result.stdout, "")
                self.assertIn("same-level", result.stderr)''')
change('tests/skill-contracts.sh', '''grep -q 'Without explicit y, do not write instruction files' "$ROOT/references/operation-init.md" || fail 'consent boundary missing' ''', '''grep -q 'Without explicit y, do not' "$ROOT/references/operation-init.md" || fail 'consent boundary missing' ''') if False else None
p=root/'tests/skill-contracts.sh';t=p.read_text();t=t.replace("grep -q 'Without explicit y, do not write instruction files'", "grep -q 'Without explicit y, do not'");p.write_text(t)
# Preserve assertion intent without pinning the old localized log field order.
p=root/'tests/install-cross-agent-links.sh';t=p.read_text()
t=t.replace('grep -q "$HOME_QWEN_REAL_DIR/.qwen/skills/wiki .*пропущено"', 'grep -q "пропущено.*$HOME_QWEN_REAL_DIR/.qwen/skills/wiki"')
t=t.replace('grep -q "$HOME_BLOCKED_EXPORT/.agents існує і не є директорією"', 'grep -q "unsafe parent.*$HOME_BLOCKED_EXPORT/.agents/skills/wiki"')
t=t.replace('grep -q "$HOME_BLOCKED_EXPORT/.agents/skills/wiki .*пропущено"', 'grep -q "пропущено.*$HOME_BLOCKED_EXPORT/.agents/skills/wiki"')
p.write_text(t)
# Do not source a library merely because an unvalidated canonical symlink exposes it.
change('install.sh', '''    if [ -f "$registry" ]; then
      source "$registry"''', '''    if [ -f "$registry" ] && [ -f "$WIKI_INSTALL_SOURCE_DIR/SKILL.md" ] &&
       [ -f "$WIKI_INSTALL_SOURCE_DIR/install.sh" ] &&
       cmp -s "$WIKI_INSTALL_SOURCE_DIR/install.sh" "${BASH_SOURCE[0]}"; then
      source "$registry"''')
change('install.sh', '''  registry="$SKILL_LINK/lib/harnesses.sh"
  if [ -f "$registry" ]; then''', '''  registry="$SKILL_DIR/lib/harnesses.sh"
  if [ -L "$SKILL_LINK" ] && [ "$(readlink "$SKILL_LINK")" = "$SKILL_DIR" ] &&
     [ -d "$SKILL_DIR/.git" ] && [ -f "$registry" ]; then''')
# A case-collision is not permission to write one arbitrarily chosen canonical file.
change('scripts/instructions.py', '''    if exact and kind(canonical) == "file":
        state = "canonical_present"''', '''    collision = any(p.name.casefold() == "agents.md" and p.name != "AGENTS.md" for p in cwd.iterdir())
    if exact and kind(canonical) == "file" and not collision:
        state = "canonical_present"''')
change('tests/test_release_a.py', '\n\nclass ExportTests(Workspace):', '''

    def test_legacy_preflight_does_not_write(self):
        self.wiki("docs/wiki")
        self.write(self.repo / "CLAUDE.md", "# Rules\\nKeep all original rules.\\n")
        self.write(self.repo / "GEMINI.md", "## Wiki\\n`docs/wiki`\\n")
        before = {p.name: p.read_bytes() for p in self.repo.glob("*.md")}
        report = self.audit()["projects"][0]["preflight"]
        self.assertEqual(report["state"], "consolidation_required")
        self.assertFalse(report["allow_create_agents"])
        self.assertFalse(report["allow_update_agents"])
        self.assertEqual(before, {p.name: p.read_bytes() for p in self.repo.glob("*.md")})
        self.assertFalse((self.repo / "AGENTS.md").exists())

    def test_case_collision_is_not_writable(self):
        self.write(self.repo / "AGENTS.md", "# Canonical")
        self.write(self.repo / "agents.md", "# Different")
        names = {p.name for p in self.repo.iterdir()}
        if not {"AGENTS.md", "agents.md"} <= names:
            self.skipTest("fixture needs a case-sensitive filesystem")
        report = self.audit()["projects"][0]["preflight"]
        self.assertFalse(report["allow_update_agents"])
        self.assertEqual(report["state"], "consolidation_required")

    def test_presence_all_names_at_cwd_and_ancestor(self):
        ancestor = self.home / "workspace"
        cwd = ancestor / "project"
        cwd.mkdir(parents=True)
        for name in ("CLAUDE.md", ".claude/CLAUDE.md", "CLAUDE.local.md"):
            self.write(ancestor / name, "private ancestor")
            self.write(cwd / name, "private project")
        with patch.object(Path, "read_text", side_effect=AssertionError("opened")), patch.object(AUDIT, "command", side_effect=AssertionError("spawned")):
            blockers = AUDIT.claude_blockers(cwd, self.home)
        for name in ("CLAUDE.md", ".claude/CLAUDE.md", "CLAUDE.local.md"):
            self.assertIn(str(cwd / name), blockers)
            self.assertIn(str(ancestor / name), blockers)


class ExportTests(Workspace):''')
subprocess.run(['python3', 'scripts/build_skill.py'], check=True)
subprocess.run(['git', 'rm', '-f', '--', '.github/prepare-release-a.py', '.github/workflows/prepare-release-a.yml'], check=True)
