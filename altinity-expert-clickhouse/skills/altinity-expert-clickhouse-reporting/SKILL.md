---
name: altinity-expert-clickhouse-reporting
description: Diagnose ClickHouse SELECT query performance, analyze query patterns, identify slow queries, and find optimization opportunities. Use for query latency and timeout issues.
---

# Query Performance Analysis

Diagnose SELECT query performance issues, analyze query patterns, and identify optimization opportunities.

---

## Quick Diagnostics

### 1. Current Running Queries

```sql
select
    query_id,
    user,
    round(elapsed, 1) as elapsed_sec,
    formatReadableSize(read_bytes) as read_bytes,
    formatReadableSize(memory_usage) as memory,
    read_rows,
    substring(query, 1, 80) as query_preview
from system.processes
where is_cancelled = 0
order by elapsed desc
limit 20
```

### 2. Recent Query Performance Summary

```sql
select
    toStartOfFiveMinutes(event_time) as ts,
    count() as queries,
    countIf(type like 'Exception%') as failed,
    round(avg(query_duration_ms)) as avg_ms,
    round(quantile(0.95)(query_duration_ms)) as p95_ms,
    round(max(query_duration_ms)) as max_ms,
    formatReadableSize(sum(read_bytes)) as read_bytes,
    formatReadableSize(sum(memory_usage)) as memory
from system.query_log
where event_time > now() - interval 1 hour
  and type in ('QueryFinish', 'ExceptionWhileProcessing')
group by ts
order by ts desc
```

### 3. Slowest Queries (Last 24h)

```sql
select
    query_id,
    user,
    query_duration_ms,
    formatReadableSize(read_bytes) as read_bytes,
    formatReadableSize(memory_usage) as memory,
    read_rows,
    result_rows,
    substring(query, 1, 100) as query_preview
from system.query_log
where type = 'QueryFinish'
  and event_date >= today() - 1
  and query_kind = 'Select'
order by query_duration_ms desc
limit 20
```

### 4. Most Frequent Queries

```sql
select
    normalized_query_hash,
    count() as executions,
    round(avg(query_duration_ms)) as avg_ms,
    round(quantile(0.95)(query_duration_ms)) as p95_ms,
    formatReadableSize(avg(read_bytes)) as avg_read,
    formatReadableSize(avg(memory_usage)) as avg_memory,
    any(substring(query, 1, 100)) as query_sample
from system.query_log
where type = 'QueryFinish'
  and event_date = today()
  and query_kind = 'Select'
group by normalized_query_hash
having count() > 5
order by count() desc
limit 30
```

---

## Query Analysis

### Queries by CPU Time

```sql
select
    normalized_query_hash,
    sum(ProfileEvents['UserTimeMicroseconds']) as user_cpu_us,
    sum(ProfileEvents['SystemTimeMicroseconds']) as system_cpu_us,
    count() as executions,
    round(avg(query_duration_ms)) as avg_duration_ms,
    any(substring(query, 1, 80)) as query_sample
from system.query_log
where type = 'QueryFinish'
  and event_date >= today() - 1
group by normalized_query_hash
order by user_cpu_us desc
limit 20
```

### Queries Reading Too Much Data

```sql
select
    query_id,
    user,
    formatReadableSize(read_bytes) as read_bytes,
    read_rows,
    result_rows,
    round(read_rows / nullIf(result_rows, 0)) as read_amplification,
    round(query_duration_ms / 1000, 1) as duration_sec,
    substring(query, 1, 100) as query_preview
from system.query_log
where type = 'QueryFinish'
  and event_date = today()
  and query_kind = 'Select'
  and read_rows > 0
order by read_bytes desc
limit 20
```

**High `read_amplification`** indicates:
- Missing or ineffective indexes
- Poor ORDER BY alignment with query patterns
- Full table scans

### Queries by Tables Accessed

```sql
select
    arrayStringConcat(tables, ', ') as tables,
    count() as queries,
    round(avg(query_duration_ms)) as avg_ms,
    formatReadableSize(avg(read_bytes)) as avg_read
from system.query_log
where type = 'QueryFinish'
  and event_date = today()
  and length(tables) > 0
group by tables
order by count() desc
limit 30
```

---

## Failed Queries

### Recent Failures

```sql
select
    event_time,
    user,
    exception_code,
    substring(exception, 1, 150) as exception,
    substring(query, 1, 100) as query_preview
from system.query_log
where type like 'Exception%'
  and event_date = today()
order by event_time desc
limit 30
```

### Failure Summary by Error Code

```sql
select
    exception_code,
    count() as failures,
    any(substring(exception, 1, 100)) as example_exception
from system.query_log
where type like 'Exception%'
  and event_date = today()
group by exception_code
order by failures desc
limit 20
```

