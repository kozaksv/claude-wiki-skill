# Release A validation and review receipts

Scope: issues #7 and #8, integration of #9 under epic #6 r3.
This code does not implement release B or delete project instruction files.

## Automated checks

```bash
python3 scripts/build_skill.py --check
python3 -m unittest discover -s tests -p 'test_*.py' -v
bash tests/skill-contracts.sh
bash tests/install-cross-agent-links.sh
bash tests/uninstall.sh
```

`tests/test_release_a.py` checks the read-only inventory/preflight, same-level
conflict/no-write behavior, nearest subproject selection, case/fence/boundary
handling, Claude presence-only diagnostics and export/retirement safety.
Existing hook protection, settings-lock and uninstall tests remain in the suite.
Generated reader scenarios and export tables are checked on every change.

## Native and GitHub-agent acceptance — pending

These are review/acceptance instructions, not claims that a native session ran.
A CI pass is not a receipt for Claude, Codex, Qwen, agy or the ChatGPT connector.
Do not close issue #9 until all four CLI receipts and the separate GitHub-agent
receipt are present with passing results on the reviewed commit.

| Surface | Required evidence | Status in this source receipt |
|---|---|---|
| Claude Code | New root/nested sessions, AGENTS loading, wiki query, `/compact` | Not run |
| Codex | New root/nested sessions, fallback preservation, wiki query | Not run |
| Qwen Code | New sessions, wiki query, no duplicated skill registration | Not run |
| agy CLI | New sessions, global skill discovery, root/nested rules, wiki query | Not run |
| ChatGPT/GitHub | Connector reads against portable discovery cases, no writes | Not run |

Use synthetic repositories and a separate test HOME so real instructions,
credentials and private context are not changed or posted in receipts. Test
AGENTS-only first without prompting the model to read the file. Check the host
loading view (`/memory` for Claude AGENTS; `/context` for rules), not only the
model's assertion. Describe the actual CLI version in the receipt as test
environment metadata; the product does not probe or gate the Claude version.

Run the scenarios in `references/discovery-cases.json` through the GitHub
connector separately. Record repo/commit, returned source reads, chosen wiki
and conflict status. Local shell results do not prove remote-agent parity.

For each receipt record commit, surface, cwd/scenario, command or interaction,
observed result and pass/fail/not-run. Do not include private rules or credentials.
The release remains pending when required runs are missing, even when code
review and all automated checks have passed.
