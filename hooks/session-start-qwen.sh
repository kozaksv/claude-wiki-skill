#!/usr/bin/env bash
# hooks/session-start-qwen.sh
#
# Qwen Code SessionStart transport wrapper. Qwen Code hooks speak a
# different envelope than Claude Code's raw-stdout SessionStart contract:
# Qwen expects a SINGLE line of JSON on stdout shaped like
#   {"continue":true,"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"…"}}
# This script never reimplements wiki discovery or injection — it only
# calls the neighboring canonical hooks/session-start.sh (resolved
# relative to this file, NEVER a hardcoded $HOME/… path, so the
# `/skills/wiki/hooks/` marker in the canonical hook's own path keeps
# granularity un/install behavior correct without any change here) and
# repackages whatever that hook printed on stdout.
#
# The canonical hook already enforces the 24 KB injected-content cap
# BEFORE this wrapper ever sees the text; this wrapper's own JSON
# encoding (json.dumps escaping \n, quotes, etc.) can grow the byte count
# of the final envelope past that cap — that is expected and not a bug
# here, the cap is a pre-escaping content budget, not a wire-size budget.
#
# stderr from the child hook is diagnostic-only and is deliberately NOT
# folded into stdout: Qwen Code parses stdout as JSON, so any child
# stderr noise reaching stdout would corrupt or contaminate the envelope.
#
# Every path below ends in `exit 0` — this wrapper must never block Qwen
# Code session startup, regardless of what the child hook or python3
# does.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# No python3 -> nothing we could produce would be well-formed JSON, so
# stay silent and exit 0. Checked before invoking the child hook is fine
# (and cheaper): a missing python3 is fatal to this wrapper regardless of
# what the child prints.
command -v python3 >/dev/null 2>&1 || exit 0

# Capture ONLY stdout from the canonical hook; let its stderr pass through
# to this wrapper's own stderr untouched (diagnostics stay diagnostics,
# never leak into the Qwen-parsed stdout channel).
out="$("$HOOK_DIR/session-start.sh")"

# Empty stdout (no wiki discoverable, or the canonical hook otherwise
# chose to say nothing) -> print nothing and exit 0. A wrapped-empty
# envelope would inject noisy but content-free "info" into every Qwen
# session on a project without a wiki.
[ -n "$out" ] || exit 0

packed="$(printf '%s' "$out" | python3 -c '
import json
import sys

text = sys.stdin.read()
envelope = {
    "continue": True,
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": text,
    },
}
sys.stdout.write(json.dumps(envelope))
' 2>/dev/null)"
rc=$?

# Nonzero python3 exit or an empty packing result -> stay silent, exit 0.
if [ "$rc" -ne 0 ] || [ -z "$packed" ]; then
  exit 0
fi

printf '%s\n' "$packed"
exit 0
