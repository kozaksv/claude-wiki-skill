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

# The orphan-wiki gate is purely informational. The skill never runs
# `git init` for an orphan wiki — it explains the situation and asks
# the user to handle it manually. Guards encode that invariant.

if ! tr '\n' ' ' <"$ROOT/references/discovery-versioning.md" | tr -s ' ' |
  grep -q 'never runs `git init` for an orphan-wiki state'; then
  fail "orphan-wiki gate must declare that the skill never runs git init for orphan wiki"
fi

if ! tr '\n' ' ' <"$ROOT/references/discovery-versioning.md" | tr -s ' ' |
  grep -q 'Я не запускаю `git init` для orphan-wiki сам'; then
  fail "orphan-wiki gate user-facing text must say the skill won't run git init itself"
fi

if ! tr '\n' ' ' <"$ROOT/references/discovery-versioning.md" | tr -s ' ' |
  grep -q 'Що зробити вручну'; then
  fail "orphan-wiki gate must list manual fix instructions (cd → git init → retry)"
fi

if ! tr '\n' ' ' <"$ROOT/references/discovery-versioning.md" | tr -s ' ' |
  grep -q 'After showing the gate, end the operation'; then
  fail "orphan-wiki gate must end the operation after showing the gate (no reply parsing, no loop)"
fi

# Anti-patterns: every prior heuristic / suggesting / auto-init design
# must not return.

if tr '\n' ' ' <"$ROOT/references/discovery-versioning.md" | tr -s ' ' |
  grep -q 'Best-guess algorithm'; then
  fail "best-guess algorithm is removed; the skill no longer proposes a project root"
fi

if tr '\n' ' ' <"$ROOT/references/discovery-versioning.md" | tr -s ' ' |
  grep -q 'Two-candidate gate'; then
  fail "two-candidate gate is removed; the skill no longer enumerates candidate roots"
fi

if tr '\n' ' ' <"$ROOT/references/discovery-versioning.md" | tr -s ' ' |
  grep -q 'walk up from the resolved wiki'; then
  fail "walk-up heuristic is removed and must not return"
fi

if grep -q 'absolute_best_guess_directory' "$ROOT/references/discovery-versioning.md"; then
  fail "best-guess placeholder is removed; the skill no longer suggests a candidate"
fi

if grep -q 'absolute_wiki_owning_directory' "$ROOT/references/discovery-versioning.md"; then
  fail "wiki-owning placeholder is removed; the skill never targets an auto-derived directory for git init"
fi

if tr '\n' ' ' <"$ROOT/references/discovery-versioning.md" | tr -s ' ' |
  grep -q 'If the resolved wiki path matches both strips at once'; then
  fail "ambiguity tie-breaker is removed and must not return"
fi

if grep -q 'owning directory = parent of the resolved wiki directory' "$ROOT/references/discovery-versioning.md"; then
  fail "stale 'parent of resolved wiki directory' rule must not return"
fi

if grep -q 'prefer the deeper candidate' "$ROOT/references/discovery-versioning.md"; then
  fail "stale 'prefer the deeper candidate' tie-breaker must not return"
fi

if tr '\n' ' ' <"$ROOT/references/discovery-versioning.md" | tr -s ' ' |
  grep -q 'each requires explicit \[y\] from the user'; then
  fail "stale '[y] required for both gates' invariant must not return — orphan gate accepts no reply at all"
fi

if tr '\n' ' ' <"$ROOT/references/discovery-versioning.md" | tr -s ' ' |
  grep -q 'Варіант 2 (я виконаю)'; then
  fail "orphan-wiki gate must not offer 'I will run git init for you' option — the skill never auto-inits orphan repair"
fi

if tr '\n' ' ' <"$ROOT/references/discovery-versioning.md" | tr -s ' ' |
  grep -q 'Must be an ancestor of the agent.s current working directory'; then
  fail "ancestor-of-cwd validation belonged to the absolute-path override design, which is removed"
fi

# Cross-references in operation-init must match the new model.

grep -q 'orphan-wiki repair gate' "$ROOT/references/operation-init.md" ||
  fail "operation-init must describe the orphan-wiki repair gate alongside the absent-state Init gate"

grep -q 'never runs `git init` for orphan-wiki' "$ROOT/references/operation-init.md" ||
  fail "operation-init must reaffirm that the orphan-wiki gate never auto-inits git"

if grep -q 'project-root path the user explicitly provided' "$ROOT/references/operation-init.md"; then
  fail "operation-init must no longer reference the absolute-path override (removed)"
fi

