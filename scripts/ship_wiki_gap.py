#!/usr/bin/env python3
"""Detect undocumented "ship signals" in a diff and bucket them against the wiki.

A ship signal is a change that usually deserves a wiki note. Which changes count
is NOT hardcoded here — the signal/noise regexes live in a signals preset
(``presets/signals/<name>.json``) selected by the wiki's track config, and the
mapping from a changed path to a candidate wiki page comes from each track's
``path_map`` globs. This framework carries no project-specific regex literals.

For every signal the detector finds candidate wiki pages that already mention the
area and buckets the signal:
  - GAP          — no page references the area (decision needed: write/waiver).
  - NEEDS-REVIEW — a page references it, but adequacy is a human call.

The detector only finds signals and candidates; it never judges page quality.

Usage:
  ship_wiki_gap.py --diff-file FILE --wiki DIR [--signals FILE] [--gaps-only]
  ship_wiki_gap.py --git [--repo DIR] --wiki DIR [--signals FILE] [--gaps-only]

Exit 0 = nothing to block on (ship may proceed), 1 = blocking signal(s) found
(gate MUST stop and prompt), 2 = usage/config/runtime error (FAIL-CLOSED — never
silently 0 on bad input).

CALLER CONTRACT: this detector only reports; it cannot stop a ship on its own.
The invoker (a /ship step, pre-push hook, or CI job) MUST treat a non-zero exit
as a hard stop — `ship_wiki_gap.py ... || exit 1`. A caller that ignores the exit
code defeats the gate. See references/ship-gate.md for ready-to-paste examples.

By default ANY signal (GAP or NEEDS-REVIEW) yields exit 1. With --gaps-only only
true GAPs block; NEEDS-REVIEW is printed but advisory (exit 0).

Signals config shape (JSON):
  {"signal_patterns": {"<category>": "<regex>"}, "noise_patterns": ["<regex>"]}
A ``--signals FILE`` argument overrides config and is read as a literal path.
Otherwise the signals entrypoint name from ``wiki_config.load_config(wiki)`` is
resolved to ``presets/signals/<name>.json`` with a SAFE name confined to that
directory. A *declared but unresolvable* entrypoint is fatal (exit 2); a wiki
that simply declares no signals (e.g. the default preset) has nothing to detect
and exits 0.
"""
import argparse
import fnmatch
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wiki_config

SIGNALS_DIR = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "presets", "signals")
_SAFE_NAME_RE = re.compile(r"^[a-z0-9][a-z0-9_-]*$")

PLUS_FILE_RE = re.compile(r"^\+\+\+ b/(.+)$")
DIFF_HEADER_RE = re.compile(r"^diff --git ")


class GateError(Exception):
    """Fatal configuration/usage error — caller maps this to exit 2."""


# --------------------------------------------------------------------------- #
# Signals preset resolution (patterns live in config, not in this file).
# --------------------------------------------------------------------------- #
def _within(root, path):
    root = os.path.normpath(root)
    path = os.path.normpath(path)
    return path == root or path.startswith(root + os.sep)


def _resolve_signals_path(name):
    """Resolve a signals entrypoint NAME to presets/signals/<name>.json.

    SAFE name only (^[a-z0-9][a-z0-9_-]*$): no separators, no ``..``, no abs
    paths. Confined to SIGNALS_DIR. Raises GateError otherwise (fail-closed)."""
    if not _SAFE_NAME_RE.match(name or ""):
        raise GateError("unsafe signals entrypoint name: %r" % (name,))
    path = os.path.normpath(os.path.join(SIGNALS_DIR, name + ".json"))
    if not _within(SIGNALS_DIR, path) or not os.path.isfile(path):
        raise GateError("unknown signals entrypoint: %r" % (name,))
    return path


