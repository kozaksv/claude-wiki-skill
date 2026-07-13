# Presets

A **preset** is a named track set a project selects with `preset: <name>` in
`{wiki}/schema.md`. Built-in presets:

- **`karpathy`** (default when nothing is declared) — `concepts` / `entities` /
  `transcripts`.
- **`code-project`** — `guide` / `workflows` / `modules` (the `modules` track
  requires a `module:` field).

A preset file is JSON:

```json
{
  "name": "my-preset",
  "extends": "code-project",          // optional: merge parent tracks by `dir`
  "extractor": "my-extractor",        // optional: facts extractor entrypoint
  "signals": "my-signals",            // optional: ship-gate signal set
  "tracks": [
    {"dir": "modules", "type": "module", "requires": ["module"],
     "path_map": ["pkg/*"]}
  ]
}
```

## Extension points (project-provided, framework-specific)

The core ships **no** framework-specific code. A project that wants automatic
facts or ship-gate signals drops its own files here and references them by name
from its preset:

- **Extractor** → `presets/extractors/<name>.py`, exposing
  `extract_facts(component_dir) -> dict`. Used by `scripts/wiki_autogen.py` to
  fill the `WIKI-AUTOGEN` facts block for a component. Referenced via the
  preset's `extractor` field (or `--extractor <name>`). Without one, autogen is
  a no-op.
- **Signals** → `presets/signals/<name>.json`, of shape
  `{"signal_patterns": {"<category>": "<regex>"}, "noise_patterns": ["<regex>"]}`.
  Used by `scripts/ship_wiki_gap.py`. Referenced via the preset's `signals`
  field (or `--signals <file>`).

Names are confined to their directory (no `..` / absolute paths / separators).
`path_map` globs map changed source paths to the owning track (the `*` segment
is the component name).
