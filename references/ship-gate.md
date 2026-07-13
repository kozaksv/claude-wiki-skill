# Ship gate — caller contract & enforcement

`scripts/ship_wiki_gap.py` inspects a diff for "ship signals" (changes that
usually deserve a wiki note) and buckets each against the wiki:

- **GAP** — no page references the area (a decision is needed: write or waive).
- **NEEDS-REVIEW** — a page references it, but adequacy is a human call.

The detector **only reports**. It cannot stop a ship by itself — closing the
"depends on the caller" gap is the invoker's job.

## Exit-code contract

| Exit | Meaning | Caller MUST |
|------|---------|-------------|
| `0`  | Nothing to block on | proceed |
| `1`  | Blocking signal(s) found | **stop and prompt** |
| `2`  | Usage/config/runtime error (fail-closed) | **stop** — never treat as "clean" |

A caller that ignores the exit code defeats the gate. Always chain it:

```sh
python3 scripts/ship_wiki_gap.py --git --wiki docs/wiki || exit 1
```

## Severity knob: `--gaps-only`

By default **any** signal (GAP or NEEDS-REVIEW) yields exit `1`. With
`--gaps-only`, only true **GAPs** block; NEEDS-REVIEW is printed but advisory
(exit `0`). Use it when you want hard misses to stop a ship while soft ones only
warn:

```sh
# Block only on undocumented areas; just warn on maybe-stale pages.
python3 scripts/ship_wiki_gap.py --git --wiki docs/wiki --gaps-only || exit 1
```

## Ready-to-paste: git pre-push hook

`.git/hooks/pre-push` (make it executable):

```sh
#!/usr/bin/env sh
# Block a push when changes lack wiki coverage. Exit 2 (config/runtime error)
# also blocks — fail-closed.
python3 scripts/ship_wiki_gap.py --git --wiki docs/wiki
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "wiki ship-gate: blocking push (exit $rc). Add a wiki note or waive." >&2
  exit 1
fi
```

## Ready-to-paste: CI step

```yaml
- name: Wiki ship-gate
  run: python3 scripts/ship_wiki_gap.py --git --wiki docs/wiki
  # A non-zero exit fails the job. Add --gaps-only to block on GAPs only.
```

A wiki that declares **no signals** (e.g. the default Karpathy preset) has
nothing to detect and always exits `0` — the gate is a safe no-op until a
project ships a signals preset (see `presets/README.md`).