if grep -q 'both requiring explicit `\[y\]`' "$ROOT/references/operation-init.md"; then
  fail "operation-init must no longer claim 'both gates require [y]' — orphan gate has no consent reply at all"
fi

if grep -q 'Init is the only operation that may run `git init`' "$ROOT/references/operation-init.md"; then
  fail "operation-init must no longer claim Init is the only git-init gate"
fi

grep -q 'orphan-wiki repair gate' "$ROOT/references/operation-lint.md" ||
  fail "operation-lint must reference the orphan-wiki repair gate when explaining the missing-git case"

if grep -q 'will offer `git init`' "$ROOT/references/operation-lint.md"; then
  fail "operation-lint must not say the orphan-wiki gate will offer git init — under 4.2.20 the gate is informational only"
fi

grep -q 'Lint never\|never runs `git init`' "$ROOT/references/operation-lint.md" ||
  fail "operation-lint must affirm it never runs git init itself for orphan-wiki"

grep -q 'fewer than 20 active' "$ROOT/references/operation-lint.md" ||
  fail "operation-lint must skip the full-lint heads-up for small wikis (< 20 active pages)"

if grep -q 'Heads-up before starting full lint — always' "$ROOT/references/operation-lint.md"; then
  fail "operation-lint must no longer claim the full-lint heads-up runs unconditionally"
fi

grep -q 'Scenario 3e: Orphan wiki — skill explains and refuses' "$ROOT/tests/scenarios/cross-agent-discovery.md" ||
  fail "scenarios must cover orphan-wiki repair where the skill explains and refuses (no auto git init)"

grep -q 'Scenario 3f: Non-canonical wiki resolved via `## Wiki` pointer is not treated as absent' "$ROOT/tests/scenarios/cross-agent-discovery.md" ||
  fail "scenarios must cover non-canonical wiki resolved via pointer (Init must not classify it as absent and bootstrap a second wiki)"

if grep -q '| `absent` | No `docs/wiki/` exists |' "$ROOT/references/operation-init.md"; then
  fail "absent state must be defined by 'no wiki resolved at all', not by missing canonical docs/wiki/ — a pointer-resolved non-canonical wiki is not absent"
fi

if ! tr '\n' ' ' <"$ROOT/references/operation-init.md" | tr -s ' ' |
  grep -q 'Step 0 found no wiki at all'; then
  fail "operation-init absent-state condition must require both no docs/wiki/ AND no resolving pointer"
fi

for stale_scenario in '^## Scenario 3i:'; do
  if grep -q "$stale_scenario" "$ROOT/tests/scenarios/cross-agent-discovery.md"; then
    fail "stale orphan-wiki scenario must be removed: $stale_scenario"
  fi
done

grep -q 'Scenario 3h: Partial wiki without git (orphan + partial combined)' "$ROOT/tests/scenarios/cross-agent-discovery.md" ||
  fail "scenarios must cover no-git partial wiki (orphan + partial combined — must not bootstrap a second wiki via absent-state gate)"

if ! tr '\n' ' ' <"$ROOT/references/discovery-versioning.md" | tr -s ' ' |
  grep -q 'no-git artifact scan includes partial signals\|Wiki artifacts include both fully-formed and partial wikis'; then
  fail "no-git orphan-wiki detection must include partial signals (schema.md, log.md, etc.), not just index.md"
fi

if grep -q '`git show <hash>:{wiki_path}/index.md`' "$ROOT/references/discovery-versioning.md"; then
  fail "git show command must use repo-relative wiki path, not absolute — split into git_root + relative components"
fi

if ! tr '\n' ' ' <"$ROOT/references/discovery-versioning.md" | tr -s ' ' |
  grep -q 'wiki_path_relative_to_git_root'; then
  fail "partial-wiki recovery example must use repo-relative path placeholder for git show"
fi

grep -q 'Scenario 3g: Partial wiki' "$ROOT/tests/scenarios/cross-agent-discovery.md" ||
  fail "scenarios must cover partial wiki state (wiki-owned files exist but index.md missing — must not overwrite via absent bootstrap)"

if ! tr '\n' ' ' <"$ROOT/references/discovery-versioning.md" | tr -s ' ' |
  grep -q 'partial wiki state'; then
  fail "discovery reference must define partial-wiki detection to prevent absent bootstrap from overwriting existing wiki files"
fi

if ! tr '\n' ' ' <"$ROOT/references/discovery-versioning.md" | tr -s ' ' |
  grep -q 'wiki-owned files that count as evidence'; then
  fail "discovery reference must list the wiki-owned files that trigger partial-wiki detection (schema.md, log.md, .usage.json, etc.)"
