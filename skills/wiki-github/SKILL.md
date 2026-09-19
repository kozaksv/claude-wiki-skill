---
name: wiki-github
description: >
  Read and maintain Markdown wikis in GitHub repositories through the
  connected GitHub tools in ChatGPT. Use for wiki/вікі questions, project
  architecture and setup, adding or correcting knowledge, editing pages,
  splitting history, protecting pages and saving direct commits or pull requests.
---

# Wiki via GitHub

Use [references/reader-core.md](references/reader-core.md) for all requests.
For an authorized change, also load
[references/writer-core.md](references/writer-core.md) and
[references/github-write.md](references/github-write.md). Read-only questions
must not trigger changes; requests to change the wiki should produce the
requested edit and deliver a direct commit or PR in the selected mode.

The skill installs independently with its bundled references and catalog
helper. GitHub supplies access; no shell, checkout, hooks, or PAT in chat is
needed to read or prepare ordinary edits. Scope: Markdown committed inside a
repository; the separate `owner/repo.wiki.git` service is different storage.

## Establish the Repository and Snapshot

1. Use the repository named by the user or unambiguously established for this
   task. If ambiguous, ask for `owner/repo`. Loading this skill from one repo
   does not select that repo as the target of the user's question.
2. Discover the GitHub tools exposed in this chat. Prefer direct file reads
   and directory/tree listing. Tool names differ across surfaces: `fetch_file`,
   `fetch`, and `search` below describe capabilities, not guaranteed names.
   A scratch filesystem does not imply that the target repo is checked out.
3. Get repository metadata to verify access and discover its default branch.
   Honor an explicitly requested branch/tag/commit; otherwise use that default.
   Resolve the selected ref to a **commit SHA** when supported and keep all
   reads for this answer at that commit. A file/blob SHA or tree SHA is not a
   commit SHA. If the tool cannot pin a commit, use its supported verified ref
   and disclose that the reads were not frozen to one snapshot.
4. Retain `(repository, ref, commit if known, wiki path, files read)` for this
   answer. A new request for current state needs a fresh ref check; discard
   cached discovery when the repo, ref, or relevant files change.

With tools like the current GitHub plugin, these operations can be expressed as:

- `fetch(https://api.github.com/repos/OWNER/REPO)` — metadata/default branch.
- `fetch(https://api.github.com/repos/OWNER/REPO/commits/REF)` — selected commit.
- `fetch_file(repository_full_name=OWNER/REPO, path=PATH, ref=COMMIT)` — file.
- `fetch(https://api.github.com/repos/OWNER/REPO/contents/PATH?ref=COMMIT)` —
  directory; a returned directory SHA can be used for a subtree listing.

Use the advertised tool schema and URL-encode ref/path components as needed.
Do not invent tool calls or fall back to an unauthenticated public URL to read
private repository content.

## Discover the Wiki

Start at the user-selected subdirectory, or repository root when none is
specified. The selected repository is the boundary; do not walk into sibling
repositories, local home directories, symlink targets, or submodules.

1. List the relevant directory and read existing agent instruction files:
   `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `QWEN.md`. Find the level-two
   `Wiki` / `Вікі` section, case-insensitive, including headings with suffixes.
   Resolve its path relative to that instruction file. A path ending in
   `schema.md` or `index.md` identifies the containing wiki directory.
2. Validate candidates by reading their `index.md`. Normalize relative paths
   inside the selected repository; reject absolute filesystem paths, URLs as
   local pointers, and paths escaping the repository. Continue past stale
   pointers. In a subdirectory, walk toward repository root only.
   Prefer a valid `AGENTS.md` pointer for ChatGPT at the nearest level; break
   remaining same-level ties in `CLAUDE.md`, `GEMINI.md`, `QWEN.md` order.
   An explicit user-selected wiki path takes precedence. Report conflicting
   valid wikis rather than combining their contents.
3. If no valid pointer is found, check `docs/wiki/index.md` relative to the
   nearest pointer-bearing directory, the selected directory, and repository
   root, de-duplicating those locations. Never create a second wiki.
4. Read the complete index and, if present, `schema.md`. Follow project-declared
   starting pages (for example, a strategy page) when relevant to the request.
   Schema v4 uses `concepts/`, `entities/`, and optional `transcripts/`.
   Missing or older schema metadata does not authorize a migration. Read
   intelligible Markdown and label uncertain schema interpretation. For a
   newer major, do not assume v4 semantics or claim full compatibility.

An absent `index.md` with existing wiki pages is a partial/unindexed wiki,
not an empty repository. If directory listing succeeds, read relevant pages
and state the limitation. If access fails, distinguish an unavailable read
from an absent path: authentication, permission, indexing, truncation, and
rate-limit errors are not proof that a file or wiki does not exist. If tools
cannot establish the path, ask for the exact path or supplied files.

## Query and Cite

Follow the shared reader contract. Read at the selected commit and use
clickable citations such as
`https://github.com/OWNER/REPO/blob/COMMIT/path/to/page.md`.
Use a verified branch/ref if commit pinning is unavailable. Encode paths and
refs correctly. Keep internal wikilinks unchanged in stored wiki pages.

The optional `catalog.json` is a path/range accelerator. Validate its membership
and blob IDs against a complete wiki subtree before relying on completeness.
Without a catalog, enumerate actual files and resolve unique basenames. Search
is a candidate finder and may cover only the default branch; re-read candidates
at the selected snapshot. A search excerpt is not a complete page read.

## Basic Status and Side Effects

Basic remote status reports the repo/ref, discovered wiki path, schema,
inventory coverage, and observed navigation gaps. Counts require a complete
listing; describe a limited sample as a sample. This is not the full local
`wiki status`/lint/cleanup workflow and does not verify every page's content.

Query and basic status are read-only: do not create `.usage.json`, increment
counters, synchronize agent files, install hooks, initialize git, migrate
schemas, edit the index, commit, or file an answer back automatically.
Gitignored per-clone telemetry and local `archive/` binaries normally cannot
be read through GitHub; their absence does not invalidate a wiki.

For changes, continue with `references/github-write.md`. Capability checks,
policy protection, snapshot conflict handling, diff verification and the
selected direct-commit/PR delivery mode apply. Do not invoke local migration, hook-installation or telemetry
flows merely because the user asked to update a page.
