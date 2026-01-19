---
name: altinity-expert-clickhouse-metrics
description: Real-time monitoring of ClickHouse metrics, events, and asynchronous metrics. Use for load average, connections, queue monitoring, and resource saturation.
---

# Real-Time Metrics Monitoring

Real-time monitoring of ClickHouse metrics, events, and asynchronous metrics.

---

## Quick Diagnostics

### 1. Key Health Metrics

```sql
select
    'Running Queries' as metric,
    (select value from system.metrics where metric = 'Query') as value,
    '' as unit,
    if(value > 100, 'High', 'OK') as status

union all select
    'Memory Usage',
    (select value from system.asynchronous_metrics where metric = 'MemoryResident'),
    formatReadableSize(value),
    if(value > (select value from system.asynchronous_metrics where metric = 'OSMemoryTotal') * 0.8, 'High', 'OK')

union all select
    'Load Average (1m)',
    (select value from system.asynchronous_metrics where metric = 'LoadAverage1'),
    toString(round(value, 2)),
    if(value > (select count() from system.asynchronous_metrics where metric like 'CPUFrequencyMHz%'), 'High', 'OK')

union all select
    'Readonly Replicas',
    (select value from system.metrics where metric = 'ReadonlyReplica'),
    toString(value),
    if(value > 0, 'Critical', 'OK')

union all select
    'Max Replica Delay',
    (select max(value) from system.asynchronous_metrics where metric like 'ReplicasMax%Delay'),
    formatReadableTimeDelta(value),
    if(value > 300, 'High', 'OK')

union all select
    'Max Parts in Partition',
    (select value from system.asynchronous_metrics where metric = 'MaxPartCountForPartition'),
    toString(value),
    if(value > 200, 'High', 'OK')

order by status desc, metric
```

### 2. Resource Saturation

```sql
select
    'CPU Load' as resource,
    (select value from system.asynchronous_metrics where metric = 'LoadAverage1') as current,
    (select count() from system.asynchronous_metrics where metric like 'CPUFrequencyMHz%') as capacity,
    round(100.0 * current / capacity, 1) as utilization_pct,
    multiIf(utilization_pct > 200, 'Critical', utilization_pct > 100, 'High', 'OK') as status

union all select
    'Memory',
    (select value from system.asynchronous_metrics where metric = 'MemoryResident'),
    (select value from system.asynchronous_metrics where metric = 'OSMemoryTotal'),
    round(100.0 * current / capacity, 1),
    multiIf(utilization_pct > 90, 'Critical', utilization_pct > 80, 'High', 'OK')

union all select
    'Connections',
    (select sum(value) from system.metrics where metric like '%Connection'),
    (select toFloat64(value) from system.server_settings where name = 'max_connections'),
    round(100.0 * current / capacity, 1),
    multiIf(utilization_pct > 90, 'Critical', utilization_pct > 75, 'High', 'OK')

union all select
    'Concurrent Queries',
    (select value from system.metrics where metric = 'Query'),
    (select toFloat64(value) from system.server_settings where name = 'max_concurrent_queries'),
    round(100.0 * current / capacity, 1),
    multiIf(utilization_pct > 90, 'Critical', utilization_pct > 75, 'High', 'OK')
```

---

## System Metrics (Gauges)

### Current Metrics Snapshot

```sql
select
    metric,
    value,
    description
from system.metrics
where value > 0
order by metric
```

### Connection Metrics

```sql
select
    metric,
    value
from system.metrics
where metric like '%Connection%'
order by value desc
```

### Background Task Metrics

```sql
select
    metric,
    value
from system.metrics
where metric like 'Background%' or metric like '%Pool%'
order by metric
```

### Query Metrics

```sql
select
    metric,
    value
from system.metrics
where metric like '%Query%' or metric like '%Insert%' or metric like '%Select%'
order by metric
```

---

## Asynchronous Metrics

### Memory Metrics

