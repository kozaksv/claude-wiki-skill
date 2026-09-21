#!/usr/bin/env bash
# Read-only hook provisioning audit. Does not execute configured commands.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v python3 >/dev/null 2>&1; then
  echo 'wiki hooks: python3 not found; verification unavailable' >&2
  exit 3
fi
exec python3 "$HERE/lib/config_audit.py" check "$@"