fi

if ! tr '\n' ' ' <"$ROOT/references/discovery-versioning.md" | tr -s ' ' |
  grep -q 'docs/wiki/. relative to the git root'; then
  fail "partial-wiki candidate set must include docs/wiki/ relative to the git root so partial wikis at project root are caught from nested cwd"
fi

if ! tr '\n' ' ' <"$ROOT/references/discovery-versioning.md" | tr -s ' ' |
  grep -q 'then relative to the git root'; then
  fail "Step 5 fallback for docs/wiki/index.md must include git-root-relative search so valid root wikis are found from nested cwd without instruction files"
fi

if ! tr '\n' ' ' <"$ROOT/references/discovery-versioning.md" | tr -s ' ' |
  grep -q 'a `## Wiki` section exists but its pointer is stale/broken'; then
  fail "Step 5 fallback must also fire when an instruction file has a stale/broken `## Wiki` pointer — otherwise a stale pointer can hide a valid canonical wiki"
fi

if ! tr '\n' ' ' <"$ROOT/references/operation-init.md" | tr -s ' ' |
  grep -q 'Consequence for non-canonical layouts without a pointer'; then
  fail "operation-init must document the non-canonical-without-pointer limitation explicitly (intentional trade-off, not silent split-brain)"
fi

if ! grep -q 'no wiki-owned files' "$ROOT/references/operation-init.md"; then
  fail "operation-init absent-state condition must require no wiki-owned files (not just missing index.md)"
fi

if ! tr '\n' ' ' <"$ROOT/references/operation-init.md" | tr -s ' ' |
  grep -q 'Wiki location is part of the contract, not a heuristic'; then
  fail "operation-init must declare that wiki location is contract-bound to docs/wiki/ or a `## Wiki` pointer"
fi

if tr '\n' ' ' <"$ROOT/references/operation-init.md" | tr -s ' ' |
  grep -q 'Pre-bootstrap stray-wiki scan'; then
  fail "pre-bootstrap stray-wiki scan is removed (over-broad, halts on ordinary docs/index.md); wiki location is contract-bound instead"
fi

if tr '\n' ' ' <"$ROOT/references/operation-init.md" | tr -s ' ' |
  grep -q 'scan the new git root for any `index.md`'; then
  fail "stray index.md scan must not return — non-canonical layouts are not wikis by contract"
fi

if grep -q 'Project root candidates: \[1\]' "$ROOT/references/discovery-versioning.md"; then
  fail "ambiguous root [1]/[2] menu in gate must not return — gate is suggested guess + user override"
fi

if tr '\n' ' ' <"$ROOT/references/discovery-versioning.md" | tr -s ' ' |
  grep -q 'no in-gate path override'; then
  fail "the 'no in-gate path override' invariant was deliberately dropped — the gate now accepts an absolute-path override"
fi

if grep -q 'parent of\s*$' "$ROOT/tests/scenarios/cross-agent-discovery.md" ||
   grep -q 'parent of `/work/money/docs/wiki/` is `/work/money/`' "$ROOT/tests/scenarios/cross-agent-discovery.md"; then
  fail "scenario rationale must not reuse the obsolete 'parent of <docs/wiki/>' wording — that resolves to docs/, not the project root"
fi

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

grep -q 'set_skill_link' "$ROOT/references/crystallization.md" &&
  fail "crystallization must not reference installer skill helpers (skill tier removed in 4.4)"

grep -rq '🧹' "$ROOT/references/" &&
  fail "cleanup-prompt emoji must not appear in references/ (removed in 4.4)"

grep -rq 'writing-skills' "$ROOT/references/" &&
  fail "skill-delegation must not appear in references/ (skill tier removed in 4.4)"

grep -q 'Two entry points' "$ROOT/references/cleanup-flow.md" &&
  fail "cleanup-flow must have a single entry point (wiki status)"

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

grep -q 'replacing the `## Wiki` section with the full Session-Start' "$ROOT/references/discovery-versioning.md" ||
  fail "instruction-file sync must repair a stale pointer by rewriting the ## Wiki section with the Session-Start Contract block"

grep -q 'never silently discard' "$ROOT/references/discovery-versioning.md" ||
  fail "stale-pointer repair must surface pre-existing custom ## Wiki content as a DECIDE finding before overwriting"

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

grep -q 'any pointer line that resolves to a valid on-disk wiki' "$ROOT/references/discovery-versioning.md" ||
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

grep -q 'version: "4.5.0"' "$ROOT/SKILL.md" ||
  fail "SKILL.md frontmatter must be bumped to 4.5.0"

