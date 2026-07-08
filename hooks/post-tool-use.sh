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
# file_path resolution: `tool_input.file_path` is resolved against a
# project anchor with strict precedence `$CLAUDE_PROJECT_DIR` -> stdin
# `cwd` (documented hook-input field) -> `pwd`, never against the hook
# process's own cwd alone — Claude Code hands hooks a project-root-relative
# file_path while the hook's cwd can be any subdirectory, and
# CLAUDE_PROJECT_DIR is not guaranteed to be exported; missing both would
# silently break the guard below and drop telemetry with no signal
# (plan Task 3 point 3 + wave4 P1).
#
# MultiEdit shape (fixwave0-3 P1): MultiEdit's tool_input does not
# reliably carry a single top-level `file_path` the way Edit/Write do — it
# can instead (or additionally) carry a per-edit `file_path` on each entry
# of `tool_input.edits[]`. Reading only the top-level field silently
# skipped telemetry for every MultiEdit call. The stdin parser below
# therefore collects the UNION of the top-level `tool_input.file_path`
# (if any) and every distinct `tool_input.edits[].file_path` (if any), and
# main() bumps telemetry once per distinct resolved path — covering both
# the single-file-path shape and the per-edit-array shape without double
# counting a path that appears in both places.
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
# key is absent. For a record that already exists, migrates a legacy
# `pinned` field to `protected` and backfills any other missing v4 fields
# with defaults (telemetry.md "Field-rename compat" / "Backfill missing
# keys silently") before bumping. Bumps the relevant counters + timestamp,
# stamps `_hooks.post_tool_use_at`, and writes back atomically (tmp file in
# the same dir + rename). No python3 on PATH, or any read/write error:
# swallowed silently — this function never raises the caller's attention.
_wiki_ptu_bump() {
  local wiki_dir="$1" key="$2" action="$3"
  command -v python3 >/dev/null 2>&1 || return 0
  python3 - "$wiki_dir" "$key" "$action" 2>/dev/null <<'PYEOF'
import fcntl
import json
import os
import stat
import sys
import tempfile
import time

wiki_dir, key, action = sys.argv[1], sys.argv[2], sys.argv[3]
usage_path = os.path.join(wiki_dir, ".usage.json")

# Serialize the whole read-modify-write against concurrent hook writers
# (agy-атк P1, wave3: two overlapping tool hooks clobbered each other's
# records — last rename wins, the other invocation's bumps vanish). The
# advisory flock lives on the WIKI DIRECTORY fd: the dir inode is stable,
# whereas locking the usage file itself would race with the atomic rename
# below that replaces it; and no lockfile litters the wiki tree. Shared
# invariant with hooks/session-start.sh's heartbeat writer. Non-blocking
# with a short retry — a contender holds it for milliseconds; if the lock
# still cannot be taken, we skip this bump entirely (tolerance: one lost
# increment beats blocking tool execution or losing ANOTHER file's records).
lock_fd = None
try:
    lock_fd = os.open(wiki_dir, os.O_RDONLY)
except OSError:
    sys.exit(0)
locked = False
for _ in range(10):
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        locked = True
        break
    except OSError:
        time.sleep(0.03)
if not locked:
    try:
        os.close(lock_fd)
    except Exception:
        pass
    sys.exit(0)

# Read the sidecar defensively (codex-атк P1). The version-gate already
# rejects a symlink / FIFO / char-device .usage.json, but this open() is
# the second, TOCTOU-proof line of the same shared invariant:
#   * O_NOFOLLOW  -> a .usage.json that is a symlink raises ELOOP here
#     instead of being followed, so external JSON can never be slurped in
#     and then copied into the repo sidecar by the atomic rename below.
#   * O_NONBLOCK  -> opening a FIFO / char-device (e.g. /dev/zero) returns
#     immediately instead of blocking the hook forever ("never blocks"
#     invariant); the fstat/S_ISREG check then rejects it before any read.
# Anything that isn't a plain regular file leaves `data == {}`, i.e. the
# hook proceeds exactly as if the sidecar were absent-but-bootstrappable,
# and the atomic tmp+rename below replaces the offending path with a real
# regular file (rename never follows a symlink at the target path).
data = {}
try:
    fd = os.open(usage_path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
except OSError:
    fd = None
if fd is not None:
    try:
        if stat.S_ISREG(os.fstat(fd).st_mode):
            with os.fdopen(fd, "r", encoding="utf-8") as f:
                loaded = json.load(f)
            if isinstance(loaded, dict):
                data = loaded
        else:
            os.close(fd)
    except Exception:
        try:
            os.close(fd)
        except Exception:
            pass
        data = {}

now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

DEFAULTS = {
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

rec = data.get(key)
if not isinstance(rec, dict):
    rec = dict(DEFAULTS)
else:
    # telemetry.md "Field-rename compat" + "accept either name as truthy":
    # on the first write to a record still carrying the legacy `pinned`
    # key, migrate to `protected` and drop `pinned`. The migrated value is
    # the UNION of both names' truthiness, never a blind overwrite
    # (codex-атк P1): a record like {"protected": true, "pinned": false}
    # must stay protected — clobbering `protected` with `pinned` would
    # silently un-protect a page and expose it to cleanup, contradicting
    # the documented read-side "either name truthy" contract.
    if "pinned" in rec:
        pinned_val = rec.pop("pinned")
        rec["protected"] = bool(rec.get("protected")) or bool(pinned_val)
    # telemetry.md "Backfill missing keys silently": a record that already
    # exists but predates newer fields gets those fields filled with
    # defaults, without touching any field it already has.
    for _field, _default in DEFAULTS.items():
        rec.setdefault(_field, _default)

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

  # Single python3 pass over the raw stdin JSON: NUL-separated fields —
  # tool_name, then the documented stdin `cwd`, then every distinct
  # candidate file path. Candidates are the UNION of the top-level
  # `tool_input.file_path` (Edit/Write shape, and any MultiEdit that also
  # sets it) and each `tool_input.edits[].file_path` (MultiEdit's per-edit
  # array shape) — order-preserving de-dup so a path present in both
  # places is only bumped once. Malformed JSON / non-object / missing keys
  # all degrade to empty output rather than raising — this hook must never
  # fail loudly on an unexpected stdin shape. NUL-separated (not
  # newline-separated) so a pathological file_path containing a newline
  # can never be mis-split into a bogus extra field, AND piped straight
  # into the read loop via process substitution below rather than ever
  # being captured into a plain bash variable — a bash variable cannot
  # hold an embedded NUL byte (command substitution silently truncates at
  # the first one), so an intermediate `meta="$(...)"` capture would drop
  # every field after the first NUL.
  local tool_name stdin_cwd
  local tool_idx=0 field
  local -a file_paths=()
  while IFS= read -r -d '' field; do
    case "$tool_idx" in
      0) tool_name="$field" ;;
      1) stdin_cwd="$field" ;;
      *) file_paths+=("$field") ;;
    esac
    tool_idx=$((tool_idx + 1))
  done < <(printf '%s' "$input" | python3 -c '
import json, sys

try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
if not isinstance(d, dict):
    d = {}

tool_name = d.get("tool_name", "")
if not isinstance(tool_name, str):
    tool_name = ""
tool_input = d.get("tool_input", {})
if not isinstance(tool_input, dict):
    tool_input = {}
cwd = d.get("cwd", "")
if not isinstance(cwd, str):
    cwd = ""

paths = []
seen = set()


def add(p):
    if isinstance(p, str) and p and p not in seen:
        seen.add(p)
        paths.append(p)


add(tool_input.get("file_path", ""))

edits = tool_input.get("edits", [])
if isinstance(edits, list):
    for item in edits:
        if isinstance(item, dict):
            add(item.get("file_path", ""))

sys.stdout.write("\0".join([tool_name, cwd] + paths) + "\0")
' 2>/dev/null)

  [ "${#file_paths[@]}" -gt 0 ] || exit 0

  local action
  case "$tool_name" in
    Read) action="view" ;;
    Edit|Write|MultiEdit) action="patch" ;;
    *) exit 0 ;;
  esac

  # Project anchor with strict precedence CLAUDE_PROJECT_DIR -> stdin cwd
  # -> pwd (wave4 P1: Claude Code does not always export
  # CLAUDE_PROJECT_DIR, but the hook stdin carries the documented `cwd`;
  # anchoring at the hook process's own pwd alone mis-resolves relative
  # file_path when the session sits in a subdirectory and silently drops
  # telemetry). The same anchor seeds discovery.
  local anchor
  anchor="${CLAUDE_PROJECT_DIR:-}"
  [ -n "$anchor" ] || anchor="$stdin_cwd"
  [ -n "$anchor" ] || anchor="$(pwd)"

  local wiki
  wiki="$(discover_wiki "$anchor" 2>/dev/null)"
  [ -n "$wiki" ] || exit 0
  local wiki_real
  wiki_real="$(realpath "$wiki" 2>/dev/null || true)"
  [ -n "$wiki_real" ] || exit 0

  # Version gate BEFORE any write: legacy/unrecognized schema -> untouched.
  # Computed once for the whole invocation (same wiki for every candidate
  # path in this tool call).
  local gated=0
  if wiki_writable "$wiki_real" 2>/dev/null; then
    :
  elif wiki_bootstrappable "$wiki_real" 2>/dev/null; then
    :
  else
    gated=1
  fi
  [ "$gated" -eq 0 ] || exit 0

  local project_dir="$anchor"
  local file_path resolved_input file_real base key
  for file_path in "${file_paths[@]}"; do
    # file_path resolution: project-anchor-relative, never hook-cwd-relative.
    case "$file_path" in
      /*) resolved_input="$file_path" ;;
      *) resolved_input="$project_dir/$file_path" ;;
    esac
    file_real="$(realpath "$resolved_input" 2>/dev/null || true)"
    [ -n "$file_real" ] || continue

    # Boundary guard: resolved file must be strictly inside {wiki}/.
    case "$file_real" in
      "$wiki_real"/*) ;;
      *) continue ;;
    esac

    # Filters: only *.md, excluding the service-navigation pages.
    case "$file_real" in
      *.md) ;;
      *) continue ;;
    esac
    base="$(basename "$file_real")"
    case "$base" in
      index.md|schema.md|log.md) continue ;;
    esac

    # Exclude the entire {wiki}/log/ subtree (archived log shards, e.g.
    # {wiki}/log/2026-01-01_to_2026-01-02.md — fixwave0-5): wiki-structure's
    # log-rotation "Out of scope" is explicit — shards are not tracked in
    # .usage.json; telemetry tracks knowledge pages, not the log substrate.
    # A shard passes the *.md filter and is never index/schema/log.md, so
    # without this guard every Read/Edit of a rotated shard would create a
    # phantom page record polluting status/lint/doctor.
    case "$file_real" in
      "$wiki_real"/log/*) continue ;;
    esac

    key="${file_real#"$wiki_real"/}"
    _wiki_ptu_bump "$wiki_real" "$key" "$action"
  done

  exit 0
}

main
exit 0
