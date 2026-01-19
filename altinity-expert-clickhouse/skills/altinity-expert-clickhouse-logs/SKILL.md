---
name: altinity-expert-clickhouse-logs
description: Analyze ClickHouse system log table health including TTL configuration, disk usage, freshness, and cleanup. Use for system log issues and TTL configuration.
---

# System Log Table Health

Analyze system log table health: TTL configuration, disk usage, freshness, and cleanup.

---

## Quick Diagnostics

### 1. System Log Tables Overview

```sql
select
    name as log_table,
    engine,
    formatReadableSize(total_bytes) as size,
    total_rows as rows,
    (select count() from system.parts where database = 'system' and table = t.name and active) as parts,
    create_table_query like '% TTL %' as has_ttl
from system.tables t
where database = 'system'
  and name like '%_log'
  and engine like '%MergeTree%'
order by total_bytes desc
```

### 2. TTL Configuration Audit

```sql
select
    name as log_table,
    if(create_table_query like '% TTL %', 'Configured', 'MISSING') as ttl_status,
    multiIf(
        create_table_query not like '% TTL %', 'Major',
        'OK'
    ) as severity,
    if(severity = 'Major', 'System log should have TTL to prevent disk fill', 'OK') as note
from system.tables
where database = 'system'
  and name like '%_log'
  and engine like '%MergeTree%'
order by severity, name
```

### 3. Log Disk Usage vs Free Space

```sql
with
    (select sum(bytes_on_disk) from system.parts where database = 'system' and table like '%_log' and active) as log_bytes,
    (select arrayMin([free_space, unreserved_space]) from system.disks where name = 'default' limit 1) as free_bytes,
    log_bytes / (log_bytes + free_bytes) as ratio
select
    formatReadableSize(log_bytes) as log_usage,
    formatReadableSize(free_bytes) as free_space,
    round(100.0 * ratio, 2) as log_pct_of_used_disk,
    multiIf(ratio > 0.2, 'Critical', ratio > 0.1, 'Major', ratio > 0.05, 'Moderate', 'OK') as severity
```

---

## Log Table Details

### Log Sizes by Table

```sql
select
    table,
    formatReadableSize(sum(bytes_on_disk)) as size,
    sum(rows) as rows,
    count() as parts,
    min(min_date) as oldest_data,
    max(max_date) as newest_data,
    dateDiff('day', min(min_date), max(max_date)) as days_span
from system.parts
where database = 'system'
  and table like '%_log'
  and active
group by table
order by sum(bytes_on_disk) desc
```

### Log Freshness Check

```sql
with
    (select max(modification_time) from system.parts) as global_max_time
select
    table,
    max(modification_time) as last_write,
    dateDiff('minute', max(modification_time), global_max_time) as minutes_behind,
    multiIf(
        minutes_behind > 240, 'Major - no recent data',
        minutes_behind > 60, 'Moderate - may be stale',
        'OK'
    ) as freshness
from system.parts
where database = 'system'
  and table like '%_log'
  and active
group by table
order by minutes_behind desc
```

### Leftover Log Tables (Post-Upgrade)

```sql
select
    name,
    engine,
    formatReadableSize(total_bytes) as size,
    total_rows as rows,
    'Minor - leftover from version upgrade, consider dropping' as note
from system.tables
where database = 'system'
  and match(name, '\\w+_log_\\d+')
order by total_bytes desc
```

---

## Log Retention Analysis

### Estimated Retention by Table

```sql
select
    table,
    min(min_date) as oldest_date,
    max(max_date) as newest_date,
    dateDiff('day', min(min_date), max(max_date)) as retention_days,
    formatReadableSize(sum(bytes_on_disk)) as total_size,
    formatReadableSize(sum(bytes_on_disk) / nullIf(dateDiff('day', min(min_date), max(max_date)), 0)) as size_per_day
from system.parts
where database = 'system'
  and table like '%_log'
  and active
group by table
having retention_days > 0
order by retention_days desc
```

### Log Growth Rate

```sql
select
    table,
    toDate(modification_time) as day,
    count() as new_parts,
    sum(rows) as new_rows,
    formatReadableSize(sum(bytes_on_disk)) as new_bytes
from system.parts
where database = 'system'
  and table like '%_log'
  and modification_time > now() - interval 7 day
group by table, day
order by table, day desc
```

---

