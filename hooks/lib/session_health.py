#!/usr/bin/env python3
"""Best-effort SessionStart diagnostics; no LLM, lint, edits or git commits.

Shares the existing wiki-directory flock with PostToolUse. Corrupt legacy
protection is never replaced. Content hashes schedule checks, not truth claims.
"""
from __future__ import annotations

import argparse
import calendar
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import time
from typing import Any, Iterator

try:
    import fcntl
except ImportError:
    fcntl = None

MAX_BYTES = 32 * 1024 * 1024
MAX_FILES = 5000
STALE_SECONDS = 7 * 24 * 60 * 60


def unique_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate metadata key")
        result[key] = value
    return result


def regular_bytes(path: Path, limit: int) -> bytes:
    if path.is_symlink():
        raise ValueError("symlink")
    fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0))
    with os.fdopen(fd, "rb") as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_size > limit:
            raise ValueError("not a bounded regular file")
        value = stream.read(limit + 1)
    if len(value) > limit:
        raise ValueError("file limit exceeded")
    return value


def read_usage(wiki: Path) -> dict[str, Any]:
    try:
        data = json.loads(regular_bytes(wiki / ".usage.json", MAX_BYTES), object_pairs_hook=unique_pairs)
    except FileNotFoundError:
        return {}
    if not isinstance(data, dict) or not all(
        key.startswith("_") or (
            isinstance(rec, dict) and all(field not in rec or type(rec[field]) is bool
                                         for field in ("protected", "pinned")))
        for key, rec in data.items()
    ):
        raise ValueError("invalid usage/protection metadata")
    return data


def epoch(value: Any) -> float | None:
    if not isinstance(value, str):
        return None
    try:
        return calendar.timegm(time.strptime(value, "%Y-%m-%dT%H:%M:%SZ"))
    except ValueError:
        return None


def timestamp() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def fingerprint(wiki: Path) -> str | None:
    """Hash paths + content, including deletions/untracked files; exclude logs/state.

Bounded work; symlinks or limits mean unknown, never 'unchanged'. No filesystem
mtime heuristic and no accidental recheck caused by our own heartbeat writes.
"""
    digest = hashlib.sha256()
    consumed = 0
    count = 0
    deadline = time.monotonic() + 1.5
    directories = 0
    def scan_error(error: OSError) -> None:
        raise error
    try:
        for directory, dirs, files in os.walk(wiki, followlinks=False, onerror=scan_error):
            directories += 1
            if directories > MAX_FILES or time.monotonic() > deadline:
                return None
            base = Path(directory)
            dirs[:] = sorted(d for d in dirs if not d.startswith(".") and d not in ("log", "archive"))
            if any((base / d).is_symlink() for d in dirs):
                return None
            for name in sorted(files):
                if name.startswith(".") or name == "log.md":
                    continue
                if not name.endswith(".md") and name != "policy.json":
                    continue
                count += 1
                if count > MAX_FILES or time.monotonic() > deadline:
                    return None
                path = base / name
                content = regular_bytes(path, MAX_BYTES - consumed)
                consumed += len(content)
                relative = path.relative_to(wiki).as_posix().encode("utf-8")
                digest.update(len(relative).to_bytes(8, "big") + relative)
                digest.update(len(content).to_bytes(8, "big") + content)
        return digest.hexdigest()
    except (OSError, ValueError):
        return None


@contextmanager
def usage_lock(wiki: Path) -> Iterator[bool]:
    if fcntl is None:
        # Match existing hooks' Windows fallback; never mix lock primitives.
        yield True
        return
    fd = os.open(wiki, os.O_RDONLY)
    locked = False
    try:
        for _ in range(10):
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                locked = True
                break
            except OSError:
                time.sleep(0.03)
        yield locked
    finally:
        os.close(fd)


def write_usage(wiki: Path, data: dict[str, Any]) -> None:
    fd, path = tempfile.mkstemp(prefix=".usage.json.", dir=wiki)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(data, stream, indent=2, sort_keys=True)
            stream.write("\n")
        os.replace(path, wiki / ".usage.json")
    finally:
        if os.path.exists(path):
            os.unlink(path)


