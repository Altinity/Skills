---
name: altinity-expert-clickhouse-expert
description: ClickHouse performance analysis and troubleshooting agent. Use when analyzing ClickHouse server health, diagnosing query performance issues, investigating system problems, or performing root cause analysis (RCA). Triggers on requests involving ClickHouse logs, metrics, query optimization, ingestion issues, merge problems, or server diagnostics.
---

# ClickHouse Analyst

Modular agent for ClickHouse diagnostics and performance analysis.

## Startup Procedure

1. Verify connectivity: `select hostname(), version()`
2. If connection fails, stop and report error
3. Report hostname and version to user
4. Based on user request, load appropriate module(s)

---

## Module Index

Complete module registry. This is the single source of truth for routing logic.

| Module | Purpose | Triggers (Keywords) | Symptoms | Chains To |
|--------|---------|---------------------|----------|-----------|
| **altinity-expert-clickhouse-overview** | System health entry point, comprehensive audit | health check, audit, status, overview | General slowness, unclear issues | Route based on findings |
| **altinity-expert-clickhouse-reporting** | Query performance analysis | slow query, SELECT, performance, latency, timeout | High query duration, timeouts, excessive reads | memory, caches, schema |
| **altinity-expert-clickhouse-ingestion** | Insert performance diagnostics | slow insert, ingestion, batch size, new parts | Insert timeouts, part backlog growing | merges, storage, memory |
| **altinity-expert-clickhouse-merges** | Merge performance and part management | merge, parts, "too many parts", part count, backlog | High disk IO during merges, growing part counts | storage, schema, mutations |
| **altinity-expert-clickhouse-mutations** | ALTER UPDATE/DELETE tracking | mutation, ALTER UPDATE, ALTER DELETE, stuck | Mutations not completing, blocked mutations | merges, errors |
| **altinity-expert-clickhouse-memory** | RAM usage and OOM diagnostics | memory, OOM, MemoryTracker, RAM | Out of memory errors, high memory usage | merges, schema |
| **altinity-expert-clickhouse-storage** | Disk usage and compression | disk, storage, space, compression | Disk space issues, slow IO | - |
| **altinity-expert-clickhouse-caches** | Cache hit ratios and tuning | cache, hit ratio, mark cache, query cache, uncompressed cache | Low cache hit rates, cache misses | schema, memory |
| **altinity-expert-clickhouse-errors** | Exception patterns and failed queries | error, exception, failed, crash | Query failures, exceptions | - |
| **altinity-expert-clickhouse-text-log** | Server log analysis | log, text_log, debug, trace | Need to investigate server logs | - |
| **altinity-expert-clickhouse-schema** | Table design and optimization | table design, ORDER BY, partition, index, PK, MV | Poor compression, suboptimal partitioning, MV issues | merges, ingestion |
| **altinity-expert-clickhouse-dictionaries** | External dictionary diagnostics | dictionary, external dictionary | Dictionary load failures, slow dictionary updates | - |
| **altinity-expert-clickhouse-replication** | Replication health and Keeper | replica, replication, keeper, zookeeper, lag, readonly | Replication lag, readonly replicas, queue backlog | merges, storage, text_log |
| **altinity-expert-clickhouse-logs** | System log table health | system log, TTL, query_log health, log disk usage | System logs consuming disk, missing TTL | storage |
| **altinity-expert-clickhouse-metrics** | Real-time metrics monitoring | metrics, load average, connections, queue | High load, connection saturation, queue buildup | - |

### Multi-Module Scenarios

Some problems require multiple modules. Load in order listed.

| Symptom Pattern | Modules to Load |
|-----------------|-----------------|
| "general health check" | `altinity-expert-clickhouse-overview` → route to specific modules |
| "inserts are slow" | `altinity-expert-clickhouse-ingestion` → `altinity-expert-clickhouse-merges` → `altinity-expert-clickhouse-storage` |
| "too many parts error" | `altinity-expert-clickhouse-merges` → `altinity-expert-clickhouse-ingestion` → `altinity-expert-clickhouse-schema` |
| "queries timing out" | `altinity-expert-clickhouse-reporting` → `altinity-expert-clickhouse-memory` → `altinity-expert-clickhouse-caches` |
| "server is slow overall" | `altinity-expert-clickhouse-overview` → `altinity-expert-clickhouse-memory` → `altinity-expert-clickhouse-storage` |
| "replication lag" | `altinity-expert-clickhouse-replication` → `altinity-expert-clickhouse-merges` → `altinity-expert-clickhouse-storage` |
| "OOM during merge" | `altinity-expert-clickhouse-memory` → `altinity-expert-clickhouse-merges` → `altinity-expert-clickhouse-schema` |
| "mutations not completing" | `altinity-expert-clickhouse-mutations` → `altinity-expert-clickhouse-merges` → `altinity-expert-clickhouse-errors` |
| "cache hit ratio low" | `altinity-expert-clickhouse-caches` → `altinity-expert-clickhouse-schema` → `altinity-expert-clickhouse-memory` |
| "readonly replica" | `altinity-expert-clickhouse-replication` → `altinity-expert-clickhouse-storage` → `altinity-expert-clickhouse-text-log` |
| "schema review needed" | `altinity-expert-clickhouse-schema` → `altinity-expert-clickhouse-overview` → `altinity-expert-clickhouse-ingestion` |
| "version upgrade planning" | `altinity-expert-clickhouse-overview` (version check) |
| "system log issues" | `altinity-expert-clickhouse-logs` → `altinity-expert-clickhouse-storage` |

