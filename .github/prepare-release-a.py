#!/usr/bin/env python3
"""Temporary assembly driver; removed before the reviewable PR snapshot."""
import json
from pathlib import Path
import re
import subprocess

ROOT = Path.cwd()
BASE = 'efa0e14eebe79337e74f0e063593de530a371a69'
NEW_FILES = ['docs/release-a-validation.md', 'hooks/lib/discover.sh', 'lib/harnesses.sh', 'references/discovery-cases.json', 'references/instructions-audit.md', 'scripts/build_skill.py', 'scripts/doctor.py', 'scripts/instructions.py', 'tests/test_release_a.py']

def replace(text, old, new, count=1):
    found = text.count(old)
    if found != count:
        raise ValueError(f'Expected {count} occurrences, got {found}: {old[:100]!r}')
    return text.replace(old, new)

def save(path, text):
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text)

changed = subprocess.check_output(['git', 'diff', '--name-only', BASE, 'HEAD'], text=True).splitlines()
assert set(changed) <= set(NEW_FILES) | {'.github/prepare-release-a.py', '.github/workflows/prepare-release-a.yml'}, changed
for path in NEW_FILES:
    assert (ROOT / path).is_file(), path

# Installer: retain checkout/pinning and hook safety; share export lifecycle.
p = ROOT / 'install.sh'; text = p.read_text()
text = replace(text, 'WIKI_INSTALL_RUNNING_COPY=1 bash "$installer_copy" "$@" || copy_rc=$?',
               'WIKI_INSTALL_RUNNING_COPY=1 WIKI_INSTALL_SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" bash "$installer_copy" "$@" || copy_rc=$?')
text = re.sub(r'^(?:AGENTS|GEMINI|QWEN)_SKILLS_ROOT=.*\n', '', text, flags=re.M)
start = text.index('export_skill_link() {')
end = text.index('repair_cross_agent_exports() {')
text = text[:start] + '''HARNESS_REGISTRY_READY=0
load_harness_registry() {
  [ "$HARNESS_REGISTRY_READY" = 0 ] || return 0
  local registry
  if [ -n "${WIKI_INSTALL_SOURCE_DIR:-}" ]; then
    registry="$WIKI_INSTALL_SOURCE_DIR/lib/harnesses.sh"
    if [ -f "$registry" ]; then
      source "$registry"
      HARNESS_REGISTRY_READY=1
      return 0
    fi
  fi
  registry="$SKILL_LINK/lib/harnesses.sh"
  if [ -f "$registry" ]; then
    source "$registry"
    HARNESS_REGISTRY_READY=1
    return 0
  fi
  echo 'wiki: harness registry unavailable in this pinned ref; exports not verified' >&2
  return 1
}

# Retain an available current registry in memory before checkout changes refs.
load_harness_registry 2>/dev/null || true

''' + text[end:]
start = text.index('  local wiki_agents_status="ok"', text.index('repair_cross_agent_exports() {'))
end = text.index('\nif [ "$REPAIR_EXPORTS" -eq 1 ]; then', start)
text = text[:start] + '''  load_harness_registry || return 2
  echo "Cross-agent export targets:"
  wiki_reconcile_exports
}
''' + text[end:]
text = replace(text, '''    if [ ! -e "$link" ]; then
      echo "[$name] замінюю битий canonical link: $link"
      ln -sfn "$target_dir" "$link"
      return 0
    fi
''', '')
start = text.index('# 2. Cross-agent wiki exports')
end = text.index('# 4. Git hooks', start)
text = text[:start] + '''# 2. Optional extractor. The shared registry exports only installed skills.
DOC_EXTRACT_INSTALLED=0
if install_skill_at_ref "doc-extract" "$DOC_EXTRACT_REPO" "$DOC_EXTRACT_DIR" "$DOC_EXTRACT_LINK" "$DOC_EXTRACT_REF"; then
  DOC_EXTRACT_INSTALLED=1
else
  echo "Увага: doc-extract не встановлено. Wiki skill працюватиме, але ingest-binary буде недоступний до повторного встановлення."
fi

# 3. Active exports and exact-owned retirement use one lifecycle.
EXPORTS_STATUS=0
if load_harness_registry; then
  wiki_reconcile_exports || EXPORTS_STATUS=$?
else
  EXPORTS_STATUS=2
fi

''' + text[end:]
start = text.index('ANY_SKIPPED=0\n')
end = text.index('echo ""\necho "Скіл встановлено/оновлено;', start)
text = text[:start] + 'ANY_SKIPPED=0\n[ "$EXPORTS_STATUS" -eq 0 ] || ANY_SKIPPED=1\n\n' + text[end:]
start = text.index('echo "Cross-agent exports (symlinks to shared canonical):"')
end = text.index('echo "Session-хуки Claude Code:"', start)
text = text[:start] + '''echo "Cross-agent exports: detailed results above (not runtime verification)"
if [ "$DOC_EXTRACT_INSTALLED" -eq 1 ]; then
  echo "  $DOC_EXTRACT_LINK → $DOC_EXTRACT_DIR  (@ $DOC_EXTRACT_REF)"
fi
''' + text[end:]
text = text.replace('Codex/Gemini бачитимуть', 'Codex/agy/Qwen бачитимуть')
text = text.replace('Claude Code, Codex або Gemini CLI', 'Claude Code, Codex, agy CLI або Qwen Code')
save('install.sh', text)

