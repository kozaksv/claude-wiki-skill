# tests/ship_wiki_gap_test.sh — contract tests for the configurable ship-gate.
# Run: bash tests/ship_wiki_gap_test.sh
#
# Framework-neutral: signal/noise patterns come from a signals config (here a
# --signals fixture), path->page mapping comes from track path_map. No project
# regex is hardcoded in the .py. Proves detection, GAP/NEEDS-REVIEW bucketing,
# config-driven-ness, and fail-closed exit codes (0/1/2).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GAP="$ROOT/scripts/ship_wiki_gap.py"
fail=0

# Inline, NON-framework wiki: a "components" track owning paths under pkg/.
mk_wiki() {
  local w; w="$(mktemp -d)"
  printf -- '---\ntype: reference\ntracks:\n  - dir: components\n    type: comp\n    path_map: ["pkg/*"]\n---\n# Schema\n' > "$w/schema.md"
  printf '# Index\n' > "$w/index.md"
  printf '# Log\n' > "$w/log.md"
  echo "$w"
}
# Default wiki: no declaration -> karpathy preset -> signals: none.
mk_default_wiki() {
  local w; w="$(mktemp -d)"
  printf -- '---\ntype: reference\n---\n# Schema\n' > "$w/schema.md"
  printf '# Index\n' > "$w/index.md"; printf '# Log\n' > "$w/log.md"
  echo "$w"
}

# Generic signals fixture (no framework literals).
SIG="$(mktemp --suffix=.json)"
cat > "$SIG" <<'EOF'
{
  "signal_patterns": {"rule": "RULE_TOKEN", "route": "ROUTE_TOKEN"},
  "noise_patterns": ["VERSION_BUMP", "(^|/)tests?/"]
}
EOF

W="$(mk_wiki)"
runsig() { python3 "$GAP" --diff-file "$1" --wiki "$2" --signals "$SIG" >"$3" 2>&1; echo $?; }

# --- Case A: a "rule" signal under pkg/foo -> exit 1, bucketed GAP (no page). ---
DA="$(mktemp)"
cat > "$DA" <<'EOF'
diff --git a/pkg/foo/handler.py b/pkg/foo/handler.py
--- a/pkg/foo/handler.py
+++ b/pkg/foo/handler.py
@@ -1,2 +1,3 @@
+    x = RULE_TOKEN
EOF
out="$(mktemp)"; rc="$(runsig "$DA" "$W" "$out")"
if [ "$rc" != "1" ]; then echo "FAIL A (rule signal not exit 1, got $rc):"; cat "$out"; fail=1; fi
grep -q "^GAP | rule | foo " "$out" || { echo "FAIL A (no GAP/rule/foo line):"; cat "$out"; fail=1; }

# --- Case A2: a "route" signal -> exit 1. ---
DA2="$(mktemp)"
cat > "$DA2" <<'EOF'
diff --git a/pkg/bar/ctrl.py b/pkg/bar/ctrl.py
--- a/pkg/bar/ctrl.py
+++ b/pkg/bar/ctrl.py
@@ -1,2 +1,3 @@
+    route = ROUTE_TOKEN
EOF
out="$(mktemp)"; rc="$(runsig "$DA2" "$W" "$out")"
if [ "$rc" != "1" ]; then echo "FAIL A2 (route signal not exit 1, got $rc):"; cat "$out"; fail=1; fi
grep -q "^GAP | route | bar " "$out" || { echo "FAIL A2 (no GAP/route/bar line):"; cat "$out"; fail=1; }

# --- Case B: a no-signal change -> exit 0. ---
DB="$(mktemp)"
cat > "$DB" <<'EOF'
diff --git a/pkg/foo/x.py b/pkg/foo/x.py
--- a/pkg/foo/x.py
+++ b/pkg/foo/x.py
@@ -1,2 +1,3 @@
+    ordinary = "nothing to flag"
EOF
out="$(mktemp)"; rc="$(runsig "$DB" "$W" "$out")"
if [ "$rc" != "0" ]; then echo "FAIL B (clean change not exit 0, got $rc):"; cat "$out"; fail=1; fi

# --- Case B2: a path under tests/ (path-noise) even with a signal -> exit 0. ---
DB2="$(mktemp)"
cat > "$DB2" <<'EOF'
diff --git a/pkg/foo/tests/test_x.py b/pkg/foo/tests/test_x.py
--- a/pkg/foo/tests/test_x.py
+++ b/pkg/foo/tests/test_x.py
@@ -1,2 +1,3 @@
+    x = RULE_TOKEN
EOF
out="$(mktemp)"; rc="$(runsig "$DB2" "$W" "$out")"
if [ "$rc" != "0" ]; then echo "FAIL B2 (tests/ path not noise, got $rc):"; cat "$out"; fail=1; fi

