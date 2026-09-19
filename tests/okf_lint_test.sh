# tests/okf_lint_test.sh — contract tests for the configurable-track lint.
# Run: bash tests/okf_lint_test.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINT="$ROOT/scripts/okf_lint.py"
fail=0
run() { python3 "$LINT" "$1" >"$2" 2>&1; echo $?; }

# Case A: default karpathy — a concepts/ page with type: concept is VALID.
A="$(mktemp -d)"; mkdir -p "$A/concepts"
printf -- '---\ntype: reference\nwiki_version: "6.0"\n---\n' > "$A/schema.md"
printf '# i\n' > "$A/index.md"; printf '# l\n' > "$A/log.md"
printf -- '---\ntype: concept\n---\n# C\n' > "$A/concepts/x.md"
out="$(mktemp)"; rc="$(run "$A" "$out")"
if [ "$rc" != "0" ]; then echo "FAIL A (karpathy concept rejected):"; cat "$out"; fail=1; fi

# Case B: default karpathy — a guide/ page is INVALID (no such track).
B="$(mktemp -d)"; mkdir -p "$B/guide"
printf -- '---\ntype: reference\n---\n' > "$B/schema.md"
printf '# i\n' > "$B/index.md"; printf '# l\n' > "$B/log.md"
printf -- '---\ntype: guide\n---\n# G\n' > "$B/guide/x.md"
out="$(mktemp)"; rc="$(run "$B" "$out")"
if [ "$rc" = "0" ]; then echo "FAIL B (guide accepted under karpathy default)"; fail=1; fi

# Case C: preset code-project — modules/ page WITHOUT module: is INVALID.
C="$(mktemp -d)"; mkdir -p "$C/modules"
printf -- '---\ntype: reference\npreset: code-project\n---\n' > "$C/schema.md"
printf '# i\n' > "$C/index.md"; printf '# l\n' > "$C/log.md"
printf -- '---\ntype: module\n---\n# M\n' > "$C/modules/x.md"
out="$(mktemp)"; rc="$(run "$C" "$out")"
if [ "$rc" = "0" ]; then echo "FAIL C (modules page without module: accepted)"; fail=1; fi

# Case D: preset code-project — modules/ page WITH module: is VALID.
D="$(mktemp -d)"; mkdir -p "$D/modules"
printf -- '---\ntype: reference\npreset: code-project\n---\n' > "$D/schema.md"
printf '# i\n' > "$D/index.md"; printf '# l\n' > "$D/log.md"
printf -- '---\ntype: module\nmodule: foo\n---\n# M\n' > "$D/modules/x.md"
out="$(mktemp)"; rc="$(run "$D" "$out")"
if [ "$rc" != "0" ]; then echo "FAIL D (valid module page rejected):"; cat "$out"; fail=1; fi

# Case E: preset + inline tracks together -> config error, exit code 2.
E="$(mktemp -d)"
printf -- '---\ntype: reference\npreset: code-project\ntracks:\n  - dir: a\n    type: alpha\n---\n' > "$E/schema.md"
printf '# i\n' > "$E/index.md"; printf '# l\n' > "$E/log.md"
out="$(mktemp)"; rc="$(run "$E" "$out")"
if [ "$rc" != "2" ]; then echo "FAIL E (preset+tracks not exit 2, got $rc):"; cat "$out"; fail=1; fi

# --- Regression: existing OKF rules still enforced (under karpathy default) ---
mk() { d="$(mktemp -d)"; mkdir -p "$d/concepts"; \
  printf -- '---\ntype: reference\n---\n' > "$d/schema.md"; \
  printf '# i\n' > "$d/index.md"; printf '# l\n' > "$d/log.md"; echo "$d"; }

# Case F: broken internal nav-link -> invalid.
F="$(mk)"; printf -- '---\ntype: concept\n---\n# C\n[x](/concepts/missing.md)\n' > "$F/concepts/x.md"
out="$(mktemp)"; rc="$(run "$F" "$out")"
if [ "$rc" = "0" ]; then echo "FAIL F (broken link accepted)"; fail=1; fi

# Case G: wikilink [[ ]] in body -> invalid.
G="$(mk)"; printf -- '---\ntype: concept\n---\n# C\nSee [[other]].\n' > "$G/concepts/x.md"
out="$(mktemp)"; rc="$(run "$G" "$out")"
if [ "$rc" = "0" ]; then echo "FAIL G (body wikilink accepted)"; fail=1; fi

# Case H: stray root markdown (not schema.md) -> invalid.
H="$(mk)"; printf -- '---\ntype: concept\n---\n# stray\n' > "$H/stray.md"
out="$(mktemp)"; rc="$(run "$H" "$out")"
if [ "$rc" = "0" ]; then echo "FAIL H (stray root markdown accepted)"; fail=1; fi

# Case I: page without 'type' -> invalid.
I="$(mk)"; printf -- '---\ntitle: no type\n---\n# C\n' > "$I/concepts/x.md"
out="$(mktemp)"; rc="$(run "$I" "$out")"
if [ "$rc" = "0" ]; then echo "FAIL I (missing type accepted)"; fail=1; fi

# Case J: INLINE tracks (docs/ -> type: doc) — declared track valid; a page in a
# track NOT in the inline set is invalid. Proves lint honors inline `tracks:`.
J="$(mktemp -d)"; mkdir -p "$J/docs" "$J/concepts"
printf -- '---\ntype: reference\ntracks:\n  - dir: docs\n    type: doc\n---\n' > "$J/schema.md"
printf '# i\n' > "$J/index.md"; printf '# l\n' > "$J/log.md"
printf -- '---\ntype: doc\n---\n# D\n' > "$J/docs/x.md"
out="$(mktemp)"; rc="$(run "$J" "$out")"
if [ "$rc" != "0" ]; then echo "FAIL J1 (inline doc track rejected):"; cat "$out"; fail=1; fi
printf -- '---\ntype: wrong\n---\n# D\n' > "$J/docs/y.md"
out="$(mktemp)"; rc="$(run "$J" "$out")"
if [ "$rc" = "0" ]; then echo "FAIL J2 (wrong type under inline track accepted)"; fail=1; fi
rm -f "$J/docs/y.md"
printf -- '---\ntype: concept\n---\n# C\n' > "$J/concepts/x.md"
out="$(mktemp)"; rc="$(run "$J" "$out")"
if [ "$rc" = "0" ]; then echo "FAIL J3 (page under undeclared track accepted)"; fail=1; fi

if [ "$fail" = "0" ]; then echo "okf_lint_test: PASS"; else echo "okf_lint_test: FAIL"; fi
exit "$fail"