**Common exception codes:**
- `60` - Table doesn't exist
- `62` - Syntax error
- `241` - Memory limit exceeded
- `159` - Timeout
- `252` - Too many parts

---

## Query Pattern Analysis

### Query Types Distribution

```sql
select
    query_kind,
    count() as queries,
    round(avg(query_duration_ms)) as avg_ms,
    formatReadableSize(sum(read_bytes)) as total_read,
    formatReadableSize(sum(written_bytes)) as total_written
from system.query_log
where type = 'QueryFinish'
  and event_date = today()
group by query_kind
order by queries desc
```

### Peak Query Hours

```sql
select
    toHour(event_time) as hour,
    count() as queries,
    round(avg(query_duration_ms)) as avg_ms,
    max(query_duration_ms) as max_ms
from system.query_log
where type = 'QueryFinish'
  and event_date = today()
group by hour
order by hour
```

### Queries by User

```sql
select
    user,
    count() as queries,
    countIf(type like 'Exception%') as failures,
    round(avg(query_duration_ms)) as avg_ms,
    formatReadableSize(sum(read_bytes)) as total_read
from system.query_log
where event_date = today()
group by user
order by queries desc
```

---

## Materialized View Performance

### MV Execution During Inserts

```sql
select
    view_name,
    count() as trigger_count,
    round(avg(view_duration_ms)) as avg_ms,
    round(max(view_duration_ms)) as max_ms,
    round(sum(view_duration_ms) / 1000) as total_sec,
    formatReadableSize(sum(written_bytes)) as written
from system.query_views_log
where event_time > now() - interval 1 hour
group by view_name
order by sum(view_duration_ms) desc
limit 20
```

### Slow MV Breakdown by Query

```sql
select
    query_id,
    view_name,
    view_type,
    view_duration_ms,
    read_rows,
    written_rows,
    formatReadableSize(peak_memory_usage) as memory,
    status
from system.query_views_log
where event_time > now() - interval 1 hour
order by view_duration_ms desc
limit 30
```

---

## Query Optimization Hints

### Index Usage Check

```sql
-- Check if data skipping indices exist
select
    database,
    table,
    name as index_name,
    type,
    expr,
    granularity
from system.data_skipping_indices
where database = '{database}' and table = '{table}'
```

### Mark Count for Query

For a specific slow query, check how many marks (granules) were read:

```sql
select
    query_id,
    read_rows,
    selected_marks,
    selected_parts,
    formatReadableSize(read_bytes) as read_bytes,
    round(read_rows / nullIf(selected_marks, 0)) as rows_per_mark
from system.query_log
where query_id = '{query_id}'
  and type = 'QueryFinish'
```

**High `selected_marks`** relative to result = index not selective enough.

---

## Distributed Query Analysis

### Distributed Query Performance

```sql
select
    query_id,
    is_initial_query,
    formatReadableSize(read_bytes) as read_bytes,
    read_rows,
    round(query_duration_ms / 1000, 1) as duration_sec,
    length(thread_ids) as threads,
    substring(query, 1, 80) as query_preview
from system.query_log
where type = 'QueryFinish'
  and event_date = today()
  and query like '%Distributed%' or is_initial_query = 0
order by query_duration_ms desc
limit 30
```

---

## Ad-Hoc Query Guidelines

### Required Safeguards
```sql
-- Always time-bound
where event_date >= today() - 1
-- or
where event_time > now() - interval 1 hour

-- Always limit
limit 100

-- Filter by type
where type = 'QueryFinish'  -- completed
where type like 'Exception%'  -- failed
```

### Useful Filters
```sql
-- By user
where user = 'analytics_user'

-- By query pattern
where query ilike '%SELECT%FROM my_table%'

-- By duration threshold
where query_duration_ms > 10000  -- > 10 seconds

-- By normalized hash (for specific query pattern)
where normalized_query_hash = 1234567890
```

---

## Cross-Module Triggers

| Finding | Load Module | Reason |
|---------|-------------|--------|
| High memory queries | `altinity-expert-clickhouse-memory` | Memory limits/optimization |
| Reading too many parts | `altinity-expert-clickhouse-merges` | Part consolidation |
| Poor index selectivity | `altinity-expert-clickhouse-schema` | Index/ORDER BY design |
| Cache misses | `altinity-expert-clickhouse-caches` | Cache sizing |
| MV slow | `altinity-expert-clickhouse-ingestion` | MV optimization |

---

## Settings Reference

| Setting | Scope | Notes |
|---------|-------|-------|
| `max_execution_time` | Query | Query timeout |
| `max_rows_to_read` | Query | Limit rows scanned |
| `max_bytes_to_read` | Query | Limit bytes scanned |
| `max_threads` | Query | Parallelism |
| `use_query_cache` | Query | Enable query result caching |
| `log_queries` | Server | Enable query logging |
| `log_queries_min_query_duration_ms` | Server | Log threshold |
