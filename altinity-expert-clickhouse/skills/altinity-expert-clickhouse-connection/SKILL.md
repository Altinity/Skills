---
name: altinity-expert-clickhouse-connection
description: Basic setup for all altinity-expert-clickhouse skills. Use before running any other clickhouse diagnostics.
---

## Goal

Provide a consistent, portable connection + cluster + timeframe setup for ClickHouse diagnostic skills (e.g. overview, replication).

## Connection mode

### MCP mode (preferred)

1) If multiple ClickHouse MCP servers are available, ask the user which one to use.
2) Verify connectivity:

```sql
SELECT version() AS version, hostName() AS host, now() AS now;
```

### Exec mode (clickhouse-client)

- try to run `clickhouse-client`. On failure, ask for credentials (host/port/user/password/secure).
- Prefer running queries from a `.sql` file with `--queries-file` and forcing JSON output (`-f JSON`) when capturing results to files.

## Cluster selection for `clusterAllReplicas('{cluster}', ...)`

- Verify if a cluster macro is defined: `SELECT getMacro('cluster')`. If defined - leave macro as-is.
- if not, ask the user to choose from: `SELECT DISTINCT cluster FROM system.clusters` and replace `'{cluster}'` placeholders in the queries in all `.sql` files.

## Timeframe default for logs/errors

- If the user explicitly provides a timeframe in the initial prompt, use it.
- Otherwise default to **last 24 hours**:

```sql
-- Use this pattern for system.*_log tables and system.errors time filters:
-- WHERE event_time >= now() - INTERVAL 24 HOUR
```

## Output (what to carry forward)

- Connection mode used: MCP or clickhouse-client
- `{cluster}` value (or explicitly “no cluster / single node” if user chooses to run without cluster queries)
- Log timeframe expression (default `now() - INTERVAL 24 HOUR` unless overridden)

