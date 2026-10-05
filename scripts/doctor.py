#!/usr/bin/env python3
"""Combine hook verification and read-only instruction/export findings."""
import argparse
import importlib.util
import json
from pathlib import Path
import sys
import subprocess

# A diagnostic must not create __pycache__ in the installed checkout.
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", action="append", default=[])
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    hooks = load("wiki_hooks_audit", ROOT / "hooks/lib/config_audit.py")
    instructions = load("wiki_instructions_audit", ROOT / "scripts/instructions.py")
    try:
        report = hooks.audit(args.project)
        # Preserve the existing top-level hook schema and exit-status meaning.
        report["instructions"] = instructions.audit(args.project)
        if args.json:
            print(json.dumps(report, ensure_ascii=True, indent=2))
        else:
            print("wiki hooks: " + ("verified" if report["ok"] else "incomplete"))
            print("scope: " + report["scope"])
            for path in report["settings_checked"]: print("  checked: " + path)
            for key, value in report["identity"].items(): print(f"  {key}: {value}")
            for issue in report["issues"]: print("  ! " + issue)
            instructions.render(report["instructions"])
        return 0 if report["ok"] else 3
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        print("wiki doctor: " + str(exc), file=sys.stderr)
        return 3


if __name__ == "__main__":
    raise SystemExit(main())
