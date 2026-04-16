# Claude Wiki Skill

A Claude Code skill that adds an LLM Wiki knowledge base (Karpathy pattern) to any project. Instead of re-discovering knowledge each session, the wiki accumulates synthesized understanding across conversations.

## What it does

Three operations:
- **ingest** — process a source (spec, feature, code change) into wiki pages
- **query** — search the wiki to answer questions about the project
- **lint** — health-check for staleness, contradictions, orphan pages

Trigger words: `ingest`, `wiki query`, `wiki lint`, `додай до wiki`, `оновити wiki`, `що каже wiki про...`

## Install

```bash
git clone git@github.com:kozaksv/claude-wiki-skill.git && ln -s "$(pwd)/claude-wiki-skill" ~/.claude/skills/wiki
```

## Update

```bash
cd <path-to-claude-wiki-skill> && git pull
```

## Uninstall

```bash
rm ~/.claude/skills/wiki
```

## Requirements

- [Claude Code](https://claude.ai/claude-code)
