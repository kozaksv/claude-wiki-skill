#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "$1" >&2
  exit 1
}

skill_lines="$(wc -l <"$ROOT/SKILL.md" | tr -d ' ')"
if [ "$skill_lines" -gt 450 ]; then
  fail "SKILL.md should be a thin entrypoint (<=450 lines), got $skill_lines"
fi

description_lines="$(sed -n '/^description: >/,+40p' "$ROOT/SKILL.md" | sed -n '1,/^---$/p' | wc -l | tr -d ' ')"
if [ "$description_lines" -gt 14 ]; then
  fail "SKILL.md frontmatter description should stay compact (<=14 lines including delimiters), got $description_lines"
fi

grep -q '^|---|---|---|---|$' "$ROOT/SKILL.md" ||
  fail "Platform Compatibility table separator must have 4 columns"

references=(
  references/discovery-versioning.md
  references/telemetry.md
  references/reflection.md
  references/crystallization.md
  references/cleanup-flow.md
  references/self-improvement.md
  references/wiki-structure.md
  references/operation-ingest-source.md
  references/operation-ingest-binary.md
  references/operation-query.md
  references/operation-wiki-status.md
  references/operation-lint.md
  references/operation-split.md
  references/operation-init.md
  references/operation-cleanup.md
  references/maintenance-and-mistakes.md
)

for ref in "${references[@]}"; do
  [ -s "$ROOT/$ref" ] || fail "missing reference: $ref"
  grep -q "$ref" "$ROOT/SKILL.md" || fail "SKILL.md does not route to $ref"
done

if grep -q '^## Operation:' "$ROOT/SKILL.md"; then
  fail "operation bodies should live in references/, not SKILL.md"
fi

operation_headers=(
  "Operation: Ingest-Source"
  "Operation: Ingest-Binary"
  "Operation: Query"
  "Operation: Wiki Status"
  "Operation: Lint"
  "Operation: Split"
  "Operation: Init (bootstrap-aware)"
  "Operation: Cleanup"
)

for header in "${operation_headers[@]}"; do
  grep -R -q "^## $header" "$ROOT/references" || fail "missing operation header in references: $header"
done

grep -q 'nearest ancestor containing `.git/`' "$ROOT/references/discovery-versioning.md" ||
  fail "discovery reference must define the walk-up boundary"

grep -q '`.git` file' "$ROOT/references/discovery-versioning.md" ||
  fail "discovery reference must define worktree/submodule .git file behavior"

grep -q 'Git is the foundation of the wiki' "$ROOT/references/discovery-versioning.md" ||
  fail "discovery reference must state that git is required for wiki operation"

grep -q 'absolute_current_working_directory' "$ROOT/references/discovery-versioning.md" ||
  fail "git-init gate must show the absolute cwd before asking for consent"

grep -q 'run `git init` in that' "$ROOT/references/discovery-versioning.md" ||
  fail "discovery reference must require confirmed git init in the displayed directory"

if grep -q 'Wiki requires git' "$ROOT/references/discovery-versioning.md"; then
  fail "git-init gate should be user-facing Ukrainian, not mixed English/Ukrainian"
fi

if grep -q 'continue to filesystem root' "$ROOT/SKILL.md" "$ROOT/references/discovery-versioning.md" "$ROOT/references/operation-init.md"; then
  fail "wiki discovery must not continue without a git root"
fi

grep -q '1\. Git repository' "$ROOT/references/operation-init.md" ||
  fail "bootstrap plan must list git verification as step 1"

grep -q 'Bootstrap plan template (step 12)' "$ROOT/references/operation-init.md" ||
  fail "operation-init must cross-reference bootstrap step 12 for skill exports"

grep -q 'step 6: `entities/`' "$ROOT/references/operation-init.md" ||
  fail "operation-init must cross-reference bootstrap step 6 for entities"

