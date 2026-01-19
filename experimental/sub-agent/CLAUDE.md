# CLAUDE.md

ClickHouse incident response, audit, and debugging skill using a **parallel sub-agent architecture**.

Runs in two environments:
- **CLI**: Claude Code, Codex CLI, Gemini CLI (process spawning available)
- **Web**: claude.ai, ChatGPT with MCP (no process spawning, uses MCP connectors)

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    SKILL.md (Coordinator)                       │
│  - Receives user problem                                        │
│  - Maps symptoms to agents                                      │
│  - Selects backend based on environment capabilities            │
│  - Aggregates findings into RCA report                          │
└───────────────────────┬─────────────────────────────────────────┘
                        │
              ┌─────────┴─────────┐
              ▼                   ▼
    ┌─────────────────┐  ┌─────────────────┐
    │  BACKEND-CLI.md │  │  BACKEND-MCP.md │
    │  (can spawn)    │  │  (WebUI only)   │
    └────────┬────────┘  └────────┬────────┘
             │                    │
    ┌────────┴────────┐  ┌────────┴────────┐
    │ run-agent.sh    │  │ MCP tool calls  │
    │ clickhouse-     │  │ (execute_query) │
    │ client + LLM    │  │ + in-context    │
    │ CLI             │  │ analysis        │
    └─────────────────┘  └─────────────────┘
```

### CLI Backend (detailed flow)

```
┌──────────────┐┌──────────────┐┌──────────────┐
│ run-agent.sh ││ run-agent.sh ││ run-agent.sh │
│   memory     ││   merges     ││  replication │
├──────────────┤├──────────────┤├──────────────┤
│ 1. Run SQL   ││ 1. Run SQL   ││ 1. Run SQL   │
│ via ch-client││ via ch-client││ via ch-client│
│ (JSONCompact)││ (JSONCompact)││ (JSONCompact)│
├──────────────┤├──────────────┤├──────────────┤
│ 2. LLM CLI   ││ 2. LLM CLI   ││ 2. LLM CLI   │
│ analyzes     ││ analyzes     ││ analyzes     │
├──────────────┤├──────────────┤├──────────────┤
│ 3. JSON out  ││ 3. JSON out  ││ 3. JSON out  │
└──────────────┘└──────────────┘└──────────────┘
```

## Repository Structure

```
SKILL.md                  # Coordinator - symptom mapping and dispatch logic
CLAUDE.md                 # This file - architecture overview
BACKEND-CLI.md            # CLI backend: scripts + clickhouse-client
BACKEND-MCP.md            # MCP backend: WebUI with MCP connector

scripts/
├── run-agent.sh          # Runs one agent: SQL → LLM → JSON (CLI backend)
└── run-parallel.sh       # Batch mode for automation (LLM-independent)

agents/
├── schema/
│   ├── queries.sql
│   └── prompt.md
├── metrics/
│   ├── queries.sql
│   └── prompt.md
├── caches/
│   ├── queries.sql
│   └── prompt.md
├── dictionaries/
│   ├── queries.sql
│   └── prompt.md
├── mutations/
│   ├── queries.sql
│   └── prompt.md
├── text_log/
│   ├── queries.sql
│   └── prompt.md
├── logs/
│   ├── queries.sql
│   └── prompt.md
├── memory/
│   ├── queries.sql       # Memory diagnostic queries
│   └── prompt.md         # Analysis prompt + severity rules
├── merges/
│   ├── queries.sql
│   └── prompt.md
├── replication/
│   ├── queries.sql
│   └── prompt.md
├── reporting/
│   ├── queries.sql
│   └── prompt.md
├── storage/
│   ├── queries.sql
│   └── prompt.md
├── errors/
│   ├── queries.sql
│   └── prompt.md
├── ingestion/
│   ├── queries.sql
│   └── prompt.md
└── overview/
    ├── queries.sql
    └── prompt.md

schemas/
└── finding.json          # JSON schema for agent output