```sql
select
    metric,
    value,
    formatReadableSize(value) as readable
from system.asynchronous_metrics
where metric like '%Memory%' or metric like '%Cache%'
order by metric
```

### Load Metrics

```sql
select
    metric,
    round(value, 2) as value
from system.asynchronous_metrics
where metric like 'LoadAverage%' or metric like 'CPU%'
order by metric
```

### Disk Metrics

```sql
select
    metric,
    value,
    formatReadableSize(value) as readable
from system.asynchronous_metrics
where metric like '%Disk%' or metric like 'Filesystem%'
order by metric
```

### Replication Metrics

```sql
select
    metric,
    value,
    if(metric like '%Delay%', formatReadableTimeDelta(value), toString(value)) as readable
from system.asynchronous_metrics
where metric like 'Replicas%'
order by metric
```

---

## Events (Counters)

### Top Events Since Start

```sql
select
    event,
    value,
    description
from system.events
where value > 0
order by value desc
limit 50
```

### Query Events

```sql
select
    event,
    value
from system.events
where event like '%Query%' or event like '%Select%' or event like '%Insert%'
order by value desc
limit 30
```

### IO Events

```sql
select
    event,
    value,
    if(event like '%Bytes%', formatReadableSize(value), toString(value)) as readable
from system.events
where event like '%Read%' or event like '%Write%' or event like '%Disk%'
order by value desc
limit 30
```

### Cache Events

```sql
select
    event,
    value
from system.events
where event like '%Cache%'
order by event
```

---

## Metric History (from *_log tables)

### Memory Over Time

```sql
select
    toStartOfFiveMinutes(event_time) as ts,
    round(avg(value)) as avg_memory,
    formatReadableSize(avg_memory) as readable,
    round(max(value)) as max_memory
from system.asynchronous_metric_log
where metric = 'MemoryResident'
  and event_time > now() - interval 6 hour
group by ts
order by ts
```

### Load Average Over Time

```sql
select
    toStartOfFiveMinutes(event_time) as ts,
    round(avgIf(value, metric = 'LoadAverage1'), 2) as load_1m,
    round(avgIf(value, metric = 'LoadAverage5'), 2) as load_5m,
    round(avgIf(value, metric = 'LoadAverage15'), 2) as load_15m
from system.asynchronous_metric_log
where metric like 'LoadAverage%'
  and event_time > now() - interval 6 hour
group by ts
order by ts
```

### Query Rate Over Time

```sql
select
    toStartOfMinute(event_time) as ts,
    sum(ProfileEvent_Query) as queries,
    sum(ProfileEvent_SelectQuery) as selects,
    sum(ProfileEvent_InsertQuery) as inserts
from system.metric_log
where event_time > now() - interval 1 hour
group by ts
order by ts
```

---

## Alert Thresholds

### Current vs Thresholds

```sql
with
    (select value from system.metrics where metric = 'Query') as current_queries,
    (select toFloat64(value) from system.server_settings where name = 'max_concurrent_queries') as max_queries,
    (select value from system.metrics where metric = 'ReadonlyReplica') as readonly_replicas,
    (select value from system.asynchronous_metrics where metric = 'MaxPartCountForPartition') as max_parts,
    (select toUInt64(value) from system.merge_tree_settings where name = 'parts_to_delay_insert') as delay_threshold,
    (select toUInt64(value) from system.merge_tree_settings where name = 'parts_to_throw_insert') as throw_threshold,
    (select max(value) from system.asynchronous_metrics where metric like 'ReplicasMax%Delay') as max_delay,
    (select value from system.asynchronous_metrics where metric = 'MemoryResident') as memory,
    (select value from system.asynchronous_metrics where metric = 'OSMemoryTotal') as total_memory
select
    'Queries' as check_name,
    current_queries as current,
    max_queries as threshold,
    round(100.0 * current_queries / max_queries, 1) as pct,
    if(pct > 90, 'ALERT', if(pct > 75, 'WARN', 'OK')) as status

union all select
    'Readonly Replicas',
    readonly_replicas,
    0,
    0,
    if(readonly_replicas > 0, 'ALERT', 'OK')

union all select
    'Max Parts in Partition',
    max_parts,
    delay_threshold,
    round(100.0 * max_parts / delay_threshold, 1),
    if(max_parts > throw_threshold, 'ALERT', if(max_parts > delay_threshold, 'WARN', 'OK'))

union all select
    'Replica Delay (sec)',
    max_delay,
    300,
    0,
    if(max_delay > 3600, 'ALERT', if(max_delay > 300, 'WARN', 'OK'))

union all select
    'Memory Usage',
    memory,
    total_memory * 0.9,
    round(100.0 * memory / total_memory, 1),
    if(pct > 90, 'ALERT', if(pct > 80, 'WARN', 'OK'))

order by status desc
```