# Uninstall: preserve all existing settings locks and orphan/clone guards.
p = ROOT / 'uninstall.sh'; text = p.read_text()
text = re.sub(r'^(?:AGENTS|GEMINI|QWEN)_SKILLS_ROOT=.*\n', '', text, flags=re.M)
text = replace(text, '  local path="$1" expected_target="$2"\n', '''  local path="$1" expected_target="$2"
  if ! wiki_export_parent_safe "$path"; then
    echo "$path — skipped (unsafe parent)"
    SKIPPED=1
    return 0
  fi
''')
text = replace(text, '    rm "$path"\n', '''    [ -L "$path" ] && [ "$(readlink "$path")" = "$expected_target" ] || { SKIPPED=1; return 0; }
    rm -- "$path"
''')
text = replace(text, 'LOCK_LIB="$SELF_DIR/hooks/lib/settings-lock.sh"\n', '''# Registry is loaded from this trusted script checkout, not a foreign export.
if [ -f "$SELF_DIR/lib/harnesses.sh" ]; then
  source "$SELF_DIR/lib/harnesses.sh"
else
  echo 'wiki: harness registry unavailable; preserving exports'
  wiki_export_parent_safe() { return 1; }
  wiki_harness_records() { return 0; }
  SKIPPED=1
fi
LOCK_LIB="$SELF_DIR/hooks/lib/settings-lock.sh"
''')
start = text.index('# Remove exports first')
end = text.index('# ---------------------------------------------------------------------------', start)
text = text[:start] + '''# Remove supported exports and exact-owned retired links before canonical.
while IFS='|' read -r id relative entry_kind; do
  [ "$entry_kind" = export ] || continue
  for skill in wiki doc-extract; do
    remove_symlink_entry "$HOME/$relative/$skill" "$SKILLS_ROOT/$skill"
  done
done < <(wiki_harness_records)
for skill in wiki doc-extract; do
  remove_symlink_entry "$HOME/.gemini/skills/$skill" "$SKILLS_ROOT/$skill"
done
remove_symlink_entry "$SKILLS_ROOT/wiki" "$SKILL_DIR"
remove_symlink_entry "$SKILLS_ROOT/doc-extract" "$DOC_EXTRACT_DIR"
while IFS='|' read -r id relative entry_kind; do
  if wiki_export_parent_safe "$HOME/$relative/entry"; then rmdir "$HOME/$relative" 2>/dev/null || true; fi
done < <(wiki_harness_records)
if wiki_export_parent_safe "$HOME/.gemini/skills/entry"; then rmdir "$HOME/.gemini/skills" 2>/dev/null || true; fi

''' + text[end:]
save('uninstall.sh', text)

