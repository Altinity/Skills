---
name: altinity-expert-clickhouse-memory
description: Diagnose ClickHouse RAM usage, OOM errors, memory pressure, and allocation patterns. Use for memory-related issues and out-of-memory errors.
---

# Memory Usage and OOM Diagnostics

Diagnose RAM usage, memory pressure, OOM risks, and memory allocation patterns.

---

## Quick Diagnostics

### 1. Current Memory Overview

```sql
with
    (select value from system.asynchronous_metrics where metric = 'OSMemoryTotal') as total,
    (select value from system.asynchronous_metrics where metric = 'MemoryResident') as resident,
    (select value from system.asynchronous_metrics where metric = 'OSMemoryFreeWithoutCached') as free_without_cached,
    (select value from system.asynchronous_metrics where metric = 'OSMemoryCached') as cached,
    (select value from system.asynchronous_metrics where metric = 'OSMemoryBuffers') as buffers
select
    formatReadableSize(total) as total_ram,
    formatReadableSize(resident) as clickhouse_resident,
    formatReadableSize(free_without_cached) as free,
    formatReadableSize(cached) as os_cached,
    formatReadableSize(buffers) as os_buffers,
    round(100.0 * resident / total, 1) as clickhouse_pct,
    multiIf(resident > total * 0.9, 'Critical', resident > total * 0.8, 'Major', 'OK') as severity
```

### 2. Memory Breakdown by Component

```sql
select
    'Dictionaries' as component,
    formatReadableSize(sum(bytes_allocated)) as size,
    count() as count
from system.dictionaries

union all

select
    'Memory Tables (Memory/Set/Join)' as component,
    formatReadableSize(assumeNotNull(sum(total_bytes))) as size,
    count() as count
from system.tables
where engine in ('Memory', 'Set', 'Join')

union all

select
    'Primary Keys' as component,
    formatReadableSize(sum(primary_key_bytes_in_memory)) as size,
    sum(marks) as count
from system.parts
where active

union all

select
    'In-Memory Parts' as component,
    formatReadableSize(sumIf(data_uncompressed_bytes, part_type = 'InMemory')) as size,
    countIf(part_type = 'InMemory') as count
from system.parts
where active

union all

select
    'Active Merges' as component,
    formatReadableSize(sum(memory_usage)) as size,
    count() as count
from system.merges

union all

select
    'Running Queries' as component,
    formatReadableSize(sum(memory_usage)) as size,
    count() as count
from system.processes

union all

select
    'Mark Cache' as component,
    formatReadableSize(value) as size,
    0 as count
from system.asynchronous_metrics
where metric = 'MarkCacheBytes'

union all

select
    'Uncompressed Cache' as component,
    formatReadableSize(value) as size,
    0 as count
from system.asynchronous_metrics
where metric = 'UncompressedCacheBytes'

order by size desc
```

### 3. Memory Allocation Audit

```sql
with
    (select sum(bytes_allocated) from system.dictionaries) as dictionaries,
    (select assumeNotNull(sum(total_bytes)) from system.tables where engine in ('Memory','Set','Join')) as mem_tables,
    (select sum(primary_key_bytes_in_memory) from system.parts) as pk_memory,
    (select value from system.asynchronous_metrics where metric = 'OSMemoryTotal') as total_ram
select
    'Dictionaries + Memory Tables' as check_name,
    formatReadableSize(dictionaries + mem_tables) as used,
    round(100.0 * (dictionaries + mem_tables) / total_ram, 1) as pct,
    multiIf(pct > 30, 'Critical', pct > 25, 'Major', pct > 20, 'Moderate', 'OK') as severity

union all

select
    'Primary Keys' as check_name,
    formatReadableSize(pk_memory) as used,
    round(100.0 * pk_memory / total_ram, 1) as pct,
    multiIf(pct > 30, 'Critical', pct > 25, 'Major', pct > 20, 'Moderate', 'OK') as severity
```

---

## Current Memory Consumers

### Top Memory-Using Queries

```sql
select
    initial_query_id,
    user,
    round(elapsed, 1) as elapsed_sec,
    formatReadableSize(memory_usage) as memory,
    formatReadableSize(peak_memory_usage) as peak_memory,
    substring(query, 1, 80) as query_preview
from system.processes
order by peak_memory_usage desc
limit 15
```

