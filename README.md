# Skills

This repository contains skills used for ClickHouse DB performance and schema analysis and helper workflows.

## Core Skills
- `altinity-expert-clickhouse/`: Modular ClickHouse diagnostic skill set. Each module is a standalone skill under `altinity-expert-clickhouse/skills/` (e.g., memory, merges, replication).
- `automations/`: Batch and focus audit scripts that run full ClickHouse analysis and emit a single report.
- `releases/`: Built zip packages for distribution (one per skill).

## Install / Use Skills

### 1) Codex CLI

variants:
- use $skill-installer skill inside codex
- clone repo and copy needed skills into ~/.codex/skill directory.
- clone repo and ln (symlink) repo's skill directory into ~/.codex

### 2) Claude CLI (Claude Code)

variants:
- claude skills add URL
- clone repo and copy needed skills into ~/.claude/skill directory.
- clone repo and ln (symlink) repo's skill directory into ~/.claude

### 3) Gemini CLI

Install an agent skill from a git repository URL or a local path. 
```
gemini skills install <source> [--scope] [--path] 
```
 
or manually:

```sh
git clone https://github.com/Altinity/Skills.git
mkdir -p ~/.gemini/skills
cp /absolute/path/to/Skills/altinity-expert-clickhouse/skills/altinity-expert-clickhouse-memory ~/.gemini/skills/
# or
ln -s /absolute/path/to/Skills/altinity-expert-clickhouse/skills ~/.gemini/skills/
```


### 4) Claude.ai (web)
Download the zip files from `releases/` and upload them in Settings (or Admin Settings for org‑wide use) to Capabilities section. 

## Experimental Skills 
- `experimental/codex-summarize-pipeline/`: Chunk→reduce pipeline for summarizing large articles/files into `summaries/*.md`.
- `experimental/github-triage/`: Search and summarize relevant GitHub issues/PRs using `gh`.
- `experimental/sub-agent/`: Prototype sub-agent workflow (multi-agent attempt by exec of next codex/claude inside skill processing).

## Conventions
- Each skill lives in its own directory and includes a `SKILL.md`.
- Supporting content is stored next to `SKILL.md` (e.g., `modules/`, scripts, prompts).
