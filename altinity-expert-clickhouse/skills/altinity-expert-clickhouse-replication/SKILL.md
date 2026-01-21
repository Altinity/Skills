---
name: altinity-expert-clickhouse-replication
description: Diagnose ClickHouse replication health, Keeper connectivity, replica lag, and queue issues. Use for replication lag and readonly replica problems.
---

# Replication Health and Keeper Analysis

Diagnose replication health, Keeper connectivity, replica lag, and queue issues.

---

## Quick Diagnostics

### 1. Replication Overview

```sql
select
    database,
    table,
    is_readonly,
    is_session_expired,
    future_parts,
    parts_to_check,
    queue_size,
    inserts_in_queue,
    merges_in_queue,
    log_pointer,
    total_replicas,
    active_replicas,
    last_queue_update,
    absolute_delay,
    formatReadableTimeDelta(absolute_delay) as delay_human
from system.replicas
order by absolute_delay desc
limit 30
```

**Red flags:**
- `is_readonly = 1` → Critical, replica can't accept writes
- `is_session_expired = 1` → Keeper connection lost
- `absolute_delay > 300` → Significant lag

### 2. Readonly Replicas Check

```sql
select
    database,
    table,
    is_readonly,
    is_session_expired,
    zookeeper_path,
    replica_path
from system.replicas
where is_readonly = 1 or is_session_expired = 1
```

**If found:** Check Keeper connectivity, disk space, network.

### 3. Replication Delay Audit

```sql
with
    (select max(value) from system.asynchronous_metrics where metric = 'ReplicasMaxAbsoluteDelay') as max_delay
select
    'ReplicasMaxAbsoluteDelay' as metric,
    max_delay as seconds,
    formatReadableTimeDelta(max_delay) as human,
    multiIf(max_delay > 86400, 'Critical', max_delay > 10800, 'Major', max_delay > 1800, 'Moderate', 'OK') as severity

union all

select
    'ReplicasMaxRelativeDelay' as metric,
    (select max(value) from system.asynchronous_metrics where metric = 'ReplicasMaxRelativeDelay') as seconds,
    formatReadableTimeDelta(seconds) as human,
    multiIf(seconds > 86400, 'Critical', seconds > 10800, 'Major', seconds > 1800, 'Moderate', 'OK') as severity
```

---

## Replication Queue Analysis

### Queue Size by Table

```sql
with
    count() as count_all,
    countIf(last_exception != '') as count_err,
    countIf(num_postponed > 0) as count_postponed,
    countIf(is_currently_executing) as count_executing
select
    database,
    table,
    count_all as queue_size,
    count_err as with_errors,
    count_postponed as postponed,
    count_executing as executing,
    multiIf(count_all > 500, 'Critical', count_all > 400, 'Major', count_all > 200, 'Moderate', 'OK') as severity
from system.replication_queue
group by database, table
having count_all > 50
order by count_all desc
```

### Old Tasks in Queue

```sql
with
    (select maxArray([create_time, last_attempt_time, last_postpone_time]) from system.replication_queue) as max_time,
    max_time - min(create_time) as max_age
select
    database,
    table,
    max_age as oldest_task_age_sec,
    formatReadableTimeDelta(max_age) as oldest_task_age,
    multiIf(max_age > 86400, 'Critical', max_age > 7200, 'Major', max_age > 1800, 'Moderate', 'OK') as severity,
    count() as tasks_in_queue
from system.replication_queue
group by database, table
having max_age > 300
order by max_age desc
```

### Stalled Tasks Detection

```sql
with
    (select maxArray([create_time, last_attempt_time, last_postpone_time]) from system.replication_queue) as max_time,
    last_attempt_time < max_time - 601 and last_postpone_time < max_time - 601 as no_activity
select
    database,
    table,
    countIf(no_activity) as stalled_tasks,
    count() as total_tasks,
    round(100.0 * countIf(no_activity) / count(), 1) as stalled_pct
from system.replication_queue
group by database, table
having stalled_tasks > 0
order by stalled_tasks desc
```

### Queue Tasks with Errors

```sql
select
    database,
    table,
    type,
    create_time,
    last_attempt_time,
    num_tries,
    last_exception,
    postpone_reason
from system.replication_queue
where last_exception != '' or postpone_reason != ''
order by last_attempt_time desc
limit 50
```

### NO_REPLICA_HAS_PART

Such type of errors should be considered differently depending on the part name suffix. For _0 and _1 suffixes (example: 20240518_71684_71689_1), it should be considered as normal behaviour of the replication process on big insert load. For suffixes greater than "_1" it can be a sign of the replication problem.