[ -f "$ROOT/references/operation-doctor.md" ] ||
  fail "references/operation-doctor.md must exist (wiki doctor operation)"

grep -q 'operation-doctor.md' "$ROOT/SKILL.md" ||
  fail "SKILL.md must route to references/operation-doctor.md"

grep -q 'wiki-hooks-optout' "$ROOT/references/discovery-versioning.md" ||
  fail "discovery-versioning.md must define the wiki-hooks-optout marker"

grep -q '### 4.5.0' "$ROOT/references/discovery-versioning.md" ||
  fail "discovery-versioning.md Migration Log must have a ### 4.5.0 entry"

skill_version="$(sed -n 's/^version: "\([0-9][0-9]*\)\..*/\1/p' "$ROOT/SKILL.md" | head -1)"
init_schema_major="$(grep -E 'wiki_version: "[0-9]+\.' "$ROOT/references/operation-init.md" | sed -n 's/.*wiki_version: "\([0-9][0-9]*\)\..*/\1/p' | head -1)"
[ -n "$skill_version" ] || fail "could not parse SKILL.md major version"
[ -n "$init_schema_major" ] || fail "could not parse operation-init schema major"
[ "$skill_version" = "$init_schema_major" ] ||
  fail "operation-init wiki_version major ($init_schema_major) must match SKILL.md major ($skill_version)"

grep -q '_hooks' "$ROOT/references/telemetry.md" ||
  fail "telemetry.md must define the reserved _hooks metadata key"

grep -q 'post_tool_use_at' "$ROOT/references/telemetry.md" ||
  fail "telemetry.md must define the _hooks.post_tool_use_at field and dual-signal rule"

grep -q 'last_lint_at' "$ROOT/references/operation-lint.md" ||
  fail "operation-lint.md must write _hooks.last_lint_at at the end of a lint run"

grep -q 'last_lint_at' "$ROOT/references/operation-init.md" ||
  fail "operation-init.md bootstrap must seed _hooks.last_lint_at"

# Task 8: hook-file contract guards (v45-hooks) — the hook scripts, installer
# and version gate must exist, be wired together, and be executable before
# the executable hooks test suite (below) is trusted to have run at all.

grep -q 'WIKI INDEX (hook-injected)' "$ROOT/hooks/session-start.sh" ||
  fail "hooks/session-start.sh must inject the WIKI INDEX (hook-injected) block"

grep -q 'НЕ інструкції' "$ROOT/hooks/session-start.sh" ||
  fail "hooks/session-start.sh must label injected wiki content as untrusted data (НЕ інструкції)"

grep -q '.claude/skills/wiki/hooks/' "$ROOT/hooks/install-hooks.sh" ||
  fail "hooks/install-hooks.sh must register hooks under the canonical ~/.claude/skills/wiki/hooks/ path"

grep -q 'settings.json.lock' "$ROOT/hooks/install-hooks.sh" ||
  fail "hooks/install-hooks.sh must serialize settings.json writes via a settings.json.lock"

[ -f "$ROOT/hooks/lib/version-gate.sh" ] ||
  fail "hooks/lib/version-gate.sh must exist"

grep -q 'version-gate.sh\|wiki_writable' "$ROOT/hooks/session-start.sh" ||
  fail "hooks/session-start.sh must invoke the version gate before writing telemetry"

grep -q 'version-gate.sh\|wiki_writable' "$ROOT/hooks/post-tool-use.sh" ||
  fail "hooks/post-tool-use.sh must invoke the version gate before writing telemetry"

grep -q 'install-hooks.sh' "$ROOT/install.sh" ||
  fail "install.sh must call hooks/install-hooks.sh"

grep -q 'uninstall-hooks.sh' "$ROOT/uninstall.sh" ||
  fail "uninstall.sh must call hooks/uninstall-hooks.sh"

[ -x "$ROOT/hooks/session-start.sh" ] || fail "hooks/session-start.sh must be executable"
[ -x "$ROOT/hooks/post-tool-use.sh" ] || fail "hooks/post-tool-use.sh must be executable"
[ -x "$ROOT/hooks/install-hooks.sh" ] || fail "hooks/install-hooks.sh must be executable"
[ -x "$ROOT/hooks/uninstall-hooks.sh" ] || fail "hooks/uninstall-hooks.sh must be executable"

# Wire the executable hooks test suite into the project gate — it must run
# as the last step so all of the above static guards fail fast first.
bash "$ROOT/tests/hooks/run.sh" || fail "hooks executable tests failed"

echo "skill contracts: ok"
