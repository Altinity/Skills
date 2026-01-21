---
name: altinity-expert-clickhouse-overview
description: Router skill for ClickHouse diagnostics. Runs a quick overview and chains to other skills based on findings.
---

# System Health and Routing Overview

Quick health check and routing entry point for ClickHouse diagnostics. Run this first, then chain to other skills based on findings.

## Timeframe Handling

Use the timeframe specified by the user. If none is provided, default to the last 24 hours.
Use it consistently for `system.errors` and for scanning all `system.*_log` tables.

## Routing Rules (Chain to Other Skills)

- High memory usage or OOMs → `altinity-expert-clickhouse-memory`
- Disk usage > 80% or poor compression → `altinity-expert-clickhouse-storage`
- Many parts, merge backlog, or TOO_MANY_PARTS → `altinity-expert-clickhouse-merges`
- Replication lag/readonly replicas/Keeper issues → `altinity-expert-clickhouse-replication`
- Slow SELECTs / heavy reads in query_log → `altinity-expert-clickhouse-reporting`
- Slow INSERTs / high part creation rate → `altinity-expert-clickhouse-ingestion`
- Low cache hit ratios / cache pressure → `altinity-expert-clickhouse-caches`
- Dictionary load failures or high dictionary memory → `altinity-expert-clickhouse-dictionaries`
- Frequent exceptions or error spikes → include `system.errors` and `system.*_log` summaries below
- System log TTL issues or log growth → `altinity-expert-clickhouse-logs`
- Schema anti‑patterns (partitioning/ORDER BY/MV issues) → `altinity-expert-clickhouse-schema`
- High load/connection saturation/queue buildup → `altinity-expert-clickhouse-metrics`
- Suspicious server log entries → `altinity-expert-clickhouse-logs`

---

## System Identification

If a connection recommendation is not provided explicitly, ask the user to choose the MCP server from the list or 
ask for connection details for clickhouse-client .

```sql
select
    hostName() as hostname,
    version() as version,
    formatReadableTimeDelta(uptime()) as uptime_human,
    getSetting('max_memory_usage') as max_memory_usage,
    (select value from system.asynchronous_metrics where metric = 'OSMemoryTotal') as os_memory_total
```

---

## Quick Health Score

Run all checks, aggregate by severity:

### Object Counts Audit

```sql
select
    'Replicated Tables' as check_name,
    (select count() from system.tables where engine like 'Replicated%') as value,
    multiIf(value > 2000, 'Critical', value > 900, 'Major', value > 200, 'Moderate', 'OK') as severity,
    'Recommend: <200, tune background_schedule_pool_size if higher' as note

union all

select
    'MergeTree Tables' as check_name,
    (select count() from system.tables where engine like '%MergeTree%') as value,
    multiIf(value > 10000, 'Critical', value > 3000, 'Major', value > 1000, 'Moderate', 'OK') as severity,
    'High count increases metadata overhead' as note

union all

select
    'Databases' as check_name,
    (select count() from system.databases) as value,
    multiIf(value > 1000, 'Critical', value > 300, 'Major', value > 100, 'Moderate', 'OK') as severity,
    'Consider consolidating if >100' as note

union all

select
    'Active Parts' as check_name,
    (select count() from system.parts where active) as value,
    multiIf(value > 120000, 'Critical', value > 90000, 'Major', value > 60000, 'Moderate', 'OK') as severity,
    'High count slows restarts and metadata ops' as note

union all

select
    'Current Queries' as check_name,
    (select count() from system.processes where is_cancelled = 0) as value,
    multiIf(value > 100, 'Major', value > 50, 'Moderate', 'OK') as severity,
    'Check max_concurrent_queries setting' as note

order by
    multiIf(severity = 'Critical', 1, severity = 'Major', 2, severity = 'Moderate', 3, 4),
    check_name
```

### Resource Utilization

