#!/usr/bin/env python3
"""wiki_autogen — deterministic, framework-neutral wiki autofill (stdlib only).

Given changed file paths, find each path's *owning track* (the first configured
track whose `path_map` glob matches), derive the component name (the segment
captured by the glob's `*`), run the configured *extractor* over that
component's directory and keep a delimited `WIKI-AUTOGEN` facts block current
inside `<track.dir>/<component>.md`.

The core is extractor-agnostic: it knows nothing about any specific framework.
It resolves an extractor NAME (from `--extractor` or the wiki's preset) to
`presets/extractors/<name>.py`, imports it and calls `extract_facts(dir) ->
dict`. The facts dict is rendered generically (label -> value); keys prefixed
with `_` are private scaffold hints, never rendered as facts.

Behaviour contract:
  * No extractor configured  -> COMPLETE NO-OP (no scaffold, no block, no index
    pointer).
  * Extractor returns `{}`    -> no-op for that component.
  * Otherwise: scaffold a valid OKF page of the track's type (including any
    track-`requires` fields) when missing; replace the block in place when
    present (curated prose outside the markers is preserved); add an `index.md`
    pointer once.

Fail-open: every error is swallowed and the process exits 0 so a broken parse
never blocks the agent or a hook.

Usage:
  wiki_autogen.py --src <repo_root> --wiki <wiki_dir>
                  [--paths p1 p2 ...] [--extractor <name>]
"""
from __future__ import annotations

import argparse
import datetime
import fnmatch
import importlib.util
import os
import re
import sys
from pathlib import Path

START_PREFIX = "<!-- WIKI-AUTOGEN:start"
START_MARK = (START_PREFIX
              + " згенеровано автоматично з коду — не редагувати вручну -->")
END_MARK = "<!-- WIKI-AUTOGEN:end -->"
_BLOCK_RE = re.compile(re.escape(START_PREFIX) + r".*?" + re.escape(END_MARK),
                       re.DOTALL)
_CITATIONS_RE = re.compile(r"^#+\s*Citations\s*$", re.IGNORECASE)
_SAFE_NAME_RE = re.compile(r"^[a-z0-9][a-z0-9_-]*$")

_EXTRACTORS_DIR = (Path(__file__).resolve().parent / ".." / "presets"
                   / "extractors").resolve()

# Make wiki_config importable whether run as a script or imported.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wiki_config  # noqa: E402


# --- extractor resolution ---------------------------------------------------
def load_extractor(name):
    """Resolve an extractor NAME to `presets/extractors/<name>.py`, import it
    and return the module (must expose `extract_facts`). Returns None for an
    unsafe/missing/broken extractor (fail-open)."""
    if not name or not _SAFE_NAME_RE.match(name):
        return None
    path = (_EXTRACTORS_DIR / (name + ".py")).resolve()
    # Confine to the extractors dir (no .. / abs / separators escaping).
    try:
        within = (path == _EXTRACTORS_DIR / (name + ".py"))
    except Exception:
        within = False
    if not within or not path.is_file():
        return None
    try:
        spec = importlib.util.spec_from_file_location(
            "_wiki_extractor_" + name, str(path))
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
    except Exception:
        return None
    if not hasattr(mod, "extract_facts"):
        return None
    return mod


# --- path -> (track, component) ---------------------------------------------
def _match_component(pattern, rel_path):
    """If `rel_path` is matched by glob `pattern` (which must contain a single
    `*`), return the path segment captured by the `*`. Otherwise None.

    e.g. pattern 'pkg/*' over 'pkg/foo/models/x.py' -> 'foo'.
    """
    pattern = pattern.strip().strip("/")
    rel = str(rel_path or "").strip().lstrip("/")
    if "*" not in pattern:
        return None
    prefix, _star, _suffix = pattern.partition("*")
    prefix = prefix.rstrip("/")
    parts = rel.split("/")
    pre_parts = [p for p in prefix.split("/") if p]
    # The literal prefix segments must match the head of the changed path.
    if len(parts) <= len(pre_parts):
        return None
    for a, b in zip(pre_parts, parts):
        if not fnmatch.fnmatch(b, a):
            return None
    return parts[len(pre_parts)] or None


def owning(tracks, rel_path):
    """Return (track, component) for the first track whose path_map matches the
    changed path, else (None, None)."""
    for track in tracks:
        for pattern in track.get("path_map") or []:
            comp = _match_component(pattern, rel_path)
            if comp:
                return track, comp
    return None, None


def targets_from_paths(tracks, paths):
    """Ordered unique (track, component) tuples from changed paths."""
    seen, out = set(), []
    for raw in paths or []:
        track, comp = owning(tracks, raw)
        if not track:
            continue
        key = (track["dir"], comp)
        if key in seen:
            continue
        seen.add(key)
        out.append((track, comp))
    return out


