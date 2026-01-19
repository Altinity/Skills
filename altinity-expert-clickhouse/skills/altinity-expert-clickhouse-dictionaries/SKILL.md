---
name: altinity-expert-clickhouse-dictionaries
description: Analyze ClickHouse external dictionaries including configuration, memory usage, reload status, and performance. Use for dictionary issues and load failures.
---

# Dictionary Diagnostics

Analyze external dictionaries: configuration, memory usage, reload status, and performance.

---

## Quick Diagnostics

### 1. Dictionary Overview

```sql
select
    database,
    name,
    status,
    origin,
    type,
    formatReadableSize(bytes_allocated) as memory,
    element_count as elements,
    loading_duration,
    last_successful_update_time,
    last_exception
from system.dictionaries
order by bytes_allocated desc
```

### 2. Dictionary Health Check

```sql
select
    database,
    name,
    status,
    multiIf(
        status = 'FAILED', 'Critical',
        status = 'LOADING', 'Moderate',
        last_exception != '', 'Major',
        dateDiff('hour', last_successful_update_time, now()) > 24, 'Moderate',
        'OK'
    ) as severity,
    last_exception,
    last_successful_update_time
from system.dictionaries
order by
    multiIf(severity = 'Critical', 1, severity = 'Major', 2, severity = 'Moderate', 3, 4),
    bytes_allocated desc
```

### 3. Memory Usage Audit

```sql
with
    sum(bytes_allocated) as dict_memory,
    (select value from system.asynchronous_metrics where metric = 'OSMemoryTotal') as total_ram
select
    formatReadableSize(dict_memory) as total_dictionary_memory,
    formatReadableSize(total_ram) as total_ram,
    round(100.0 * dict_memory / total_ram, 2) as pct_of_ram,
    multiIf(pct_of_ram > 20, 'Critical', pct_of_ram > 15, 'Major', pct_of_ram > 10, 'Moderate', 'OK') as severity
from system.dictionaries
```

---

## Dictionary Details

### Top Dictionaries by Memory

```sql
select
    database,
    name,
    type,
    formatReadableSize(bytes_allocated) as memory,
    element_count as elements,
    round(bytes_allocated / nullIf(element_count, 0), 2) as bytes_per_element,
    loading_duration,
    lifetime_min,
    lifetime_max
from system.dictionaries
order by bytes_allocated desc
limit 20
```

### Dictionary Configuration

```sql
select
    database,
    name,
    key,
    attribute.names as attributes,
    attribute.types as types,
    source,
    lifetime_min,
    lifetime_max,
    loading_start_time,
    loading_duration
from system.dictionaries
order by name
```

### Dictionary Staleness Check

```sql
select
    database,
    name,
    last_successful_update_time,
    dateDiff('minute', last_successful_update_time, now()) as minutes_since_update,
    lifetime_max,
    multiIf(
        minutes_since_update > lifetime_max * 2, 'Critical - very stale',
        minutes_since_update > lifetime_max, 'Major - past lifetime',
        minutes_since_update > lifetime_max * 0.9, 'Moderate - approaching lifetime',
        'OK'
    ) as freshness
from system.dictionaries
where lifetime_max > 0
order by minutes_since_update desc
```

---

## Failed Dictionaries

### Current Failures

```sql
select
    database,
    name,
    status,
    last_exception,
    loading_start_time,
    last_successful_update_time
from system.dictionaries
where status = 'FAILED' or last_exception != ''
```

### Dictionary Load Errors in Logs

```sql
select
    event_time,
    level,
    logger_name,
    substring(message, 1, 300) as message
from system.text_log
where logger_name like '%Dictionary%'
  and level in ('Error', 'Warning')
  and event_time > now() - interval 1 hour
order by event_time desc
limit 30
```

---

## Dictionary Performance

### Lookup Performance (via query_log)

```sql
select
    normalized_query_hash,
    count() as executions,
    round(avg(query_duration_ms)) as avg_ms,
    any(substring(query, 1, 100)) as query_sample
from system.query_log
where type = 'QueryFinish'
  and query ilike '%dictGet%'
  and event_date = today()
group by normalized_query_hash
order by count() desc
limit 20
```

