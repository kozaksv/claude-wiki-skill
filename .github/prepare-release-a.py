from pathlib import Path
import subprocess

root = Path.cwd()
def change(path, old, new):
    p = root / path
    text = p.read_text()
    assert text.count(old) == 1, (path, old)
    p.write_text(text.replace(old, new))

change('hooks/lib/discover.sh', '  WIKI_DISC_RECORDS+=("$1" "$2" "$3" "$4")\n', '''  WIKI_DISC_RECORDS+=("$1" "$2" "$3" "$4")
  case "$4" in
    outside_boundary|symlink_escape)
      printf '[wiki-hook] pointer поза межами репо, ігнорую: %s\\n' "${1:-$2}" >&2 ;;
  esac
''')
change('tests/hooks/run.sh', '#     CLAUDE.md wins (higher priority, first in the consult order).', '#     Release A reports same-level conflict and returns no writeable path.')
change('tests/hooks/run.sh', '''expected="$(real "$fixture/from-claude/wiki")"
out="$(discover_wiki "$fixture" 2>/dev/null)"
assert_eq "CLAUDE.md and QWEN.md both valid: CLAUDE.md wins" "$expected" "$out"''', '''conflict_rc=0
out="$(discover_wiki "$fixture" 2>/dev/null)" || conflict_rc=$?
assert_eq "CLAUDE.md and QWEN.md differ on same level: no writeable path" "" "$out"
assert_eq "same-level conflict has explicit status" "3" "$conflict_rc"''')
change('references/operation-doctor.md', '''are reported, not rewritten. Repair uses the existing explicit pointer-repair or
`wiki init` workflow; never initialize a second wiki.''', '''are reported, not rewritten. Release A repair uses `instructions-audit.md`:
only an existing regular AGENTS.md may be repaired after consent; legacy pointers
remain report-only/consolidation-required. Never initialize a second wiki.''')
change('references/operation-doctor.md', '''to the intended Git checkout, then verify `~/.agents/skills/wiki`,
`~/.gemini/skills/wiki` and `~/.qwen/skills/wiki` exports. Report actual commit,''', '''to the intended Git checkout, then verify the active exports from
`lib/harnesses.sh`: `~/.agents/skills/wiki`,
`~/.gemini/antigravity-cli/skills/wiki`, and `~/.qwen/skills/wiki`.
Old `.gemini/skills` entries are retirement findings, not required exports.
Report actual commit,''')
subprocess.run(['python3', 'scripts/build_skill.py'], check=True)
subprocess.run(['git', 'rm', '-f', '--', '.github/prepare-release-a.py', '.github/workflows/prepare-release-a.yml'], check=True)
# Print remaining terminology for human review; history and read-only legacy
# references are legitimate and are not automatically rewritten.
subprocess.run(['git', 'grep', '-n', '-E', 'Gemini CLI|Cross-agent instruction-file sync|~/.gemini/skills/wiki', '--', 'SKILL.md', 'README.md', 'references'], check=False)
