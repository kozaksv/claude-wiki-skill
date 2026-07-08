#!/usr/bin/env bash
# hooks/post-tool-use.sh
#
# Claude Code PostToolUse hook. install-hooks.sh registers this under the
# PostToolUse event with tool-matcher `Read|Edit|Write|MultiEdit`
# (docs/superpowers/plans/2026-07-08-v45-hooks.md Task 3). Reads the
# hook's stdin JSON (`tool_name`, `tool_input.file_path` per the official
# Claude Code hooks stdin schema), and — for a file inside the discovered
# project wiki — bumps the corresponding `.usage.json` telemetry record
# (`bump_view` for Read, `bump_patch` for Edit/Write/MultiEdit).
#
# Pure bash for stdin-shape branching, discovery and the boundary/version
# guards; python3 is used ONLY for the JSON read-modify-write of
# `.usage.json` (the plan's "Спільні інваріанти" JSON r-m-w carve-out) —
# missing python3, unparseable stdin, or a write failure are all silently
# swallowed. This hook NEVER writes anything else and NEVER blocks tool
# execution: every path ends in `exit 0`.
#
# file_path resolution: `tool_input.file_path` is resolved against the
# ABSOLUTE `$CLAUDE_PROJECT_DIR` (falling back to `pwd` only when that var
# is unset), never against the hook process's own cwd — Claude Code hands
# hooks a project-root-relative file_path while the hook's cwd can be any
# subdirectory, so resolving against cwd would silently break the guard
# below and drop telemetry with no signal (plan Task 3 point 3).
#
# Boundary guard: resolved realpath(file_path) must land strictly inside
# realpath({wiki})/ — mirrors hooks/lib/discover.sh's own boundary-guard
# posture so a wiki-external Read/Edit/Write can never mutate the
# sidecar (spec risk 12 / plan "Спільні інваріанти" boundary-guard).
#
# Version gate: no `.usage.json` write happens unless `wiki_writable` or
# `wiki_bootstrappable` (hooks/lib/version-gate.sh) says so — a legacy or
# unrecognized schema version is left completely untouched, exactly like
# session-start.sh's heartbeat.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/discover.sh
source "$HOOK_DIR/lib/discover.sh"
# shellcheck source=./lib/version-gate.sh
source "$HOOK_DIR/lib/version-gate.sh"

# Best-effort telemetry mutator. $1 = wiki dir (already realpath'd),
# $2 = record key (path relative to {wiki}/), $3 = action ("view"|"patch").
# Reads {wiki}/.usage.json (corrupt/non-object -> treated as `{}`, per
# telemetry.md Tolerance rules), creates the 10-field-default record if the
# key is absent, bumps the relevant counters + timestamp, stamps
# `_hooks.post_tool_use_at`, and writes back atomically (tmp file in the
# same dir + rename). No python3 on PATH, or any read/write error: swallowed
# silently — this function never raises the caller's attention.
_wiki_ptu_bump() {
  local wiki_dir="$1" key="$2" action="$3"
  command -v python3 >/dev/null 2>&1 || return 0
  python3 - "$wiki_dir" "$key" "$action" 2>/dev/null <<'PYEOF'
import json
import os
import sys
import tempfile
import time

wiki_dir, key, action = sys.argv[1], sys.argv[2], sys.argv[3]
usage_path = os.path.join(wiki_dir, ".usage.json")

data = {}
if os.path.exists(usage_path):
    try:
        with open(usage_path, "r", encoding="utf-8") as f:
            loaded = json.load(f)
        if isinstance(loaded, dict):
            data = loaded
    except Exception:
        data = {}

now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

rec = data.get(key)
if not isinstance(rec, dict):
    rec = {
        "view_count": 0,
        "use_count": 0,
        "patch_count": 0,
        "last_viewed_at": None,
        "last_used_at": None,
        "last_patched_at": None,
        "created_at": now,
        "state": "active",
        "protected": False,
        "archived_at": None,
    }

if action == "view":
    rec["view_count"] = int(rec.get("view_count") or 0) + 1
    rec["last_viewed_at"] = now
else:
    rec["patch_count"] = int(rec.get("patch_count") or 0) + 1
    rec["last_patched_at"] = now

data[key] = rec

hooks_meta = data.get("_hooks")
if not isinstance(hooks_meta, dict):
    hooks_meta = {}
hooks_meta["post_tool_use_at"] = now
data["_hooks"] = hooks_meta

try:
    dir_name = os.path.dirname(usage_path) or "."
    fd, tmp_path = tempfile.mkstemp(prefix=".usage.json.", dir=dir_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as tf:
            json.dump(data, tf, indent=2, sort_keys=True)
            tf.write("\n")
        os.replace(tmp_path, usage_path)
    except Exception:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass
except Exception:
    pass
PYEOF
}

main() {
  command -v python3 >/dev/null 2>&1 || exit 0

  local input
  input="$(cat)" || exit 0

  # Single python3 pass over the raw stdin JSON: print tool_name on line 1,
  # tool_input.file_path on line 2. Malformed JSON / non-object / missing
  # keys all degrade to empty strings rather than raising — this hook must
  # never fail loudly on an unexpected stdin shape.
  local meta tool_name file_path
  meta="$(printf '%s' "$input" | python3 -c '
import json, sys

try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
if not isinstance(d, dict):
    d = {}

tool_name = d.get("tool_name", "")
tool_input = d.get("tool_input", {})
if not isinstance(tool_input, dict):
    tool_input = {}
file_path = tool_input.get("file_path", "")

print(tool_name if isinstance(tool_name, str) else "")
print(file_path if isinstance(file_path, str) else "")
' 2>/dev/null)"
  tool_name="$(printf '%s\n' "$meta" | sed -n '1p')"
  file_path="$(printf '%s\n' "$meta" | sed -n '2p')"

  [ -n "$file_path" ] || exit 0

  local action
  case "$tool_name" in
    Read) action="view" ;;
    Edit|Write|MultiEdit) action="patch" ;;
    *) exit 0 ;;
  esac

  local wiki
  wiki="$(discover_wiki 2>/dev/null)"
  [ -n "$wiki" ] || exit 0
  local wiki_real
  wiki_real="$(realpath "$wiki" 2>/dev/null || true)"
  [ -n "$wiki_real" ] || exit 0

  # file_path resolution: project-root-relative, never hook-cwd-relative.
  local project_dir resolved_input file_real
  project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
  case "$file_path" in
    /*) resolved_input="$file_path" ;;
    *) resolved_input="$project_dir/$file_path" ;;
  esac
  file_real="$(realpath "$resolved_input" 2>/dev/null || true)"
  [ -n "$file_real" ] || exit 0

  # Boundary guard: resolved file must be strictly inside {wiki}/.
  case "$file_real" in
    "$wiki_real"/*) ;;
    *) exit 0 ;;
  esac

  # Filters: only *.md, excluding the service-navigation pages.
  case "$file_real" in
    *.md) ;;
    *) exit 0 ;;
  esac
  local base
  base="$(basename "$file_real")"
  case "$base" in
    index.md|schema.md|log.md) exit 0 ;;
  esac

  # Version gate BEFORE any write: legacy/unrecognized schema -> untouched.
  if wiki_writable "$wiki_real" 2>/dev/null; then
    :
  elif wiki_bootstrappable "$wiki_real" 2>/dev/null; then
    :
  else
    exit 0
  fi

  local key
  key="${file_real#"$wiki_real"/}"

  _wiki_ptu_bump "$wiki_real" "$key" "$action"
  exit 0
}

main
exit 0