### Top Memory-Using Dictionaries

```sql
select
    database,
    name,
    formatReadableSize(bytes_allocated) as memory,
    element_count as elements,
    source,
    loading_duration
from system.dictionaries
order by bytes_allocated desc
limit 20
```

### Top Memory-Using Tables (Memory Engine)

```sql
select
    database,
    name,
    engine,
    formatReadableSize(total_bytes) as size,
    total_rows as rows
from system.tables
where engine in ('Memory', 'Set', 'Join')
order by total_bytes desc
limit 20
```

### Top Primary Key Memory by Table

```sql
select
    database,
    table,
    formatReadableSize(sum(primary_key_bytes_in_memory)) as pk_memory,
    formatReadableSize(sum(primary_key_bytes_in_memory_allocated)) as pk_allocated,
    sum(marks) as marks
from system.parts
where active
group by database, table
order by sum(primary_key_bytes_in_memory) desc
limit 20
```

---

## Historical Analysis

### Memory Usage Over Time

```sql
select
    toStartOfFiveMinutes(event_time) as ts,
    formatReadableSize(max(value)) as peak_memory
from system.asynchronous_metric_log
where metric = 'MemoryResident'
  and event_time > now() - interval 4 hour
group by ts
order by ts
```

### Recent Memory-Heavy Queries

```sql
select
    event_time,
    initial_query_id,
    user,
    formatReadableSize(memory_usage) as memory,
    round(query_duration_ms / 1000, 1) as duration_sec,
    substring(query, 1, 100) as query_preview
from system.query_log
where event_date >= today()
  and type = 'QueryFinish'
order by memory_usage desc
limit 20
```

### Memory Exceptions

```sql
select
    event_time,
    user,
    exception_code,
    substring(exception, 1, 200) as exception,
    substring(query, 1, 100) as query_preview
from system.query_log
where type like 'Exception%'
  and exception_code = 241  -- MEMORY_LIMIT_EXCEEDED
  and event_date >= today() - 1
order by event_time desc
limit 30
```

---

## Advanced: Memory Timeline Reconstruction

Reconstructs memory usage peaks by operation type from query_log + part_log:

```sql
with
    now() - interval 6 hour as min_time,
    now() as max_time,
    interval 30 minute as time_frame_size
select
    toStartOfInterval(event_timestamp, time_frame_size) as timeframe,
    formatReadableSize(max(mem_overall)) as peak_ram,
    formatReadableSize(maxIf(mem_by_type, event_type = 'Insert')) as inserts_ram,
    formatReadableSize(maxIf(mem_by_type, event_type = 'Select')) as selects_ram,
    formatReadableSize(maxIf(mem_by_type, event_type = 'MergeParts')) as merge_ram,
    formatReadableSize(maxIf(mem_by_type, event_type = 'MutatePart')) as mutate_ram
from (
    select
        toDateTime(toUInt32(ts)) as event_timestamp,
        t as event_type,
        sum(mem) over (partition by t order by ts) as mem_by_type,
        sum(mem) over (order by ts) as mem_overall
    from (
        -- From part_log (merges, mutations)
        with arrayJoin([
            (toFloat64(event_time_microseconds) - (duration_ms / 1000), toInt64(peak_memory_usage)),
            (toFloat64(event_time_microseconds), -peak_memory_usage)
        ]) as data
        select
            cast(event_type, 'LowCardinality(String)') as t,
            data.1 as ts,
            data.2 as mem
        from system.part_log
        where event_time between min_time and max_time
          and peak_memory_usage != 0

        union all

        -- From query_log
        with arrayJoin([
            (toFloat64(query_start_time_microseconds), toInt64(memory_usage)),
            (toFloat64(event_time_microseconds), -memory_usage)
        ]) as data
        select
            query_kind as t,
            data.1 as ts,
            data.2 as mem
        from system.query_log
        where event_time between min_time and max_time
          and memory_usage != 0
    )
)
group by timeframe
order by timeframe
```

---

## Memory Settings Analysis

### Current Settings

