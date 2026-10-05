# Release A — GitHub connector discovery receipt

Date: 2026-10-05. Surface: ChatGPT with the connected GitHub tools.
Scope: the seven portable cases in `references/discovery-cases.json`, source
commit `973703640942a4c6a7a9fde8ba31baa2b48e8187`, cases blob
`9f948fd35cb5b40c50e407824af6238f8135b34b`.
The agent loaded that commit's `skills/wiki-github/SKILL.md` and shared reader
contract, then performed actual tree and file reads through the connector.
Those contracts/cases are unchanged by the portability follow-up.

## Method and limits

Each case was prepared as an isolated Git commit object containing the case's
exact files at repository root, not as a nested fixture inside another wiki.
No branch was pointed at these fixture commits, and they are not PR changes.
`canonical-fallback` adds only an empty `src/.gitkeep` so Git can represent the
requested empty starting directory. All other files match the source cases.
Preparation writes created synthetic objects; the subsequent **query phases
used only GET/tree/file reads**. No fixture content, branch ref, user wiki,
telemetry, instruction file or real HOME was changed by those query phases.

For each snapshot the agent read the complete recursive tree (all returned
`truncated: false`), inspected exact filename case, fetched the relevant
instruction files, and fetched the complete selected index. All schemas are
absent in these minimal fixtures; this is not treated as permission to migrate.
For same-level conflict, both indexes were read to validate both candidates;
no write tool was invoked. Ancestor reads in the nested case were diagnostic,
not a reason to override the nearer scope.

This is a maintainer-operated, non-blind scenario exercise in one conversation:
the expected outcomes were visible and the same agent prepared the fixtures.
It is evidence of actual connector access and application of the reader
contract, **not** a deterministic CI execution of prose, an independent blind
model evaluation, a guarantee for future model responses, or a release-B
remote deletion/validator test. No filesystem discovery executable supplied
the observed selections.

## Observed results

Snapshot links provide the exact read inputs; `.` means repository root.
All seven observed selected paths and conflict flags match the normative cases.

| Case / snapshot | Start | Files read after complete tree listing | Observed result |
|---|---|---|---|
| [canonical-fallback](https://github.com/kozaksv/claude-wiki-skill/tree/edbc37dae6abd5dc9f6f7ae9096a5335d1d19a10) | `src` | `docs/wiki/index.md`; tree proves no root/src pointers | PASS: `docs/wiki`, conflict=false |
| [stale-canonical](https://github.com/kozaksv/claude-wiki-skill/tree/ae42fdb694ddce76ba569f18a5c43f715b64845a) | `.` | `AGENTS.md`, `CLAUDE.md`, `knowledge/index.md`; tree proves `missing` absent | PASS: `knowledge`, conflict=false; stale canonical did not hide valid legacy |
| [same-level](https://github.com/kozaksv/claude-wiki-skill/tree/132e8db3eca0728fee5d9025654e6fa4771d3390) | `.` | `AGENTS.md`, `CLAUDE.md`, `one/index.md`, `two/index.md` | PASS: named read selection `one`, conflict=true; `two` also valid, no unaddressed writes |
| [nested](https://github.com/kozaksv/claude-wiki-skill/tree/2e8ca32b96ae66c9d06ff6cffbd8a14475a9fb4c) | `component` | `component/AGENTS.md`, `component/wiki/index.md`; diagnostic root `CLAUDE.md` and `one/index.md` | PASS: `component/wiki`, conflict=false; ancestor difference only a warning |
| [same-wiki](https://github.com/kozaksv/claude-wiki-skill/tree/37243806d401d98518c83c2e9e20ed86db693420) | `.` | `AGENTS.md`, `CLAUDE.md`, `knowledge/index.md` | PASS: `knowledge`, conflict=false; schema/index pointers identify one directory |
| [fenced](https://github.com/kozaksv/claude-wiki-skill/tree/c38ced1193ecef82ce18397680ce5c1f333cfc03) | `.` | `AGENTS.md`, `knowledge/index.md` | PASS: `knowledge`, conflict=false; example pointer in code fence ignored |
| [case](https://github.com/kozaksv/claude-wiki-skill/tree/b015ed85d2fda9f5d4a3d052b2b119d2067e5278) | `.` | `agents.md` for diagnosis; complete tree proves no canonical pointer or `docs/wiki` fallback | PASS: selected=null, conflict=false; lowercase filename not silently promoted |

The final case contains an existing noncanonical knowledge directory. A null
portable selection is a diagnostic outcome, **not** evidence of an empty repo
or authorization to create a second wiki. The same-level case likewise allows
only a named warned read until a user explicitly selects a write target.

These seven checks complete the bounded connector-discovery exercise. They do
not resolve Qwen's API failure, prove agy global loading, or replace the Codex
query with the actual PR skill. Overall issue #9 acceptance remains pending.
