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

grep -q 'resume the originally requested operation' "$ROOT/references/discovery-versioning.md" ||
  fail "migration flow must resume the original operation"

grep -q 'Migration failure' "$ROOT/references/discovery-versioning.md" ||
  fail "migration flow must document partial-failure handling"

grep -q 'one canonical wiki per `.git` ancestor' "$ROOT/references/discovery-versioning.md" ||
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