def _compile_signals(data):
    """Validate + compile a signals dict into (signal_patterns, noise_patterns).

    ``signal_patterns`` -> [(category, compiled_regex)]; ``noise_patterns`` ->
    [compiled_regex]. Any structural or regex error is fatal (fail-closed)."""
    if not isinstance(data, dict):
        raise GateError("signals config must be a JSON object")
    raw_sig = data.get("signal_patterns", {})
    raw_noise = data.get("noise_patterns", [])
    if not isinstance(raw_sig, dict):
        raise GateError("'signal_patterns' must be an object of category->regex")
    if not isinstance(raw_noise, list):
        raise GateError("'noise_patterns' must be a list of regex strings")
    signals = []
    for category, pattern in raw_sig.items():
        if not isinstance(pattern, str):
            raise GateError("signal pattern for %r must be a string" % (category,))
        try:
            signals.append((str(category), re.compile(pattern)))
        except re.error as exc:
            raise GateError("bad signal regex for %r: %s" % (category, exc))
    noise = []
    for pattern in raw_noise:
        if not isinstance(pattern, str):
            raise GateError("noise pattern must be a string: %r" % (pattern,))
        try:
            noise.append(re.compile(pattern))
        except re.error as exc:
            raise GateError("bad noise regex %r: %s" % (pattern, exc))
    return signals, noise


def load_signals(wiki_dir, override_path=None):
    """Return (signal_patterns, noise_patterns) or (None, None) when no signals
    are declared at all.

    ``override_path`` (``--signals FILE``) is read as a literal path. Otherwise
    the entrypoint name from the wiki track config is resolved within
    SIGNALS_DIR. A declared-but-unresolvable entrypoint, unreadable/invalid file
    or bad regex is fatal (GateError). A wiki that declares NO signals returns
    (None, None): there is simply nothing to detect."""
    if override_path is not None:
        path = override_path
    else:
        cfg = wiki_config.load_config(wiki_dir)  # ConfigError -> caller -> exit 2
        name = cfg.get("signals")
        if not name:
            return None, None
        path = _resolve_signals_path(name)
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except FileNotFoundError:
        raise GateError("signals file not found: %s" % path)
    except OSError as exc:
        raise GateError("cannot read signals file %s: %s" % (path, exc))
    except ValueError as exc:
        raise GateError("invalid JSON in signals file %s: %s" % (path, exc))
    return _compile_signals(data)


# --------------------------------------------------------------------------- #
# Diff splitting + path -> track mapping (path_map globs from track config).
# --------------------------------------------------------------------------- #
def _split_diff_by_file(diff_text):
    """Return {path: [added_content_lines]} from a unified diff."""
    files = {}
    cur = None
    for line in diff_text.split("\n"):
        if DIFF_HEADER_RE.match(line):
            cur = None
            continue
        m = PLUS_FILE_RE.match(line)
        if m:
            cur = m.group(1).strip()
            files.setdefault(cur, [])
            continue
        if cur is not None and line.startswith("+") and not line.startswith("+++"):
            files[cur].append(line[1:])
    return files


def _match_path_map(path, glob):
    """If ``glob`` (a path_map entry) matches ``path``, return the segment
    captured by the single ``*`` wildcard; else None.

    A glob ``pkg/*`` matches a changed path ``pkg/foo/models/x.py``
    by matching segment-for-segment against the path's leading segments; the
    component name is the path segment aligned with the ``*`` (``foo``). Globs
    without a ``*`` capture nothing (return "" on a positional match)."""
    gsegs = glob.strip("/").split("/")
    psegs = path.strip("/").split("/")
    if len(psegs) < len(gsegs):
        return None
    captured = ""
    for gseg, pseg in zip(gsegs, psegs):
        if gseg == "*":
            captured = pseg
        elif not fnmatch.fnmatch(pseg, gseg):
            return None
    return captured


def _track_for_path(path, tracks):
    """Return (track_dict, component_token) for the first track whose path_map
    matches ``path``; (None, None) if no track claims it."""
    for track in tracks:
        for glob in track.get("path_map", []):
            if not glob:
                continue
            token = _match_path_map(path, glob)
            if token is not None:
                return track, token
    return None, None


def _is_noise_path(path, noise_patterns):
    return any(p.search(path) for p in noise_patterns)


def _strip_noise_lines(added_lines, noise_patterns):
    """Drop added lines matching any noise pattern (e.g. a version-bump line)."""
    return [ln for ln in added_lines if not any(p.search(ln) for p in noise_patterns)]


