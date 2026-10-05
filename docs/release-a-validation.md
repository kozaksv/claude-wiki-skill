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

## Reviewer receipts on `9737036` — 2026-10-05

Source: [review and native receipts](https://github.com/kozaksv/claude-wiki-skill/pull/15#issuecomment-5994628035).
The reviewer found no code blockers; these are reviewer-observed runs on the
original PR commit, not reruns by the editing agent and not blanket validation
of subsequent commits. The real HOME was not changed.

| Surface | Observed evidence | Remaining acceptance work |
|---|---|---|
| Claude | Root/nested AGENTS with tools disabled; local blocker control; compact; wiki query using PR skill and PR hook | `/memory` interactive view not run; behavioral evidence is recorded, not a fabricated UI receipt |
| Codex | Root/nested and fallback control passed | Wiki query used the global **master** skill; rerun with the PR skill for #9 |
| agy | Root/nested and wiki query using workspace PR skill passed | Global CLI export runtime not run; temporary-HOME filesystem check is not equivalent |
| Qwen | No completed model runs | API 403 `Access to model denied`; query and duplicate-skill check remain unverified |
| GitHub agent | Not run on the reviewer's stand | Connector scenario receipt still required |

The reviewer also reproduced macOS fixture path mismatches (`/var` versus
`/private/var`). The follow-up normalizes test fixture roots, makes missing
outside-pointer reasons independent of `realpath` behavior, preserves safe
physical aliases, and adds Ubuntu/macOS CI. Native model receipts remain
separate from these deterministic regression tests.
