---
name: altinity-expert-clickhouse-ingestion
description: Diagnose ClickHouse INSERT performance, batch sizing, part creation patterns, and ingestion bottlenecks. Use for slow inserts and data pipeline issues.
---

# Insert Performance and Ingestion Analysis

Diagnose INSERT performance, batch sizing, part creation patterns, and ingestion bottlenecks.

---

## Diagnostics

Run all queries from the file checks.sql and analyze the results.

---

## Problem-Specific Investigation

### Insert with MV Overhead - Correlate by Query ID

When inserts feed materialized views, slow MVs cause insert delays. To correlate a slow insert with its MV breakdown:

```sql
-- Correlate slow insert with MV breakdown (requires query_id)
select
    view_name,
    view_duration_ms,
    read_rows,
    written_rows,
    status
from system.query_views_log
where query_id = '{query_id}'
order by view_duration_ms desc
```

---

## Ad-Hoc Query Guidelines

### Required Safeguards

```sql
-- Always limit results
limit 100

-- Always time-bound
where event_date = today()
-- or
where event_time > now() - interval 1 hour

-- For query_log, filter by type
where type = 'QueryFinish'  -- completed
-- or
where type like 'Exception%'  -- failed
```

### Useful Filters

```sql
-- Filter by table
where has(tables, 'database.table_name')

-- Filter by user
where user = 'producer_app'

-- Filter by insert size
where written_rows > 1000000  -- large inserts
where written_rows < 100      -- micro-batches
```

---

## Cross-Module Triggers

| Finding | Load Module | Reason |
|---------|-------------|--------|
| Part creation > 1/sec | `altinity-expert-clickhouse-merges` | Merge backlog likely |
| High memory during insert | `altinity-expert-clickhouse-memory` | Memory limits, buffer settings |
| Slow MV during insert | `altinity-expert-clickhouse-reporting` | Analyze MV query |
| TOO_MANY_PARTS error | `altinity-expert-clickhouse-merges` + `altinity-expert-clickhouse-schema` | Immediate action needed |
| Insert queries reading too much | `altinity-expert-clickhouse-schema` | MV design issues |
| Disk slow during insert | `altinity-expert-clickhouse-storage` | Storage bottleneck |

---

## Key Settings Reference

| Setting | Default | Impact |
|---------|---------|--------|
| `max_insert_block_size` | 1048545 | Rows per block |
| `min_insert_block_size_rows` | 1048545 | Min rows before flush |
| `min_insert_block_size_bytes` | 268435456 | Min bytes before flush |
| `async_insert` | 0 | Async insert mode |
| `async_insert_max_data_size` | 1000000 | Async batch threshold |
| `async_insert_busy_timeout_ms` | 200 | Max wait for async batch |
