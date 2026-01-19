---
name: altinity-expert-clickhouse-text-log
description: Deep analysis of ClickHouse server logs, debug traces, and low-level diagnostics. Use for investigating server log messages and trace analysis.
---

# Server Log Analysis

Deep analysis of server logs, debug traces, and low-level diagnostics.

---

## Quick Diagnostics

### 1. Log Level Distribution (Last Hour)

```sql
select
    level,
    count() as messages,
    uniq(logger_name) as components
from system.text_log
where event_time > now() - interval 1 hour
group by level
order by
    multiIf(level = 'Fatal', 1, level = 'Critical', 2, level = 'Error', 3,
            level = 'Warning', 4, level = 'Notice', 5, level = 'Information', 6, 7)
```

### 2. Recent Critical Messages

```sql
select
    event_time,
    level,
    logger_name,
    thread_id,
    query_id,
    substring(message, 1, 200) as message
from system.text_log
where level in ('Fatal', 'Critical', 'Error')
  and event_time > now() - interval 1 hour
order by event_time desc
limit 50
```

### 3. Warning Trends

```sql
select
    toStartOfFiveMinutes(event_time) as ts,
    countIf(level = 'Error') as errors,
    countIf(level = 'Warning') as warnings,
    countIf(level = 'Fatal' or level = 'Critical') as critical
from system.text_log
where event_time > now() - interval 6 hour
group by ts
order by ts desc
```

---

## Component-Specific Analysis

### Errors by Component

```sql
select
    logger_name,
    count() as error_count,
    min(event_time) as first,
    max(event_time) as last,
    any(substring(message, 1, 100)) as sample_message
from system.text_log
where level in ('Error', 'Critical', 'Fatal')
  and event_time > now() - interval 24 hour
group by logger_name
order by error_count desc
limit 30
```

### Keeper/ZooKeeper Logs

```sql
select
    event_time,
    level,
    logger_name,
    substring(message, 1, 200) as message
from system.text_log
where (logger_name like '%ZooKeeper%' or logger_name like '%Keeper%')
  and event_time > now() - interval 1 hour
order by event_time desc
limit 50
```

### Merge Logs

```sql
select
    event_time,
    level,
    logger_name,
    substring(message, 1, 200) as message
from system.text_log
where logger_name like '%Merge%'
  and level in ('Error', 'Warning')
  and event_time > now() - interval 1 hour
order by event_time desc
limit 50
```

### Replication Logs

```sql
select
    event_time,
    level,
    logger_name,
    substring(message, 1, 200) as message
from system.text_log
where (logger_name like '%Replicat%' or logger_name like '%Fetch%')
  and event_time > now() - interval 1 hour
order by event_time desc
limit 50
```

### Storage Logs

```sql
select
    event_time,
    level,
    logger_name,
    substring(message, 1, 200) as message
from system.text_log
where (logger_name like '%Storage%' or logger_name like '%Disk%' or logger_name like '%Part%')
  and level in ('Error', 'Warning')
  and event_time > now() - interval 1 hour
order by event_time desc
limit 50
```

---

## Query-Specific Logs

### Logs for Specific Query

```sql
select
    event_time,
    level,
    logger_name,
    thread_id,
    substring(message, 1, 300) as message
from system.text_log
where query_id = '{query_id}'
order by event_time, thread_id
```

### Recent Query Errors with Context

```sql
select
    event_time,
    query_id,
    level,
    logger_name,
    substring(message, 1, 200) as message
from system.text_log
where level in ('Error', 'Warning')
  and query_id != ''
  and event_time > now() - interval 1 hour
order by event_time desc
limit 50
```

---

## Pattern Matching

### Search for Specific Pattern

```sql
select
    event_time,
    level,
    logger_name,
    substring(message, 1, 300) as message
from system.text_log
where message ilike '%{pattern}%'
  and event_time > now() - interval 1 hour
order by event_time desc
limit 100
```

### Memory-Related Logs

```sql
select
    event_time,
    level,
    logger_name,
    substring(message, 1, 200) as message
from system.text_log
where (message ilike '%memory%' or message ilike '%oom%' or message ilike '%alloc%')
  and level in ('Error', 'Warning')
  and event_time > now() - interval 1 hour
order by event_time desc
limit 50
```

