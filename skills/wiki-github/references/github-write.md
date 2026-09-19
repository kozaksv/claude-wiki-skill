# GitHub Write Adapter

Load [writer-core.md](writer-core.md) for an authorized wiki change. Continue
using the repository, wiki path and commit established by `SKILL.md`.

## Capabilities

Discover the connected tools for exact file reads, tree/commit creation,
branch creation/update and pull requests. Use advertised schemas; do not
assume every ChatGPT GitHub connection grants write access. Never ask for a
PAT in chat. If the connection is read-only, still prepare a concrete patch
and explain that publishing it requires a write-capable GitHub connection.
The presence of this skill cannot grant repository permissions.

An available execution environment can stage files and run the bundled
catalog helper; it is optional for ordinary file edits. Prefer a checkout
when available. Otherwise materialize only the wiki at the selected snapshot,
ensuring a complete tree and complete contents for catalog regeneration.
Do not claim a scratch copy is the user's checkout.

## Choose delivery

Use direct mode when the user asks to commit/push to a named branch without a
PR, or has established that preference for this project. Use PR mode when
requested or when no preference is known. Do not require a PR for a solo
workflow, add a confirmation to an already authorized direct commit, or
silently substitute a PR for a "без PR" request.

## Direct commit to master/main or another selected branch

1. Resolve the requested branch (or verified default) to its current commit.
   Read all source files at that commit and prepare/validate the full change
   under the shared writer contract. Capture the commit's actual tree ID.
2. Create a tree using that base tree and only intended changes, preserving
   unrelated paths and file modes. Create a commit whose parent is exactly
   the captured branch head. Review its complete remote tree/content diff.
3. Re-read the target branch head immediately before publishing. If it has
   changed, re-read affected files, reconcile the edits against the new head,
   revalidate, and create a new commit with that new parent. Do not simply
   reuse old whole-file replacements after a conflict.
4. Update `refs/heads/<branch>` to the new commit with **force=false** (a
   fast-forward only update), or use an atomic commit API with an expected-head
   precondition. A concurrent advance must fail rather than overwrite it.
   After a conflict, re-read and reconcile; bound retries to three and preserve
   the prepared change if contention continues. Never force push or remove
   branch protection to satisfy the request.
5. Verify the published branch head and committed contents. If another commit
   already followed yours, verify yours is an ancestor before claiming success.
   Return the commit URL and target branch; no PR is needed. If branch rules or
   permissions reject direct writes, report the actual restriction and preserve
   a reviewable patch/commit. Do not claim success or open an unwanted PR.

Repository rules can forbid direct writes. The skill supports the mode but
cannot bypass those rules. A write-capable connection and a branch that permits
the operation are required; do not turn that into a generic warning on every edit.

## Pull request mode

1. Retain the base commit SHA and its actual `commit.tree.sha`. A tree lookup
   queried with a commit ref may echo that ref; do not assume it is a tree ID.
   Read the full touched files at that commit and prepare the complete diff.
2. Use a new task branch, normally `wiki/<short-topic>-<unique-suffix>`, based
   on that commit. Create a tree **with the base tree** and only intended file
   additions/changes/deletions. Omitting the base tree could delete unrelated
   repository files. Preserve existing file modes; wiki Markdown is normally
   `100644`. Use the tool's explicit deletion form only for authorized removals.
3. Create one commit with that tree and the captured base commit as parent.
   Create the branch at the new commit (or fast-forward the task branch with
   an expected-head check if it was created earlier). No force update of a
   shared branch. Before updating an existing task branch, re-read its head;
   if someone else changed it, reconcile their changes or use a new branch.
   A force=false update by itself is not a substitute for checking conflicts.
4. Verify the remote commit and tree: intended paths changed, no unintended
   deletions, exact edited contents. Re-check the target branch head. If it
   moved, inspect relevant changes and reconcile conflicts; never claim the
   PR is based on the latest state without verification.
5. Open a PR to the requested base, or the verified default branch. Include
   the reason, resulting wiki behavior, verification and pending checks.
   Use draft status if validation is incomplete; honor a user request for a
   draft. Do not merge unless the user has authorized merging. If PR creation
   fails after the commit/branch succeeded, preserve that branch and report
   its URL; do not silently retry by creating duplicate branches or PRs.

Tools may instead offer an atomic multi-file commit operation. Use it when
it preserves the same base-snapshot, scope and conflict guarantees. For a
single-file API, supply the existing blob SHA where required, never omit a
precondition to get around a conflict. Do not degrade a related multi-file
edit to unverified partial writes on the default branch.

## Typical requests

- “Додай рішення у вікі”: read relevant source evidence and topic pages,
  create or update synthesis, cross-links, index/catalog and one log entry.
- “Онови інструкцію”: read the whole target page, verify the new facts and
  preserve unrelated guidance; produce the change and PR.
- “Онови інструкцію й закоміть у master без PR”: use direct mode, verify the
  branch did not advance, fast-forward it and return the commit link.
- “Розділи поточні правила та історію”: read the full source and inbound
  links, resolve protection, propose a concrete separation, and implement it
  when the user's request already authorizes that scope.
- “Захисти сторінку”: record its exact path in committed `policy.json`.
- “Видали/об'єднай сторінки”: check protection and all inbound references,
  remove/redirect links, and review the complete tree diff before publishing.