---

## Block Device Metrics

### Disk IO Metrics

```sql
select
    metric,
    value
from system.asynchronous_metrics
where metric like 'BlockInFlightOps%'
   or metric like 'BlockReadOps%'
   or metric like 'BlockWriteOps%'
order by metric
```

### Disk Queue Depth

```sql
select
    metric,
    value,
    multiIf(value > 245, 'Critical', value > 200, 'High', value > 128, 'Moderate', 'OK') as status
from system.asynchronous_metrics
where metric like 'BlockInFlightOps%'
  and value > 0
order by value desc
```

---

## Uptime and Version

```sql
select
    uptime() as uptime_seconds,
    formatReadableTimeDelta(uptime()) as uptime_human,
    version() as version,
    (select value from system.build_options where name = 'VERSION_DESCRIBE') as version_full
```

---

## Profile Events Summary

### Top Profile Events (metric_log)

```sql
select
    arrayJoin(mapKeys(ProfileEvents)) as event,
    sum(ProfileEvents[event]) as total
from system.metric_log
where event_time > now() - interval 1 hour
group by event
order by total desc
limit 30
```

---

## Ad-Hoc Query Guidelines

### Key Tables
- `system.metrics` - Current gauge values
- `system.events` - Cumulative counters since restart
- `system.asynchronous_metrics` - System-level metrics
- `system.metric_log` - Historical metrics
- `system.asynchronous_metric_log` - Historical async metrics

### Useful Patterns
```sql
-- Find metrics by pattern
select * from system.metrics where metric like '%pattern%'
select * from system.asynchronous_metrics where metric like '%pattern%'
select * from system.events where event like '%pattern%'
```

---

## Cross-Module Triggers

| Finding | Load Module | Reason |
|---------|-------------|--------|
| High memory metrics | `altinity-expert-clickhouse-memory` | Memory analysis |
| High replica delay | `altinity-expert-clickhouse-replication` | Replication issues |
| High parts count | `altinity-expert-clickhouse-merges` | Merge backlog |
| High load average | `altinity-expert-clickhouse-reporting` | Query analysis |
| High connections | `altinity-expert-clickhouse-reporting` | Connection analysis |

---

## Monitoring Recommendations

### Key Metrics to Alert On

| Metric | Warning | Critical |
|--------|---------|----------|
| `ReadonlyReplica` | - | > 0 |
| `Query` | > 75% max | > 90% max |
| `MemoryResident` | > 80% RAM | > 90% RAM |
| `MaxPartCountForPartition` | > parts_to_delay | > parts_to_throw |
| `ReplicasMaxAbsoluteDelay` | > 5 min | > 1 hour |
| `LoadAverage1` | > CPU count | > 2x CPU count |

### Prometheus/Grafana Export

ClickHouse exposes metrics at `:9363/metrics` in Prometheus format when enabled.

```sql
-- Check if Prometheus endpoint is enabled
select * from system.server_settings where name like '%prometheus%'
```
