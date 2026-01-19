---
name: altinity-expert-clickhouse-caches
description: Analyze ClickHouse cache systems including mark cache, uncompressed cache, and query cache. Use for cache hit ratio issues and cache tuning.
---

# Cache Analysis and Tuning

Analyze ClickHouse cache systems: mark cache, uncompressed cache, query cache, and compiled expression cache.

---

## Quick Audits

### 1. Mark Cache Health

```sql
with
    (select value from system.events where event = 'MarkCacheHits') as hits,
    (select value from system.events where event = 'MarkCacheMisses') as misses,
    hits / nullIf(hits + misses, 0) as hit_ratio,
    (select value from system.asynchronous_metrics where metric = 'MarkCacheBytes') as cache_bytes,
    (select sum(marks_bytes) from system.parts where active) as total_marks_bytes,
    (select value from system.asynchronous_metrics where metric = 'OSMemoryTotal') as total_ram
select
    'Mark Cache' as cache,
    formatReadableSize(cache_bytes) as size,
    hits,
    misses,
    round(hit_ratio, 3) as hit_ratio,
    multiIf(hit_ratio < 0.3, 'Critical', hit_ratio < 0.5, 'Major', hit_ratio < 0.7, 'Moderate', 'OK') as hit_severity,
    round(100.0 * cache_bytes / total_ram, 2) as pct_of_ram,
    multiIf(pct_of_ram > 25, 'Critical', pct_of_ram > 20, 'Major', pct_of_ram > 15, 'Moderate', 'OK') as size_severity,
    round(100.0 * cache_bytes / nullIf(total_marks_bytes, 0), 2) as pct_marks_cached
settings system_events_show_zero_values = 1
```

**Interpretation:**
- `hit_ratio < 0.7` → Cache too small or access pattern not cache-friendly
- `pct_of_ram > 15%` → Cache consuming too much RAM
- `pct_marks_cached < 1%` → Very few marks in cache (might be OK for large datasets)

### 2. Uncompressed Cache Health

```sql
with
    assumeNotNull((select value from system.events where event = 'UncompressedCacheHits')) as hits,
    assumeNotNull((select value from system.events where event = 'UncompressedCacheMisses')) as misses,
    hits / nullIf(hits + misses, 0) as hit_ratio,
    (select value from system.asynchronous_metrics where metric = 'UncompressedCacheBytes') as cache_bytes,
    (select value from system.asynchronous_metrics where metric = 'OSMemoryTotal') as total_ram
select
    'Uncompressed Cache' as cache,
    formatReadableSize(cache_bytes) as size,
    hits,
    misses,
    round(hit_ratio, 3) as hit_ratio,
    multiIf(hit_ratio < 0.01 and misses > 1000, 'Moderate', 'OK') as hit_severity,
    round(100.0 * cache_bytes / total_ram, 2) as pct_of_ram,
    multiIf(pct_of_ram > 25, 'Critical', pct_of_ram > 20, 'Major', pct_of_ram > 15, 'Moderate', 'OK') as size_severity
settings system_events_show_zero_values = 1
```

**Note:** Uncompressed cache is disabled by default. Low hit ratio is normal if not explicitly configured.

### 3. Query Cache Health (v23.1+)

```sql
select
    'Query Cache' as cache,
    formatReadableSize(sum(result_size)) as cached_data,
    count() as entries,
    sum(times_used) as total_hits,
    round(avg(times_used), 2) as avg_hits_per_entry,
    min(query_start_time) as oldest_entry,
    max(query_start_time) as newest_entry
from system.query_cache
```

### 4. Compiled Expression Cache

```sql
with
    (select value from system.events where event = 'CompiledExpressionCacheHits') as hits,
    (select value from system.events where event = 'CompiledExpressionCacheMisses') as misses
select
    'Compiled Expression Cache' as cache,
    hits,
    misses,
    round(hits / nullIf(hits + misses, 0), 3) as hit_ratio
settings system_events_show_zero_values = 1
```

---

## Detailed Diagnostics

### Mark Cache by Table

```sql
select
    database,
    table,
    formatReadableSize(sum(marks_bytes)) as marks_size,
    sum(marks) as marks_count,
    count() as parts
from system.parts
where active
group by database, table
order by sum(marks_bytes) desc
limit 20
```

### Primary Key Memory by Table

```sql
select
    database,
    table,
    formatReadableSize(sum(primary_key_bytes_in_memory)) as pk_in_memory,
    formatReadableSize(sum(primary_key_bytes_in_memory_allocated)) as pk_allocated,
    sum(marks) as marks
from system.parts
where active
group by database, table
order by sum(primary_key_bytes_in_memory) desc
limit 20
```