```sql
with
    (select value from system.asynchronous_metrics where metric = 'OSMemoryTotal') as total_ram,
    (select value from system.asynchronous_metrics where metric = 'MemoryResident') as used_ram,
    (select sum(primary_key_bytes_in_memory) from system.parts) as pk_memory,
    (select sum(bytes_allocated) from system.dictionaries) as dict_memory,
    (select assumeNotNull(sum(total_bytes)) from system.tables where engine in ('Memory','Set','Join')) as mem_tables
select
    'Memory Usage' as resource,
    formatReadableSize(used_ram) as used,
    formatReadableSize(total_ram) as total,
    round(100.0 * used_ram / total_ram, 1) as pct,
    multiIf(pct > 90, 'Critical', pct > 80, 'Major', pct > 70, 'Moderate', 'OK') as severity

union all

select
    'Primary Keys in RAM' as resource,
    formatReadableSize(pk_memory) as used,
    formatReadableSize(total_ram) as total,
    round(100.0 * pk_memory / total_ram, 1) as pct,
    multiIf(pct > 30, 'Critical', pct > 25, 'Major', pct > 20, 'Moderate', 'OK') as severity

union all

select
    'Dictionaries + MemTables' as resource,
    formatReadableSize(dict_memory + mem_tables) as used,
    formatReadableSize(total_ram) as total,
    round(100.0 * (dict_memory + mem_tables) / total_ram, 1) as pct,
    multiIf(pct > 30, 'Critical', pct > 25, 'Major', pct > 20, 'Moderate', 'OK') as severity

order by pct desc
```

### Disk Health

```sql
select
    name as disk,
    path,
    formatReadableSize(total_space) as total,
    formatReadableSize(free_space) as free,
    round(100.0 * (total_space - free_space) / total_space, 1) as used_pct,
    multiIf(used_pct > 90, 'Critical', used_pct > 85, 'Major', used_pct > 80, 'Moderate', 'OK') as severity
from system.disks
where type = 'Local'
order by used_pct desc
```

### Replication Health

```sql
select
    'Readonly Replicas' as check_name,
    toFloat64((select value from system.metrics where metric = 'ReadonlyReplica')) as value,
    if(value > 0, 'Critical', 'OK') as severity

union all

select
    'Max Replica Delay' as check_name,
    toFloat64((select max(value) from system.asynchronous_metrics where metric in ('ReplicasMaxAbsoluteDelay', 'ReplicasMaxRelativeDelay'))) as value,
    multiIf(value > 86400, 'Critical', value > 10800, 'Major', value > 1800, 'Moderate', 'OK') as severity

union all

select
    'Replication Queue Size' as check_name,
    toFloat64((select value from system.asynchronous_metrics where metric = 'ReplicasSumQueueSize')) as value,
    multiIf(value > 500, 'Major', value > 200, 'Moderate', 'OK') as severity
```

### Background Pool Status

```sql
with
    transform(extract(metric, '^Background(.*)PoolTask'),
        ['MergesAndMutations', 'Fetches', 'Move', 'Common', 'Schedule', 'BufferFlushSchedule', 'MessageBrokerSchedule', 'DistributedSchedule'],
        ['pool', 'fetches_pool', 'move_pool', 'common_pool', 'schedule_pool', 'buffer_flush_schedule_pool', 'message_broker_schedule_pool', 'distributed_schedule_pool'],
        ''
    ) as pool_key,
    concat('background_', lower(pool_key), '_size') as setting_name
select
    extract(m.metric, '^Background(.*)Task') as pool_name,
    m.value as active_tasks,
    toFloat64OrZero(s.value) as pool_size,
    round(100.0 * m.value / pool_size, 1) as utilization_pct,
    multiIf(utilization_pct > 99, 'Major', utilization_pct > 90, 'Moderate', 'OK') as severity
from system.metrics m
left join system.settings s on s.name = setting_name
where m.metric like 'Background%PoolTask'
  and pool_size > 0
order by utilization_pct desc
```

---

## Version Check

