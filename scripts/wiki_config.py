#!/usr/bin/env python3
"""Track configuration loader for the wiki skill — stdlib only, no pyyaml.

A project declares its documentation tracks in `{wiki}/schema.md` frontmatter:
  preset: <name>      # built-in set from presets/<name>.json, OR
  tracks:             # inline list (mutually exclusive with preset)
    - dir: guide
      type: guide
Neither -> default preset `karpathy`. Declaring both -> ConfigError.

A track is {dir, type, requires:[...], path_map:[...]}. Presets may `extends`
another preset (parent tracks merged by `dir`; child overrides same `dir`).
Preset names are confined to presets/ (no separators / `..`). Track `dir`/`type`
must each be a single safe segment, and `dir` values must be unique.
"""
import json
import os
import re

PRESETS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "presets")
DEFAULT_PRESET = "karpathy"
_SAFE_NAME_RE = re.compile(r"^[a-z0-9][a-z0-9_-]*$")
_SAFE_SEG_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]*$")  # dir/type: single safe segment
_INLINE_LIST_RE = re.compile(r"^\[(.*)\]$")


class ConfigError(Exception):
    pass


def _normalize_track(raw):
    if not isinstance(raw, dict) or not raw.get("dir") or not raw.get("type"):
        raise ConfigError("track needs non-empty 'dir' and 'type': %r" % (raw,))
    d, ty = str(raw["dir"]).strip(), str(raw["type"]).strip()
    if not _SAFE_SEG_RE.match(d):
        raise ConfigError("invalid track 'dir' (no /, .., abs paths): %r" % d)
    if not _SAFE_SEG_RE.match(ty):
        raise ConfigError("invalid track 'type': %r" % ty)
    t = dict(raw)  # preserve extra keys (e.g. a per-track 'extractor')
    t["dir"] = d
    t["type"] = ty
    t["requires"] = [str(x).strip() for x in (raw.get("requires") or [])]
    t["path_map"] = [str(x).strip() for x in (raw.get("path_map") or [])]
    return t


def _ensure_unique_dirs(tracks):
    seen = set()
    for t in tracks:
        if t["dir"] in seen:
            raise ConfigError("duplicate track 'dir': %r" % t["dir"])
        seen.add(t["dir"])
    return tracks


def _merge_tracks(parent, child):
    by_dir = {t["dir"]: t for t in parent}
    for t in child:
        by_dir[t["dir"]] = t
    return list(by_dir.values())


def _within(root, path):
    root = os.path.normpath(root)
    path = os.path.normpath(path)
    return path == root or path.startswith(root + os.sep)


def _read_preset_json(name):
    if not _SAFE_NAME_RE.match(name or ""):
        raise ConfigError("unsafe preset name: %r" % (name,))
    path = os.path.normpath(os.path.join(PRESETS_DIR, name + ".json"))
    if not _within(PRESETS_DIR, path) or not os.path.isfile(path):
        raise ConfigError("unknown preset: %r" % name)
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def _load_preset(name, _seen=None):
    _seen = _seen or set()
    if name in _seen:
        raise ConfigError("preset extends cycle at %r" % name)
    _seen.add(name)
    data = _read_preset_json(name)
    tracks = [_normalize_track(t) for t in data.get("tracks", [])]
    parent_name = data.get("extends")
    if parent_name:
        tracks = _merge_tracks(_load_preset(parent_name, _seen), tracks)
    return _ensure_unique_dirs(tracks)


def _read_schema_lines(wiki_dir):
    schema = os.path.join(wiki_dir, "schema.md")
    if not os.path.isfile(schema):
        return []
    with open(schema, encoding="utf-8") as fh:
        text = fh.read()
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return []
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return lines[1:i]
    return []


def _inline_scalar(val):
    val = val.strip()
    m = _INLINE_LIST_RE.match(val)
    if m:
        inner = m.group(1).strip()
        if not inner:
            return []
        return [x.strip().strip('"').strip("'") for x in inner.split(",")]
    return val.strip('"').strip("'")


def _parse_inline_tracks(fm_lines):
    """Parse a constrained `tracks:` block: a list of `- key: value` dicts with
    scalar or inline-list values. Indentation-based; a column-0 key ends it."""
    tracks, cur, in_block = [], None, False
    for ln in fm_lines:
        if re.match(r"^tracks:\s*$", ln):
            in_block = True
            continue
        if not in_block:
            continue
        if ln.strip() and not ln.startswith(" "):
            break  # frontmatter key at column 0 ends the block
        item = re.match(r"^\s*-\s*(\w+):\s*(.*)$", ln)
        if item:
            if cur is not None:
                tracks.append(cur)
            cur = {item.group(1): _inline_scalar(item.group(2))}
            continue
        kv = re.match(r"^\s+(\w+):\s*(.*)$", ln)
        if kv and cur is not None:
            cur[kv.group(1)] = _inline_scalar(kv.group(2))
    if cur is not None:
        tracks.append(cur)
    return [_normalize_track(t) for t in tracks]


def load_config(wiki_dir):
    """Resolve the full track config from {wiki}/schema.md. Returns:
      {'preset': name|None, 'tracks': [track,...],
       'extractor': str|None, 'signals': str|None}
    'extractor'/'signals' are entrypoint names declared at the top level of a
    preset file (None for inline or default). Consumers (autogen/ship-gate)
    resolve those entrypoints within their own confined directories.
    """
    fm_lines = _read_schema_lines(wiki_dir)
    preset = None
    has_tracks_block = False
    for ln in fm_lines:
        m = re.match(r"^preset:\s*(.+)$", ln)
        if m:
            preset = _inline_scalar(m.group(1))
        if re.match(r"^tracks:\s*$", ln):
            has_tracks_block = True
    if preset and has_tracks_block:
        raise ConfigError("declare either 'preset' or 'tracks', not both")
    if preset:
        data = _read_preset_json(preset)
        return {"preset": preset, "tracks": _load_preset(preset),
                "extractor": data.get("extractor"), "signals": data.get("signals")}
    if has_tracks_block:
        tracks = _parse_inline_tracks(fm_lines)
        if not tracks:
            raise ConfigError("empty 'tracks' block")
        return {"preset": None, "tracks": _ensure_unique_dirs(tracks),
                "extractor": None, "signals": None}
    return {"preset": DEFAULT_PRESET, "tracks": _load_preset(DEFAULT_PRESET),
            "extractor": None, "signals": None}


def load_tracks(wiki_dir):
    return load_config(wiki_dir)["tracks"]
