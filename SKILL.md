---
name: wiki
version: "4.4.0"
description: >
  Manage a project's LLM Wiki (Karpathy pattern): init, ingest-source,
  ingest-binary, query, lint, cleanup, split, wiki status. Triggers:
  "створи/ініціалізуй wiki/вікі", "init wiki", "bootstrap wiki",
  "додай/оновити/перевір wiki/вікі", "wiki/вікі lint/query/cleanup/status",
  "що каже wiki про...", "знайди у вікі", binaries in tmp/. Proactively query
  before project-specific how-to/config/setup/recipe/explanation answers,
  including "як налаштувати X", "що таке X", "як працює X", "де лежить X",
  "пам'ятаєш як ми Y", "потрібно знову Z".
  ОБОВ'ЯЗКОВО на старті сесії в проєкті з вікі: прочитай `{wiki}/index.md`
  ДО будь-якої project-specific відповіді. Кожна project-specific відповідь
  МАЄ містити `[[page-name]]` цитати з вікі. Відповідь без цитат на
  wiki-backed темі — баг, переробити.
---

# LLM Wiki (Karpathy Pattern)

A persistent, compounding knowledge base maintained by an AI coding agent.
Instead of re-discovering knowledge each session, the wiki accumulates
synthesized understanding across conversations.

This skill is **project-agnostic** and **agent-neutral**: it discovers wiki
location automatically and can be used from Claude, Codex, or Gemini.

This file is intentionally a thin entrypoint. The operational contract lives in
`references/` and should be loaded only when needed for the current operation.

## Platform Compatibility

The workflow is written in Claude-era terms, but the contract is platform-neutral:

| Generic action | Claude Code | Codex | Gemini CLI |
|---|---|---|---|
| Read file(s) | Read | shell/read tools | shell/read tools |
| Edit file(s) | Edit/Write | apply_patch | shell/edit tools |
| Run commands | Bash | exec_command | shell tool |
| Track tasks | TodoWrite | update_plan | native plan/todo mechanism if available |

When references name a platform-specific tool (`Read`, `Edit`, `Write`, `Bash`,
`TodoWrite`), translate it to the current agent's equivalent. The behavior is
normative; tool names are examples.

## Always Start Here

Before **any** operation, load and follow:

- `references/discovery-versioning.md`

That reference contains Step 0 discovery, schema lookup, version comparison,
migration flow, and the rule to resume the user's original operation after a
migration. Never create a second wiki if a valid existing wiki can be found.

## Session-Start Contract (NON-NEGOTIABLE)

Якщо Step 0 знайшов валідну вікі для цього проєкту — діє блокуючий контракт.
Жодних винятків окрім явно зазначеного нижче.

1. **READ FIRST.** До першої project-specific відповіді в сесії — прочитай
   `{wiki}/index.md` та сторінки, на які він вказує по темі питання. Не
   після відповіді, не «пізніше», не «коли буде час» — спочатку.
2. **CITE OR FAIL.** Кожна project-specific claim, recipe, path, config,
   setup-step, «як ми робимо X», «де лежить Y», «як працює Z» МАЄ нести
   `[[wikilink]]` на сторінку вікі, що це підтверджує. Відповідь без
   `[[page-name]]` цитат на wiki-backed темі — баг, перероби з вікі.
3. **NO MEMORY-FIRST.** «Я пам'ятаю як цей проєкт робить X» — недостатньо.
   Memory не замінює read. Спершу прочитай вікі, потім цитуй, потім
   відповідай. Якщо вікі суперечить пам'яті — вікі виграє.
4. **EMPTY-WIKI EXCEPTION.** Якщо у вікі немає релевантної сторінки —
   скажи це прямо («у вікі нема, відповідаю з training») І познач тему як
   кандидата на crystallization (див. `references/crystallization.md`).
   Цей exception легалізує відповідь без цитат — але лише якщо ти справді
   прочитав `index.md` і релевантні сторінки, і їх немає. Не використовуй
   його, щоб обійти крок READ FIRST.

### Red Flags — це раціоналізації, СТОП

| Думка                                | Реальність                                                       |
|--------------------------------------|------------------------------------------------------------------|
| «Я й так знаю»                       | Знання загального ≠ знання саме цього проєкту. Читай вікі.       |
| «Питання просте»                     | Прості питання найчастіше мають специфічну відповідь у вікі.     |
| «Подивлюся у файли — швидше»         | Файли = код. Вікі = рішення/обґрунтування. Спершу вікі.          |
| «Перевірю вікі після відповіді»      | Ні. READ → CITE → ANSWER. Не «answer-then-verify».               |
| «Це не project-specific»             | Якщо торкаєшся paths/configs/decisions цього проєкту — є.        |
| «Цитата зайва, бо очевидно»          | Цитата дешева. Її відсутність = баг за контрактом.               |
| «Я вже читав вікі в попередній сесії»| Resident-контекст не зберігся між сесіями. Читай знову.          |

Контракт не залежить від типу операції — він діє завжди, коли є валідна
вікі для поточного проєкту. Operation Query (`references/operation-query.md`)
дає механіку (як шукати, як цитувати, як filing back); контракт тут — це
коли і чому це обов'язково.

## Reference Loading Map

