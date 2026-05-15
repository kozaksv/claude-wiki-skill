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

references=(
  references/discovery-versioning.md
  references/telemetry.md
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

grep -q 'set_skill_link' "$ROOT/references/self-improvement.md" ||
  fail "direct skill creation must point at installer safety helpers"

grep -q '### РЕФЛЕКСІЯ block format (strict template)' "$ROOT/references/self-improvement.md" ||
  fail "reflection strict template missing"

for field in 'Дізнався:' 'Чому це краще:' 'Зберіг у wiki:' 'Автоматизував:' 'Перевірив:'; do
  grep -q "$field" "$ROOT/references/self-improvement.md" ||
    fail "reflection template missing field: $field"
done

grep -q 'never emit a separate РЕФЛЕКСІЯ block' "$ROOT/references/operation-lint.md" ||
  fail "lint reference must preserve anti-recursion rule"

grep -q '~/.gemini/skills/doc-extract' "$ROOT/references/operation-ingest-binary.md" ||
  fail "doc-extract fallback must include Gemini direct export"

echo "skill contracts: ok"
