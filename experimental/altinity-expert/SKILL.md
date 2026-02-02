---
name: altinity-expert
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
| **altinity-expert-overview** | System health entry point, comprehensive audit | health check, audit, status, overview | General slowness, unclear issues | Route based on findings |
| **altinity-expert-reporting** | Query performance analysis | slow query, SELECT, performance, latency, timeout | High query duration, timeouts, excessive reads | memory, caches, schema |
| **altinity-expert-ingestion** | Insert performance diagnostics | slow insert, ingestion, batch size, new parts | Insert timeouts, part backlog growing | merges, storage, memory |
| **altinity-expert-merges** | Merge performance and part management | merge, parts, "too many parts", part count, backlog | High disk IO during merges, growing part counts | storage, schema, mutations |
| **altinity-expert-mutations** | ALTER UPDATE/DELETE tracking | mutation, ALTER UPDATE, ALTER DELETE, stuck | Mutations not completing, blocked mutations | merges, errors |
| **altinity-expert-memory** | RAM usage and OOM diagnostics | memory, OOM, MemoryTracker, RAM | Out of memory errors, high memory usage | merges, schema |
| **altinity-expert-storage** | Disk usage and compression | disk, storage, space, compression | Disk space issues, slow IO | - |
| **altinity-expert-caches** | Cache hit ratios and tuning | cache, hit ratio, mark cache, query cache, uncompressed cache | Low cache hit rates, cache misses | schema, memory |
| **altinity-expert-errors** | Exception patterns and failed queries | error, exception, failed, crash | Query failures, exceptions | - |
| **altinity-expert-text-log** | Server log analysis | log, text_log, debug, trace | Need to investigate server logs | - |
| **altinity-expert-schema** | Table design and optimization | table design, ORDER BY, partition, index, PK, MV | Poor compression, suboptimal partitioning, MV issues | merges, ingestion |
| **altinity-expert-dictionaries** | External dictionary diagnostics | dictionary, external dictionary | Dictionary load failures, slow dictionary updates | - |
| **altinity-expert-replication** | Replication health and Keeper | replica, replication, keeper, zookeeper, lag, readonly | Replication lag, readonly replicas, queue backlog | merges, storage, text_log |
| **altinity-expert-logs** | System log table health | system log, TTL, query_log health, log disk usage | System logs consuming disk, missing TTL | storage |
| **altinity-expert-metrics** | Real-time metrics monitoring | metrics, load average, connections, queue | High load, connection saturation, queue buildup | - |

### Multi-Module Scenarios

Some problems require multiple modules. Load in order listed.

| Symptom Pattern | Modules to Load |
|-----------------|-----------------|
| "general health check" | `altinity-expert-overview` → route to specific modules |
| "inserts are slow" | `altinity-expert-ingestion` → `altinity-expert-merges` → `altinity-expert-storage` |
| "too many parts error" | `altinity-expert-merges` → `altinity-expert-ingestion` → `altinity-expert-schema` |
| "queries timing out" | `altinity-expert-reporting` → `altinity-expert-memory` → `altinity-expert-caches` |
| "server is slow overall" | `altinity-expert-overview` → `altinity-expert-memory` → `altinity-expert-storage` |
| "replication lag" | `altinity-expert-replication` → `altinity-expert-merges` → `altinity-expert-storage` |
| "OOM during merge" | `altinity-expert-memory` → `altinity-expert-merges` → `altinity-expert-schema` |
| "mutations not completing" | `altinity-expert-mutations` → `altinity-expert-merges` → `altinity-expert-errors` |
| "cache hit ratio low" | `altinity-expert-caches` → `altinity-expert-schema` → `altinity-expert-memory` |
| "readonly replica" | `altinity-expert-replication` → `altinity-expert-storage` → `altinity-expert-text-log` |
| "schema review needed" | `altinity-expert-schema` → `altinity-expert-overview` → `altinity-expert-ingestion` |
| "version upgrade planning" | `altinity-expert-overview` (version check) |
| "system log issues" | `altinity-expert-logs` → `altinity-expert-storage` |

### Module Chaining

Modules may suggest loading additional modules based on findings. Follow these triggers:

```
altinity-expert-merges findings:
  - Slow merges + high disk IO → load altinity-expert-storage
  - Slow merges + normal disk → load altinity-expert-schema
  - Merge blocked by mutation → load altinity-expert-mutations

altinity-expert-ingestion findings:
  - Part backlog growing → load altinity-expert-merges
  - High memory during insert → load altinity-expert-memory
  - MV slow during insert → load altinity-expert-reporting (for MV analysis)

altinity-expert-reporting findings:
  - Query reads too many parts → load altinity-expert-merges, altinity-expert-schema
  - High memory queries → load altinity-expert-memory
  - Distributed query slow → load altinity-expert-replication
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
altinity-expert-overview       # System health check, entry point, audit summary
altinity-expert-schema         # Table design, ORDER BY, partitioning, MVs, PK analysis
altinity-expert-reporting      # SELECT query performance, query_log analysis
altinity-expert-ingestion      # INSERT patterns, part_log, batch analysis
altinity-expert-merges         # Merge performance, part management
altinity-expert-mutations      # ALTER UPDATE/DELETE tracking
altinity-expert-memory         # RAM usage, MemoryTracker, OOM, memory timeline
altinity-expert-storage        # Disk usage, compression, part sizes
altinity-expert-caches         # Mark cache, uncompressed cache, query cache
altinity-expert-replication    # Keeper, replicas, replication queue
altinity-expert-errors         # Exception patterns, failed queries
altinity-expert-text-log       # Server logs, debug traces
altinity-expert-dictionaries   # External dictionaries
altinity-expert-logs           # System log table health (TTL, disk usage)
altinity-expert-metrics        # Real-time async/sync metrics monitoring
```

Load modules with skill invocation: `/altinity-expert-{name}`

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
