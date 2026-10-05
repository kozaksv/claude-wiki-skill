#!/usr/bin/env python3
"""Read-only release-A inventory/preflight. No host/version probing or writes.

Schema 1 is the reusable input to future consolidation, not an implementation
of it. Discovery uses the existing Bash parser; there is no second parser here.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
NAMES = ("AGENTS.md", "CLAUDE.md", "GEMINI.md", "QWEN.md",
         "AGENTS.override.md", "CLAUDE.local.md", "QWEN.local.md")
SKIP = {".git", "node_modules", "vendor", ".venv", "venv", "__pycache__",
        "dist", "build", ".next", ".cache"}


def command(argv: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess:
    env = dict(os.environ, GIT_OPTIONAL_LOCKS="0", GIT_TERMINAL_PROMPT="0")
    return subprocess.run(argv, cwd=cwd, env=env, capture_output=True, timeout=15)


def kind(path: Path) -> str:
    try:
        mode = path.lstat().st_mode
        if stat.S_ISLNK(mode): return "symlink"
        if stat.S_ISREG(mode): return "file"
        return "other"
    except FileNotFoundError:
        return "missing"
    except OSError:
        return "unavailable"


def inside(path: Path, root: Path) -> bool:
    return path == root or root in path.parents


def discovery(cwd: Path) -> dict[str, Any]:
    proc = command(["bash", str(ROOT / "hooks/lib/discover.sh"), "--records", str(cwd)])
    fields = proc.stdout.decode("utf-8", "surrogateescape").split("\0")
    if proc.returncode or len(fields) < 5 or (len(fields) - 5) % 4:
        raise ValueError("discovery transport failed")
    root, selected, level, conflict = fields[:4]
    candidates = [dict(zip(("source", "pointer", "wiki", "reason"), fields[i:i + 4]))
                  for i in range(4, len(fields) - 1, 4)]
    return {"root": root or None, "selected": selected or None,
            "level": level or None, "same_level_conflict": conflict == "1",
            "candidates": candidates}


def inventory(root: Path) -> tuple[list[dict[str, Any]], list[str]]:
    """Metadata only, including ignored private instructions; no symlink walk."""
    entries: list[dict[str, Any]] = []
    warnings: list[str] = []
    proc = command(["git", "ls-files", "-z", "--cached"], root)
    if proc.returncode:
        raise ValueError("cannot inventory tracked files")
    tracked = {p for p in proc.stdout.decode("utf-8", "surrogateescape").split("\0") if p}
    def onerror(exc: OSError) -> None:
        warnings.append("inventory incomplete: " + str(exc.filename))
    for directory, dirs, files in os.walk(root, topdown=True, followlinks=False, onerror=onerror):
        base = Path(directory)
        names = files + dirs
        dirs[:] = [d for d in dirs if d not in SKIP and not (base / d).is_symlink()
                   and not os.path.lexists(base / d / ".git")]
        for name in sorted(names):
            if name.casefold() not in {n.casefold() for n in NAMES}: continue
            path = base / name
            rel = path.relative_to(root).as_posix()
            entry: dict[str, Any] = {"path": rel, "scope": base.relative_to(root).as_posix(),
                                    "kind": kind(path), "tracked": rel in tracked,
                                    "exact_case": name in NAMES,
                                    "private": name in ("CLAUDE.local.md", "QWEN.local.md")}
            if entry["kind"] == "symlink":
                entry["link_target"] = os.readlink(path)
            entries.append(entry)
    return sorted(entries, key=lambda item: item["path"]), warnings


def claude_blockers(cwd: Path, home: Path) -> list[str]:
    # Presence/path only: never read a blocker, config, plugin or version.
    blockers: list[str] = []
    for directory in (cwd, *cwd.parents):
        for name in ("CLAUDE.md", ".claude/CLAUDE.md", "CLAUDE.local.md"):
            path = directory / name
            if path == home / ".claude/CLAUDE.md": continue
            # .claude/rules and separately managed instructions are not scanned.
            if os.path.lexists(path): blockers.append(str(path))
    return blockers


def default_fallbacks(home: Path) -> tuple[list[str], list[str]]:
    """Only default user config; unknown profiles are warnings, never a gate."""
    config = Path(os.environ.get("CODEX_HOME", str(home / ".codex"))).expanduser() / "config.toml"
    warnings = ["Codex preflight inspects default fallback names, not effective profiles"]
    if kind(config) == "missing": return [], warnings
    try:
        # A3 is metadata-only except for explicitly documented default config.
        # Do not hang on FIFO or follow config links into arbitrary files.
        if kind(config) != "file": raise ValueError("not a regular config file")
        import tomllib
        fd = os.open(config, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0))
        with os.fdopen(fd, "rb") as stream:
            if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode): raise ValueError("not regular")
            raw = stream.read(1024 * 1024 + 1)
        if len(raw) > 1024 * 1024: raise ValueError("config too large")
        data = tomllib.loads(raw.decode("utf-8"))
        names = data.get("project_doc_fallback_filenames", [])
        if not isinstance(names, list) or any(not isinstance(n, str) or not n
                or n in (".", "..") or any(c in n for c in ("/", "\\", "\0")) for n in names):
            raise ValueError("invalid fallback names")
        return names, warnings
    except (ImportError, OSError, ValueError, UnicodeError):
        return [], warnings + ["Codex default config unknown; empty-scope init is not blocked by this"]


def preflight(cwd: Path, home: Path) -> dict[str, Any]:
    fallbacks, warnings = default_fallbacks(home)
    paths = [cwd / name for name in NAMES]
    paths += [cwd / ".claude/CLAUDE.md", cwd / ".claude/AGENTS.md"]
    paths += [cwd / name for name in fallbacks]
    # Case variants matter even on a case-sensitive runner.
    paths += [p for p in cwd.iterdir() if p.name.casefold() in {n.casefold() for n in NAMES}]
    present = list(dict.fromkeys(str(p) for p in paths if os.path.lexists(p)))
    canonical = cwd / "AGENTS.md"
    exact = any(p.name == "AGENTS.md" for p in cwd.iterdir())
    if exact and kind(canonical) == "file":
        state = "canonical_present"
    elif present:
        state = "consolidation_required"
    else:
        state = "instruction_empty"
    return {"scope": str(cwd), "state": state, "allow_create_agents": state == "instruction_empty",
            "allow_update_agents": state == "canonical_present", "existing": present,
            "default_fallback_names": fallbacks, "warnings": warnings}


def parent_safe(path: Path, home: Path) -> bool:
    if not inside(path, home): return False
    for parent in path.parents:
        if parent == home: return True
        if parent.is_symlink() or (parent.exists() and not parent.is_dir()): return False
    return False


def exports(home: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    proc = command(["bash", str(ROOT / "lib/harnesses.sh"), "--list"])
    if proc.returncode: raise ValueError("harness registry unavailable")
    for line in proc.stdout.decode("utf-8").splitlines():
        identity, relative, entry_kind = line.split("|")
        for skill in ("wiki", "doc-extract"):
            path = home / relative / skill
            expected = home / ".claude/skills" / skill
            status = "missing"
            if not parent_safe(path, home): status = "unsafe_parent"
            elif path.is_symlink():
                if entry_kind == "canonical":
                    status = "available" if (path / "SKILL.md").is_file() else "source_missing"
                elif os.readlink(path) == str(expected):
                    status = "available" if (path / "SKILL.md").is_file() else "source_missing"
                else: status = "conflict"
            elif os.path.lexists(path): status = "conflict"
            rows.append({"harness": identity, "skill": skill, "path": str(path),
                         "status": status, "optional": skill == "doc-extract"})
    for skill in ("wiki", "doc-extract"):
        path = home / ".gemini/skills" / skill
        if not parent_safe(path, home): status = "unsafe_parent"
        elif not os.path.lexists(path): status = "absent"
        elif path.is_symlink() and os.readlink(path) == str(home / ".claude/skills" / skill):
            status = "retired_export_present"
        else: status = "retired_export_conflict"
        rows.append({"harness": "retired_gemini", "skill": skill, "path": str(path),
                     "status": status, "optional": skill == "doc-extract"})
    return rows


def audit(projects: list[str]) -> dict[str, Any]:
    home = Path.home().absolute()
    reports: list[dict[str, Any]] = []
    for value in projects:
        cwd = Path(value).resolve(strict=True)
        if not cwd.is_dir(): raise ValueError("project must be a directory")
        selection = discovery(cwd)
        root = Path(selection["root"]) if selection["root"] else None
        entries, warnings = inventory(root) if root else ([], ["no Git boundary; audit only"])
        selected = selection["selected"]
        if selected and selection["level"]:
            for candidate in selection["candidates"]:
                if (candidate["reason"] == "valid" and candidate["source"]
                        and str(Path(candidate["source"]).parent) != selection["level"]
                        and candidate["wiki"] != selected):
                    warnings.append("cross-level wiki mismatch (warning only): " + candidate["source"])
        reports.append({"cwd": str(cwd), "root": str(root) if root else None,
                        "inventory": entries, "discovery": selection,
                        "claude_blockers": claude_blockers(cwd, home),
                        "preflight": preflight(cwd, home), "warnings": warnings})
    return {"schema_version": 1, "projects": reports, "exports": exports(home),
            "runtime_verification": "not_run"}


def render(report: dict[str, Any]) -> None:
    print("wiki instructions: read-only audit (no runtime/version checks)")
    for project in report["projects"]:
        print("  project: " + project["cwd"])
        print("  instructions: " + project["preflight"]["state"])
        print("  wiki: " + str(project["discovery"]["selected"] or "not found"))
        if project["discovery"]["same_level_conflict"]:
            print("  ! same-level pointer conflict; no unaddressed wiki writes")
        for path in project["claude_blockers"]: print("  ! Claude blocker present: " + path)
        for warning in project["warnings"] + project["preflight"]["warnings"]: print("  ! " + warning)
    for entry in report["exports"]:
        print("  export: {harness}/{skill}: {status}".format(**entry))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("audit",))
    parser.add_argument("--project", action="append", default=[])
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    try:
        report = audit(args.project or [str(Path.cwd())])
        if args.json: print(json.dumps(report, ensure_ascii=True, indent=2))
        else: render(report)
        return 0
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        print("wiki instructions: " + str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