# --- Covered: a components/foo.md page mentioning foo -> NEEDS-REVIEW. ---
mkdir -p "$W/components"
printf -- '---\ntype: comp\n---\n# foo\nThe foo component handles requests.\n' > "$W/components/foo.md"
out="$(mktemp)"; rc="$(runsig "$DA" "$W" "$out")"
if [ "$rc" != "1" ]; then echo "FAIL Covered (still a signal, exit 1) got $rc:"; cat "$out"; fail=1; fi
grep -q "^NEEDS-REVIEW | rule | foo " "$out" || { echo "FAIL Covered (not NEEDS-REVIEW):"; cat "$out"; fail=1; }
grep -q "components/foo.md" "$out" || { echo "FAIL Covered (candidate page not listed):"; cat "$out"; fail=1; }

# --- Config-driven proof: SAME signal diff under a default wiki (signals: none)
#     and NO --signals -> nothing detected -> exit 0 (patterns are NOT hardcoded).
WD="$(mk_default_wiki)"
out="$(mktemp)"; rc="$(python3 "$GAP" --diff-file "$DA" --wiki "$WD" >"$out" 2>&1; echo $?)"
if [ "$rc" != "0" ]; then echo "FAIL ConfigDriven (signal fired with no signals config, got $rc):"; cat "$out"; fail=1; fi

# --- D1: --signals missing file -> exit 2 (fail-closed). ---
out="$(mktemp)"; rc="$(python3 "$GAP" --diff-file "$DA" --wiki "$W" --signals "/no/such/file.json" >"$out" 2>&1; echo $?)"
if [ "$rc" != "2" ]; then echo "FAIL D1 (missing signals file not exit 2, got $rc):"; cat "$out"; fail=1; fi

# --- D2: --signals path that does not exist (unresolvable) -> exit 2. ---
out="$(mktemp)"; rc="$(python3 "$GAP" --diff-file "$DA" --wiki "$W" --signals "nope-not-a-file" >"$out" 2>&1; echo $?)"
if [ "$rc" != "2" ]; then echo "FAIL D2 (unresolvable signals not exit 2, got $rc):"; cat "$out"; fail=1; fi

# --- D3: unreadable diff file -> exit 2. ---
out="$(mktemp)"; rc="$(python3 "$GAP" --diff-file "/no/such/diff.patch" --wiki "$W" --signals "$SIG" >"$out" 2>&1; echo $?)"
if [ "$rc" != "2" ]; then echo "FAIL D3 (unreadable diff not exit 2, got $rc):"; cat "$out"; fail=1; fi

# --- D4: preset + inline tracks both declared -> config error -> exit 2. ---
WBOTH="$(mktemp -d)"
printf -- '---\ntype: reference\npreset: code-project\ntracks:\n  - dir: a\n    type: alpha\n---\n' > "$WBOTH/schema.md"
printf '# i\n' > "$WBOTH/index.md"; printf '# l\n' > "$WBOTH/log.md"
out="$(mktemp)"; rc="$(python3 "$GAP" --diff-file "$DB" --wiki "$WBOTH" >"$out" 2>&1; echo $?)"
if [ "$rc" != "2" ]; then echo "FAIL D4 (preset+tracks not exit 2, got $rc):"; cat "$out"; fail=1; fi

# --- D5: an unsafe signals entrypoint NAME is rejected by the SAFE-name guard. ---
rc="$(python3 -c "import sys; sys.path.insert(0,'$ROOT/scripts'); import ship_wiki_gap as g
try:
    g._resolve_signals_path('../../etc/passwd'); print('NO-RAISE')
except g.GateError:
    print('RAISED')" 2>&1)"
if [ "$rc" != "RAISED" ]; then echo "FAIL D5 (traversal signals name not rejected): $rc"; fail=1; fi

# --- F: no diff source flag -> usage error -> exit 2. ---
out="$(mktemp)"; rc="$(python3 "$GAP" --wiki "$W" --signals "$SIG" >"$out" 2>&1; echo $?)"
if [ "$rc" != "2" ]; then echo "FAIL F (missing diff source not exit 2, got $rc):"; cat "$out"; fail=1; fi

if [ "$fail" = "0" ]; then echo "ship_wiki_gap_test: PASS"; else echo "ship_wiki_gap_test: FAIL"; fi
exit "$fail"
