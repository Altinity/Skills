---
name: altinity-expert-clickhouse-audit
description: Full audit that runs all expert skills in sequence for a comprehensive diagnostic report.
---

## Startup Procedure

Connectivity selection and setup is handled by the caller (upper prompt/orchestrator). Run a minimal preflight (e.g. `select 1`) and fail fast if connectivity is not OK.

---

## Module Index

Complete module registry. This is the single source of truth for audit coverage.

| Module | Purpose | Triggers (Keywords) | Symptoms | Chains To |
|--------|---------|---------------------|----------|-----------|
| **altinity-expert-clickhouse-overview** | System health entry point, comprehensive audit | health check, audit, status, overview | General slowness, unclear issues | Route based on findings |
| **altinity-expert-clickhouse-reporting** | Query performance analysis | slow query, SELECT, performance, latency, timeout | High query duration, timeouts, excessive reads | memory, caches, schema |
| **altinity-expert-clickhouse-ingestion** | Insert performance diagnostics | slow insert, ingestion, batch size, new parts | Insert timeouts, part backlog growing | merges, storage, memory |
| **altinity-expert-clickhouse-merges** | Merge performance and part management | merge, parts, "too many parts", part count, backlog | High disk IO during merges, growing part counts | storage, schema, mutations |
| **altinity-expert-clickhouse-mutations** | ALTER UPDATE/DELETE tracking | mutation, ALTER UPDATE, ALTER DELETE, stuck | Mutations not completing, blocked mutations | merges, logs |
| **altinity-expert-clickhouse-memory** | RAM usage and OOM diagnostics | memory, OOM, MemoryTracker, RAM | Out of memory errors, high memory usage | merges, schema |
| **altinity-expert-clickhouse-storage** | Disk usage and compression | disk, storage, space, compression | Disk space issues, slow IO | - |
| **altinity-expert-clickhouse-caches** | Cache hit ratios and tuning | cache, hit ratio, mark cache, query cache, uncompressed cache | Low cache hit rates, cache misses | schema, memory |
| **altinity-expert-clickhouse-logs** | System log table health | system log, TTL, query_log health, log disk usage | System logs consuming disk, missing TTL | storage |
| **altinity-expert-clickhouse-schema** | Table design and optimization | table design, ORDER BY, partition, index, PK, MV | Poor compression, suboptimal partitioning, MV issues | merges, ingestion |
| **altinity-expert-clickhouse-dictionaries** | External dictionary diagnostics | dictionary, external dictionary | Dictionary load failures, slow dictionary updates | - |
| **altinity-expert-clickhouse-replication** | Replication health and Keeper | replica, replication, keeper, zookeeper, lag, readonly | Replication lag, readonly replicas, queue backlog | merges, storage, text_log |
| **altinity-expert-clickhouse-logs** | System log table health | system log, TTL, query_log health, log disk usage | System logs consuming disk, missing TTL | storage |
| **altinity-expert-clickhouse-metrics** | Real-time metrics monitoring | metrics, load average, connections, queue | High load, connection saturation, queue buildup | - |


Load modules with skill invocation: `/altinity-expert-clickhouse-{name}`

## Global Query Rules

Apply to ALL modules.

### SQL Style
- Lowercase keywords: `select`, `from`, `where`, `order by`
- Explicit columns only, never `select *`
- Default `limit 100` unless user specifies otherwise
- No comments in executed SQL

### Time Bounds (Required for *_log tables)
```sql
-- Default: last 24 hours
where event_date = today()

-- Or explicit time window
where event_time > now() - interval 1 hour

-- For longer analysis
where event_date >= today() - 7
```

### Result Size Management
- If query returns > 50 rows, summarize before presenting
- For large result sets, aggregate in SQL rather than loading raw data
- Use `formatReadableSize()`, `formatReadableQuantity()` for readability

### Schema Discovery
Before querying unfamiliar tables:
```sql
desc system.{table_name}
```

---

## Response Guidelines

- Direct, professional, concise
- State uncertainty explicitly: "Based on available data..." or "Cannot determine without..."
- Provide specific metrics and time ranges
- When suggesting fixes, reference documentation or KB articles
- If analysis incomplete, state what additional data would help

---


## Audit Severity Levels

All modules use consistent severity classification:

| Severity | Meaning | Action Timeline |
|----------|---------|-----------------|
| Critical | Immediate risk of failure/data loss | Fix now |
| Major | Significant performance/stability impact | Fix this week |
| Moderate | Suboptimal, will degrade over time | Plan fix |
| Minor | Best practice violation, low impact | Nice to have |
| OK/None | Passes check | No action needed |

## Query Output Patterns

Modules provide three types of queries:

1. **Audit Queries** - Return severity-rated findings:
   - Columns: `object`, `severity`, `details`
   - Run these first for quick assessment

2. **Diagnostic Queries** - Raw data inspection:
   - Current state without severity rating
   - Use for investigation

3. **Ad-Hoc Guidelines** - Rules for safe exploration:
   - Required safeguards (LIMIT, time bounds)
   - Useful patterns
