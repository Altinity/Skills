# Altinity Clickhouse Expert 

ClickHouse incident response + periodic audits + ad-hoc debugging via **parallel sub-agents**.

Works in two environments:
- **CLI**: Claude Code, Codex CLI, Gemini CLI (uses `clickhouse-client`)
- **Web**: claude.ai or other LLM UIs with MCP ClickHouse connector (no local processes)

## How to use

1. Start in `SKILL.md` (coordinator instructions and symptom → agent mapping).
2. Choose an execution backend based on your environment:

| Environment | Can spawn processes? | Has MCP connector? | Use |
|-------------|---------------------|-------------------|-----|
| Terminal / SSH / Claude Code | Yes | Maybe | `BACKEND-CLI.md` |
| claude.ai / WebUI | No | Yes | `BACKEND-MCP.md` |
| Both available | Yes | Yes | Prefer `BACKEND-CLI.md` |

- `modules/` is **legacy reference material** (not executed by the agent runner).

## Files
- `SKILL.md`: coordinator (symptom routing, wave logic, output format)
- `BACKEND-CLI.md`: CLI backend instructions (`clickhouse-client` + LLM CLI)
- `BACKEND-MCP.md`: MCP backend instructions (WebUI + MCP connector)
- `CLAUDE.md`: architecture overview for developers
- `scripts/run-agent.sh`: run one agent (SQL → LLM → JSON) - CLI backend only
- `scripts/run-parallel.sh`: run multiple agents in parallel - CLI backend only
- `scripts/run-all-dry.sh`: run all agents in dry-run mode (SQL only)
- `agents/<name>/{queries.sql,prompt.md}`: per-domain query set + analysis prompt
- `schemas/finding.json`: JSON schema for agent output validation
- `modules/*.md`: legacy reference docs (not executed by agents)

## Quick start

```bash
# Test connection (shows hostname, version, uptime)
scripts/run-agent.sh --test-connection

# Single agent
scripts/run-agent.sh memory "OOM at 14:30" -- --host=prod-ch --user=admin

# Multiple agents (parallel)
scripts/run-parallel.sh "slow queries" -- --host=prod-ch --agents reporting memory

# All agents (dry-run, SQL only)
scripts/run-all-dry.sh -- --host=prod-ch
```

## ClickHouse connection

Connection parameters can be provided via environment variables or explicit arguments.

**Environment variables** (recommended - keeps passwords out of shell history):
```bash
export CLICKHOUSE_HOST=prod-ch.example.com
export CLICKHOUSE_USER=analyst
export CLICKHOUSE_PASSWORD=secret
export CLICKHOUSE_PORT=9440        # optional, default 9000
export CLICKHOUSE_SECURE=1         # optional, enables TLS
export CLICKHOUSE_DATABASE=default # optional

# Then run without explicit connection args
scripts/run-agent.sh memory "OOM at 14:30"
```

**Explicit arguments** (override env vars):
```bash
scripts/run-agent.sh memory "OOM" -- --host=prod-ch --user=admin --password=secret
```

For local ClickHouse with default settings, no configuration is needed.

## Why `run-parallel.sh` exists

When an LLM coordinator (Claude Code, Codex) runs this skill, it can spawn multiple `run-agent.sh` processes directly and do adaptive chaining based on results.

`scripts/run-parallel.sh` is kept as an **LLM-independent execution layer**:
- One command to fan out to multiple agents
- Always-valid aggregated JSON output (including failures/stderr)
- Useful for runbooks, automation, or CI/CD pipelines without an LLM orchestrator

## What is MCP?

MCP (Model Context Protocol) allows LLM interfaces like claude.ai to call external tools. If your ClickHouse is exposed via an MCP connector (e.g., `mcp__clickhouse__execute_query`), the skill can run queries through that connector instead of `clickhouse-client`.

See `BACKEND-MCP.md` for details on MCP-based execution.

## Agents

Currently implemented agents:
- `overview`: quick triage (health signals + which agent to run next)
- `memory`: OOM / RAM pressure
- `merges`: parts pressure / merge backlog
- `replication`: lag / readonly replicas / Keeper issues
- `reporting`: query performance / latency
- `storage`: disk usage / tiny parts / IO risk
- `errors`: exception patterns
- `ingestion`: INSERT performance (includes MV attribution via `system.query_views_log` when available)
- `schema`: table design / partition sizing / MV risk (global “top risky tables” scan)
- `metrics`: saturation signals (metrics/events/async metrics)
- `caches`: cache efficiency signals
- `dictionaries`: dictionary memory + load failures
- `mutations`: mutation backlog + failures
- `text_log`: server Error/Critical/Fatal patterns
- `logs`: system log tables growth/retention signals

## LLM selection (sub-agents)

`scripts/run-agent.sh` supports selecting which CLI to use for analysis (default: `codex`).

```bash
scripts/run-agent.sh reporting "p95 spike" --llm-provider claude -- --host=prod-ch
scripts/run-agent.sh reporting "p95 spike" --llm-provider gemini -- --host=prod-ch
scripts/run-agent.sh reporting "p95 spike" --llm-provider codex -- --host=prod-ch
```

Sub-agents run with minimal permissions (analysis-only, no file/network access):
- **Claude Code**: `--tools ""` (all tools disabled)
- **Codex**: `-a never -s workspace-write` (no auto-approve, limited scope)
- **Gemini**: stdin/stdout only

## Runtime knobs

```bash
# Keep per-run artifacts under runs/<timestamp>-<agent>/
export CH_ANALYST_KEEP_ARTIFACTS=1

# Per-query ClickHouse timeout in seconds (set to 0 to disable)
export CH_ANALYST_QUERY_TIMEOUT_SEC=60
```
