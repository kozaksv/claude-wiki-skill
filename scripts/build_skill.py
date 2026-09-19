#!/usr/bin/env python3
"""Bundle the canonical reader/writer contracts and helper so the ChatGPT skill installs alone."""
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    for relative in ("references/reader-core.md", "references/writer-core.md", "scripts/wiki.py"):
        source = ROOT / relative
        target = ROOT / "skills/wiki-github" / relative
        expected = source.read_bytes()
        if args.check:
            if not target.is_file() or target.read_bytes() != expected:
                parser.exit(1, f"Stale bundle: {relative}; run python3 scripts/build_skill.py\n")
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(expected)


if __name__ == "__main__":
    main()