## Specific Log Table Analysis

### query_log Health

```sql
select
    'query_log' as log_table,
    (select count() from system.query_log where event_date = today()) as today_queries,
    (select count() from system.query_log where event_date = yesterday()) as yesterday_queries,
    (select min(event_date) from system.query_log) as oldest_date,
    (select max(event_date) from system.query_log) as newest_date,
    formatReadableSize((select sum(bytes_on_disk) from system.parts where database = 'system' and table = 'query_log' and active)) as size
```

### part_log Health

```sql
select
    'part_log' as log_table,
    (select count() from system.part_log where event_date = today()) as today_events,
    (select count() from system.part_log where event_date = yesterday()) as yesterday_events,
    (select min(event_date) from system.part_log) as oldest_date,
    (select max(event_date) from system.part_log) as newest_date,
    formatReadableSize((select sum(bytes_on_disk) from system.parts where database = 'system' and table = 'part_log' and active)) as size
```

### query_thread_log Warning

```sql
select
    name,
    formatReadableSize(total_bytes) as size,
    'Major - query_thread_log should be disabled in production (high overhead)' as warning
from system.tables
where database = 'system' and name = 'query_thread_log'
```

---

## TTL Recommendations

### Current TTL Extraction

```sql
select
    name,
    extract(create_table_query, 'TTL [^\\n]+') as ttl_clause
from system.tables
where database = 'system'
  and name like '%_log'
  and create_table_query like '% TTL %'
```

### Recommended TTL Settings

| Log Table | Recommended TTL | Notes |
|-----------|----------------|-------|
| query_log | 7-30 days | Balance debugging vs disk |
| query_thread_log | Disable or 3 days | Very verbose |
| part_log | 14-30 days | Important for RCA |
| trace_log | 3-7 days | Large, mostly for debugging |
| text_log | 7-14 days | Important for debugging |
| metric_log | 7-14 days | Useful for trending |
| asynchronous_metric_log | 7-14 days | Low volume |
| crash_log | 90+ days | Rare, keep longer |

### Add TTL Example

```sql
-- Example: Add 14-day TTL to query_log
-- ALTER TABLE system.query_log MODIFY TTL event_date + INTERVAL 14 DAY;
```

---

## Log Cleanup

### Parts to Drop After TTL

```sql
select
    table,
    count() as expired_parts,
    formatReadableSize(sum(bytes_on_disk)) as expired_size
from system.parts
where database = 'system'
  and table like '%_log'
  and active
  and max_date < today() - 30  -- Assuming 30-day retention
group by table
order by sum(bytes_on_disk) desc
```

### Force TTL Cleanup

```sql
-- Force TTL evaluation and cleanup
-- OPTIMIZE TABLE system.query_log FINAL;
-- Or: ALTER TABLE system.query_log MATERIALIZE TTL;
```

---

## Log Configuration

### Current Log Settings

```sql
select
    name,
    value
from system.server_settings
where name like '%log%'
  and name not like '%path%'
order by name
```

### Log Flush Intervals

```sql
select
    name,
    value
from system.server_settings
where name like '%flush%'
order by name
```

---

## Ad-Hoc Query Guidelines

### Required Safeguards
```sql
-- Log tables can be huge
limit 100

-- Time-bound when querying log contents
where event_date >= today() - 7
```

### Key Tables
- `system.tables` (database = 'system' and name like '%_log') - Log table metadata
- `system.parts` (database = 'system') - Log table storage
- Individual log tables (query_log, part_log, etc.) - Log contents

---

## Cross-Module Triggers

| Finding | Load Module | Reason |
|---------|-------------|--------|
| Logs filling disk | `altinity-expert-clickhouse-storage` | Disk space analysis |
| query_log missing data | `altinity-expert-clickhouse-errors` | Check for errors |
| High log volume | `altinity-expert-clickhouse-ingestion` | Batch sizing (affects part_log) |
| No query_log entries | `altinity-expert-clickhouse-overview` | System configuration |

---

## Settings Reference

| Setting | Notes |
|---------|-------|
| `log_queries` | Enable query_log |
| `log_queries_min_query_duration_ms` | Minimum duration to log |
| `log_queries_min_type` | Minimum query type to log |
| `query_log_database` | Database for query_log |
| `part_log_database` | Database for part_log |
| `text_log_level` | Minimum level for text_log |