bootstrap_plan_numbers="$(awk '
  /^### Bootstrap plan template/ { in_section=1 }
  in_section && /^```$/ { fence++; next }
  in_section && fence == 1 && /^  [0-9]+\. / {
    line=$0
    sub(/^  /, "", line)
    sub(/\..*/, "", line)
    printf "%s ", line
  }
  in_section && fence == 2 { exit }
' "$ROOT/references/operation-init.md")"
[ "$bootstrap_plan_numbers" = "1 2 3 4 5 6 7 8 9 10 11 12 " ] ||
  fail "bootstrap plan must contain numbered steps 1..12, got: $bootstrap_plan_numbers"

bootstrap_plan_substeps="$(awk '
  /^### Bootstrap plan template/ { in_section=1 }
  in_section && /^```$/ { fence++; next }
  in_section && fence == 1 && /^  [0-9]+[a-z]\. / { print }
  in_section && fence == 2 { exit }
' "$ROOT/references/operation-init.md")"
[ -z "$bootstrap_plan_substeps" ] ||
  fail "bootstrap plan must not contain lettered sub-steps: $bootstrap_plan_substeps"

grep -q 'Scenario 3d: Fresh non-git project' "$ROOT/tests/scenarios/cross-agent-discovery.md" ||
  fail "scenarios must cover fresh non-git project flow"

grep -q 'Scenario 2e: Git worktree or submodule .git file' "$ROOT/tests/scenarios/cross-agent-discovery.md" ||
  fail "scenarios must cover .git file worktree/submodule flow"

grep -q 'Scenario 2f: Worktree/submodule with no wiki yet' "$ROOT/tests/scenarios/cross-agent-discovery.md" ||
  fail "scenarios must cover .git file worktree/submodule absent-state init flow"

grep -q 'git worktree repair' "$ROOT/references/discovery-versioning.md" ||
  fail "discovery reference must address stale .git file (worktree removed) recovery"

grep -q 'Orphan wiki detected' "$ROOT/references/discovery-versioning.md" ||
  fail "discovery reference must distinguish orphan-wiki state from truly absent projects"

grep -q 'absolute_wiki_artifact_directory' "$ROOT/references/discovery-versioning.md" ||
  fail "orphan-wiki gate must show the directory where wiki artifacts were found"

grep -q 'orphan-wiki repair gate' "$ROOT/references/operation-init.md" ||
  fail "operation-init must describe the orphan-wiki repair gate alongside the absent-state Init gate"

if grep -q 'Init is the only operation that may run `git init`' "$ROOT/references/operation-init.md"; then
  fail "operation-init must no longer claim Init is the only git-init gate after orphan-wiki repair gate was added"
fi

grep -q 'orphan-wiki repair gate' "$ROOT/references/operation-lint.md" ||
  fail "operation-lint must reference the orphan-wiki repair gate when explaining the missing-git case"

grep -q 'Scenario 3e: Orphan wiki' "$ROOT/tests/scenarios/cross-agent-discovery.md" ||
  fail "scenarios must cover orphan-wiki (wiki exists, no git) repair flow"

grep -q 'Running wiki in a non-git directory' "$ROOT/references/maintenance-and-mistakes.md" ||
  fail "maintenance-and-mistakes must list the non-git anti-pattern"

grep -q 'Do not suggest `git reset --hard HEAD`' "$ROOT/references/discovery-versioning.md" ||
  fail "unborn HEAD recovery must not recommend git reset --hard HEAD"

if grep -q 'demote obvious AUTO' "$ROOT/references/operation-lint.md"; then
  fail "lint non-git gate should not mention impossible AUTO demotion paths"
fi

grep -q 'resume the originally requested operation' "$ROOT/references/discovery-versioning.md" ||
  fail "migration flow must resume the original operation"

grep -q 'Migration failure' "$ROOT/references/discovery-versioning.md" ||
  fail "migration flow must document partial-failure handling"

grep -q 'one canonical wiki per git root marker' "$ROOT/references/discovery-versioning.md" ||
  fail "discovery reference must define monorepo multi-wiki scope"