### Connection/Network Logs

```sql
select
    event_time,
    level,
    logger_name,
    substring(message, 1, 200) as message
from system.text_log
where (message ilike '%connection%' or message ilike '%network%' or message ilike '%timeout%')
  and level in ('Error', 'Warning')
  and event_time > now() - interval 1 hour
order by event_time desc
limit 50
```

---

## Trace Log Analysis

### Recent CPU Traces

```sql
select
    trace_type,
    count() as samples,
    topK(5)(query_id) as top_query_ids
from system.trace_log
where event_time > now() - interval 1 hour
  and trace_type = 'CPU'
group by trace_type
```

### Memory Allocation Traces

```sql
select
    trace_type,
    count() as samples,
    formatReadableSize(sum(size)) as total_allocated
from system.trace_log
where event_time > now() - interval 1 hour
  and trace_type in ('Memory', 'MemorySample')
group by trace_type
```

### Trace Types Distribution

```sql
select
    trace_type,
    count() as samples
from system.trace_log
where event_time > now() - interval 24 hour
group by trace_type
order by samples desc
```

---

## Log Volume Analysis

### Log Size Over Time

```sql
select
    toStartOfHour(event_time) as hour,
    count() as messages,
    uniq(logger_name) as components,
    countIf(level in ('Error', 'Critical', 'Fatal')) as errors
from system.text_log
where event_time > now() - interval 24 hour
group by hour
order by hour desc
```

### Most Verbose Components

```sql
select
    logger_name,
    count() as messages,
    countIf(level = 'Debug') as debug,
    countIf(level = 'Trace') as trace
from system.text_log
where event_time > now() - interval 1 hour
group by logger_name
order by messages desc
limit 30
```

---

## Stack Trace Analysis

### Recent Stack Traces in Logs

```sql
select
    event_time,
    level,
    logger_name,
    substring(message, 1, 500) as message
from system.text_log
where message like '%Stack trace%' or message like '%Backtrace%'
  and event_time > now() - interval 24 hour
order by event_time desc
limit 20
```

### Crash Stack Traces

```sql
select
    event_time,
    signal,
    query_id,
    trace_full
from system.crash_log
where event_time > now() - interval 7 day
order by event_time desc
limit 10
```

---

## Log Configuration Check

### Current Log Level

```sql
select
    name,
    value
from system.server_settings
where name in ('logger.level', 'logger.console', 'logger.log', 'logger.errorlog')
```

### Text Log Table Settings

```sql
select
    engine_full,
    create_table_query
from system.tables
where database = 'system' and name = 'text_log'
```

---

## Ad-Hoc Query Guidelines

### Required Safeguards
```sql
-- Always time-bound (text_log can be huge)
where event_time > now() - interval 1 hour

-- Limit results
limit 100

-- Filter by level for large time ranges
where level in ('Error', 'Warning')
```

### Performance Tips
- `text_log` can be very large - always use time filters
- Filter by `logger_name` to narrow scope
- Use `query_id` to correlate with query_log
- `message ilike` is slow - use specific time windows

### Key Logger Names
- `executeQuery` - Query execution
- `MergeTreeData` - Part/merge operations
- `ReplicatedMergeTree*` - Replication
- `ZooKeeper*`, `Keeper*` - Coordination
- `StorageDistributed` - Distributed tables
- `BackgroundSchedulePool*` - Background tasks

---

## Cross-Module Triggers

| Finding | Load Module | Reason |
|---------|-------------|--------|
| Query errors | `altinity-expert-clickhouse-reporting` | Query analysis |
| Memory messages | `altinity-expert-clickhouse-memory` | Memory investigation |
| Merge errors | `altinity-expert-clickhouse-merges` | Merge analysis |
| Replication errors | `altinity-expert-clickhouse-replication` | Replica status |
| Storage errors | `altinity-expert-clickhouse-storage` | Disk issues |
| Keeper errors | `altinity-expert-clickhouse-replication` | Keeper health |

---

## Settings Reference

| Setting | Notes |
|---------|-------|
| `logger.level` | Global log level |
| `text_log.flush_interval_milliseconds` | Flush frequency |
| `text_log.level` | text_log capture level |
| `trace_log` | Enable/disable trace logging |
| `query_thread_log` | Per-thread logging (expensive) |
