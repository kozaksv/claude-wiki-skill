## Operation: Query

Search the wiki to answer a question about the project.

### When to Query

**BLOCKING RULE (NON-NEGOTIABLE):** Перш ніж згенерувати будь-який project-specific контент — query the wiki. Жодних memory-first відповідей. Жодного «перевірю вікі пізніше», «спершу подивлюся файли», «я й так знаю». Послідовність — READ → CITE → ANSWER, без винятків окрім явного Empty-Wiki Exception (див. SKILL.md → Session-Start Contract).

Відповідь без `[[page-name]]` цитат на wiki-backed темі — баг за контрактом, переробити з вікі. Це стосується кожної project-specific claim: path, config, recipe, setup-step, decision, «як ми робимо X». Цитата — це доказ, що ти справді прочитав вікі, а не вигадав.

The wiki captures project-specific facts (paths, configs, prior decisions, gotchas) that may not match general training knowledge. Default-answering from memory is a gamble; query is cheap (3-5 file reads).

This rule exists because the user should not have to know wiki keywords. The user types in plain Ukrainian — "як налаштувати X", "де лежить Y", "пам'ятаєш як ми Z" — and the active agent is responsible for translating that into a wiki check before generating anything.

Concretely, query when:

- The user's question takes any of these shapes:
  - «як [налаштувати/встановити/підключити/зробити/запустити] X»
  - «як [працює/влаштовано] X у [нашому проєкті/нас]»
  - «що таке X», «розкажи про X», «поясни X»
  - «де лежить X», «де знаходиться X», «де у нас Y»
  - «пам'ятаєш як ми Y», «ми вже робили X», «потрібно знову Z»
  - any «як ми вирішили…», «який у нас підхід до…»
- You're about to generate a recipe, paste-able block, config snippet, or multi-step setup for this project.
- The user asks about architecture, flows, or design decisions.
- You need context about how a system works before making changes.
- You're searching for gotchas before touching a specific area.
- The user explicitly invokes via "що каже wiki про...", "wiki query", "знайди у wiki".

**Don't query for ambient operations** — `ls`, `pwd`, `git status`, generic shell exploration. Those don't have project-specific knowledge to retrieve.

**Pair with crystallization.** If you query and find nothing relevant, that's a discovery signal: this topic isn't yet captured. Hold it in mind — once you derive the answer, it becomes a candidate for crystallization (see `references/crystallization.md`). Discovery and crystallization are two halves of the same loop: query reads what was saved, crystallization saves what was re-derived. The OpenSSH-on-Windows-DC scenario in the reflection examples is the canonical case — a wiki entity existed but lacked the paste-able block, so the agent re-derived it from memory; query before generating would have surfaced the gap and prompted crystallization the first time, not the second.

### Process

```
0. DISCOVER wiki location (Step 0 above)
1. READ {wiki}/index.md
2. IDENTIFY relevant pages from index (usually 1-3)
3. READ those pages
4. SYNTHESIZE answer with citations: [[page-name]]
5. If answer is valuable and reusable → FILE BACK as new wiki page
6. UPDATE telemetry — call bump_view(path) for each page read in step 3
```

After step 3, for each page you read with the `Read` tool, call `bump_view(path)` against `.usage.json` (see `## Telemetry Sidecar`). If step 5 fires and you create or edit a page, also call `bump_patch(new_path)` and `bump_use(target)` for each `[[wikilink]]` added.

**Step 6 is conditional, not unconditional.** `bump_view`/`bump_patch` are
suppressed **only** when `_hooks.post_tool_use_at` is fresh for the current
session — i.e. confirmed-live PostToolUse telemetry, per the dual-signal
rule (`references/telemetry.md`). A `WIKI INDEX (hook-injected)` block in
context proves only that SessionStart fired; it does **not** by itself
suppress step 6. If the index was injected but `post_tool_use_at` is stale
or absent, keep making the manual `bump_view`/`bump_patch` calls above as
fallback. `bump_use(path)` is always manual, hooks or no hooks.

### Filing Back

When a query produces a valuable synthesis (comparison, analysis, connection between topics), consider saving it as a new wiki page. This is a key Karpathy insight: **good answers compound into the knowledge base** rather than disappearing into chat history.

Ask yourself: "Would this answer be useful in a future session?" If yes → create a page.

### After completion

Query is read-only by default — apply the **anti-noise rule** and skip the РЕФЛЕКСІЯ block (see `references/reflection.md`). The exception is when step 5 (Filing Back) fires and you actually create or edit a wiki page: that turns the operation into a synthesis-write, and reflection should fire as if it were an Ingest-Source.

---
