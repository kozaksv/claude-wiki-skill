## Operation: Split

Load `writer-core.md` for shared write/protection rules. After an authorized
content/path change, regenerate existing catalog navigation with
`scripts/wiki.py catalog --wiki <wiki> --write` and run `--check`.
For fresh Init, create tracked `policy.json` with version 1 and empty pages,
then generate catalog/index after the initial pages exist. For existing wikis,
adopt these files only during authorized maintenance, never during Query.


Break an over-grown wiki page into focused successors. Lint flags candidates (check #12); this operation executes the split cleanly.

### When to Split

- Page > ~200 lines (soft limit from Page Conventions)
- Page covers 2+ independent topics with visible H2 boundaries
- Lint item #12 fires

### Process

1. **Identify boundaries** — usually H2 sections. Propose N successor pages with titles and which sections land in each.
2. **Resolve scope** — present the concrete split plan when boundaries are not yet agreed. If the user's request already authorizes these boundaries, continue without a second confirmation. User changes to the plan take precedence.
3. **Create successor pages** using the Page Template. Each inherits relevant `## Sources` from the original.
4. **Rewrite or delete original** — either keep it as a hub page (just a list of `[[successor]]` links if the umbrella topic still makes sense) or delete it outright. **If deleted**, call `forget(original_path)` against `.usage.json` (see `## Telemetry Sidecar`). For each successor, telemetry will auto-create a record on the first patch — no manual init needed.
5. **Rewire cross-references** — scan wiki for `[[old-page]]` and replace with the correct `[[new-page]]`. Grep the whole `{wiki}/` tree.
6. **Update `## See also`** on every page that referenced the original — point to the specific successor, not the generic replacement.
7. **Update `{wiki}/index.md`** — remove old entry, add N new entries with one-line descriptions.
8. **Append to `log.md`:**
```markdown
## [YYYY-MM-DD] split | old-page → new-a + new-b
- Reason: lint check #12 flagged 247 lines / 3 independent topics
- Successors: [[new-a]] (topic X), [[new-b]] (topic Y)
- Cross-refs updated: N pages
```

### Anti-Patterns

- **Don't split for size alone.** A focused 210-line page is fine. Size is a heuristic, not a rule.
- **Don't leave a bait-and-switch hub** (original title, but just a list of links) unless the umbrella topic has standalone value. Prefer deletion + cross-ref rewire.
- **Don't forget the log.md entry.** Future lint runs need to know the split happened, so they don't re-flag stubs.

### After completion

If this operation was triggered by a TodoWrite-completion or is part of a pre-commit moment, emit a РЕФЛЕКСІЯ block per `references/reflection.md`. Split always rewrites multiple files (successors + cross-refs + index + log) and almost always touches `index.md` and `log.md`, so reflection should fire and include the `Перевірив:` section. Anti-noise does not apply.

---
