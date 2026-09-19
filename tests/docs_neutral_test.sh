# tests/docs_neutral_test.sh — format docs stay framework-neutral + describe config.
# Run: bash tests/docs_neutral_test.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
# Format docs must NOT hardcode framework-specific identifiers as the canonical
# example (those belong in a project's own preset, see presets/README.md).
for f in SKILL.md references/wiki-structure.md references/discovery-versioning.md; do
  if grep -nE 'tut_core|src/custom|__manifest__' "$ROOT/$f" >/dev/null 2>&1; then
    echo "FAIL: framework-specific token in $f (move to a project preset)"; fail=1
  fi
done
# Docs must mention the configurable model + default — in SKILL.md AND references.
grep -q 'preset' "$ROOT/SKILL.md" || { echo "FAIL: SKILL.md does not mention preset/tracks config"; fail=1; }
grep -qi 'karpathy' "$ROOT/SKILL.md" || { echo "FAIL: SKILL.md does not state Karpathy default"; fail=1; }
for f in references/wiki-structure.md references/discovery-versioning.md; do
  grep -qiE 'preset|configurable track|karpathy' "$ROOT/$f" \
    || { echo "FAIL: $f not updated for configurable tracks"; fail=1; }
done
[ "$fail" = "0" ] && echo "docs_neutral_test: PASS"
exit "$fail"