Load the smallest set of references that covers the user's request:

| User intent / operation | Required references |
|---|---|
| Create / initialize / migrate a wiki (`створи вікі`, `init wiki`, `bootstrap wiki`) | `references/discovery-versioning.md`, `references/wiki-structure.md`, `references/operation-init.md`, `references/telemetry.md`, `references/reflection.md` |
| Add source Markdown/spec/code knowledge (`ingest-source`, `додай до вікі`) | `references/discovery-versioning.md`, `references/wiki-structure.md`, `references/operation-ingest-source.md`, `references/telemetry.md`, `references/reflection.md` |
| Add binary artifact from `tmp/` (`ingest-binary`, PDF/DOCX/image) | `references/discovery-versioning.md`, `references/wiki-structure.md`, `references/operation-ingest-binary.md`, `references/telemetry.md`, `references/reflection.md` |
| Ask project-specific questions / recipes / setup details | `references/discovery-versioning.md`, `references/operation-query.md`, `references/telemetry.md` |
| Print wiki status | `references/discovery-versioning.md`, `references/operation-wiki-status.md`, `references/telemetry.md`, `references/maintenance-and-mistakes.md` |
| Run lint / verify wiki health | `references/discovery-versioning.md`, `references/operation-lint.md`, `references/telemetry.md`, `references/maintenance-and-mistakes.md` |
| Split a large page | `references/discovery-versioning.md`, `references/wiki-structure.md`, `references/operation-split.md`, `references/telemetry.md`, `references/reflection.md` |
| Cleanup / resolve lint/status actions | `references/discovery-versioning.md`, `references/operation-cleanup.md`, `references/operation-lint.md`, `references/cleanup-flow.md`, `references/maintenance-and-mistakes.md` |
| Reflection / crystallization | `references/reflection.md`, `references/crystallization.md`, `references/cleanup-flow.md`, `references/self-improvement.md` |
| Telemetry sidecar details | `references/telemetry.md` |
| Wiki layer and navigation conventions | `references/wiki-structure.md` |

If a referenced file is missing, stop and tell the user which file is missing
instead of improvising the behavior from memory.

## Core Invariants

- **DRY topology:** one real git clone, one canonical entrypoint, symlink exports
  for other agents. Do not copy skills into per-agent private registries.
- **Shared canonical registry:** `~/.claude/skills/` is the canonical skill
  registry for this stack even in Codex-only or Gemini-only sessions. It does
  not require Claude Code to be installed.
- **Agent-neutral discovery:** `CLAUDE.md`, `AGENTS.md`, and `GEMINI.md` are
  equal sources of a `## Wiki` pointer. Validate every pointer by checking for
  `{wiki}/index.md`.
- **Git-backed wiki:** Git is the foundation of the wiki: snapshots, rollback,
  lint auto-fixes, cleanup, and migration safety all rely on commits. A project
  without git metadata (`.git/` directory or `.git` file) is not wiki-ready.
- **Boundary-aware discovery:** walk from cwd upward only to the nearest git
  marker ancestor (`.git/` directory or `.git` file), inclusive. If no git
  marker ancestor exists, stop and require explicit git initialization before
  any wiki operation can proceed.
- **No split-brain wiki:** a stale active-agent pointer is a cleanup/lint finding,
  not permission to create a second wiki.
- **Optional `doc-extract`:** required only for `ingest-binary`. The rest of the
  wiki must remain usable when `doc-extract` is missing or broken.
- **Karpathy content-verification:** telemetry prioritizes what to read; it never
  flags stale content by itself.
- **Resident context is expensive:** keep agent instruction files short. Move
  implementation details and full schemas into the wiki.

## Philosophy

From Karpathy's original pattern: the problem is that an LLM rediscovers project
knowledge from scratch every session. The wiki is not generic documentation; it
is synthesized understanding that compounds across sessions. Cross-references
are first-class, and the LLM does the mechanical bookkeeping humans abandon.

Use the wiki as a palette, not a checklist. Small projects may only need
`ingest-source` and `query`; research projects may lean on `ingest-binary`; mature
projects may benefit from lint/status/cleanup and skill crystallization.

## Operation Index

All operation bodies live in references:

- `references/operation-init.md`
- `references/operation-ingest-source.md`
- `references/operation-ingest-binary.md`
- `references/operation-query.md`
- `references/operation-wiki-status.md`
- `references/operation-lint.md`
- `references/operation-split.md`
- `references/operation-cleanup.md`

The supporting contracts are:

- `references/discovery-versioning.md`
- `references/wiki-structure.md`
- `references/telemetry.md`
- `references/reflection.md`
- `references/crystallization.md`
- `references/cleanup-flow.md`
- `references/self-improvement.md`
- `references/maintenance-and-mistakes.md`

## Session-Start Checklist

При першому project-specific питанні в сесії (якщо Step 0 знайшов валідну вікі):

- [ ] Прочитати `{wiki}/index.md`
- [ ] Визначити релевантні до питання сторінки з index
- [ ] Прочитати ці сторінки
- [ ] Сформувати відповідь з `[[page-name]]` цитатами на прочитані сторінки
- [ ] Якщо знання нове/синтезоване — filing back (нова сторінка) або mark for crystallization
