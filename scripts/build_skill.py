#!/usr/bin/env python3
"""Generate shared fixtures/export tables and bundle the standalone GitHub skill."""
import argparse
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def put(path, data, check):
    expected = data.encode("utf-8") if isinstance(data, str) else data
    if check:
        if not path.is_file() or path.read_bytes() != expected:
            raise ValueError(f"Stale generated file: {path.relative_to(ROOT)}; run python3 scripts/build_skill.py")
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(expected)


def export_table():
    rows = subprocess.check_output(["bash", str(ROOT / "lib/harnesses.sh"), "--list"], text=True).splitlines()
    table = ["| Harness | Global wiki entrypoint | Kind |", "|---|---|---|"]
    for row in rows:
        name, relative, kind = row.split("|")
        table.append(f"| {name} | `~/{relative}/wiki` | {kind} |")
    return "\n".join(table)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        cases = json.loads((ROOT / "references/discovery-cases.json").read_text())
        lines = ["# Portable discovery cases", "", "Generated from `discovery-cases.json`; do not edit independently.", "",
                 "The local engine is tested in CI. GitHub-agent parity requires a separate",
                 "recorded connector run on these scenarios; a local pass is not that run.", "",
                 "| Case | Scenario | Selected wiki | Same-level conflict / no-write |", "|---|---|---|---|"]
        for case in cases:
            lines.append(f"| {case['id']} | {case['description']} | `{case['selected'] or 'absent'}` | {'yes' if case['conflict'] else 'no'} |")
        put(ROOT / "references/discovery-cases.md", "\n".join(lines) + "\n", args.check)
        for relative in ("README.md", "references/operation-init.md"):
            path = ROOT / relative
            text = path.read_text()
            start, end = "<!-- harness-exports:start -->", "<!-- harness-exports:end -->"
            if start not in text or end not in text:
                raise ValueError(f"Missing export-table markers in {relative}")
            before, tail = text.split(start, 1)
            _, after = tail.split(end, 1)
            put(path, before + start + "\n" + export_table() + "\n" + end + after, args.check)
        for relative in ("references/reader-core.md", "references/writer-core.md", "scripts/wiki.py",
                         "references/discovery-cases.md", "references/discovery-cases.json"):
            put(ROOT / "skills/wiki-github" / relative, (ROOT / relative).read_bytes(), args.check)
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        parser.exit(1, str(exc) + "\n")


if __name__ == "__main__":
    main()