# PostToolUse's existing empty-path guard already stops on conflict.
p = ROOT / 'hooks/session-start.sh'; text = p.read_text()
text = replace(text, '  wiki="$(discover_wiki "$anchor" 2>/dev/null)"\n', '''  local discovery_rc=0
  wiki="$(discover_wiki "$anchor" 2>/dev/null)" || discovery_rc=$?
  if [ "$discovery_rc" -eq 3 ]; then
    printf '%s\\n' 'wiki: same-level pointer conflict; no telemetry writes — wiki doctor'
    return 0
  fi
''')
save('hooks/session-start.sh', text)
p = ROOT / 'hooks/doctor.sh'
save('hooks/doctor.sh', replace(p.read_text(), 'exec python3 "$HERE/lib/config_audit.py" check "$@"',
                               'exec python3 "$HERE/../scripts/doctor.py" "$@"'))

p = ROOT / 'references/reader-core.md'
text = p.read_text() + '''
## Release A: deterministic selection and write safety

Use the normative [discovery cases](discovery-cases.md); their exact fixture
inputs are in [discovery-cases.json](discovery-cases.json). CI tests the local
parser; GitHub-agent parity requires its own recorded connector run.

An explicit validated target wins for its operation. Otherwise inspect all
candidates at the nearest valid directory in the cwd-to-repository-root walk.
Within that directory the order is `AGENTS.md` → `CLAUDE.md` → `GEMINI.md` →
`QWEN.md`, regardless of harness. Use exact-case directory/tree entries. A stale
pointer does not hide another valid one. Two paths to the same resolved wiki
are not a conflict. Legacy names remain read sources, not new write targets.

Different valid wikis **on the selected level** are a same-level conflict:
read-only analysis names the selected wiki and the conflict; unaddressed writes
(including AUTO-lint and hook metadata) stop. An explicitly validated target can
resolve that operation, not change other pointers or authorize unrelated hooks.
Root-X/nested-Y is a normal nearest-scope case. Report an observed cross-level
mismatch without blocking it; no full native-loading simulation is required.

Local absolute pointers can be read only after boundary validation; they are
non-portable legacy. GitHub cannot map host paths and reports them rather than
inventing a repository-relative equivalent. Neither transport follows an
instruction-file symlink outside its selected repository.
'''
save('references/reader-core.md', text)
p = ROOT / 'references/local-reader.md'; text = p.read_text()
text = replace(text, '''   the same bounded discovery implementation used by the hooks. Set
   `WIKI_DISCOVERY_AGENT` to `claude`, `codex`, `gemini`, or `qwen` when known;
   otherwise use its deterministic default priority. Do not reimplement the
   pointer parser in an ad-hoc shell command.''', '''   the same bounded discovery implementation used by the hooks. Priority is
   agent-neutral: AGENTS first within the nearest valid level. Exit 3 means
   same-level conflict and deliberately returns no writeable wiki path. For a
   read-only selected-path/conflict report use `scripts/instructions.py audit
   --project START_DIRECTORY --json`. Do not reimplement the pointer parser.''')
save('references/local-reader.md', text)
p = ROOT / 'skills/wiki-github/SKILL.md'; text = p.read_text()
text = replace(text, '''   An explicit user-selected wiki path takes precedence. Report conflicting
   valid wikis rather than combining their contents.''', '''   An explicit user-selected wiki path takes precedence. Inspect all pointers
   on the selected level. Different valid same-level wikis allow a named,
   warned read only; unaddressed writes stop. Cross-level differences do not
   block normal nearest-scope monorepos. Follow the bundled reader contract
   and discovery-cases.md; local CI alone does not prove this adapter's parity.''')