self_improvement_lines="$(wc -l <"$ROOT/references/self-improvement.md" | tr -d ' ')"
if [ "$self_improvement_lines" -gt 90 ]; then
  fail "self-improvement routing reference should stay compact (<=90 lines), got $self_improvement_lines"
fi

grep -q 'set_skill_link' "$ROOT/references/crystallization.md" ||
  fail "direct skill creation must point at installer safety helpers"

grep -q '### РЕФЛЕКСІЯ block format (strict template)' "$ROOT/references/reflection.md" ||
  fail "reflection strict template missing"

for field in 'Дізнався:' 'Чому це краще:' 'Зберіг у wiki:' 'Автоматизував:' 'Перевірив:'; do
  grep -q "$field" "$ROOT/references/reflection.md" ||
    fail "reflection template missing field: $field"
done

grep -q 'never emit a separate РЕФЛЕКСІЯ block' "$ROOT/references/operation-lint.md" ||
  fail "lint reference must preserve anti-recursion rule"

grep -q '~/.gemini/skills/doc-extract' "$ROOT/references/operation-ingest-binary.md" ||
  fail "doc-extract fallback must include Gemini direct export"

grep -q 'Cross-agent skill availability' "$ROOT/references/operation-init.md" ||
  fail "init reference must include cross-agent skill availability self-heal"

grep -q '~/.agents/skills/wiki' "$ROOT/references/operation-init.md" ||
  fail "init reference must ensure Codex can discover the wiki skill"

grep -q 'install.sh' "$ROOT/references/operation-init.md" ||
  fail "init reference must point agents at the installer for skill exports"

grep -q -- '--repair-exports' "$ROOT/references/operation-init.md" ||
  fail "init reference must use repair-only installer mode for skill exports"

grep -q 'Cross-agent instruction-file sync' "$ROOT/references/discovery-versioning.md" ||
  fail "discovery reference must define cross-agent instruction-file sync"

grep -q 'Cross-agent instruction-file sync' "$ROOT/references/operation-init.md" ||
  fail "init reference must include cross-agent instruction-file sync"

grep -q '{schema_path_relative_to_instruction_file}' "$ROOT/references/discovery-versioning.md" ||
  fail "instruction-file sync must compute schema pointer relative to each instruction file"

grep -q 'replace only the pointer line' "$ROOT/references/discovery-versioning.md" ||
  fail "instruction-file sync must preserve custom Wiki section content when repairing stale pointers"

grep -q 'Do not run this sync during status, lint, or query' "$ROOT/references/discovery-versioning.md" ||
  fail "status/lint/query must remain read-only unless the user explicitly asks for pointer repair"

grep -q 'Cross-agent skill exports' "$ROOT/references/operation-init.md" ||
  fail "init bootstrap plan must disclose cross-agent skill export repair"

grep -q 'Non-absent Init consent block' "$ROOT/references/operation-init.md" ||
  fail "init reference must consent-gate repairs for current/legacy/older/newer states"

grep -q 'Проєктні instruction-файли потребують ремонту' "$ROOT/references/operation-init.md" ||
  fail "non-absent init consent block must include project-local pointer repairs"

grep -q 'Глобальні skill exports потребують ремонту' "$ROOT/references/operation-init.md" ||
  fail "non-absent init consent block must include global export repairs in the user-facing language"

if grep -q 'Project-local instruction files: OK' "$ROOT/references/operation-init.md"; then
  fail "non-absent init no-op labels must not mix English project-local status text into the UA flow"
fi

if ! awk '/write only after explicit approval\./ { getline; exit ($0 == "" ? 0 : 1) }' \
  "$ROOT/references/discovery-versioning.md"; then
  fail "discovery sync consent gate and read-only invariant should be separate paragraphs"
fi

if ! tr '\n' ' ' <"$ROOT/references/operation-init.md" |
  grep -q 'Without explicit y, do not write instruction files'; then
  fail "non-absent init must not write pointer files without consent"
fi

if ! tr '\n' ' ' <"$ROOT/references/discovery-versioning.md" |
  grep -q 'For non-absent Init states'; then
  fail "instruction-file sync reference must point non-absent init writes at the consent block"
