---
name: altinity-clickhouse-expert
description: ClickHouse incident response, periodic audits, and ad-hoc debugging via focused agents (run in waves). Uses ClickHouse system tables to diagnose slow queries/inserts, too many parts/merge backlog, wrong partitioning, log-table errors, replication/Keeper lag, and memory/disk pressure, producing an RCA-style report with reproducible artifacts.
---

# ClickHouse Analyst (Sub-Agent Architecture)

This skill uses focused agents (often run in waves) to diagnose ClickHouse issues quickly. Each agent:
1. Runs SQL queries directly against ClickHouse (via a backend: CLI or MCP)
2. Analyzes results with an LLM
3. Produces reproducible artifacts and an RCA-style report

## How to Use

## Pick an execution backend (do this first)

Before running any agents, decide **how** queries will be executed in this environment. Then load exactly one backend doc and follow it for execution details.

Choose a backend using these rules:
- BACKEND-MCP.md  use when you **cannot spawn/exec** processes and **cannot run** `clickhouse-client`, but you **do** have an MCP ClickHouse connector tool available (WebUI-style environments).
- BACKEND-CLI.md  use when you **can spawn/exec** locally and have `clickhouse-client` available (terminal/SSH environments).

Prefer BACKEND-CLI when a spawn/exec tool is available.
Prefer BACKEND-MCP when process spawning is restricted or as a fallback if clickhouse-client is not available or has connectivity problems.

## Map symptoms to agents (wave 1 → wave 2+)

| User Symptom | Agents to run (often wave 2) |
|--------------|---------------------------|
| "OOM" / "memory" / "MemoryTracker" | memory, reporting |
| "slow queries" / "timeouts" / "latency" | reporting, memory |
| "slow inserts" / "insert lag" | ingestion, merges, storage |
| "too many parts" / "merge backlog" | merges, ingestion, storage |
| "replication lag" / "readonly replica" | replication, merges, storage |
| "disk full" / "storage" | storage, ingestion |
| "errors" / "exceptions" / "failures" | errors, reporting |
| "mutations" / "ALTER UPDATE/DELETE" | mutations, merges, storage |
| "dictionary" / "dictionaries" | dictionaries, memory, errors |
| "cache" / "caches" | caches, reporting |
| "metrics" / "saturation" | metrics, overview |
| "server log" / "text_log" | text_log, errors |
| "log tables" / "query_log too big" | logs, storage |
| "schema" / "partitioning" / "bad ORDER BY" | schema, reporting, merges |
| "health check" / "audit" / "status" | overview |

## Coordinator loop (adaptive chaining)

When coordinating as an LLM, prefer this loop over a fixed “run everything” approach:

1. Start an **artifact** for the user’s important question (analysis or proposal).
2. Run **wave 1**: `overview` (triage).
3. Run **wave 2**: pick 2–3 targeted agents from the table above.
4. Optional **wave 3**: 1–2 deep dives (schema/mutations/dictionaries) or dynamic follow-up queries if needed.
5. Stop early when the highest-severity finding has concrete evidence and actions.
6. Produce a single RCA-style report + one consolidated artifact (see backend docs for capture details).

## Available Agents

| Agent | Purpose | Primary Tables |
|-------|---------|----------------|
| `overview` | Quick health triage | processes, parts, metrics, disks |
| `memory` | OOM, MemoryTracker, RAM pressure | processes, query_log, asynchronous_metrics |
| `merges` | Parts pressure, merge backlog | merges, part_log, parts |
| `replication` | Lag, readonly replicas, Keeper | replicas, replication_queue, text_log |
| `reporting` | Query performance, latency | processes, query_log |
| `storage` | Disk space, IO, table sizes | disks, parts |
| `errors` | Exceptions, failures | query_log, text_log, part_log |
| `ingestion` | INSERT performance, part creation | processes, query_log, part_log, query_views_log |
| `schema` | Table design review, partition sizing | parts, columns, tables |
| `metrics` | Saturation and key metrics | metrics, events, asynchronous_metrics |
| `caches` | Cache efficiency | events, metrics, asynchronous_metrics |
| `dictionaries` | Dictionary health | dictionaries, text_log |
| `mutations` | Mutations backlog | mutations |
| `text_log` | Server logs | text_log |
| `logs` | System log tables | parts, tables |

## Agent Files

Each agent has two files in `agents/<name>/`:
- `queries.sql` - SQL queries executed by the selected backend (semicolon-delimited)
- `prompt.md` - Analysis prompt with severity rules and output format

## Output Format

Final RCA report should include:
- **Summary**: Top findings by severity (Critical > Major > Moderate)
- **Evidence**: Key metrics and query outputs
- **Root Cause**: Most likely explanation
- **Actions**: Concrete next steps
- **Save**: If filesystem is available, write report to `reports/<timestamp>-<topic>.md`; otherwise include it inline in the final response.

## Safety Rules

All SQL queries follow these rules (already baked into agent queries):
- Prefer explicit columns; allow `SELECT *` for `system.*` tables where schemas vary by ClickHouse version
- Default `LIMIT 100` or less
- Time-bounded `*_log` queries (1h default, 24h max)
- Aggregated results (top-N, percentiles) instead of raw dumps

## Runtime Knobs

Runtime knobs are backend-specific; see `BACKEND-CLI.md` / `BACKEND-MCP.md`.