save('skills/wiki-github/SKILL.md', text)

p = ROOT / 'references/discovery-versioning.md'; text = p.read_text()
text = replace(text, '''For local maintenance, execute `hooks/lib/discover.sh` for path discovery;
`WIKI_DISCOVERY_AGENT=claude|codex|gemini|qwen` supplies the active agent.''', '''For local maintenance, execute `hooks/lib/discover.sh` for path discovery.
Use `instructions-audit.md` before any instruction write. Priority is agent-
neutral; `WIKI_DISCOVERY_AGENT` no longer changes selection. A same-level
conflict returns exit 3 without a path; audit reports the read-only selection.''')
start = text.index('2. **Find agent instruction files**')
end = text.index('3. **Read the pointer section**', start)
text = text[:start] + '''2. **Find agent instruction files** — walk cwd to the nearest Git boundary,
   inclusive. At each level validate exact-case `AGENTS.md`, `CLAUDE.md`,
   `GEMINI.md`, `QWEN.md` pointers in that order, independent of active agent.
   Inspect every candidate at the nearest valid level. Same-level different
   valid wikis: warned read-only selection; no unaddressed writes (including
   AUTO-lint and hooks) until an explicit target resolves that operation.
   Root-X/nested-Y: nearest wins, cross-level difference is warning only.
   Stale pointers do not hide valid ones. See reader-core.md/discovery-cases.md.
''' + text[end:]
start = text.index('### Cross-agent instruction-file sync')
end = text.index('## Versioning & Migration', start)
text = text[:start] + '''### Canonical instruction-file maintenance (release A)

Load `instructions-audit.md`. No four-file sync remains. Fresh empty-scope Init
creates only `AGENTS.md`; maintenance/ingest writes shared rules or pointers
only to an existing regular canonical file after preflight and consent.
Legacy scope without it: `consolidation required`, no instruction writes.
Stale legacy pointers are report-only; no placeholder, redirect or symlink is
created. Scope-aware consolidation and deletion belong to release B.

For canonical-pointer repairs compute `{schema_path_relative_to_instruction_file}`
and the index/wiki paths from the canonical file's directory. Keep any pointer
line that resolves to a valid on-disk wiki unchanged. Before replacing the
pointer section with the full Session-Start block, preserve custom details;
never silently discard existing rules. Do not run pointer maintenance during
status, lint, or query. For non-absent Init states, use the Non-absent Init
consent block and write only after explicit approval.

**CRITICAL: Never create a second wiki.** Existing valid pointers and canonical
fallback select the current wiki; missing instruction files are not permission
for another knowledge store. The default is one canonical wiki per git root marker,
with explicitly declared nested subproject wikis allowed by nearest-scope rules.
Schema/procedures stay in schema.md or skill references, not resident context.

''' + text[end:]
start = text.index('```markdown\n### 4.0 (2026-05-01)', text.index('### Migration Log'))
end = text.index('\n```', start + len('```markdown')) + len('\n```')
history = text[start:end]
save('docs/history/instruction-schema-release-log.md', '# Historical wiki release log examples\n\nSuperseded behavior is history, not current instruction-file policy.\n\n' + history + '\n')
text = text[:start] + '''Use a dated entry naming the actual schema/content change. Historical release
examples moved to `docs/history/instruction-schema-release-log.md`; do not load
them as current behavior or copy their four-file sync into a new project.
Instruction layout changes in 4.11 do not require a schema-major migration.
''' + text[end:]
save('references/discovery-versioning.md', text)