modules/                  # Legacy - reference documentation
mode-*.md                 # Legacy - workflow guidance
```

## Agent Summary

| Agent | Purpose | Key Indicators |
|-------|---------|----------------|
| `overview` | Quick triage | Memory %, parts count, disk free, errors |
| `memory` | OOM analysis | resident_pct, query memory, dictionaries |
| `merges` | Parts pressure | parts count, merge rate, failures |
| `replication` | Lag/readonly | is_readonly, queue_size, log_gap |
| `reporting` | Query perf | p95 latency, read bytes, failures |
| `storage` | Disk/IO | free_pct, table sizes, tiny parts |
| `errors` | Exceptions | exception codes, server errors |
| `ingestion` | INSERT perf | parts/sec, part size, insert latency |
| `schema` | Schema/design | partitions, tiny parts, MV patterns |
| `metrics` | Saturation | background pools, counters, async metrics |
| `caches` | Cache health | cache events/metrics, efficiency signals |
| `dictionaries` | Dictionaries | bytes_allocated, load failures |
| `mutations` | Mutations | backlog, failures, long-running |
| `text_log` | Server logs | Error/Critical/Fatal patterns |
| `logs` | Log tables | system log sizes/retention |

## Usage

```bash
# Test connection (shows hostname, version, uptime)
scripts/run-agent.sh --test-connection

# Configure connection via environment variables
export CLICKHOUSE_HOST=prod-ch.example.com
export CLICKHOUSE_USER=analyst
export CLICKHOUSE_PASSWORD=secret

# Run an agent (uses env vars for connection)
scripts/run-agent.sh memory "OOM at 14:30"

# Or with explicit args (override env vars)
scripts/run-agent.sh memory "OOM at 14:30" -- --host=localhost --user=admin

# Select LLM provider (default: codex)
scripts/run-agent.sh memory "OOM" --llm-provider claude
scripts/run-agent.sh memory "OOM" --llm-provider gemini

# Dry-run (SQL only, no LLM) for debugging
scripts/run-agent.sh memory "OOM at 14:30" --dry-run

# List available agents
scripts/run-agent.sh --list-agents
```

**Connection environment variables** (preferred - keeps passwords out of shell history):
- `CLICKHOUSE_HOST` - server hostname (default: localhost)
- `CLICKHOUSE_PORT` - native port (default: 9000)
- `CLICKHOUSE_USER` - username
- `CLICKHOUSE_PASSWORD` - password
- `CLICKHOUSE_SECURE` - set to `1` for TLS
- `CLICKHOUSE_DATABASE` - default database

Output is JSON with `status`, `findings`, and `chain_to` recommendations.

## Coordinator Loop (Adaptive Chaining)

Prefer adaptive waves of `run-agent.sh` over a fixed "run everything" approach:

1. Pick initial agents from the symptom table (usually 2–3 in parallel).
2. Run each via `scripts/run-agent.sh ...` and parse JSON.
3. Merge findings by severity; note repeated evidence across agents.
4. If `chain_to` suggests additional agents and the root cause is not yet clear, run a second wave (cap at 1–2 extra waves).
5. Stop early when there is a clear highest-severity finding with concrete actions.

## Symptom → Agent Mapping

| Symptom | Agents |
|---------|--------|
| OOM / memory | memory, reporting |
| slow queries | reporting, memory |
| slow inserts | ingestion, merges, storage |
| too many parts | merges, ingestion, storage |
| replication lag | replication, merges, storage |
| disk full | storage, ingestion |
| errors | errors, reporting |
| mutations | mutations, merges, storage |
| dictionaries | dictionaries, memory, errors |
| cache issues | caches, reporting |
| saturation/metrics | metrics, overview |
| server logs | text_log, errors |
| log tables growing | logs, storage |
| health check | overview |

## Output Schema

Each agent returns:
```json
{
  "agent": "memory",
  "status": "critical|major|moderate|ok",
  "findings": [
    {
      "severity": "critical|major|moderate|minor",
      "title": "Short description",
      "evidence": "Key metrics",
      "values": {"metric": value},
      "recommendation": "Action"
    }
  ],
  "chain_to": ["next", "agents"]
}
```

## Benefits of This Architecture

- **Portable**: Same agents work in CLI (Claude Code, Codex) and Web (claude.ai + MCP)
- **Fast**: SQL runs directly (no LLM latency for queries)
- **Reliable**: Queries are fixed, no risk of LLM modifications
- **Adaptive**: Run agents iteratively, follow `chain_to`, stop when root cause is clear
- **Cheap**: LLM only analyzes results, doesn't execute queries
- **Debuggable**: SQL files can be tested independently (`--dry-run` in CLI, manual MCP calls in Web)

## LLM Provider Security

Sub-agents run with minimal permissions since they only need to analyze data and return JSON:

| Provider | Permission Model |
|----------|-----------------|
| Claude Code | `--tools ""` (all tools disabled) |
| Codex | `-a never -s workspace-write` (no auto-approve, limited scope) |
| Gemini | stdin/stdout only (no tool access) |

This ensures sub-agents cannot modify files, execute commands, or access the network.
