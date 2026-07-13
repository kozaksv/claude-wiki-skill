#!/usr/bin/env bash
# tests/run_all.sh — run every fork test suite (compat runner).
# Proves the generic core (default karpathy) + each subsystem all pass together.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
fail=0
run() {
  printf '%-18s ' "$1"
  if eval "$2" >"/tmp/_runall.$$" 2>&1; then echo "PASS"; else echo "FAIL"; cat "/tmp/_runall.$$"; fail=1; fi
}
run wiki_config    "python3 tests/wiki_config_test.py"
run okf_lint       "bash tests/okf_lint_test.sh"
run docs_neutral   "bash tests/docs_neutral_test.sh"
run wiki_engagement "python3 tests/wiki_engagement_test.py"
run wiki_autogen   "python3 tests/wiki_autogen_test.py"
run ship_wiki_gap  "bash tests/ship_wiki_gap_test.sh"
rm -f "/tmp/_runall.$$"
echo "------------------------------"
[ "$fail" = 0 ] && echo "ALL GREEN" || echo "SOME FAILED"
exit "$fail"
