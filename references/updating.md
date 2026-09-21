# Update the installed skill and hooks

Use this workflow for an explicit request to update the **installed wiki skill**
or repair its hook registration. Updating wiki content, migrating a wiki schema,
and updating the installed skill are different operations. A query never invokes
this workflow. In ChatGPT/GitHub mode, do not pretend to update the user's machine:
edit the requested repository code, or supply the local command instead.

## Local update

1. Resolve the canonical `~/.claude/skills/wiki` symlink and its Git checkout.
   Record the current commit and local changes. Do not reset, stash, delete or
   overwrite user changes automatically. A behavior version in `SKILL.md`, a
   schema version in `schema.md`, and a Git commit are three different values.
2. Use the user-selected ref, or `master` for an explicit latest-version request.
   Use a fresh copy of the installer: an old running `install.sh` does not acquire
   new argument parsing just because its checkout was updated midway through.
   The verified download location and safe temp-file command are in
   `README.md` → **Оновлення**. Do not pipe a failed download into a successful shell.
3. Pass the current Git project with `--project <root>`; repeated `--project`
   arguments select multiple checkouts/worktrees. Never scan every directory in
   HOME. Do not infer other project paths from transcript names. Previously given
   authorization covers updating the skill and known wiki hook registrations in
   the selected scope; do not ask repeatedly for the same permission.
4. The full installer refreshes global registrations and migrates recognized
   project registrations under the shared settings lock. Only standalone commands
   attributable to this wiki skill are removed. Inline/composite or otherwise
   ambiguous wiki-looking commands are preserved and reported with their settings
   path/event/index; do not execute them or dump unrelated settings/secrets.
5. Require the post-update audit. `wiki hooks: verified` means commands, matchers,
   paths, executability and duplicates passed **within the reported settings scope**.
   It does not prove that the host has run a hook. Managed and plugin settings are
   outside the mutator's scope; inspect them via the host's `/hooks` when needed.
6. Report skill commit/version, hook verification result, selected projects and
   any incomplete steps separately. Missing Python, a write failure or ambiguous
   wiki hook is not a successful verified update. Full install exits `3` for an
   incomplete hook upgrade while leaving the updated text skill available.
   `--skip-hooks` is an explicit text-only path, not an error disguised as success.

## Registration repair without a version update

```bash
bash "$HOME/.claude/skills/wiki/hooks/install-hooks.sh" --verify --project "$PWD"
```

For a read-only report use:

```bash
bash "$HOME/.claude/skills/wiki/hooks/doctor.sh" --project "$PWD"
```

The low-level installer without `--verify` reports registration only; the full
installer always requests verification on versions supporting it. Old pinned
refs may lack the audit helper: report that limitation, never claim verified.
A discovery block proves one hook fired; it cannot suppress an explicit repair
request or prove that an old duplicate no longer exists.

Backups are unique `.bak-wiki-hooks-*` files beside the changed settings. Never
follow a settings symlink, rebuild invalid JSON over user data, change managed
configuration, or remove an unknown hook merely because its command contains
`wiki`. The source of truth for write safety remains `hooks/install-hooks.sh`
and the shared `hooks/lib/settings-lock.sh` mutex.
