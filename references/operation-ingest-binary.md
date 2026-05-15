## Operation: Ingest-Binary

Process a binary artifact (PDF, DOCX, image) into the wiki and archive.

### When to Ingest-Binary

- User drops a file into `tmp/`
- User says "ingest this PDF/DOCX/file", "додай цей документ"
- A new signed contract / certificate / letter arrives

### Process

1. **Detect / ask category** — suggest from `Entity Categories` in schema
   (`{wiki}/schema.md`, fallback to an agent instruction file). If user wants a new category,
   add a row to schema.md (or the legacy instruction-file schema for v1–v2 layout)
2. **Detect / ask type** — suggest from `Document Types` in schema
   (same fallback order). If new type, add a row to schema.md (or the legacy instruction-file schema)
3. **Propose slug** — from filename + date + parties;
   ask user to confirm or edit
4. **Extract text → transcript (via `doc-extract` skill):**
   Prefer the neutral export path. If it is missing or broken, fall back to the
   Gemini direct export and then the shared canonical entrypoint
   (`~/.claude/skills/doc-extract`). This makes the contract explicit:
   `~/.agents/skills/doc-extract` is the cross-agent default,
   `~/.gemini/skills/doc-extract` is Gemini's direct user-skill path, and
   `~/.claude/skills/doc-extract` is the recovery path when exports were
   removed or not yet created.

   Call:
   ```bash
   SOURCE_FILE="<source_file>"
   TRANSCRIPT_OUT="<wiki>/transcripts/<slug>.md"
   DOC_EXTRACT_ROOT="$HOME/.agents/skills/doc-extract"
   if [ ! -x "$DOC_EXTRACT_ROOT/bin/extract.sh" ]; then
     DOC_EXTRACT_ROOT="$HOME/.gemini/skills/doc-extract"
   fi
   if [ ! -x "$DOC_EXTRACT_ROOT/bin/extract.sh" ]; then
     DOC_EXTRACT_ROOT="$HOME/.claude/skills/doc-extract"
   fi
   if [ ! -x "$DOC_EXTRACT_ROOT/bin/extract.sh" ]; then
     echo "doc-extract не знайдено. Повторіть інсталяцію wiki stack:"
     echo "curl -fsSL https://raw.githubusercontent.com/kozaksv/claude-wiki-skill/master/install.sh | bash"
     exit 1
   fi
   bash "$DOC_EXTRACT_ROOT/bin/extract.sh" "$SOURCE_FILE" \
     --out "$TRANSCRIPT_OUT" \
     --format md
   ```

   The `-x` checks are intentional: a present but non-executable
   `bin/extract.sh` is treated as a broken export/install and the fallback chain
   continues. Do not silently `chmod` skill files during ingest-binary; ask the
   user to rerun the wiki installer or repair file permissions explicitly.

   Handle exit code:
   - `0` — transcript created, proceed.
   - `10` (extraction_failed) — STOP. Read stderr method_chain;
     tell user: "doc-extract пройшов каскад [методи], вийшло N символів.
     Варіанти: (1) вручну → summary, (2) vision-capable file read if this agent supports it, explicit and potentially expensive,
     (3) пропустити". Wait for user decision.
   - `20` (missing_dependency) — STOP. Run
     `bash "$DOC_EXTRACT_ROOT/bin/doctor.sh"`, show output,
     ask user to install missing deps, then retry.
   - `30` (unsupported_format) — ask user to skip or convert first.
   - `40/50` — caller bug, show stderr.

   **Важливо:** wiki більше НЕ падає на vision-capable file read сам.
   Єдиний шлях до LLM — явне рішення юзера у відповідь на exit 10.
   Це уникає дорогих silent fallback'ів.

   Якщо `doc-extract` скіл відсутній — повідом юзера, покажи
   install-команду wiki stack'а: `curl -fsSL https://raw.githubusercontent.com/kozaksv/claude-wiki-skill/master/install.sh | bash`.
   Do not send the user to the standalone `doc-extract` installer here: the wiki
   installer provisions the dependency and creates the cross-agent exports
   (`~/.agents/skills/doc-extract`, `~/.gemini/skills/doc-extract`) expected by
   the fallback chain above.
5. **Move binary → `archive/{category}/{slug}.{ext}`** (per File Naming convention).
   The archive category mirrors the entity path (`entities/{category}/{slug}.md`)
   so binary lookup stays predictable.
6. **Create entity page → `entities/{category}/{slug}.md`:**
   - Frontmatter (type=entity, category, key, binary, transcript, project-specific fields)
   - Synthesis (LLM proposes — user edits)
   - Cross-refs: scan transcript for mentions of other entities;
     if entity exists → link; if not → lazy-create stub and link
7. **Update related entity pages** — for each entity touched, append to its
   "Documents" section a link to this new entity page
8. **Update concepts** — if new info changes a concept (e.g., new exception
   for `discrepancies`), propose update; ask user to confirm
9. **Update navigation:**
   - `entities/index.md` (or wiki/index.md Entities section): append row
   - `transcripts/index.md`: append row
   - `log.md`: append `## [YYYY-MM-DD] ingest-binary | <description>`
10. **Update telemetry** (`.usage.json`, see `## Telemetry Sidecar`):
    - New entity page → `bump_patch(entities/{category}/{slug}.md)` (creates record with `created_at`)
    - New transcript → `bump_patch(transcripts/{slug}.md)`
    - Modified `entities/index.md` / `transcripts/index.md` → `bump_patch(...)`
    - Each existing entity page touched (back-link to new doc) → `bump_patch(...)`
    - Each `[[wikilink]]` you added pointing to another wiki page → `bump_use(target_path)`
11. **Protect auto-suggest for critically-rare pages.** For the **new** entity page created in step 6, check if it looks intentionally rare-read. Trigger if either:

    - Frontmatter contains a tag matching `security`, `incident`, `migration`, `compliance`, or `recovery`, OR
    - Filename / slug contains any of those prefixes (e.g. `security-cf-tunnel-rotation.md`, `incident-2026-02-15.md`, `migration-stock-pickings.md`, `compliance-gdpr-export.md`, `recovery-runbook.md`).

    Ask the user:

    ```
    Сторінка [[{slug}]] виглядає як критично-рідкісна. Запропонувати захист? [y/n]
    ```

    On `y`: read `.usage.json`, set `protected: true` on the new entity page's record, write atomically. Pinning does not bump `patch_count`. On `n`: leave `protected: false`. Page protection then kicks in during future Lint runs (see `## Operation: Lint > Page protection during Lint`).

### After completion

If this operation was triggered by a TodoWrite-completion or is part of a pre-commit moment, emit a РЕФЛЕКСІЯ block per `references/reflection.md`. Ingest-Binary always creates structural artifacts (entity page, transcript, archive move, navigation updates), so reflection should fire and include the `Перевірив:` section listing structural files touched. Anti-noise does not apply.

---