```sql
with
    (select value from system.build_options where name = 'VERSION_DESCRIBE') as current_version,
    nullIf((select value from system.build_options where name = 'BUILD_DATE'), '') as build_date_str,
    parseDateTimeBestEffortOrNull(build_date_str) as build_dt,
    if(build_dt is null, NULL, dateDiff('day', toDate(build_dt), today())) as age_days
select
    current_version as version,
    build_date_str as build_date,
    age_days,
    multiIf(age_days is null, 'Moderate', age_days > 365, 'Major', age_days > 180, 'Moderate', 'OK') as severity,
    multiIf(
        age_days is null, 'Build date not available; check packaging / release notes',
        age_days > 180, 'Consider upgrading - security and performance fixes available',
        'Version is reasonably current'
    ) as recommendation
```

---

## System Log Health

```sql
select
    format('system.{}', name) as log_table,
    engine_full like '% TTL %' as has_ttl,
    if(not has_ttl, 'Major', 'OK') as severity,
    if(not has_ttl, 'System log should have TTL to prevent disk fill', 'TTL configured') as note
from system.tables
where database = 'system' and name like '%_log' and engine like '%MergeTree%'
order by has_ttl, name
```

```sql
-- Log disk usage
select
    table,
    formatReadableSize(sum(bytes_on_disk)) as size,
    count() as parts
from system.parts
where database = 'system' and table like '%_log' and active
group by table
order by sum(bytes_on_disk) desc
```

---

## Recent Errors Summary (Timeframe-Based)

```sql
select
    toStartOfHour(event_time) as hour,
    countIf(type like 'Exception%') as failed_queries,
    count() as total_queries,
    round(100.0 * countIf(type like 'Exception%') / count(), 2) as error_rate_pct
from system.query_log
where event_time >= now() - interval 24 hour
group by hour
order by hour desc
limit 12
```

---

## system.errors Summary (Timeframe-Based)

```sql
select
    code,
    name,
    value as count,
    last_error_time,
    substring(last_error_message, 1, 160) as last_error_message
from system.errors
where last_error_time >= now() - interval 24 hour
order by last_error_time desc
limit 20
```

---

## system.*_log Activity Summary (Timeframe-Based)

1) Identify which log tables have timestamp columns:

```sql
select
    table,
    groupArray(name) as time_cols
from system.columns
where database = 'system'
  and table like '%_log'
  and name in ('event_time', 'event_date')
group by table
order by table
```

2) For each log table, run a short activity summary using the appropriate column:

```sql
-- Example: event_time-based tables
select
    count() as rows_24h,
    min(event_time) as min_time,
    max(event_time) as max_time
from system.query_log
where event_time >= now() - interval 24 hour
```

```sql
-- Example: event_date-based tables
select
    count() as rows_24h,
    min(event_date) as min_date,
    max(event_date) as max_date
from system.part_log
where event_date >= today() - 1
```

Use the user-specified timeframe if provided; otherwise use the last 24 hours.

---

## Warnings from ClickHouse

```sql
select message as warning
from system.warnings
```

---

## Module Routing

Based on findings, load specific modules:

| Finding | Load Module |
|---------|-------------|
| High memory usage | `altinity-expert-clickhouse-memory` |
| Disk > 80% | `altinity-expert-clickhouse-storage` |
| Many parts | `altinity-expert-clickhouse-merges` |
| Replica delay | `altinity-expert-clickhouse-replication` |
| High error rate | Include `system.errors` + log table summaries (see below) |
| Pool saturation | `altinity-expert-clickhouse-ingestion` or `altinity-expert-clickhouse-merges` |
| Old version | Check ClickHouse release notes |
| Log issues | `altinity-expert-clickhouse-logs` |
| Schema concerns | `altinity-expert-clickhouse-schema` |

---

## Full Audit Script

For comprehensive audit, run modules in order:
1. `altinity-expert-clickhouse-overview` (this module) - system identification
2. `altinity-expert-clickhouse-schema` - table design issues
3. `altinity-expert-clickhouse-merges` - part management
4. `altinity-expert-clickhouse-memory` - RAM analysis
5. `altinity-expert-clickhouse-storage` - disk analysis
6. `altinity-expert-clickhouse-replication` - if replicated tables exist
7. `altinity-expert-clickhouse-reporting` - if query performance issues