### Dictionary Hit/Miss Ratio

```sql
select
    'DictCacheHits' as metric,
    (select value from system.events where event = 'DictCacheHits') as value
union all
select
    'DictCacheMisses' as metric,
    (select value from system.events where event = 'DictCacheMisses') as value
settings system_events_show_zero_values = 1
```

---

## Dictionary Types

### Cache Dictionary Analysis

For cache dictionaries, check hit rate and size:

```sql
select
    database,
    name,
    type,
    element_count,
    formatReadableSize(bytes_allocated) as memory,
    loading_duration
from system.dictionaries
where type like '%cache%'
```

### Flat/Hashed Dictionary Size Check

```sql
select
    database,
    name,
    type,
    element_count,
    formatReadableSize(bytes_allocated) as memory,
    round(bytes_allocated / nullIf(element_count, 0)) as bytes_per_key,
    if(bytes_per_key > 1000, 'High memory per key', 'OK') as note
from system.dictionaries
where type in ('Flat', 'Hashed', 'ComplexKeyHashed')
order by bytes_allocated desc
```

---

## Dictionary Sources

### Identify Source Types

```sql
select
    source,
    count() as dictionaries,
    formatReadableSize(sum(bytes_allocated)) as total_memory
from system.dictionaries
group by source
order by sum(bytes_allocated) desc
```

### Check Source Connectivity

For ClickHouse source dictionaries:
```sql
-- Verify source table exists
select
    d.name as dictionary_name,
    d.source,
    t.database as source_database,
    t.name as source_table
from system.dictionaries d
left join system.tables t on d.source like concat('%', t.database, '.', t.name, '%')
where d.source like '%clickhouse%'
```

---

## Dictionary Reload Operations

### Force Reload (diagnostic query - shows syntax)

```sql
-- SYSTEM RELOAD DICTIONARY {database}.{name}
-- SYSTEM RELOAD DICTIONARIES

-- Check reload result
select
    name,
    status,
    loading_start_time,
    loading_duration,
    last_exception
from system.dictionaries
where name = '{dictionary_name}'
```

### Scheduled Reload Check

```sql
select
    database,
    name,
    lifetime_min,
    lifetime_max,
    last_successful_update_time,
    dateDiff('second', last_successful_update_time, now()) as seconds_since_update,
    if(seconds_since_update > lifetime_max, 'Should have reloaded', 'OK') as reload_status
from system.dictionaries
where lifetime_max > 0
order by seconds_since_update desc
```

---

## Best Practices

### Dictionary Sizing Guidelines

| Elements | Recommended Type |
|----------|-----------------|
| < 100K | Flat (if sequential keys) |
| 100K - 10M | Hashed |
| > 10M | Consider partitioning or cache |
| Complex keys | ComplexKeyHashed |
| Sparse access | Cache with SSD |

### Common Issues

| Symptom | Cause | Solution |
|---------|-------|----------|
| High memory | Too many elements | Use cache type, filter data |
| Slow reload | Large source table | Add filters, use delta updates |
| Stale data | Source unreachable | Check connectivity, add retry |
| Failed status | Source query fails | Check source table/query |

---

## Ad-Hoc Query Guidelines

### Required Safeguards
```sql
-- For text_log
where event_time > now() - interval 1 hour
limit 100
```

### Key Tables
- `system.dictionaries` - Dictionary state
- `system.text_log` (logger_name like '%Dictionary%') - Load logs
- `system.events` (DictCache*) - Cache statistics

---

## Cross-Module Triggers

| Finding | Load Module | Reason |
|---------|-------------|--------|
| High memory usage | `altinity-expert-clickhouse-memory` | Overall memory analysis |
| Load failures | `altinity-expert-clickhouse-errors` | Error investigation |
| Source connectivity | `altinity-expert-clickhouse-text-log` | Deep log analysis |
| Slow lookups | `altinity-expert-clickhouse-reporting` | Query optimization |

---

## Settings Reference

| Setting | Notes |
|---------|-------|
| `dictionaries_lazy_load` | Load on first access vs startup |
| `dictionary_load_wait_timeout_ms` | Wait time for lazy load |
| `max_dictionary_num_to_warn` | Warning threshold |