p = ROOT / 'references/operation-init.md'; text = p.read_text()
start = text.index('1. **Find agent instruction files**')
end = text.index('2. **Determine wiki state**', start)
text = text[:start] + '''1. **Find agent instruction files** with Step 0 and the same Git boundary.
   Before the first init write, load `instructions-audit.md` and audit the
   instruction directory. Wiki-absent is not instruction-empty. Fresh empty
   scope can create AGENTS even when effective Codex profiles are unknown;
   a known existing legacy/fallback file cannot be shadowed by a short stub.
   In legacy scope without canonical, leave instruction files unchanged and
   report `consolidation required`. Existing custom pointers still work;
   canonical docs/wiki can be initialized with consent without a pointer.
   New custom pointers requiring legacy-scope changes wait for release B.
''' + text[end:]
start = text.index('### Cross-agent instruction-file sync')
end = text.index('### Non-absent Init consent block', start)
text = text[:start] + '''### Canonical instruction-file maintenance

Use `instructions-audit.md` for preflight and every pointer action. Create only
AGENTS.md in a genuinely empty instruction scope. In an existing regular
AGENTS.md, preserve rules and valid Wiki/Вікі blocks; repair only a stale
canonical block after showing its custom content. Legacy files are never
created or modified, including stale-pointer repair. Instruction aliases are
consolidation-required, not writable through their target.

### Cross-agent skill availability

Check the shared canonical `~/.claude/skills/wiki`, then registry-derived
exports. The Bootstrap plan template (step 12) lists this check. An export means
filesystem availability, not verified runtime loading. Missing CLI binaries
are not a reason to delete supported exports or to claim a runtime test.

<!-- harness-exports:start -->
<!-- harness-exports:end -->

If repairs are needed, disclose them in the plan. After consent run the installed
new `install.sh --repair-exports` once. It performs no fetch/ref switch, creates
and verifies agy's export before retiring exact-owned old Gemini links, and
preserves conflicting foreign paths. Optional doc-extract is independent.
Report missing/broken exports if the installer is unavailable, never invent
cross-agent readiness. Non-absent Init uses the consent block below.

''' + text[end:]
text = replace(text, '  N-1. Проєктні instruction-файли — синхронізувати `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `QWEN.md`, якщо відсутні або stale',
               '  N-1. Проєктні instruction-файли — погоджений ремонт лише наявного AGENTS.md; legacy scope: звіт consolidation required')
text = replace(text, '  10. Agent instruction file(s) — синхронізувати `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `QWEN.md` через Cross-agent instruction-file sync; create missing minimal instruction files with a relative "Wiki schema → ..." path computed per file (usually `docs/wiki/schema.md`)',
               '  10. AGENTS.md — створити лише після empty-scope preflight або доповнити наявний canonical; legacy scope: без instruction-записів, consolidation required')
text = text.replace('~/.gemini/skills/wiki', '~/.gemini/antigravity-cli/skills/wiki')
start = text.index('   Add a single `## Wiki` pointer through Cross-agent instruction-file sync:')
end = text.index('6a. Create `{wiki}/.usage.json`.', start)
text = text[:start] + '''   Apply `instructions-audit.md`: a single relative Wiki block only in an
   allowed AGENTS.md. Do not edit legacy instruction schemas/pointers in A;
   report consolidation-required and preserve originals. A separate, approved
   wiki-schema migration cannot authorize legacy instruction writes.
''' + text[end:]
text = text.replace('10. Run `Cross-agent instruction-file sync` and `Cross-agent skill availability`;',
                         '10. Report `Canonical instruction-file maintenance` and `Cross-agent skill availability`;')
text = text.replace('телеметрія, порожня крім `_hooks.last_lint_at = now`', 'телеметрія з `_hooks.telemetry_first_seen_at`, без удаваного lint')
save('references/operation-init.md', text)

