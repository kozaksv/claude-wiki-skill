#!/usr/bin/env python3
"""Daily wiki reminder for SessionStart: at most once per 20 h per session.

Universal by design: no roles, no project knowledge. Prints facts from git
(last wiki change, commits in the last 24 h with and without the wiki) and
the next step. Without a wiki it suggests `init` only inside a git repo that
had commits in the last 24 h. Never blocks: every failure is silent.

State: one empty marker file per session key under
`$WIKI_REMINDER_STATE_DIR` (default `${XDG_STATE_HOME:-~/.local/state}/claude-wiki-skill/reminders`).
`WIKI_REMINDER=off` disables the reminder.
"""
from __future__ import annotations

import argparse
import hashlib
import os
import re
from pathlib import Path
import subprocess
import sys
import time

INTERVAL_SECONDS = 20 * 60 * 60
DAY_SECONDS = 24 * 60 * 60
KEEP_SECONDS = 14 * DAY_SECONDS


def state_dir() -> Path:
    explicit = os.environ.get("WIKI_REMINDER_STATE_DIR")
    if explicit:
        return Path(explicit)
    base = os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state")
    return Path(base) / "claude-wiki-skill" / "reminders"


def git(repo: str, *args: str) -> str | None:
    try:
        r = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return None
    return r.stdout.strip() if r.returncode == 0 else None


def count(out: str | None) -> int:
    return len([line for line in (out or "").splitlines() if line.strip()])


def ago(seconds: float) -> str:
    if seconds < 3600:
        return "менше години тому"
    if seconds < DAY_SECONDS:
        return f"{int(seconds // 3600)} год тому"
    return f"{int(seconds // DAY_SECONDS)} дн тому"


def due(key: str, now: float) -> Path | None:
    """Marker path when the reminder is due for this key, else None."""
    directory = state_dir()
    marker = directory / hashlib.sha256(key.encode("utf-8")).hexdigest()[:32]
    try:
        if now - marker.stat().st_mtime < INTERVAL_SECONDS:
            return None
    except FileNotFoundError:
        pass
    except OSError:
        return None
    return marker


def mark(marker: Path, now: float) -> None:
    try:
        marker.parent.mkdir(parents=True, exist_ok=True)
        marker.touch()
        os.utime(marker, (now, now))
        for old in marker.parent.iterdir():
            if old != marker and now - old.stat().st_mtime > KEEP_SECONDS:
                old.unlink()
    except OSError:
        pass


POINTER_FILES = ("AGENTS.md", "CLAUDE.md", "GEMINI.md", "QWEN.md")
POINTER_HEADING = re.compile(r"^##\s*(wiki|вікі)\b", re.IGNORECASE | re.MULTILINE)


def wiki_configured(repo: str, anchor: str) -> bool:
    for base in {repo, os.path.realpath(anchor)}:
        if os.path.isdir(os.path.join(base, "docs", "wiki")):
            return True
        for name in POINTER_FILES:
            try:
                with open(os.path.join(base, name), encoding="utf-8", errors="replace") as f:
                    if POINTER_HEADING.search(f.read(256 * 1024)):
                        return True
            except OSError:
                continue
    return False


def message(anchor: str, wiki: str | None, now: float) -> str | None:
    repo = git(anchor, "rev-parse", "--show-toplevel")
    if not repo:
        return None
    commits = count(git(repo, "log", "--since=24.hours.ago", "--format=%H"))
    if not wiki:
        if commits == 0:
            return None
        if wiki_configured(repo, anchor):
            # A pointer or docs/wiki exists but discovery found nothing usable:
            # a broken wiki is never a licence to create another one.
            return ("=== WIKI DAILY (hook) === Вікі в репо вказано, але її не знайдено чи вона пошкоджена — "
                    "перевір скілом wiki (doctor). === END WIKI DAILY ===")
        return ("=== WIKI DAILY (hook) === У репо вікі нема, а за добу комітів: "
                f"{commits}. Якщо в проєкті є рішення й причини, які варто зберегти, створи вікі скілом wiki (init). "
                "=== END WIKI DAILY ===")
    try:
        rel = os.path.relpath(os.path.realpath(wiki), os.path.realpath(repo))
    except ValueError:
        return None
    if rel.startswith(".."):
        return None
    last = git(repo, "log", "-1", "--format=%ct", "--", rel)
    with_wiki = count(git(repo, "log", "--since=24.hours.ago", "--format=%H", "--", rel))
    last_text = ago(now - int(last)) if last and last.isdigit() else "у git ще нема"
    return ("=== WIKI DAILY (hook) === "
            f"Вікі: остання правка {last_text}; комітів за добу {commits}, з них із вікі {with_wiki}. "
            "Нове знання за добу (рішення, причини, пастки, поганий шлях, якого уникли) запиши скілом wiki "
            "(ingest-source); у спільному репо правка вікі — у тій самій гілці, що й код. "
            "Живий стан і журнал дій у вікі не пиши. === END WIKI DAILY ===")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--anchor", required=True)
    parser.add_argument("--wiki", default="")
    parser.add_argument("--session", default="")
    args = parser.parse_args(argv)
    if os.environ.get("WIKI_REMINDER", "").lower() in ("off", "0", "false", "no"):
        return 0
    now = time.time()
    key = args.session or ("anchor:" + os.path.realpath(args.anchor))
    marker = due(key, now)
    if marker is None:
        return 0
    text = message(args.anchor, args.wiki or None, now)
    if text:
        sys.stdout.write(text + "\n")
        mark(marker, now)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception:
        sys.exit(0)
