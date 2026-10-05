# Release A validation and review receipts

Scope: issues #7 and #8, integration of #9 under epic #6 r3.
This code does not implement release B or delete project instruction files.
**Code-review approval, deterministic regression, and native acceptance are
separate. Issue #9 remains open while required native evidence is incomplete.**

## Automated checks

```bash
python3 scripts/build_skill.py --check
python3 -m unittest discover -s tests -p 'test_*.py' -v
bash tests/skill-contracts.sh
bash tests/install-cross-agent-links.sh
bash tests/uninstall.sh
```

The standard workflow now runs these checks on Ubuntu and macOS. Tests use
synthetic repositories and temporary HOME directories, not the user's real
installation. Fixture roots are physically resolved to avoid comparing macOS
`/var` spelling with `/private/var`; intentional test symlinks remain intact.

`tests/test_release_a.py` covers inventory/preflight, same-level conflict,
nearest scope, Claude presence-only diagnostics and export retirement.
`tests/test_pr15_review.py` adds missing/outside-pointer normalization with a
strict resolver, directory symlink escapes, symlink-plus-parent traversal,
validated physical aliases, safe canonical-link recovery instructions and
the agy binary-ingest example. Existing protection and uninstall suites remain.

The follow-up source candidate `1bd556fe553250481e8d8b5b8010cbfeae1b88e6`
(tree `0e47af763007c47a4fda2e04dbb4fd188351a9e3`) passed all five commands on
[Ubuntu](https://github.com/kozaksv/claude-wiki-skill/actions/runs/37313980008/job/111776030705)
and [macOS](https://github.com/kozaksv/claude-wiki-skill/actions/runs/37313980008/job/111776030753).
The macOS log records 93 Python tests, `OK (skipped=1)` (the case-collision
fixture requires a case-sensitive filesystem), and 495 passing hook assertions.
The skip is platform-specific, not a disabled failing test; Ubuntu covers the
case-sensitive fixture. These links identify the tested source candidate;
the final PR workflow also runs on the final commit/merge candidate.
Temporary preparation scripts/workflows are not part of the PR tree/history.

## Native reviewer receipts — original commit `9737036`

Source: [review and native receipts](https://github.com/kozaksv/claude-wiki-skill/pull/15#issuecomment-5994628035),
2026-10-05. The reviewer found no code blockers and reported the runs below.
They are reviewer-observed runs on the original PR commit, not native reruns
by the editing agent and not blanket validation of subsequent commits.
The reviewer's real HOME was not changed.

| Surface | Observed evidence | Remaining acceptance work |
|---|---|---|
| Claude Code | Root/nested AGENTS with tools disabled; local-blocker control; compact; wiki query using PR skill and PR hook passed | `/memory` interactive view was not run; behavioral evidence is recorded, not a fabricated UI receipt |
| Codex | Root/nested and fallback control passed | Wiki query used the global **master** skill; rerun with the PR skill for #9 |
| agy CLI | Root/nested and wiki query using workspace PR skill passed | Global CLI skill loading was not run; temporary-HOME filesystem checks are not equivalent |
| Qwen Code | No completed model runs | API 403 `Access to model denied`; wiki query and duplicate-registration check remain unverified |
| ChatGPT/GitHub | Seven portable discovery scenarios exercised through the connected GitHub tools | See the separate bounded [connector receipt](release-a-github-receipt.md); this does not validate native CLI sessions |

A CI pass is not a receipt for Claude, Codex, Qwen or agy model sessions.
Do not close #9 until the required runs have passing evidence on the reviewed
implementation. Changes relevant to a native scenario require an appropriate
retest; retaining old receipts does not silently make them current.

## How to complete native acceptance

Use synthetic repositories and a separate test HOME, without modifying real
instructions, credentials or private context. Test AGENTS-only first without
prompting the model to read the file. Check the host loading view (`/memory`
for Claude AGENTS; `/context` for rules) where available and record actual
behavior. A described CLI version is test-environment metadata, not a product
version probe or gate. Do not post credentials or private rules in receipts.

For every required run record the commit, CLI, skill path/version actually
used, cwd/scenario, command or interaction, observed result, and pass/fail/
not-run. In particular, distinguish the PR skill from a pre-existing global
master installation, and agy workspace skill discovery from global discovery.
An API/account failure remains an infrastructure-blocked run, not a product
pass or proof of a product bug.

The portable connector scenario receipt is separate from native loading and
from local CI. Missing native evidence leaves release acceptance pending even
when code review, deterministic regressions and connector scenarios pass.