### Cache Events Over Time

```sql
select
    toStartOfFiveMinutes(event_time) as ts,
    sumIf(value, metric = 'MarkCacheBytes') as mark_cache_bytes,
    sumIf(value, metric = 'UncompressedCacheBytes') as uncompressed_cache_bytes,
    sumIf(value, metric = 'QueryCacheBytes') as query_cache_bytes
from system.asynchronous_metric_log
where event_time > now() - interval 1 hour
  and metric in ('MarkCacheBytes', 'UncompressedCacheBytes', 'QueryCacheBytes')
group by ts
order by ts
```

---

## Cache Sizing Recommendations

### Current Cache Settings

```sql
select name, value, description
from system.server_settings
where name in (
    'mark_cache_size',
    'uncompressed_cache_size',
    'query_cache_max_size',
    'compiled_expression_cache_size'
)
```

### Recommended Sizing

| Cache | Typical Size | Notes |
|-------|-------------|-------|
| Mark Cache | 5-10% of RAM | Higher if random access patterns |
| Uncompressed | 0 (disabled) or 5-10% | Enable only for specific workloads |
| Query Cache | 1-5GB | For repeated identical queries |
| Compiled Expression | 128MB-1GB | Higher for complex expressions |

### Sizing Analysis

```sql
with
    (select value from system.asynchronous_metrics where metric = 'OSMemoryTotal') as total_ram,
    (select sum(marks_bytes) from system.parts where active) as total_marks
select
    formatReadableSize(total_marks) as total_marks_size,
    formatReadableSize(total_ram * 0.05) as recommended_mark_cache_5pct,
    formatReadableSize(total_ram * 0.10) as recommended_mark_cache_10pct,
    formatReadableSize(least(total_marks, total_ram * 0.15)) as ideal_mark_cache,
    'Ideal = min(all_marks, 15% RAM)' as formula
```

---

## Problem Investigation

### Poor Mark Cache Hit Ratio

**Possible causes:**
1. Cache too small for working set
2. Queries scan many different tables
3. Many small queries to cold data

**Diagnostic:**
```sql
-- Check which tables are being queried
select
    arrayStringConcat(tables, ', ') as tables,
    count() as query_count,
    round(avg(read_rows)) as avg_rows_read
from system.query_log
where type = 'QueryFinish'
  and event_date = today()
  and length(tables) > 0
group by tables
order by query_count desc
limit 20
```

### Cache Too Large

If mark cache > 15% RAM:

```sql
-- Check for tables with excessive marks
select
    database,
    table,
    formatReadableSize(sum(marks_bytes)) as marks_size,
    sum(marks) as marks_count,
    round(sum(marks_bytes) / (select value from system.asynchronous_metrics where metric = 'MarkCacheBytes') * 100, 2) as pct_of_cache
from system.parts
where active
group by database, table
having sum(marks_bytes) > 100000000
order by sum(marks_bytes) desc
limit 20
```

**Solutions:**
- Reduce `index_granularity` for tables with excessive marks
- Drop unused tables
- Reduce `mark_cache_size` setting

---

## Ad-Hoc Query Guidelines

### Required Safeguards
- Cache metrics are cumulative since restart - check uptime for context
- Compare hit ratios over time, not just current values

### Useful Views

```sql
-- Cache hit ratio over time (last hour)
select
    toStartOfMinute(event_time) as ts,
    sum(ProfileEvent_MarkCacheHits) as hits,
    sum(ProfileEvent_MarkCacheMisses) as misses,
    round(hits / nullIf(hits + misses, 0), 3) as hit_ratio
from system.metric_log
where event_time > now() - interval 1 hour
group by ts
order by ts
```

---

## Cross-Module Triggers

| Finding | Load Module | Reason |
|---------|-------------|--------|
| Cache using too much RAM | `altinity-expert-clickhouse-memory` | Overall memory analysis |
| Poor hit ratio + high disk IO | `altinity-expert-clickhouse-storage` | Disk bottleneck |
| Many marks per table | `altinity-expert-clickhouse-schema` | Consider index_granularity tuning |
| Query cache misses | `altinity-expert-clickhouse-reporting` | Query pattern analysis |

---

## Settings Reference

| Setting | Scope | Notes |
|---------|-------|-------|
| `mark_cache_size` | Server | Global mark cache limit |
| `uncompressed_cache_size` | Server | Set to 0 to disable |
| `use_uncompressed_cache` | Query | Enable per-query |
| `query_cache_max_size` | Server | Query result cache |
| `use_query_cache` | Query | Enable per-query |