p = ROOT / 'references/operation-ingest-source.md'; text = p.read_text()
text = replace(text, '- **Agent instruction files** (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `QWEN.md`) get ONLY: new conventions, rules, data model summary changes (1-2 lines max)',
'''- **Shared instructions:** first use `instructions-audit.md`. Only an existing
  regular `AGENTS.md` may receive approved new conventions/rules/model summaries.
  Without canonical, leave all instruction files unchanged and report
  `consolidation required`; preserve the learned knowledge in the selected wiki.
  Never create a stub or append to CLAUDE.md/GEMINI.md/QWEN.md during ingest.''')
save('references/operation-ingest-source.md', text)
p = ROOT / 'references/operation-ingest-binary.md'; text = p.read_text()
text = text.replace('~/.gemini/skills/doc-extract', '~/.gemini/antigravity-cli/skills/doc-extract').replace('Gemini CLI', 'agy CLI')
save('references/operation-ingest-binary.md', text)
p = ROOT / 'references/operation-lint.md'; text = p.read_text()
marker = '**11. Agent Instruction File Content Verification (Karpathy-style)**'
assert marker in text
text = text.replace(marker, '''**Release A instruction-write boundary:** load `instructions-audit.md` before
any instruction edit. Legacy files are report-only, including stale-pointer
repair; do not condense, delete, or write their rules. Canonical changes require
preflight/consent. Critical rules and their conditions are KEEP by default;
changing them is DECIDE, and dead links never authorize deleting a whole rule.

''' + marker)
save('references/operation-lint.md', text)
p = ROOT / 'references/updating.md'; text = p.read_text()
text += '''
## Release A instruction/export audit

After an explicit update in the selected projects, run the read-only instruction
preflight described in `instructions-audit.md`. Report consolidation-required;
do not migrate or delete project instruction files in this release. An old
installer's running copy may have recreated retired exports: the new installed
`install.sh --repair-exports` repairs them after the same scoped consent. No
Gemini CLI settings are written. Unknown Codex profiles alone do not block fresh
empty-scope init. Claude version checks and global instruction-mode flips are
not part of this update. Project instruction migration is release B, not a
successful side effect of installing A.
'''
save('references/updating.md', text)
p = ROOT / 'references/operation-doctor.md'; text = p.read_text()
text += '''
### Release A instruction/export diagnostics

Use `instructions-audit.md` and `hooks/doctor.sh --project <repo> --json`.
The nested `instructions` report separates presence, wiki selection, exports
and untested runtime loading from hook verification. No Claude version floor,
plugin probe or full effective-loading model. Same-level pointer conflict blocks
unaddressed writes; cross-level mismatch is warning only. Private fixes are
release B. Doctor is read-only; explicit repairs require their own scope/consent.
'''
save('references/operation-doctor.md', text)

p = ROOT / 'SKILL.md'; text = p.read_text()
text = text.replace('version: "4.10.0"', 'version: "4.11.0"')
text = text.replace('| Generic action | Claude Code | Codex | Gemini CLI | Qwen Code |', '| Generic action | Claude Code | Codex | agy CLI | Qwen Code |')
text = text.replace('| Read files | Read | file/shell tools | read_file | read_file |', '| Read files | Read | file/shell tools | native file tools | read_file |')
text = text.replace('symlink exports for Codex, Gemini and Qwen.', 'symlink exports for Codex, agy CLI and Qwen; registry in `lib/harnesses.sh`.')
text = text.replace('- Use the canonical `hooks/lib/discover.sh` parser for local discovery.', '''- Shared instruction writes use `references/instructions-audit.md`: only
  AGENTS.md, no legacy sync or consolidation in release A. Unknown profiles
  do not block empty-scope Init; known existing fallback rules are preserved.
- Same-level different valid wiki pointers block unaddressed writes, including
  hook metadata. Nearest subproject scope is not a conflict with its ancestor.
- Use the canonical `hooks/lib/discover.sh` parser for local discovery.''')
text = text.replace('| Update the installed skill / repair hook registration | `references/updating.md` |',
                    '| Update the installed skill / repair hook registration | `references/updating.md`, `references/instructions-audit.md` |')
