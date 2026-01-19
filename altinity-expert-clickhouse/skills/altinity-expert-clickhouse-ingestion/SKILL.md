---
name: altinity-expert-clickhouse-ingestion
description: Diagnose ClickHouse INSERT performance, batch sizing, part creation patterns, and ingestion bottlenecks. Use for slow inserts and data pipeline issues.
---

# Insert Performance and Ingestion Analysis

Diagnose INSERT performance, batch sizing, part creation patterns, and ingestion bottlenecks.

---

## Quick Diagnostics (Run First)

### 1. Current Insert Activity

```sql
select
    query_id,
    user,
    elapsed,
    formatReadableSize(written_bytes) as written,
    written_rows,
    formatReadableSize(memory_usage) as memory,
    substring(query, 1, 80) as query_preview
from system.processes
where query_kind = 'Insert'
order by elapsed desc
limit 20
```

### 2. Recent Insert Performance (Last Hour)

```sql
select
    toStartOfFiveMinutes(event_time) as ts,
    count() as insert_count,
    round(avg(query_duration_ms)) as avg_ms,
    round(quantile(0.95)(query_duration_ms)) as p95_ms,
    sum(written_rows) as total_rows,
    formatReadableSize(sum(written_bytes)) as total_bytes
from system.query_log
where type = 'QueryFinish'
  and query_kind = 'Insert'
  and event_time > now() - interval 1 hour
group by ts
order by ts desc
limit 20
```

### 3. Part Creation Rate by Table

```sql
select
    database,
    table,
    toStartOfMinute(event_time) as minute,
    count() as parts_created,
    round(avg(rows)) as avg_rows_per_part,
    formatReadableSize(avg(size_in_bytes)) as avg_part_size
from system.part_log
where event_type = 'NewPart'
  and event_time > now() - interval 1 hour
group by database, table, minute
order by parts_created desc
limit 30
```

**Red flags:**
- `parts_created > 60` per minute (> 1/sec) → Batching too small
- `avg_rows_per_part < 10000` → Micro-batches, will cause merge pressure

### 4. Insert vs Merge Balance

```sql
select
    database,
    table,
    countIf(event_type = 'NewPart') as new_parts,
    countIf(event_type = 'MergeParts') as merges,
    countIf(event_type = 'MergeParts') - countIf(event_type = 'NewPart') as net_reduction
from system.part_log
where event_time > now() - interval 1 hour
group by database, table
having new_parts > 10
order by new_parts desc
limit 20
```

**If `net_reduction` negative** → Load `altinity-expert-clickhouse-merges` for merge backlog analysis

---

## Problem-Specific Queries

### Slow Inserts Investigation

```sql
-- Find slowest inserts
select
    event_time,
    query_id,
    user,
    query_duration_ms,
    written_rows,
    formatReadableSize(written_bytes) as written,
    formatReadableSize(memory_usage) as peak_memory,
    arrayStringConcat(tables, ', ') as tables,
    substring(query, 1, 100) as query_preview
from system.query_log
where type = 'QueryFinish'
  and query_kind = 'Insert'
  and event_date = today()
order by query_duration_ms desc
limit 20
```

### Insert with MV Overhead

When inserts feed materialized views, slow MVs cause insert delays.

```sql
-- Find slow MVs during inserts
select
    toStartOfFiveMinutes(qvl.event_time) as ts,
    qvl.view_name,
    count() as trigger_count,
    round(avg(qvl.view_duration_ms)) as avg_mv_ms,
    round(max(qvl.view_duration_ms)) as max_mv_ms,
    sum(qvl.written_rows) as rows_written_by_mv
from system.query_views_log qvl
where qvl.event_time > now() - interval 1 hour
group by ts, qvl.view_name
order by avg_mv_ms desc
limit 20
```

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

### Failed Inserts

```sql
select
    event_time,
    user,
    exception_code,
    exception,
    substring(query, 1, 150) as query_preview
from system.query_log
where type like 'Exception%'
  and query_kind = 'Insert'
  and event_date = today()
order by event_time desc
limit 30
```

**Common exception codes:**
- `241` (MEMORY_LIMIT_EXCEEDED) → Load `altinity-expert-clickhouse-memory`
- `252` (TOO_MANY_PARTS) → Load `altinity-expert-clickhouse-merges`
- `319` (UNKNOWN_PACKET_FROM_CLIENT) → Client/network issue

### Batch Size Analysis

```sql
-- Analyze actual batch sizes being inserted
select
    database,
    table,
    count() as insert_count,
    round(avg(written_rows)) as avg_batch_rows,
    min(written_rows) as min_batch,
    max(written_rows) as max_batch,
    round(quantile(0.5)(written_rows)) as median_batch
from system.query_log
where type = 'QueryFinish'
  and query_kind = 'Insert'
  and event_date = today()
  and written_rows > 0
group by database, table
having insert_count > 10
order by avg_batch_rows asc
limit 20
```

**Recommendations:**
- `avg_batch_rows < 1000` → Seriously under-batched
- `avg_batch_rows < 10000` → Could improve
- `avg_batch_rows > 100000` → Good batching
- Ideal: 10K-1M rows per insert

---

## Data Pipeline Patterns

### Kafka Engine Ingestion

```sql
-- Check Kafka consumer lag (if using Kafka engine)
select
    database,
    name,
    engine,
    total_rows,
    total_bytes
from system.tables
where engine like '%Kafka%'
```

```sql
-- Kafka-related messages in logs
select
    event_time,
    level,
    message
from system.text_log
where logger_name like '%Kafka%'
  and event_time > now() - interval 1 hour
order by event_time desc
limit 50
```

### Buffer Table Flush Patterns

```sql
-- Buffer table status
select
    database,
    name,
    total_rows,
    total_bytes
from system.tables
where engine = 'Buffer'
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

```sql
-- Check current settings for a user/profile
select name, value, changed
from system.settings
where name like '%insert%'
order by name
```
