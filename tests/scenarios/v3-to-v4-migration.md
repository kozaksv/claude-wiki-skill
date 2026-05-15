# Scenario: v3 → v4 migration

## Setup

Mock wiki state:
- `docs/wiki/schema.md` exists, no `wiki_version` frontmatter (legacy v3)
- `docs/wiki/concepts/`, `docs/wiki/entities/`, `docs/wiki/transcripts/` populated
- `docs/wiki/index.md` and `log.md` present
- `docs/wiki/.usage.json` does NOT exist
- `.gitignore` does NOT have `docs/wiki/.usage.json`

## Trigger

User says: "що каже wiki про purchase-flow"

## Expected skill behavior

1. Step 0 reads schema.md frontmatter, finds no `wiki_version` → state = `legacy`
2. Skill halts the query operation
3. Skill outputs migration plan:
   - Identify: "Wiki existing but no version. Current skill behavior version is
     4.2.0, but the current schema major is still 4.0. Last documented schema
     version before `wiki_version` was 3.0 (post-schema-canonicalization).
     Treat as 3.0?"
   - User confirms
   - Plan proposed:
     1. Add wiki_version: "4.0" + last_migration: "{today}" to schema.md frontmatter
     2. Add `## Migration Log` section to schema.md with v4.0 entry. The
        later v4.1/v4.2 log entries are behavior/install notes with no schema
        migration.
     3. Create docs/wiki/.usage.json (empty dict)
     4. Add "docs/wiki/.usage.json" to .gitignore
     5. Append "## [{today}] migration | 3.0 → 4.0" to log.md
4. User confirms `y`, all 5 steps execute
5. After migration, original query operation resumes

## Manual verification

After running the scenario in a test wiki:
- `cat docs/wiki/schema.md` shows new frontmatter
- `cat docs/wiki/.usage.json` returns `{}`
- `grep ".usage.json" .gitignore` finds the line
- `grep "migration" docs/wiki/log.md` finds the entry