save('SKILL.md', text)
p = ROOT / '.codex-plugin/plugin.json'; data = json.loads(p.read_text()); data['version'] = '4.11.0'
save('.codex-plugin/plugin.json', json.dumps(data, ensure_ascii=False, indent=2) + '\n')
p = ROOT / 'README.md'; text = p.read_text().replace('Версія скіла: 4.10.0', 'Версія скіла: 4.11.0').replace('Gemini CLI', 'agy CLI')
start = text.index('```text\n~/claude-wiki-skill')
end = text.index('\n```', start) + 4
text = text[:start] + '''Реальний клон: `~/claude-wiki-skill`; решта шляхів — посилання.

<!-- harness-exports:start -->
<!-- harness-exports:end -->''' + text[end:]
text = text.replace('до 4.10+', 'до 4.11+')
text += '''
## AGENTS.md-only — реліз A (4.11)

Нові спільні правила створюються лише в `AGENTS.md`. У порожньому проєкті
невідомі Codex profiles не блокують init. Якщо вже є legacy/fallback instructions,
короткий AGENTS-stub не створюється; скіл повідомляє `consolidation required`.
Ingest і stale-pointer repair також не пишуть у старі instruction-файли.
Наявні custom pointers працюють; у legacy scope можна використовувати
`docs/wiki/` без нового pointer. Новий custom path, що вимагає instruction-змін,
чекає на консолідацію B. Наявні проєктні файли A не видаляє.

```bash
python3 "$HOME/.claude/skills/wiki/scripts/instructions.py" audit --project "$PWD" --json
bash "$HOME/.claude/skills/wiki/hooks/doctor.sh" --project "$PWD" --json
```

Аудит показує layout, вибрану вікі, старі blocker-файли Claude й exports окремо
від hook verification. **Версію Claude не перевіряємо.** Конфлікт різних валідних
вікі в одній директорії зупиняє неадресовані записи, навіть телеметрію hooks;
окремі вікі кореня й вкладеного компонента не блокують роботу.

**Gemini CLI більше не підтримується; з Google-харнесів — лише agy CLI.**
Новий installer спочатку перевіряє agy export, потім прибирає лише exact-owned
`~/.gemini/skills/wiki` / `doc-extract` links. За конфлікту заміни старий link
зберігається з попередженням. `.gemini` tree, settings, credentials і сторонні
skills не видаляються. Після запуску старої копії installer перевірте новим
`install.sh --repair-exports`. Старий pinned ref без registry явно повідомляє,
що exports не перевірені. Повний install зберігає історичну best-effort політику
export-кроку; repair повертає `2` за неповних exports, hook failure — `3`.

**Реліз B ще не реалізований:** змістовне об’єднання, оптимізація через наявний
lint, видалення legacy-файлів і автоматизовані private checkpoints не є частиною
A. Вони описані в епіку #6 та сабепіках #10–#14. Оновіть усі інсталяції перед
майбутньою спільною міграцією, щоб старі версії не відтворювали дублікати.

Приймання A: автоматичні тести плюс окремі live receipts Claude/Codex/Qwen/agy
і GitHub-адаптера. `not run` не означає pass; див. `docs/release-a-validation.md`.
'''
save('README.md', text)

