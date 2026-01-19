---
name: altinity-expert-clickhouse-overview
description: System health entry point for ClickHouse diagnostics. Use for general health checks, audits, status reviews, and quick assessment of server resource utilization and object counts.
---

# System Health and Comprehensive Audit

System-wide health check and entry point for ClickHouse diagnostics. Run this first for general health assessment.

---

## System Identification

```sql
select
    hostName() as hostname,
    version() as version,
    uptime() as uptime_seconds,
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
    (select value from system.metrics where metric = 'ReadonlyReplica') as value,
    if(value > 0, 'Critical', 'OK') as severity

union all

select
    'Max Replica Delay' as check_name,
    (select max(value) from system.asynchronous_metrics where metric in ('ReplicasMaxAbsoluteDelay', 'ReplicasMaxRelativeDelay')) as value,
    multiIf(value > 86400, 'Critical', value > 10800, 'Major', value > 1800, 'Moderate', 'OK') as severity

union all

select
    'Replication Queue Size' as check_name,
    (select value from system.asynchronous_metrics where metric = 'ReplicasSumQueueSize') as value,
    multiIf(value > 500, 'Major', value > 200, 'Moderate', 'OK') as severity
```

### Background Pool Status

```sql
select
    extract(metric, '^Background(.*)Task') as pool_name,
    value as active_tasks,
    (
        select toFloat64(value) from system.settings
        where name = concat('background_', lower(
            transform(extract(metric, '^Background(.*)PoolTask'),
                ['MergesAndMutations', 'Fetches', 'Move', 'Common', 'Schedule', 'BufferFlushSchedule', 'MessageBrokerSchedule', 'DistributedSchedule'],
                ['pool', 'fetches_pool', 'move_pool', 'common_pool', 'schedule_pool', 'buffer_flush_schedule_pool', 'message_broker_schedule_pool', 'distributed_schedule_pool'],
                '')
        ), '_size')
    ) as pool_size,
    round(100.0 * value / pool_size, 1) as utilization_pct,
    multiIf(utilization_pct > 99, 'Major', utilization_pct > 90, 'Moderate', 'OK') as severity
from system.metrics
where metric like 'Background%PoolTask'
  and pool_size > 0
order by utilization_pct desc
```

---

## Version Check

```sql
with
    (select value from system.build_options where name = 'VERSION_DESCRIBE') as current_version,
    toDate(extract(current_version, '\\d{4}-\\d{2}-\\d{2}')) as version_date,
    today() - version_date as age_days
select
    current_version as version,
    age_days,
    multiIf(age_days > 365, 'Major', age_days > 180, 'Moderate', 'OK') as severity,
    if(age_days > 180, 'Consider upgrading - security and performance fixes available', 'Version is reasonably current') as recommendation
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

## Recent Errors Summary

```sql
select
    toStartOfHour(event_time) as hour,
    countIf(type like 'Exception%') as failed_queries,
    count() as total_queries,
    round(100.0 * countIf(type like 'Exception%') / count(), 2) as error_rate_pct
from system.query_log
where event_date = today()
group by hour
order by hour desc
limit 12
```

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
| High error rate | `altinity-expert-clickhouse-errors` |
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