fi

grep -q 'listing only the project-local repair' "$ROOT/tests/scenarios/cross-agent-discovery.md" ||
  fail "Scenario 3c2 must document consent-gated project-local pointer repair"

grep -q 'listing only the global export repair' "$ROOT/tests/scenarios/cross-agent-discovery.md" ||
  fail "cross-agent scenarios must cover exports-only non-absent init repair"

# These exact README phrasing guards intentionally protect documentation-side
# consent invariants. Wordsmithing is fine, but update the docs and guards
# together so review can see the contract changed intentionally.
grep -q 'Без \[y\] жодних файлів не пишеться' "$ROOT/README.md" ||
  fail "README recovery docs must say non-absent init repairs require explicit consent"

grep -q 'Combined migration plan with export repair' "$ROOT/references/operation-init.md" ||
  fail "legacy/older init must show how export repair is integrated into migration plans"

grep -q 'Зроблю всі N кроків одразу' "$ROOT/references/operation-init.md" ||
  fail "combined migration plan must use computed N, not a literal step count"

if ! tr '\n' ' ' <"$ROOT/references/operation-init.md" |
  grep -q 'Either, both, or neither repair step may be needed'; then
  fail "combined migration plan must clarify single-repair and no-repair cases"
fi

if grep -q 'Зроблю всі 3 кроки одразу' "$ROOT/references/operation-init.md"; then
  fail "combined migration plan must not hard-code a literal step count"
fi

grep -q 'outcome checklist, not an execution-order trace' "$ROOT/references/operation-init.md" ||
  fail "init plan must clarify plan-vs-execute ordering"

grep -q 'Use Execute checklist numbering' "$ROOT/references/discovery-versioning.md" ||
  fail "partial-failure reporting must clarify which step numbering to use"

grep -q 'valid existing pointer resolves to the resolved wiki' "$ROOT/references/discovery-versioning.md" ||
  fail "instruction-file sync must define behavior for valid but non-canonical pointer text"

if grep -q 'create missing minimal instruction files with "Wiki schema → {schema_path_relative_to_instruction_file}"' "$ROOT/references/operation-init.md"; then
  fail "init user-facing plan must not leak raw schema_path_relative_to_instruction_file placeholder"
fi

grep -q 'AGENTS.md' "$ROOT/references/operation-init.md" ||
  fail "init reference must ensure Codex project pointer files are covered"

grep -q 'GEMINI.md' "$ROOT/references/operation-init.md" ||
  fail "init reference must ensure Gemini project pointer files are covered"

grep -q 'create missing minimal instruction files' "$ROOT/references/discovery-versioning.md" ||
  fail "discovery reference must allow safe creation of missing agent pointer files"

grep -q 'empty project' "$ROOT/references/operation-init.md" ||
  fail "init reference must define empty-project bootstrap behavior"

grep -q 'do not ask the user for more project information' "$ROOT/references/operation-init.md" ||
  fail "empty-project init must not ask for extra project information"

grep -q 'entities/.*empty directory' "$ROOT/references/operation-init.md" ||
  fail "empty-project init must keep entities/ empty"

if grep -q 'no code signals.*people/' "$ROOT/references/operation-init.md"; then
  fail "no-code project detection must not invent people/documents categories"
fi

skill_version="$(sed -n 's/^version: "\([0-9][0-9]*\)\..*/\1/p' "$ROOT/SKILL.md" | head -1)"
init_schema_major="$(grep -E 'wiki_version: "[0-9]+\.' "$ROOT/references/operation-init.md" | sed -n 's/.*wiki_version: "\([0-9][0-9]*\)\..*/\1/p' | head -1)"
[ -n "$skill_version" ] || fail "could not parse SKILL.md major version"
[ -n "$init_schema_major" ] || fail "could not parse operation-init schema major"
[ "$skill_version" = "$init_schema_major" ] ||
  fail "operation-init wiki_version major ($init_schema_major) must match SKILL.md major ($skill_version)"

echo "skill contracts: ok"
