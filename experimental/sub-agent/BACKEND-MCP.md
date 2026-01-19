# Backend: MCP (WebUI / no spawn)

Use this backend when you cannot spawn processes or run `clickhouse-client`, and only have MCP connectors available.

This backend runs “agents” by reading `agents/<name>/queries.sql` and executing the statements via an MCP ClickHouse connector that returns JSON.

## MCP tool example (ai-demo)

In this environment, an example connector is exposed as a tool like:
- `mcp__ai-demo__execute_query(query: string) -> rows (JSON)`

Your WebUI may expose a similarly shaped tool with a different name; use the one available in your session.

## Execution defaults (per statement)

Append settings to every statement you execute:
- `SETTINGS max_execution_time=60, max_result_rows=1000`

Continue on errors: record the failure and proceed so partial results remain available.

## Cluster wrappers (`clusterAllReplicas`)

Agent `queries.sql` may include wrappers in the canonical form:
```sql
clusterAllReplicas('{cluster}', system.query_log)
```

It could be unwrapped in some cases (see below) by replacing `clusterAllReplicas('{cluster}', system.<table>)` with `system.<table>`

MCP backend should decide whether to keep or unwrap wrappers for the whole run:

1) **Detect zookeeper active**
- Run a tiny probe on `system.zookeeper_connection`.
- If probe fails or returns 0 rows: unwrap all cluster wrappers to local `system.<table>`.


2) **Probe `{cluster}` macro**
- If zookeeper is active, probe macro expansion by executing a tiny query like:
  - `SELECT count() FROM clusterAllReplicas('{cluster}', system.one)`
- If it fails and no explicit cluster name was provided: unwrap wrappers (fallback).

3) **Explicit cluster override**
- If the user provides a concrete cluster name, replace `{cluster}` with that name before execution.
- Still unwrap if zookeeper is inactive or the user explicitly requests “single node analysis”.


## How to run an investigation (single artifact per “important question”)

Web mode should gather evidence in waves (agents mostly) and emit **one** consolidated artifact per important user question:

- **Wave 1**: always run `overview`.
- **Wave 2**: run 2–3 targeted agents based on symptoms and wave 1 results.
- **Wave 3** (optional): 1–2 deep dives or dynamic follow-up SQL bundles.

Intermediate steps do **not** need strict JSON validation; keep them as execution records and short notes.

## Artifact capture (in-context JSON)

Since filesystem writes may not be available, the MCP backend should accumulate one in-memory artifact and return it at the end.

Suggested fields:
- `kind`: `"analysis"` or `"proposal"`
- `question`: the user’s “important question”
- `run_context`: version/host/time, zookeeper active, macro ok, explicit cluster name, limits
- `steps[]`: per agent or dynamic bundle
  - `name`, `purpose`
  - `sql_final`
  - `statements[]`: `{sql, ok, result_json, error, elapsed_ms?}`
  - `notes`: short summary of what mattered
- `conclusion`: summary/root cause/actions (for analysis)
- `report_md` or `proposal_md`

