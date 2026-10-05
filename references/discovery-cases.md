# Portable discovery cases

Generated from `discovery-cases.json`; do not edit independently.

The local engine is tested in CI. GitHub-agent parity requires a separate
recorded connector run on these scenarios; a local pass is not that run.

| Case | Scenario | Selected wiki | Same-level conflict / no-write |
|---|---|---|---|
| canonical-fallback | No pointer; canonical wiki | `docs/wiki` | no |
| stale-canonical | Stale AGENTS does not hide valid legacy | `knowledge` | no |
| same-level | Two valid different wikis at selected level: no writes | `one` | yes |
| nested | Nearest subproject wins; ancestor mismatch is warning only | `component/wiki` | no |
| same-wiki | Schema/index pointers to same wiki are not conflict | `knowledge` | no |
| fenced | Ignore example pointers inside fenced code | `knowledge` | no |
| case | Non-canonical filename is diagnostic, not a portable pointer | `absent` | no |