---

## Keeper/ZooKeeper Diagnostics

### Keeper Session Status

```sql
select *
from system.zookeeper_connection
```

### Keeper Latency

```sql
select
    'ZooKeeperWaitMicroseconds' as metric,
    (select value from system.events where event = 'ZooKeeperWaitMicroseconds') as total_us,
    (select value from system.events where event = 'ZooKeeperTransactions') as transactions,
    round(total_us / nullIf(transactions, 0)) as avg_latency_us
settings system_events_show_zero_values = 1
```

### Recent Keeper Errors

```sql
select
    event_time,
    level,
    logger_name,
    message
from system.text_log
where (logger_name like '%ZooKeeper%' or logger_name like '%Keeper%')
  and level in ('Error', 'Warning')
  and event_time > now() - interval 1 hour
order by event_time desc
limit 50
```

---

## Async Replication Metrics

```sql
select metric, value
from system.asynchronous_metrics
where metric in (
    'ReplicasMaxQueueSize',
    'ReplicasSumQueueSize',
    'ReplicasMaxInsertsInQueue',
    'ReplicasSumInsertsInQueue',
    'ReplicasMaxMergesInQueue',
    'ReplicasSumMergesInQueue',
    'ReplicasMaxAbsoluteDelay',
    'ReplicasMaxRelativeDelay'
)
order by metric
```

---

## Problem Investigation

### Fetch Stuck/Slow

```sql
-- Check active fetches
select
    database,
    table,
    elapsed,
    progress,
    formatReadableSize(total_size_bytes_compressed) as size,
    result_part_name
from system.replicated_fetches
order by elapsed desc
limit 20
```

```sql
-- Recent fetch activity in part_log
select
    event_time,
    database,
    table,
    part_name,
    duration_ms,
    formatReadableSize(size_in_bytes) as size,
    error
from system.part_log
where event_type = 'DownloadPart'
  and event_date >= today() - 1
order by event_time desc
limit 30
```

### Replica Sync Issues

```sql
-- Compare replica states
select
    database,
    table,
    replica_name,
    log_pointer,
    queue_size,
    absolute_delay
from system.replicas
where database = '{database}' and table = '{table}'
order by replica_name
```

### Distributed DDL Issues

```sql
select
    entry,
    host_name,
    host_address,
    status,
    exception_code,
    exception_text
from system.distributed_ddl_queue
where status != 'Finished'
order by entry desc
limit 30
```

---

## Replication Health Score

```sql
select
    sum(is_readonly) as readonly_replicas,
    sum(is_session_expired) as expired_sessions,
    sum(queue_size) as total_queue,
    max(absolute_delay) as max_delay_sec,
    countIf(absolute_delay > 300) as lagging_replicas,
    multiIf(
        readonly_replicas > 0 or expired_sessions > 0, 'Critical',
        max_delay_sec > 3600 or total_queue > 1000, 'Major',
        max_delay_sec > 300 or total_queue > 200, 'Moderate',
        'OK'
    ) as overall_health
from system.replicas
```

---

## Ad-Hoc Query Guidelines

### Required Safeguards
```sql
-- For text_log queries
where event_time > now() - interval 1 hour
limit 100

-- For part_log
where event_date >= today() - 1
```

### Key Tables
- `system.replicas` - replica state
- `system.replication_queue` - pending tasks
- `system.replicated_fetches` - active downloads
- `system.zookeeper_connection` - Keeper session
- `system.distributed_ddl_queue` - DDL replication

---

## Cross-Module Triggers

| Finding | Load Module | Reason |
|---------|-------------|--------|
| Merge tasks stuck | `altinity-expert-clickhouse-merges` | Merge backlog analysis |
| Fetch slow + disk issues | `altinity-expert-clickhouse-storage` | Disk bottleneck |
| Keeper connection issues | `altinity-expert-clickhouse-logs` | Log investigation |
| Many parts to fetch | `altinity-expert-clickhouse-ingestion` | Insert pattern analysis |

---

## Settings Reference

| Setting | Notes |
|---------|-------|
| `max_replicated_fetches_network_bandwidth` | Limit fetch bandwidth |
| `max_replicated_sends_network_bandwidth` | Limit send bandwidth |
| `replicated_fetches_http_connection_timeout` | Fetch timeout |
| `replicated_fetches_http_receive_timeout` | Receive timeout |
| `background_fetches_pool_size` | Parallel fetches |
