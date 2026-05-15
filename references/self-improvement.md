## Self-Improvement References

This is a routing index for the wiki's self-improvement loop. Load the smallest
specific reference needed for the current task:

- `references/reflection.md` — РЕФЛЕКСІЯ block format, trigger table, field
  rules, and anti-noise rules. Mutating wiki operations usually need only this
  file at completion time.
- `references/crystallization.md` — deciding whether repeated work should become
  a wiki page or user-level skill, including Codex/Gemini direct-create fallback
  and installer-style topology safety (`set_skill_link` / `export_skill_link`).
- `references/cleanup-flow.md` — embedded cleanup prompt, cleanup-flow action
  menu, page protection, and `wiki protect` / `wiki unprotect`.

Do not load all three by default. For example, `ingest-source` can finish with
`references/reflection.md`; only load `references/crystallization.md` when the
`Автоматизував:` field plausibly needs a proposal, and only load
`references/cleanup-flow.md` when the user enters cleanup/status follow-up.

Lint, `wiki status`, and cleanup-flow have their own reports and must not append
a separate РЕФЛЕКСІЯ block or cleanup-prompt.
