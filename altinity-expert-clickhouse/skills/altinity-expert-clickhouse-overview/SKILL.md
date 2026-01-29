---
name: altinity-expert-clickhouse-overview
description: Runs a quick overview of Clickhouse server health.
---

Read examples of reporting SQL queries from the file checks.sql and their description in a leading comment.

Prepare a summary report based on the findings

## Routing Rules (Chain to Other Skills)

Based on findings, load specific modules:

- Replication lag/readonly replicas/Keeper issues → `altinity-expert-clickhouse-replication`
- High memory usage or OOMs → `altinity-expert-clickhouse-memory`
- Disk usage > 80% or poor compression → `altinity-expert-clickhouse-storage`
- Many parts, merge backlog, or TOO_MANY_PARTS → `altinity-expert-clickhouse-merges`
- Slow SELECTs / heavy reads in query_log → `altinity-expert-clickhouse-reporting`
- Slow INSERTs / high part creation rate → `altinity-expert-clickhouse-ingestion`
- Low cache hit ratios / cache pressure → `altinity-expert-clickhouse-caches`
- Dictionary load failures or high dictionary memory → `altinity-expert-clickhouse-dictionaries`
- Frequent exceptions or error spikes → include `system.errors` and `system.*_log` summaries below
- System log TTL issues or log growth → `altinity-expert-clickhouse-logs`
- Schema anti‑patterns (partitioning/ORDER BY/MV issues) → `altinity-expert-clickhouse-schema`
- High load/connection saturation/queue buildup → `altinity-expert-clickhouse-metrics`
- Suspicious server log entries → `altinity-expert-clickhouse-logs`