def classify_diff(diff_text, signal_patterns, noise_patterns, tracks):
    """Return de-duplicated signals: list of
    {class, label, token, track, files}.

    For each changed file: skip noise paths; drop noise lines; match the remaining
    added text against each signal pattern. A match yields a signal whose track
    and component token come from the file's path_map track (when one claims it).
    Signals are de-duplicated by (category, token-or-path)."""
    merged = {}
    for path, added in _split_diff_by_file(diff_text).items():
        if _is_noise_path(path, noise_patterns):
            continue
        kept = _strip_noise_lines(added, noise_patterns)
        text = "\n".join(kept)
        if not text.strip():
            continue
        track, token = _track_for_path(path, tracks)
        track_dir = track["dir"] if track else ""
        # label: the component when a track claims the path, else the basename.
        label = token or os.path.basename(path)
        token = token or ""
        for category, pattern in signal_patterns:
            if not pattern.search(text):
                continue
            key = (category, token or path)
            entry = merged.setdefault(
                key, {"class": category, "label": label, "token": token,
                      "track": track_dir, "files": []})
            if path not in entry["files"]:
                entry["files"].append(path)
    return list(merged.values())


# --------------------------------------------------------------------------- #
# Coverage / bucketing (preserved from the original, track-aware).
# --------------------------------------------------------------------------- #
FRONTMATTER_RE = re.compile(r"^\s*---\s*\n(.*?)\n---\s*\n", re.DOTALL)
FM_TYPE_RE = re.compile(r"^\s*type\s*:\s*(.+?)\s*$", re.MULTILINE)
FM_MODULE_RE = re.compile(r"^\s*module\s*:\s*(.+?)\s*$", re.MULTILINE)


def _parse_frontmatter(text):
    """Return (type, module, body) — frontmatter values lowercased (or None) and
    the body after the leading ``--- ... ---`` block."""
    m = FRONTMATTER_RE.match(text)
    if not m:
        return None, None, text
    block = m.group(1)
    t = FM_TYPE_RE.search(block)
    mod = FM_MODULE_RE.search(block)
    body = text[m.end():]

    def _clean(v):
        if v is None:
            return None
        return v.group(1).strip().strip("'\"").lower() or None

    return _clean(t), _clean(mod), body


def _track_of(rel):
    """Top-level track directory of a wiki-relative page path, or '' for root."""
    parts = rel.replace("\\", "/").split("/")
    return parts[0] if len(parts) > 1 else ""


def _normalize(s):
    """Lowercase; treat '-', '_', '/' as equivalent (collapse to spaces)."""
    return re.sub(r"[-_/]+", " ", s.lower())


def _word_match(token, text):
    """True if the normalized token appears as whole word(s) in the normalized
    text. ``\\b`` boundaries stop short tokens (``ship``) from matching inside a
    larger word (``shipment`` / ``relationship``)."""
    ntoken = _normalize(token).strip()
    if not ntoken:
        return False
    pattern = r"\b" + re.escape(ntoken) + r"\b"
    return re.search(pattern, _normalize(text)) is not None


def _wiki_pages(wiki_dir):
    """Return list of {rel, track, type, module, body} for every wiki .md page.

    ``body`` is the page text with frontmatter stripped, lowercased — coverage
    matching runs against the body so frontmatter tokens never count."""
    pages = []
    for dirpath, _dirs, files in os.walk(wiki_dir):
        for f in files:
            if not f.endswith(".md"):
                continue
            p = os.path.join(dirpath, f)
            try:
                with open(p, encoding="utf-8") as fh:
                    raw = fh.read()
            except Exception:
                continue
            rel = os.path.relpath(p, wiki_dir)
            ptype, pmod, body = _parse_frontmatter(raw)
            pages.append({
                "rel": rel.replace("\\", "/"),
                "track": _track_of(rel),
                "type": ptype,
                "module": pmod,
                "body": body.lower(),
            })
    return pages


def find_coverage(signals, wiki_dir, tracks):
    """Bucket each signal track-aware: coverage only counts on the signal's own
    track.

    - A ``requires: [module]`` track (e.g. modules/): a page on that track with
      ``type: <track type>`` + ``module: <token>`` whose body also mentions the
      module. Mentions on other tracks do NOT count.
    - Any other track: a page on that track whose normalized body contains the
      normalized token. Pages off the track do NOT count.
    A signal whose path matched no track has no candidate page (always GAP)."""
    pages = _wiki_pages(wiki_dir)
    by_dir = {t["dir"]: t for t in tracks}
    for s in signals:
        token = s["token"].lower()
        track_dir = s.get("track", "")
        track = by_dir.get(track_dir)
        if not token or track is None:
            s["pages"] = []
        elif "module" in track.get("requires", []):
            ttype = track["type"]
            s["pages"] = sorted(
                pg["rel"] for pg in pages
                if pg["track"] == track_dir
                and pg["type"] == ttype
                and pg["module"] == token
                and token in pg["body"])
        else:
            s["pages"] = sorted(
                pg["rel"] for pg in pages
                if pg["track"] == track_dir
                and _word_match(token, pg["body"]))
        s["bucket"] = "NEEDS-REVIEW" if s["pages"] else "GAP"
    return signals


