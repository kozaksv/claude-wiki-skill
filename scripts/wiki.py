#!/usr/bin/env python3
"""Deterministic Wiki navigation and policy tools. Python 3.9+, standard library."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import sys
import tempfile

START = "<!-- wiki:catalog:start -->"
END = "<!-- wiki:catalog:end -->"
POLICY = "policy.json"


class WikiError(ValueError):
    pass


def safe_relative(value):
    path = PurePosixPath(value)
    if (not value or path.is_absolute() or "\\" in value or ":" in value
            or any(p in (".", "..", "") for p in value.split("/"))
            or any(ord(c) < 32 for c in value)):
        raise WikiError(f"Invalid wiki-relative path: {value!r}")
    return path


def page_path(value):
    path = safe_relative(value)
    return (path.suffix.lower() == ".md"
            and value not in ("index.md", "schema.md", "log.md")
            and path.parts[0] != "log"
            and not any(p.startswith(".") for p in path.parts))


class Wiki:
    def __init__(self, root):
        self.root = Path(root).resolve(strict=True)
        if not self.root.is_dir():
            raise WikiError("Wiki root must be a directory")

    def path(self, relative):
        path = self.root
        for part in safe_relative(relative).parts:
            path = path / part
            if path.is_symlink():
                raise WikiError(f"Symlink is not a wiki file: {relative}")
            if path.exists() and not (path.is_dir() or path.is_file()):
                raise WikiError(f"Not a regular file/directory: {relative}")
        return path

    def read(self, relative):
        path = self.path(relative)
        # Do not block on a FIFO or follow a final-component symlink.
        fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
                     | getattr(os, "O_NONBLOCK", 0))
        with os.fdopen(fd, "rb") as stream:
            if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
                raise WikiError(f"Not a regular file: {relative}")
            return stream.read()

    def pages(self):
        def onerror(error):
            raise error
        found = []
        for directory, dirs, files in os.walk(self.root, followlinks=False, onerror=onerror):
            dirs[:] = sorted(d for d in dirs if not d.startswith("."))
            if Path(directory) == self.root:
                dirs[:] = [d for d in dirs if d != "log"]
            for name in dirs + files:
                relative = (Path(directory) / name).relative_to(self.root).as_posix()
                if name.startswith("."):
                    continue
                self.path(relative)  # Never silently omit a symlink from a "complete" inventory.
            for name in files:
                relative = (Path(directory) / name).relative_to(self.root).as_posix()
                if page_path(relative):
                    found.append(relative)
        return sorted(found)


def json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode()


def unique_pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise WikiError(f"Duplicate JSON key: {key}")
        result[key] = value
    return result


def read_json(wiki, name, absent):
    try:
        value = json.loads(wiki.read(name), object_pairs_hook=unique_pairs)
    except FileNotFoundError:
        return absent
    except (json.JSONDecodeError, UnicodeError) as error:
        raise WikiError(f"Invalid {name}; repair it before policy changes or cleanup") from error
    if not isinstance(value, dict):
        raise WikiError(f"{name} must be a JSON object")
    return value


def atomic_write(path, content):
    fd, temporary = tempfile.mkstemp(prefix=".wiki-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o644)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def write_batch(wiki, changes):
    """Preflight all files, atomic replacement per file, rollback ordinary failures.

    A process/power failure between replacements still needs Git recovery;
    this is deliberately not advertised as a filesystem-wide transaction.
    """
    targets, before = {}, {}
    for name in changes:
        targets[name] = wiki.path(name)
        try:
            before[name] = wiki.read(name)
        except FileNotFoundError:
            before[name] = None
    written = []
    try:
        for name, content in changes.items():
            if before[name] == content:
                continue
            targets[name].parent.mkdir(parents=True, exist_ok=True)
            wiki.path(name)  # Recheck after parent creation.
            atomic_write(targets[name], content)
            written.append(name)
    except (OSError, WikiError):
        for name in reversed(written):
            if before[name] is None:
                targets[name].unlink()
            else:
                atomic_write(targets[name], before[name])
        raise


def headings(text):
    """ATX headings outside YAML frontmatter and fenced code; 1-based lines."""
    rows, fence = [], None
    lines = text.splitlines()
    frontmatter = bool(lines and lines[0] == "---")
    for number, line in enumerate(lines, 1):
        if frontmatter:
            if number > 1 and line in ("---", "..."):
                frontmatter = False
            continue
        match = re.match(r"^ {0,3}(`{3,}|~{3,})(.*)$", line)
        if match:
            token, rest = match.groups()
            if fence is None:
                fence = (token[0], len(token))
            elif token[0] == fence[0] and len(token) >= fence[1] and not rest.strip():
                fence = None
            continue
        if fence:
            continue
        match = re.match(r"^ {0,3}(#{1,6})[ \t]+(.+?)\s*$", line)
        if match:
            rows.append({"level": len(match[1]), "heading": re.sub(r"\s+#+\s*$", "", match[2]),
                         "start_line": number})
    for pos, row in enumerate(rows):
        row["end_line"] = next((n["start_line"] - 1 for n in rows[pos + 1:]
                                if n["level"] <= row["level"]), len(lines))
    return rows


def catalog(wiki, overrides=None):
    overrides = overrides or {}
    pages = []
    for path in sorted(set(wiki.pages()) | set(overrides)):
        data = overrides[path] if path in overrides else wiki.read(path)
        sections = headings(data.decode("utf-8"))
        title = next((h["heading"] for h in sections if h["level"] == 1), Path(path).stem)
        pages.append({"path": path, "title": title, "bytes": len(data),
                      "sha256": hashlib.sha256(data).hexdigest(),
                      "git_blob_sha1": hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest(),
                      "kind": "history" if path.startswith("history/") else "page",
                      "sections": [h for h in sections if h["level"] == 2]})
    return {"version": 1, "pages": pages}


def generated_index(original, inventory):
    def label(text):
        # Keep user-derived titles from creating extra Markdown or HTML.
        return re.sub(r"[\\`*_{}\[\]<>|]", "", text).replace("\n", " ")
    block = [START, "## All pages (generated)", "",
             "Exact paths; regenerate with the Wiki catalog tool.", ""]
    for kind, heading in (("page", "Pages"), ("history", "History")):
        pages = [p for p in inventory["pages"] if p["kind"] == kind]
        if pages:
            block.extend(["### " + heading, ""])
            # Markdown links encode unusual filenames without changing exact catalog paths.
            from urllib.parse import quote
            block.extend(f'- [{label(p["title"])}]({quote(p["path"], safe="/")})' for p in pages)
            block.append("")
    block.append(END)
    rendered = "\n".join(block)
    if START not in original and END not in original:
        return original.rstrip() + "\n\n" + rendered + "\n"
    if original.count(START) != 1 or original.count(END) != 1 or original.index(START) > original.index(END):
        raise WikiError("Malformed/duplicate managed catalog markers in index.md")
    start, end = original.index(START), original.index(END) + len(END)
    return original[:start] + rendered + original[end:]


def policy(wiki):
    data = read_json(wiki, POLICY, {"version": 1, "pages": {}})
    if type(data.get("version")) is not int or data["version"] != 1 or not isinstance(data.get("pages"), dict):
        raise WikiError("Unsupported policy.json; cleanup is blocked until repaired")
    for name, record in data["pages"].items():
        if not page_path(name) or not isinstance(record, dict) or type(record.get("protected")) is not bool:
            raise WikiError(f"Invalid policy record: {name}")
    return data


def legacy_protection(wiki):
    data = read_json(wiki, ".usage.json", {})
    result = {}
    for name, record in data.items():
        if name.startswith("_"):
            continue
        if not page_path(name) or not isinstance(record, dict):
            raise WikiError(f"Invalid legacy policy record: {name}")
        for field in ("protected", "pinned"):
            if field in record and type(record[field]) is not bool:
                raise WikiError(f"Invalid legacy {field} for {name}")
        result[name] = record.get("protected", False) or record.get("pinned", False)
    return result


def effective_protection(wiki, path):
    data = policy(wiki)
    if path in data["pages"]:
        return data["pages"][path]["protected"]
    return legacy_protection(wiki).get(path, False)


def migrate_policy(wiki):
    data = policy(wiki)
    for name, protected in legacy_protection(wiki).items():
        if protected and name not in data["pages"]:
            data["pages"][name] = {"protected": True}
    return data


def split_history(wiki, page, heading, destination):
    if not page_path(page) or not page_path(destination) or not destination.startswith("history/"):
        raise WikiError("Use a knowledge page and a destination under history/")
    if effective_protection(wiki, page):
        raise WikiError(f"Protected page: {page}")
    if wiki.path(destination).exists():
        raise WikiError(f"Destination already exists: {destination}")
    original = wiki.read(page).decode("utf-8")
    matches = [h for h in headings(original) if h["level"] == 2 and h["heading"] == heading]
    if len(matches) != 1:
        raise WikiError("History heading must identify exactly one H2 section")
    section = matches[0]
    lines = original.splitlines(keepends=True)
    start, end = section["start_line"], section["end_line"]
    body = "".join(lines[start:end])
    if not body.strip():
        raise WikiError("History section is empty")
    if re.search(r"\]\(|^ {0,3}\[[^\]]+\]:", body, re.MULTILINE):
        raise WikiError("Section contains Markdown links; use the reviewed Split workflow to relocate links")
    from urllib.parse import quote
    import posixpath
    forward = quote(posixpath.relpath(destination, posixpath.dirname(page) or "."), safe="/")
    back = quote(posixpath.relpath(page, posixpath.dirname(destination)), safe="/")
    current = "".join(lines[:start]) + f"\nSee [historical records]({forward}).\n\n" + "".join(lines[end:])
    history = f"# {heading}\n\nHistorical records extracted from [{page}]({back}).\n\n" + body
    return {destination: history.encode(), page: current.encode()}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("catalog", "protect", "unprotect", "policy-report", "migrate-policy", "split-history"):
        command = sub.add_parser(name)
        command.add_argument("--wiki", required=True)
        if name in ("catalog", "migrate-policy", "split-history"):
            command.add_argument("--write", action="store_true", help="apply changes (default: preview)")
        if name == "catalog":
            command.add_argument("--check", action="store_true", help="fail if catalog/index differ from actual files")
        if name in ("protect", "unprotect", "split-history"):
            command.add_argument("--page", required=True)
        if name == "split-history":
            command.add_argument("--heading", required=True)
            command.add_argument("--destination", required=True)
    args = parser.parse_args(argv)
    try:
        wiki = Wiki(args.wiki)
        if args.command == "catalog":
            if args.check and args.write:
                raise WikiError("--check and --write are mutually exclusive")
            data = catalog(wiki)
            if args.check or args.write:
                original = wiki.read("index.md").decode("utf-8")
                changes = {"catalog.json": json_bytes(data),
                           "index.md": generated_index(original, data).encode()}
                if args.check:
                    for name, expected in changes.items():
                        try:
                            actual = wiki.read(name)
                        except FileNotFoundError:
                            actual = None
                        if actual != expected:
                            raise WikiError(f"Stale {name}; run catalog --wiki {wiki.root} --write")
                else:
                    write_batch(wiki, changes)
            else:
                sys.stdout.buffer.write(json_bytes(data))
        elif args.command in ("protect", "unprotect"):
            if not page_path(args.page):
                raise WikiError("Protection applies to knowledge pages")
            wiki.read(args.page)
            data = migrate_policy(wiki)  # Preserve other legacy pins on first policy write.
            record = data["pages"].setdefault(args.page, {})
            record["protected"] = args.command == "protect"
            write_batch(wiki, {POLICY: json_bytes(data)})
            print(f'{args.page}: protected={record["protected"]}')
        elif args.command == "migrate-policy":
            data = migrate_policy(wiki)
            if args.write:
                write_batch(wiki, {POLICY: json_bytes(data)})
            else:
                sys.stdout.buffer.write(json_bytes(data))
        elif args.command == "policy-report":
            sys.stdout.buffer.write(json_bytes({p: effective_protection(wiki, p) for p in wiki.pages()}))
        else:
            changes = split_history(wiki, args.page, args.heading, args.destination)
            if args.write:
                original_index = wiki.read("index.md").decode("utf-8")
                data = catalog(wiki, changes)
                changes.update({"catalog.json": json_bytes(data),
                                "index.md": generated_index(original_index, data).encode()})
                write_batch(wiki, changes)
            else:
                print(json.dumps({p: data.decode() for p, data in changes.items()}, ensure_ascii=False, indent=2))
        return 0
    except (WikiError, OSError, UnicodeError) as error:
        print(f"wiki: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