def hook_version() -> str:
    try:
        for line in (Path(__file__).resolve().parents[2] / "SKILL.md").read_text().splitlines():
            if line.startswith("version:"):
                return line.split(":", 1)[1].strip().strip('"')
    except OSError:
        pass
    return "unknown"


def session(wiki: Path, writable: bool, source: str) -> list[str]:
    messages: list[str] = []
    # Never scan the wiki or emit maintenance diagnostics on compact/clear.
    current = fingerprint(wiki) if source == "startup" else None
    try:
        with usage_lock(wiki) as locked:
            data = read_usage(wiki)
            meta = data.get("_hooks")
            meta = dict(meta) if isinstance(meta, dict) else {}
            now = timestamp()
            if source == "startup":
                if current is None:
                    messages.append("wiki: стан перевірки невідомий (ліміт/недоступні файли); wiki doctor.")
                elif (meta.get("last_lint_fingerprint") != current
                      and meta.get("last_lint_notice_fingerprint") != current):
                    messages.append("wiki: є неперевірений стан вікі; запусти wiki lint за потреби.")
                    meta["last_lint_notice_fingerprint"] = current
                last = epoch(meta.get("post_tool_use_at"))
                first = epoch(meta.get("telemetry_first_seen_at"))
                if first is None:
                    first = epoch(meta.get("session_start_at")) or time.time()
                    meta["telemetry_first_seen_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(first))
                reference = last if last is not None else first
                key = str(meta.get("post_tool_use_at") or "never")
                if time.time() - reference > STALE_SECONDS and meta.get("telemetry_notice_key") != key:
                    messages.append("wiki: телеметрія не підтверджена >7 днів; wiki doctor (це не доказ збою).")
                    meta["telemetry_notice_key"] = key
                if last is not None and time.time() - last <= STALE_SECONDS:
                    meta.pop("telemetry_notice_key", None)
            meta["session_start_at"] = now
            meta["hook_version"] = hook_version()
            data["_hooks"] = meta
            if writable and locked:
                write_usage(wiki, data)
    except (OSError, ValueError, UnicodeError):
        if source == "startup":
            messages.append("wiki: телеметрія недоступна; дані збережено без перезапису — wiki doctor.")
    return messages


def mark_lint(wiki: Path, scope: str) -> None:
    """Explicit maintenance only; no startup path ever calls this operation."""
    lib = Path(__file__).with_name("version-gate.sh")
    script = 'source "$1"; wiki_writable "$2" || wiki_bootstrappable "$2"'
    subprocess.run(["bash", "-c", script, "wiki-health", str(lib), str(wiki)],
                   check=True, timeout=5, capture_output=True)
    current = fingerprint(wiki) if scope == "full" else None
    if scope == "full" and current is None:
        raise ValueError("cannot fingerprint complete wiki; lint not marked complete")
    with usage_lock(wiki) as locked:
        if not locked:
            raise ValueError("telemetry lock busy; lint checkpoint not written")
        data = read_usage(wiki)
        meta = data.get("_hooks")
        meta = dict(meta) if isinstance(meta, dict) else {}
        if scope == "full":
            meta["last_lint_at"] = timestamp()
            meta["last_lint_fingerprint"] = current
        else:
            meta["last_partial_lint_at"] = timestamp()
        data["_hooks"] = meta
        write_usage(wiki, data)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("session", "mark-lint"))
    parser.add_argument("--wiki", type=Path, required=True)
    parser.add_argument("--source", choices=("startup", "clear", "compact"), default="startup")
    parser.add_argument("--writable", choices=("0", "1"), default="0")
    parser.add_argument("--scope", choices=("full", "partial"), default="partial")
    args = parser.parse_args()
    try:
        if args.command == "session":
            for message in session(args.wiki, args.writable == "1", args.source):
                print(message)
        else:
            mark_lint(args.wiki, args.scope)
        return 0
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        print(f"wiki health: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