# --------------------------------------------------------------------------- #
# Git diff collection (best-effort) + rendering.
# --------------------------------------------------------------------------- #
def _run(cmd, repo):
    try:
        return subprocess.run(cmd, cwd=repo, capture_output=True, text=True).stdout
    except Exception:
        return ""


def collect_git_diff(repo):
    """Prospective PR diff: merge-base(origin/main)->HEAD + staged + unstaged +
    untracked. Each layer is best-effort so the gate still runs without a remote."""
    parts = []
    base = _run(["git", "merge-base", "origin/main", "HEAD"], repo).strip()
    if base:
        parts.append(_run(["git", "diff", base + "..HEAD"], repo))
    parts.append(_run(["git", "diff", "--cached"], repo))
    parts.append(_run(["git", "diff"], repo))
    untracked = _run(["git", "ls-files", "--others", "--exclude-standard"], repo)
    for rel in untracked.split("\n"):
        rel = rel.strip()
        if rel:
            parts.append(_run(["git", "diff", "--no-index", "/dev/null", rel], repo))
    return "\n".join(parts)


def render(signals):
    lines = []
    gaps = sum(1 for s in signals if s["bucket"] == "GAP")
    needs = sum(1 for s in signals if s["bucket"] == "NEEDS-REVIEW")
    for s in signals:
        line = "%s | %s | %s | file: %s" % (
            s["bucket"], s["class"], s["label"], ", ".join(s["files"]))
        if s["pages"]:
            line += " | pages: " + ", ".join(s["pages"])
        lines.append(line)
    lines.append("SUMMARY signals=%d gaps=%d needs_review=%d"
                 % (len(signals), gaps, needs))
    return "\n".join(lines)


def main(argv):
    parser = argparse.ArgumentParser()
    src = parser.add_mutually_exclusive_group(required=True)
    src.add_argument("--diff-file")
    src.add_argument("--git", action="store_true")
    parser.add_argument("--repo", default=".")
    parser.add_argument("--wiki", required=True)
    parser.add_argument("--signals", help="override signals JSON file (literal path)")
    parser.add_argument(
        "--gaps-only", action="store_true",
        help="exit 1 only on true GAPs; bucket NEEDS-REVIEW as advisory (exit 0). "
             "Lets a caller block on hard misses while only warning on soft ones.")
    args = parser.parse_args(argv[1:])

    # Resolve patterns first so a bad/unknown signals entrypoint fails CLOSED
    # before we even read the diff (never silently exit 0).
    try:
        signal_patterns, noise_patterns = load_signals(args.wiki, args.signals)
        tracks = wiki_config.load_tracks(args.wiki)
    except wiki_config.ConfigError as exc:
        sys.stderr.write("config error: %s\n" % exc)
        return 2
    except GateError as exc:
        sys.stderr.write("signals error: %s\n" % exc)
        return 2

    if args.diff_file:
        try:
            with open(args.diff_file, encoding="utf-8") as fh:
                diff_text = fh.read()
        except Exception as exc:
            sys.stderr.write("cannot read diff: %s\n" % exc)
            return 2
    else:
        diff_text = collect_git_diff(args.repo)

    if signal_patterns is None:
        # No signals declared for this wiki — nothing to detect, ship proceeds.
        print(render([]))
        return 0

    signals = classify_diff(diff_text, signal_patterns, noise_patterns, tracks)
    signals = find_coverage(signals, args.wiki, tracks)
    print(render(signals))
    if args.gaps_only:
        # Only hard GAPs block; NEEDS-REVIEW is advisory (printed, exit 0).
        return 1 if any(s["bucket"] == "GAP" for s in signals) else 0
    return 1 if signals else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
