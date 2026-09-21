#!/usr/bin/env python3
"""Read-only hook inventory and ownership rules shared with the installer.

Never execute a command found in settings. Only recognized standalone wiki
commands may be migrated; inline/composite commands are reported for review.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import stat
import subprocess
import sys
from typing import Any

EVENTS = {
    "SessionStart": ("startup|clear|compact", "session-start.sh"),
    "PostToolUse": ("Read|Edit|Write|MultiEdit", "post-tool-use.sh"),
}
QWEN_EVENTS = {
    "SessionStart": ("startup|clear|compact", "session-start-qwen.sh"),
    "PostToolUse": ("read_file|write_file|edit|replace|notebook_edit", "post-tool-use.sh"),
}
MAX_SETTINGS_BYTES = 4 * 1024 * 1024


def unique_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key")
        result[key] = value
    return result


def read_settings(path: Path) -> dict[str, Any]:
    """Refuse symlinks, devices, duplicate keys and malformed hook structures."""
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0)
    if path.is_symlink():
        raise ValueError("settings file is a symlink")
    try:
        fd = os.open(path, flags)
    except FileNotFoundError:
        return {}
    with os.fdopen(fd, "r", encoding="utf-8") as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_SETTINGS_BYTES:
            raise ValueError("settings must be a bounded regular file")
        text = stream.read(MAX_SETTINGS_BYTES + 1)
    if len(text.encode("utf-8")) > MAX_SETTINGS_BYTES:
        raise ValueError("settings too large")
    # Match historical installer support for empty settings files.
    data = json.loads(text, object_pairs_hook=unique_pairs) if text.strip() else {}
    validate_structure(data)
    return data


def validate_structure(data: Any) -> None:
    if not isinstance(data, dict):
        raise ValueError("settings must be a JSON object")
    hooks = data.get("hooks", {})
    if hooks is None:
        hooks = {}
    if not isinstance(hooks, dict):
        raise ValueError("hooks must be an object")
    for entries in hooks.values():
        if not isinstance(entries, list):
            raise ValueError("hook events must contain arrays")
        for entry in entries:
            if not isinstance(entry, dict) or not isinstance(entry.get("hooks"), list):
                raise ValueError("invalid hook matcher entry")
            if not all(isinstance(hook, dict) for hook in entry["hooks"]):
                raise ValueError("invalid hook handler")


def standalone_script(command: str) -> str | None:
    """Recognize a direct script invocation or our exact fail-open wrapper."""
    try:
        tokens = shlex.split(command)
    except ValueError:
        return None
    if len(tokens) == 1:
        return tokens[0]
    if len(tokens) == 2 and tokens[0] in ("bash", "/bin/bash", "sh", "/bin/sh"):
        return tokens[1]
    if (len(tokens) == 8 and tokens[:2] == ["test", "-x"]
            and tokens[3] == "&&" and tokens[4] == tokens[2]
            and tokens[5:] == ["||", "exit", "0"]):
        return tokens[2]
    return None


def classify(command: Any) -> str:
    if not isinstance(command, str):
        return "foreign"
    script = standalone_script(command)
    # Shell metacharacters inside a token may be substitutions, not a path.
    if script and not any(char in script for char in ("`", "\n", "\r", ";", "|", "&", "(", ")")):
        path = script.replace("${HOME}", "~").replace("$HOME", "~")
        if (re.search(r"(?:^|/)(?:skills/wiki|claude-wiki-skill)/hooks/[^/]+\.sh$", path)
                or re.search(r"(?:^|/)\.qwen/hooks/wiki-session-start\.sh$", path)):
            return "owned"
    if any(marker in command for marker in (
        "/skills/wiki/hooks/", "claude-wiki-skill", "wiki-session-start",
        "wiki-post-tool-use", "WIKI INDEX", "WIKI DISCOVERY",
    )):
        return "suspect"
    return "foreign"


def project_root(value: str) -> Path:
    try:
        result = subprocess.run(
            ["git", "-C", value, "rev-parse", "--show-toplevel"],
            check=True, text=True, capture_output=True, timeout=5,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise ValueError("project must be an accessible Git checkout") from exc
    root = Path(result.stdout.strip()).resolve(strict=True)
    if root == Path.home().resolve():
        raise ValueError("project settings overlap global HOME settings")
    return root


def project_files(value: str) -> list[Path]:
    root = project_root(value)
    files = []
    for client in (".claude", ".qwen"):
        directory = root / client
        # Do not follow a project-owned directory link into global settings.
        if directory.is_symlink():
            raise ValueError(f"{directory}: symlinked settings directory; review manually")
        for name in ("settings.json", "settings.local.json"):
            path = directory / name
            if path.exists() or path.is_symlink():
                if path.is_symlink():
                    raise ValueError(f"{path}: symlinked settings file; review manually")
                if root not in path.resolve().parents:
                    raise ValueError("settings path escapes selected project")
                read_settings(path)
                files.append(path)
    return files


def expected_command(script: Path) -> str:
    # Keep the established command shape (and reject shell-active HOME below).
    return f'test -x "{script}" && "{script}" || exit 0'


def safe_home() -> Path:
    home = Path.home()
    if any(c in str(home) for c in ('"', '`', '$', '\n', '\r')):
        raise ValueError("HOME contains shell-active characters; refusing hook registration")
    return home


def inspect_settings(path: Path, expected: dict | None, script_dir: Path) -> list[str]:
    data = read_settings(path)
    problems: list[str] = []
    if data.get("disableAllHooks") is True:
        problems.append(f"{path}: disableAllHooks=true (preserved)")
    hooks = data.get("hooks") or {}
    for event, entries in hooks.items():
        for number, entry in enumerate(entries):
            for index, hook in enumerate(entry["hooks"]):
                kind = classify(hook.get("command"))
                location = f"{path}: {event}[{number}].hooks[{index}]"
                if kind == "suspect":
                    problems.append(f"{location}: ambiguous wiki command preserved; inspect /hooks")
                elif kind == "owned":
                    if expected is None or event not in expected:
                        problems.append(f"{location}: legacy/duplicate wiki registration")
                    else:
                        matcher, filename = expected[event]
                        if (entry.get("matcher") != matcher or hook.get("type") != "command"
                                or hook.get("command") != expected_command(script_dir / filename)):
                            problems.append(f"{location}: stale wiki command or matcher")
    if expected:
        for event, (matcher, filename) in expected.items():
            count = sum(
                hook.get("type") == "command"
                and hook.get("command") == expected_command(script_dir / filename)
                and entry.get("matcher") == matcher
                for entry in hooks.get(event, []) for hook in entry["hooks"]
            )
            if count != 1:
                problems.append(f"{path}: expected one canonical {event}, found {count}")
    return problems


def audit(projects: list[str]) -> dict[str, Any]:
    home = safe_home()
    canonical = home / ".claude/skills/wiki"
    source = Path(__file__).resolve().parents[2]
    script_dir = canonical / "hooks"
    issues: list[str] = []
    files: list[str] = []
    identity: dict[str, str] = {}
    if not canonical.is_symlink() or canonical.resolve() != source:
        issues.append(f"{canonical}: canonical entrypoint does not resolve to this skill checkout")
    for filename in ("session-start.sh", "post-tool-use.sh", "session-start-qwen.sh"):
        path = script_dir / filename
        try:
            if (not path.is_file() or not os.access(path, os.X_OK)
                    or path.resolve().parent != source / "hooks"):
                raise ValueError("missing, non-executable or outside the skill checkout")
            identity[filename] = hashlib.sha256(path.read_bytes()).hexdigest()
        except (OSError, ValueError):
            issues.append(f"{path}: missing, non-executable or outside the skill checkout")
    skill = canonical / "SKILL.md"
    try:
        version = re.search(r'^version:\s*"([^"]+)"', skill.read_text(), re.M)
        identity["skill_version"] = version.group(1) if version else "unknown"
    except OSError:
        issues.append(f"{skill}: unavailable")
    for client, expected in ((".claude", EVENTS), (".qwen", QWEN_EVENTS)):
        path = home / client / "settings.json"
        if client == ".qwen" and not path.exists() and not shutil.which("qwen"):
            continue
        files.append(str(path))
        try:
            issues.extend(inspect_settings(path, expected, script_dir))
        except (OSError, ValueError, UnicodeError) as exc:
            issues.append(f"{path}: {exc}")
    seen: set[Path] = set()
    for project in projects:
        try:
            for path in project_files(project):
                if path in seen:
                    continue
                seen.add(path)
                files.append(str(path))
                issues.extend(inspect_settings(path, None, script_dir))
        except (OSError, ValueError, UnicodeError) as exc:
            issues.append(f"{project}: {exc}")
    return {"ok": not issues, "identity": identity, "settings_checked": files,
            "issues": issues, "scope": "user settings + explicitly selected projects; not managed/plugin settings"}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("check", "project-files", "validate"))
    parser.add_argument("--project", action="append", default=[])
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    try:
        safe_home()
        if args.command == "project-files":
            paths = dict.fromkeys(p for value in args.project for p in project_files(value))
            sys.stdout.write("".join(str(p) + "\0" for p in paths))
            return 0
        if args.command == "validate":
            for value in args.project:
                project_files(value)
            return 0
        report = audit(args.project)
        if args.json:
            print(json.dumps(report, ensure_ascii=False, indent=2))
        else:
            print("wiki hooks: " + ("verified" if report["ok"] else "incomplete"))
            print("scope: " + report["scope"])
            for path in report["settings_checked"]:
                print("  checked: " + path)
            for key, value in report["identity"].items():
                print(f"  {key}: {value}")
            for issue in report["issues"]:
                print("  ! " + issue)
        return 0 if report["ok"] else 3
    except (OSError, ValueError, UnicodeError) as exc:
        print(f"wiki hooks: {exc}", file=sys.stderr)
        return 3


if __name__ == "__main__":
    raise SystemExit(main())