# --- rendering (generic, framework-neutral) ---------------------------------
def _render_value(value):
    if isinstance(value, (list, tuple, set)):
        return ", ".join("`%s`" % v for v in value)
    return "`%s`" % value


def _renderable_facts(facts):
    """Public (non-underscore) fact entries, preserving insertion order."""
    return [(k, v) for k, v in facts.items()
            if not str(k).startswith("_") and v not in (None, "", [], (), {})]


def render_block(facts):
    lines = [START_MARK, "## Факти (авто)", ""]
    for label, value in _renderable_facts(facts):
        lines.append("- **%s:** %s" % (label, _render_value(value)))
    lines += ["", END_MARK]
    return "\n".join(lines)


def _scaffold(track, component, facts, block):
    desc = (str(facts.get("_description") or "").strip()
            or ("Авто-сторінка: %s." % component))
    title = str(facts.get("_title") or "").strip() or component
    today = datetime.date.today().isoformat()
    fm = ["---", "type: %s" % track["type"]]
    # Include every track-required field. Convention: the field carrying the
    # component identifier (e.g. `module`) gets the component name; others get
    # the component too as a safe non-empty default the curator can refine.
    for req in track.get("requires") or []:
        fm.append("%s: %s" % (req, component))
    fm += [
        "title: %s" % title,
        "description: %s" % desc,
        "tags: [%s]" % component,
        "timestamp: %s" % today,
        "---",
    ]
    return "\n".join(fm + [
        "",
        "# %s" % title,
        "",
        "> TODO: опис призначення/ролі та підводних каменів — "
        "дописати прозою над авто-блоком.",
        "",
        block,
        "",
        "# Citations",
        "",
    ])


def update_page(wiki, track, component, facts):
    block = render_block(facts)
    page = wiki / track["dir"] / (component + ".md")
    if page.is_file():
        text = page.read_text(encoding="utf-8")
        if _BLOCK_RE.search(text):
            text = _BLOCK_RE.sub(lambda _m: block, text, count=1)
        else:
            out, inserted = [], False
            for ln in text.split("\n"):
                if not inserted and _CITATIONS_RE.match(ln.strip()):
                    out += [block, "", ln]
                    inserted = True
                else:
                    out.append(ln)
            if not inserted:
                out += ["", block, ""]
            text = "\n".join(out)
    else:
        page.parent.mkdir(parents=True, exist_ok=True)
        text = _scaffold(track, component, facts, block)
    page.write_text(text, encoding="utf-8")


def update_index(wiki, track, component, facts):
    index = wiki / "index.md"
    if not index.is_file():
        return
    text = index.read_text(encoding="utf-8")
    pointer = "](%s/%s.md)" % (track["dir"], component)
    if pointer in text:
        return
    desc = str(facts.get("_description") or "").strip() or "авто-сторінка"
    bullet = "- [%s](%s/%s.md) — %s." % (component, track["dir"],
                                         component, desc)
    text = text.rstrip() + "\n" + bullet + "\n"
    index.write_text(text, encoding="utf-8")


# --- driver -----------------------------------------------------------------
def run(src, wiki, paths, extractor_name=None):
    src, wiki = Path(src), Path(wiki)
    cfg = wiki_config.load_config(str(wiki))
    name = extractor_name or cfg.get("extractor")
    extractor = load_extractor(name) if name else None
    if extractor is None:
        # No extractor configured/resolvable -> complete no-op.
        return []

    tracks = cfg.get("tracks") or []
    written = []
    for track, component in targets_from_paths(tracks, paths):
        comp_dir = _component_dir(src, track, paths, component)
        if comp_dir is None or not comp_dir.is_dir():
            continue
        try:
            facts = extractor.extract_facts(str(comp_dir))
            if not isinstance(facts, dict) or not _renderable_facts(facts):
                continue
            update_page(wiki, track, component, facts)
            update_index(wiki, track, component, facts)
            written.append(component)
        except Exception:
            continue
    return written


def _component_dir(src, track, paths, component):
    """Resolve the component's source directory: the matched path's prefix +
    the component segment. Derived from the path_map prefix so it is not
    framework-specific."""
    for pattern in track.get("path_map") or []:
        prefix = pattern.strip().strip("/").partition("*")[0].rstrip("/")
        candidate = src / prefix / component if prefix else src / component
        if candidate.is_dir():
            return candidate
    return None


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--src", required=True)
    parser.add_argument("--wiki", required=True)
    parser.add_argument("--paths", nargs="*", default=[])
    parser.add_argument("--extractor", default=None)
    try:
        args = parser.parse_args(argv[1:])
        written = run(args.src, args.wiki, args.paths, args.extractor)
        if written:
            print("wiki_autogen: оновлено " + ", ".join(written))
    except SystemExit:
        raise
    except Exception:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
