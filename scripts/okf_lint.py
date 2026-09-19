#!/usr/bin/env python3
"""OKF bundle validator — stdlib only, deterministic (no pyyaml).

Tracks are loaded from {wiki}/schema.md via wiki_config (preset/inline/default
karpathy). The directory<->type binding and required-field rules are derived
from that config, not hardcoded.

Usage: okf_lint.py <wiki_dir>
Exit 0 valid, 1 violations (one per line), 2 usage/config error.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wiki_config

RESERVED = {"index.md", "log.md"}
_LINK_RE = re.compile(r'\[[^\]]*\]\(([^)]+)\)')
_WIKILINK_RE = re.compile(r'\[\[[^\]]+\]\]')
_CITATIONS_RE = re.compile(r'^#+\s*Citations\s*$', re.IGNORECASE)
_URL_RE = re.compile(r'^[a-z][a-z0-9+.-]*://')


def parse_frontmatter(text):
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return None, text
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end is None:
        return None, text
    fm = {}
    for ln in lines[1:end]:
        if ":" in ln:
            key, _, val = ln.partition(":")
            fm[key.strip()] = val.strip()
    return fm, "\n".join(lines[end + 1:])


def strip_citations(body):
    out = []
    for ln in body.split("\n"):
        if _CITATIONS_RE.match(ln.strip()):
            break
        out.append(ln)
    return "\n".join(out)


def _within(root, path):
    root = os.path.normpath(root)
    path = os.path.normpath(path)
    return path == root or path.startswith(root + os.sep)


def check_bundle(root, tracks):
    violations = []
    track_types = {t["dir"]: t["type"] for t in tracks}
    requires_map = {t["dir"]: t["requires"] for t in tracks}
    owned_fields = {f for t in tracks for f in t["requires"]}

    for reserved in ("index.md", "log.md"):
        if not os.path.isfile(os.path.join(root, reserved)):
            violations.append("missing root %s" % reserved)

    md_files = []
    for dirpath, _dirs, files in os.walk(root):
        for f in files:
            if f.endswith(".md"):
                md_files.append(os.path.join(dirpath, f))

    for path in sorted(md_files):
        rel = os.path.relpath(path, root)
        name = os.path.basename(path)
        reserved = name in RESERVED
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        fm, body = parse_frontmatter(text)

        if reserved:
            content = text
        else:
            if fm is None or not fm.get("type"):
                violations.append("%s: missing or empty 'type' in frontmatter" % rel)
            content = body if fm is not None else text

            parts = rel.split(os.sep)
            top = parts[0]
            if len(parts) == 1:
                if name != "schema.md":
                    violations.append(
                        "%s: root markdown not allowed outside tracks" % rel)
            elif top in track_types:
                expected = track_types[top]
                if fm is not None and fm.get("type") and fm.get("type") != expected:
                    violations.append(
                        "%s: type '%s' under %s/ must be '%s'"
                        % (rel, fm.get("type"), top, expected))
                for req in requires_map.get(top, []):
                    if fm is None or not fm.get(req):
                        violations.append(
                            "%s: %s page requires non-empty '%s:' field"
                            % (rel, top, req))
                for leaked in owned_fields - set(requires_map.get(top, [])):
                    if fm is not None and fm.get(leaked):
                        violations.append(
                            "%s: field '%s:' not allowed under %s/" % (rel, leaked, top))
            else:
                allowed = "/".join(sorted(track_types)) or "(no tracks)"
                violations.append(
                    "%s: page must live under a configured track (%s)" % (rel, allowed))

        checkable = strip_citations(content)
        if not reserved and _WIKILINK_RE.search(checkable):
            violations.append(
                "%s: wikilink [[ ]] not allowed in body (use markdown links)" % rel)
        for target in _LINK_RE.findall(checkable):
            t = target.split("#", 1)[0].strip()
            if not t or _URL_RE.match(t):
                continue
            resolved = (os.path.join(root, t.lstrip("/")) if t.startswith("/")
                        else os.path.join(os.path.dirname(path), t))
            if not _within(root, resolved):
                violations.append("%s: nav link escapes bundle: %s" % (rel, target))
            elif not os.path.exists(resolved):
                violations.append("%s: broken internal link: %s" % (rel, target))

    return violations


def main(argv):
    if len(argv) != 2:
        sys.stderr.write("usage: okf_lint.py <wiki_dir>\n")
        return 2
    root = argv[1]
    if not os.path.isdir(root):
        sys.stderr.write("not a directory: %s\n" % root)
        return 2
    try:
        tracks = wiki_config.load_tracks(root)
    except wiki_config.ConfigError as e:
        sys.stderr.write("config error: %s\n" % e)
        return 2
    violations = check_bundle(root, tracks)
    for v in violations:
        print(v)
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
