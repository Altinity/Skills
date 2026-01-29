---
name: altinity-expert-clickhouse-connection
description: Basic setup for all altinity-expert-clickhouse skills. Use before running any other clickhouse diagnostics.
---

## Goal

Provide a consistent, portable connection + cluster + timeframe setup for ClickHouse diagnostic skills (e.g. overview, replication).

## Connection mode

Decide connection mode first and verify connectivity then:
```sql
select
    hostName() as hostname,
    version() as version,
    formatReadableTimeDelta(uptime()) as uptime_human,
    getSetting('max_memory_usage') as max_memory_usage,
    (select value from system.asynchronous_metrics where metric = 'OSMemoryTotal') as os_memory_total
```

### MCP mode (preferred)

If multiple ClickHouse MCP servers are available, ask the user which one to use.
When executing queries by the MCP server, push a single SQL statement to the MCP server (no multy query!)

### Exec mode (clickhouse-client)

- try to run `clickhouse-client`. Don't rely on env vars. On failure, ask how to run it properly.
- Prefer running queries from a `.sql` file with `--queries-file` and forcing JSON output (`-f JSON`) when capturing results to files.

## Cluster selection for `clusterAllReplicas('{cluster}', ...)`

- Verify if a cluster macro is defined: `SELECT getMacro('cluster')`. If defined - leave macro as-is.
- if not, ask the user to choose from: `SELECT DISTINCT cluster FROM system.clusters where not is_local` and replace `'{cluster}'` placeholders in the queries in all `.sql` files.
- if the query above returns nothing, consider single-server mode and automatically rewrite `clusterAllReplicas('{cluster}', system.<table>)` → `system.<table>` before execution.

## Timeframe default for logs/errors

- If the user explicitly provides a timeframe in the initial prompt, use it exactly.
- Otherwise default to **last 24 hours**:

```sql
-- Use this pattern for system.*_log tables and system.errors time filters:
-- WHERE event_time >= now() - INTERVAL 24 HOUR
```

## Output (what to carry forward)

- Connection mode used: MCP or clickhouse-client
- `{cluster}` value (or explicitly “no cluster / single node” if user chooses to run without cluster queries)
- Log timeframe expression (default `now() - INTERVAL 24 HOUR` unless overridden)