# Replace obsolete four-file prose assertions, retaining unrelated regressions.
p = ROOT / 'tests/skill-contracts.sh'; text = p.read_text()
start = text.index("grep -q '~/.gemini/skills/doc-extract'")
end = text.index('# Release metadata', start)
text = text[:start] + '''# Release A replaces four-file sync assertions with canonical write guards.
for ref in operation-init.md operation-ingest-source.md operation-lint.md discovery-versioning.md; do
  grep -q 'instructions-audit.md' "$ROOT/references/$ref" || fail "$ref must route instruction writes through preflight"
done
grep -q '~/.gemini/antigravity-cli/skills/doc-extract' "$ROOT/references/operation-ingest-binary.md" || fail 'agy extractor export missing'
grep -q 'consolidation_required' "$ROOT/scripts/instructions.py" || fail 'legacy preflight missing'
grep -q 'No instruction writes' "$ROOT/references/instructions-audit.md" || fail 'legacy write guard missing'
grep -q 'same-level' "$ROOT/references/reader-core.md" || fail 'shared conflict contract missing'
grep -q 'Non-absent Init consent block' "$ROOT/references/operation-init.md" || fail 'non-absent consent gate missing'
grep -q 'Without explicit y, do not write instruction files' "$ROOT/references/operation-init.md" || fail 'consent boundary missing'
grep -q 'one canonical wiki per git root marker' "$ROOT/references/discovery-versioning.md" || fail 'monorepo contract missing'

''' + text[end:]
for version in ('4.5.0', '4.5.1', '4.6.0', '4.7.0'):
    old = f"grep -q '### {version}' \"$ROOT/references/discovery-versioning.md\""
    text = replace(text, old, f"grep -q '### {version}' \"$ROOT/docs/history/instruction-schema-release-log.md\"")
text = text.replace("grep -q 'CLAUDE.md`.*AGENTS.md`.*GEMINI.md`.*QWEN.md`'", "grep -q 'AGENTS.md`.*CLAUDE.md`.*GEMINI.md`.*QWEN.md`'")
save('tests/skill-contracts.sh', text)
p = ROOT / 'tests/install-cross-agent-links.sh'; text = p.read_text()
text = text.replace('.gemini/skills', '.gemini/antigravity-cli/skills').replace('GEMINI_', 'AGY_').replace('Gemini', 'agy')
old = '''rm "$AGENTS_WIKI"
ln -s "$HOME_DIR/missing-wiki-target" "$AGENTS_WIKI"
run_install
expect_link_target "$AGENTS_WIKI" "$CLAUDE_WIKI"
'''
new = '''rm "$AGENTS_WIKI"
ln -s "$HOME_DIR/missing-wiki-target" "$AGENTS_WIKI"
run_install
expect_link_target "$AGENTS_WIKI" "$HOME_DIR/missing-wiki-target"
# Unknown dangling exports are preserved; the test explicitly resolves it.
rm "$AGENTS_WIKI"
ln -s "$CLAUDE_WIKI" "$AGENTS_WIKI"
'''
text = replace(text, old, new)
start = text.index('PATH="$BIN_DIR:$PATH" HOME="$HOME_CANONICAL_BROKEN" bash')
end = text.index('\nHOME_REPAIR_EXPORTS=', start)
text = text[:start] + '''if PATH="$BIN_DIR:$PATH" HOME="$HOME_CANONICAL_BROKEN" bash "$ROOT/install.sh" >"$TMP/install-canonical-broken.log" 2>&1; then
  echo 'foreign dangling canonical must be preserved'; exit 1
fi
expect_link_target "$HOME_CANONICAL_BROKEN/.claude/skills/wiki" "$HOME_CANONICAL_BROKEN/missing-canonical-target"
''' + text[end:]
save('tests/install-cross-agent-links.sh', text)
p = ROOT / 'tests/scenarios/cross-agent-discovery.md'
save(str(p.relative_to(ROOT)), '> Release A: old four-file sync expectations below are historical. Current\n> instruction/discovery behavior is tested by `test_release_a.py` and normative\n> `references/discovery-cases.json`; unchanged no-Git/schema cases still apply.\n\n' + p.read_text())

subprocess.run(['python3', 'scripts/build_skill.py'], check=True)
subprocess.run(['python3', 'scripts/build_skill.py', '--check'], check=True)
subprocess.run(['git', 'rm', '-f', '--', '.github/prepare-release-a.py', '.github/workflows/prepare-release-a.yml'], check=True)
print('Release A patch applied; final tree contains only product/docs/tests.')
