# Local Read Adapter

Load [reader-core.md](reader-core.md), then:

1. Run the installed skill's `hooks/lib/discover.sh START_DIRECTORY`. This is
   the same bounded discovery implementation used by the hooks. Set
   `WIKI_DISCOVERY_AGENT` to `claude`, `codex`, `gemini`, or `qwen` when known;
   otherwise use its deterministic default priority. Do not reimplement the
   pointer parser in an ad-hoc shell command.
2. If no wiki resolves, inspect the requested repository's `docs/wiki/` for
   a partial wiki; distinguish failed reads from missing files. Do not init
   git, provision hooks, sync instruction files or migrate on a query.
3. Read `index.md` and available `schema.md`, then follow the shared reading
   contract. List paths with `rg --files` or the catalog tool when necessary.
   `python3 <skill>/scripts/wiki.py catalog --wiki <wiki>` prints a fresh
   inventory without writing. A missing Python runtime does not prevent
   reading Markdown through ordinary file tools.
4. Cite local wiki pages as `[[page]]` in environments that render wikilinks;
   in ChatGPT use clickable file links or verified repository source URLs.
   Keep the read set scoped to the selected checkout. For current-state
   claims, account for local changes instead of pretending HEAD describes
   uncommitted files.

For maintenance, load `discovery-versioning.md` and the relevant operation.
For ordinary questions, neither that long reference nor telemetry is required.