```sql
select
    name,
    value,
    description
from system.server_settings
where name in (
    'max_server_memory_usage',
    'max_server_memory_usage_to_ram_ratio',
    'max_memory_usage',
    'max_memory_usage_for_user',
    'memory_tracker_fault_probability'
)
```

### Memory Used by Other Processes

```sql
with
    (select toFloat64(value) from system.server_settings where name = 'max_server_memory_usage_to_ram_ratio') as max_ratio,
    (select value from system.asynchronous_metrics where metric = 'OSMemoryTotal') as total,
    (select value from system.asynchronous_metrics where metric = 'OSMemoryFreeWithoutCached') as free_without_cached,
    (select value from system.asynchronous_metrics where metric = 'MemoryResident') as clickhouse_resident,
    (select value from system.asynchronous_metrics where metric = 'OSMemoryCached') as cached,
    (select value from system.asynchronous_metrics where metric = 'OSMemoryBuffers') as buffers,
    total - free_without_cached as total_used,
    total_used - (buffers + cached + clickhouse_resident) as used_by_others
select
    formatReadableSize(used_by_others) as other_processes_memory,
    formatReadableSize(total * (1 - max_ratio)) as max_allowed_for_others,
    round(100.0 * used_by_others / total, 1) as pct_of_total,
    multiIf(used_by_others > total * (1 - max_ratio), 'Critical', 'OK') as severity,
    if(severity = 'Critical', 'Other processes consuming RAM reserved for ClickHouse', 'OK') as note
```

---

## Problem Investigation

### High Memory from Aggregations

```sql
-- Find queries with high memory aggregations
select
    normalized_query_hash,
    count() as executions,
    formatReadableSize(max(memory_usage)) as max_memory,
    formatReadableSize(avg(memory_usage)) as avg_memory,
    any(substring(query, 1, 100)) as query_sample
from system.query_log
where type = 'QueryFinish'
  and event_date = today()
  and memory_usage > 1000000000  -- > 1GB
  and query ilike '%group by%'
group by normalized_query_hash
order by max(memory_usage) desc
limit 20
```

**Solutions:**
- Add `max_bytes_before_external_group_by`
- Use `max_threads` pragma to limit parallelism
- Restructure query to reduce group by cardinality

### High Memory from JOINs

```sql
select
    normalized_query_hash,
    count() as executions,
    formatReadableSize(max(memory_usage)) as max_memory,
    any(substring(query, 1, 100)) as query_sample
from system.query_log
where type = 'QueryFinish'
  and event_date = today()
  and memory_usage > 1000000000
  and query ilike '%join%'
group by normalized_query_hash
order by max(memory_usage) desc
limit 20
```

**Solutions:**
- Use `max_bytes_in_join`
- Consider `join_algorithm = 'partial_merge'` or `'auto'`
- Ensure smaller table on right side

---

## Ad-Hoc Query Guidelines

### Required Safeguards
```sql
-- Always time-bound log queries
where event_date >= today() - 1

-- Limit results
limit 100
```

### Memory-Related Metrics
- `MemoryTracking` - current tracked memory
- `MemoryResident` - RSS
- `OSMemoryTotal`, `OSMemoryFreeWithoutCached` - system memory

---

## Cross-Module Triggers

| Finding | Load Module | Reason |
|---------|-------------|--------|
| High merge memory | `altinity-expert-clickhouse-merges` | Analyze merge patterns |
| Large dictionaries | `altinity-expert-clickhouse-dictionaries` | Dictionary optimization |
| Cache too large | `altinity-expert-clickhouse-caches` | Cache sizing |
| PK memory high | `altinity-expert-clickhouse-schema` | ORDER BY optimization |
| Query OOMs | `altinity-expert-clickhouse-reporting` | Query optimization |

---

## Settings Reference

| Setting | Scope | Notes |
|---------|-------|-------|
| `max_memory_usage` | Query | Per-query limit |
| `max_memory_usage_for_user` | User | Per-user aggregate |
| `max_server_memory_usage` | Server | Global limit |
| `max_server_memory_usage_to_ram_ratio` | Server | Auto-limit as % of RAM |
| `max_bytes_before_external_group_by` | Query | Spill aggregation to disk |
| `max_bytes_in_join` | Query | Spill join to disk |