### Module Chaining

Modules may suggest loading additional modules based on findings. Follow these triggers:

```
altinity-expert-clickhouse-merges findings:
  - Slow merges + high disk IO → load altinity-expert-clickhouse-storage
  - Slow merges + normal disk → load altinity-expert-clickhouse-schema
  - Merge blocked by mutation → load altinity-expert-clickhouse-mutations

altinity-expert-clickhouse-ingestion findings:
  - Part backlog growing → load altinity-expert-clickhouse-merges
  - High memory during insert → load altinity-expert-clickhouse-memory
  - MV slow during insert → load altinity-expert-clickhouse-reporting (for MV analysis)

altinity-expert-clickhouse-reporting findings:
  - Query reads too many parts → load altinity-expert-clickhouse-merges, altinity-expert-clickhouse-schema
  - High memory queries → load altinity-expert-clickhouse-memory
  - Distributed query slow → load altinity-expert-clickhouse-replication
```

---

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

## Standard Diagnostics Entry Point

When user asks for general health check, run these in order:

### 1. System Overview
```sql
select
    hostName() as host,
    version() as version,
    uptime() as uptime_seconds,
    formatReadableTimeDelta(uptime()) as uptime
```

### 2. Current Activity
```sql
select
    count() as active_queries,
    sum(memory_usage) as total_memory,
    formatReadableSize(sum(memory_usage)) as memory_readable
from system.processes
where is_cancelled = 0
```

### 3. Part Health (quick)
```sql
select
    database,
    table,
    count() as parts,
    sum(rows) as rows
from system.parts
where active
group by database, table
order by parts desc
limit 10
```

### 4. Recent Errors (quick)
```sql
select
    toStartOfHour(event_time) as hour,
    count() as error_count
from system.query_log
where type like 'Exception%'
  and event_date = today()
group by hour
order by hour desc
limit 6
```

Then based on findings, load specific modules.

---

## Information Sources Priority

1. **System tables via MCP** (primary source)
2. **Module-specific queries** (predefined patterns)
3. **ClickHouse docs**: https://clickhouse.com/docs/
4. **Altinity KB**: https://kb.altinity.com/
5. **GitHub issues**: https://github.com/ClickHouse/ClickHouse/issues

---

## Response Guidelines

- Direct, professional, concise
- State uncertainty explicitly: "Based on available data..." or "Cannot determine without..."
- Provide specific metrics and time ranges
- When suggesting fixes, reference documentation or KB articles
- If analysis incomplete, state what additional data would help

---

## Available Modules

```
altinity-expert-clickhouse-overview       # System health check, entry point, audit summary
altinity-expert-clickhouse-schema         # Table design, ORDER BY, partitioning, MVs, PK analysis
altinity-expert-clickhouse-reporting      # SELECT query performance, query_log analysis
altinity-expert-clickhouse-ingestion      # INSERT patterns, part_log, batch analysis
altinity-expert-clickhouse-merges         # Merge performance, part management
altinity-expert-clickhouse-mutations      # ALTER UPDATE/DELETE tracking
altinity-expert-clickhouse-memory         # RAM usage, MemoryTracker, OOM, memory timeline
altinity-expert-clickhouse-storage        # Disk usage, compression, part sizes
altinity-expert-clickhouse-caches         # Mark cache, uncompressed cache, query cache
altinity-expert-clickhouse-replication    # Keeper, replicas, replication queue
altinity-expert-clickhouse-errors         # Exception patterns, failed queries
altinity-expert-clickhouse-text-log       # Server logs, debug traces
altinity-expert-clickhouse-dictionaries   # External dictionaries
altinity-expert-clickhouse-logs           # System log table health (TTL, disk usage)
altinity-expert-clickhouse-metrics        # Real-time async/sync metrics monitoring
```

Load modules with skill invocation: `/altinity-expert-clickhouse-{name}`

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
