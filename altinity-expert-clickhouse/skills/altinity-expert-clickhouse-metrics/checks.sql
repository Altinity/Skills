-- Key Health Metrics
select
    host,
    'Running Queries' as metric,
    query_value as value,
    '' as unit,
    if(query_value > 100, 'High', 'OK') as status
from
(
    with
        am as
        (
            select hostName() as host, metric, value
            from clusterAllReplicas('{cluster}', system.asynchronous_metrics)
            where metric in ('Query', 'MemoryResident', 'OSMemoryTotal', 'LoadAverage1', 'ReadonlyReplica', 'MaxPartCountForPartition')
               or metric like 'ReplicasMax%Delay'
               or metric like 'CPUFrequencyMHz%'
        )
    select
        host,
        toFloat64(maxIf(value, metric = 'Query')) as query_value
    from am
    group by host
)

union all select
    host,
    'Memory Usage',
    mem_resident as value,
    formatReadableSize(mem_resident),
    if(mem_resident > mem_total * 0.8, 'High', 'OK')
from
(
    select
        hostName() as host,
        toFloat64(maxIf(value, metric = 'MemoryResident')) as mem_resident,
        toFloat64(maxIf(value, metric = 'OSMemoryTotal')) as mem_total
    from clusterAllReplicas('{cluster}', system.asynchronous_metrics)
    where metric in ('MemoryResident', 'OSMemoryTotal')
    group by host
)

union all select
    host,
    'Load Average (1m)',
    load_1m as value,
    toString(round(load_1m, 2)),
    if(load_1m > cpu_count, 'High', 'OK')
from
(
    select
        hostName() as host,
        toFloat64(maxIf(value, metric = 'LoadAverage1')) as load_1m,
        toFloat64(countIf(metric like 'CPUFrequencyMHz%')) as cpu_count
    from clusterAllReplicas('{cluster}', system.asynchronous_metrics)
    where metric = 'LoadAverage1' or metric like 'CPUFrequencyMHz%'
    group by host
)

union all select
    host,
    'Readonly Replicas',
    readonly_replicas as value,
    toString(readonly_replicas),
    if(readonly_replicas > 0, 'Critical', 'OK')
from
(
    select
        hostName() as host,
        toFloat64(maxIf(value, metric = 'ReadonlyReplica')) as readonly_replicas
    from clusterAllReplicas('{cluster}', system.asynchronous_metrics)
    where metric = 'ReadonlyReplica'
    group by host
)

union all select
    host,
    'Max Replica Delay',
    max_delay as value,
    formatReadableTimeDelta(max_delay),
    if(max_delay > 300, 'High', 'OK')
from
(
    select
        hostName() as host,
        max(value) as max_delay
    from clusterAllReplicas('{cluster}', system.asynchronous_metrics)
    where metric like 'ReplicasMax%Delay'
    group by host
)

union all select
    host,
    'Max Parts in Partition',
    max_parts as value,
    toString(max_parts),
    if(max_parts > 200, 'High', 'OK')
from
(
    select
        hostName() as host,
        toFloat64(maxIf(value, metric = 'MaxPartCountForPartition')) as max_parts
    from clusterAllReplicas('{cluster}', system.asynchronous_metrics)
    where metric = 'MaxPartCountForPartition'
    group by host
)
;

-- Resource Saturation
select
    host,
    'CPU Load' as resource,
    cpu_current as current,
    cpu_capacity as capacity,
    round(100.0 * cpu_current / cpu_capacity, 1) as utilization_pct,
    multiIf(100.0 * cpu_current / cpu_capacity > 200, 'Critical', 100.0 * cpu_current / cpu_capacity > 100, 'High', 'OK') as status
from
(
    with
        am as
        (
            select hostName() as host, metric, value
            from clusterAllReplicas('{cluster}', system.asynchronous_metrics)
            where metric = 'LoadAverage1' or metric like 'CPUFrequencyMHz%' or metric in ('MemoryResident', 'OSMemoryTotal')
        ),
        m as
        (
            select hostName() as host, metric, value
            from clusterAllReplicas('{cluster}', system.metrics)
            where metric like '%Connection' or metric = 'Query'
        ),
        ss as
        (
            select hostName() as host, name, toFloat64OrZero(value) as value
            from clusterAllReplicas('{cluster}', system.server_settings)
            where name in ('max_connections', 'max_concurrent_queries')
        )
    select
        am.host as host,
        toFloat64(maxIf(am.value, am.metric = 'LoadAverage1')) as cpu_current,
        toFloat64(countIf(am.metric like 'CPUFrequencyMHz%')) as cpu_capacity,
        toFloat64(maxIf(am.value, am.metric = 'MemoryResident')) as mem_current,
        toFloat64(maxIf(am.value, am.metric = 'OSMemoryTotal')) as mem_capacity,
        toFloat64(sumIf(m.value, m.metric like '%Connection')) as conn_current,
        toFloat64(maxIf(ss.value, ss.name = 'max_connections')) as conn_capacity,
        toFloat64(sumIf(m.value, m.metric = 'Query')) as query_current,
        toFloat64(maxIf(ss.value, ss.name = 'max_concurrent_queries')) as query_capacity
    from am
    left join m on m.host = am.host
    left join ss on ss.host = am.host
    group by am.host
)

union all select
    host,
    'Memory',
    mem_current,
    mem_capacity,
    round(100.0 * mem_current / mem_capacity, 1),
    multiIf(100.0 * mem_current / mem_capacity > 90, 'Critical', 100.0 * mem_current / mem_capacity > 80, 'High', 'OK')
from
(
    select
        hostName() as host,
        toFloat64(maxIf(value, metric = 'MemoryResident')) as mem_current,
        toFloat64(maxIf(value, metric = 'OSMemoryTotal')) as mem_capacity
    from clusterAllReplicas('{cluster}', system.asynchronous_metrics)
    where metric in ('MemoryResident', 'OSMemoryTotal')
    group by host
)

union all select
    c.host as host,
    'Connections',
    conn_current,
    conn_capacity,
    round(100.0 * conn_current / conn_capacity, 1),
    multiIf(100.0 * conn_current / conn_capacity > 90, 'Critical', 100.0 * conn_current / conn_capacity > 75, 'High', 'OK')
from
(
    select
        hostName() as host,
        toFloat64(sumIf(value, metric like '%Connection')) as conn_current
    from clusterAllReplicas('{cluster}', system.metrics)
    where metric like '%Connection'
    group by host
) c
left join
(
    select
        hostName() as host,
        toFloat64OrZero(value) as conn_capacity
    from clusterAllReplicas('{cluster}', system.server_settings)
    where name = 'max_connections'
) s on s.host = c.host

union all select
    q.host as host,
    'Concurrent Queries',
    query_current,
    query_capacity,
    round(100.0 * query_current / query_capacity, 1),
    multiIf(100.0 * query_current / query_capacity > 90, 'Critical', 100.0 * query_current / query_capacity > 75, 'High', 'OK')
from
(
    select
        hostName() as host,
        toFloat64(sumIf(value, metric = 'Query')) as query_current
    from clusterAllReplicas('{cluster}', system.metrics)
    where metric = 'Query'
    group by host
) q
left join
(
    select
        hostName() as host,
        toFloat64OrZero(value) as query_capacity
    from clusterAllReplicas('{cluster}', system.server_settings)
    where name = 'max_concurrent_queries'
) s on s.host = q.host
;

-- Current Metrics Snapshot
select
    hostName() as host,
    metric,
    value,
    description
from clusterAllReplicas('{cluster}', system.metrics)
where value > 0
order by metric, host asc
;

-- Connection Metrics
select
    hostName() as host,
    metric,
    value
from clusterAllReplicas('{cluster}', system.metrics)
where metric like '%Connection%'
order by value desc, host asc
;

-- Background Task Metrics
select
    hostName() as host,
    metric,
    value
from clusterAllReplicas('{cluster}', system.metrics)
where metric like 'Background%' or metric like '%Pool%'
order by metric, host asc
;

-- Query Metrics
select
    hostName() as host,
    metric,
    value
from clusterAllReplicas('{cluster}', system.metrics)
where metric like '%Query%' or metric like '%Insert%' or metric like '%Select%'
order by metric, host asc
;

-- Memory Metrics
select
    hostName() as host,
    metric,
    value,
    formatReadableSize(value) as readable
from clusterAllReplicas('{cluster}', system.asynchronous_metrics)
where metric like '%Memory%' or metric like '%Cache%'
order by metric, host asc
;

-- Load Metrics
select
    hostName() as host,
    metric,
    round(value, 2) as value
from clusterAllReplicas('{cluster}', system.asynchronous_metrics)
where metric like 'LoadAverage%' or metric like 'CPU%'
order by metric, host asc
;

-- Disk Metrics
select
    hostName() as host,
    metric,
    value,
    formatReadableSize(value) as readable
from clusterAllReplicas('{cluster}', system.asynchronous_metrics)
where metric like '%Disk%' or metric like 'Filesystem%'
order by metric, host asc
;

-- Replication Metrics
select
    hostName() as host,
    metric,
    value,
    if(metric like '%Delay%', formatReadableTimeDelta(value), toString(value)) as readable
from clusterAllReplicas('{cluster}', system.asynchronous_metrics)
where metric like 'Replicas%'
order by metric, host asc
;

-- Top Events Since Start
select
    hostName() as host,
    event,
    value,
    description
from clusterAllReplicas('{cluster}', system.events)
where value > 0
order by value desc, host asc
limit 50
;

-- Query Events
select
    hostName() as host,
    event,
    value
from clusterAllReplicas('{cluster}', system.events)
where event like '%Query%' or event like '%Select%' or event like '%Insert%'
order by value desc, host asc
limit 30
;

-- IO Events
select
    hostName() as host,
    event,
    value,
    if(event like '%Bytes%', formatReadableSize(value), toString(value)) as readable
from clusterAllReplicas('{cluster}', system.events)
where event like '%Read%' or event like '%Write%' or event like '%Disk%'
order by value desc, host asc
limit 30
;

-- Cache Events
select
    hostName() as host,
    event,
    value
from clusterAllReplicas('{cluster}', system.events)
where event like '%Cache%'
order by event, host asc
;

-- Memory Over Time
select
    hostName() as host,
    toStartOfFiveMinutes(event_time) as ts,
    round(avg(value)) as avg_memory,
    formatReadableSize(avg_memory) as readable,
    round(max(value)) as max_memory
from clusterAllReplicas('{cluster}', system.asynchronous_metric_log)
where metric = 'MemoryResident'
  and event_time > now() - interval 6 hour
group by host, ts
order by ts, host
;

-- Load Average Over Time
select
    hostName() as host,
    toStartOfFiveMinutes(event_time) as ts,
    round(avgIf(value, metric = 'LoadAverage1'), 2) as load_1m,
    round(avgIf(value, metric = 'LoadAverage5'), 2) as load_5m,
    round(avgIf(value, metric = 'LoadAverage15'), 2) as load_15m
from clusterAllReplicas('{cluster}', system.asynchronous_metric_log)
where metric like 'LoadAverage%'
  and event_time > now() - interval 6 hour
group by host, ts
order by ts, host
;

-- Query Rate Over Time
select
    hostName() as host,
    toStartOfMinute(event_time) as ts,
    sum(ProfileEvent_Query) as queries,
    sum(ProfileEvent_SelectQuery) as selects,
    sum(ProfileEvent_InsertQuery) as inserts
from clusterAllReplicas('{cluster}', system.metric_log)
where event_time > now() - interval 1 hour
group by host, ts
order by ts, host
;

-- Current vs Thresholds
select
    host,
    'Queries' as check_name,
    current_queries as current,
    max_queries as threshold,
    round(100.0 * current_queries / max_queries, 1) as pct,
    if(100.0 * current_queries / max_queries > 90, 'ALERT', if(100.0 * current_queries / max_queries > 75, 'WARN', 'OK')) as status
from
(
    with
        met as
        (
            select hostName() as host, metric, toFloat64(value) as value
            from clusterAllReplicas('{cluster}', system.metrics)
            where metric in ('Query', 'ReadonlyReplica')
        ),
        am as
        (
            select hostName() as host, metric, toFloat64(value) as value
            from clusterAllReplicas('{cluster}', system.asynchronous_metrics)
            where metric in ('MaxPartCountForPartition', 'MemoryResident', 'OSMemoryTotal') or metric like 'ReplicasMax%Delay'
        ),
        ss as
        (
            select hostName() as host, name, toFloat64OrZero(value) as value
            from clusterAllReplicas('{cluster}', system.server_settings)
            where name = 'max_concurrent_queries'
        ),
        mts as
        (
            select hostName() as host, name, toFloat64OrZero(value) as value
            from clusterAllReplicas('{cluster}', system.merge_tree_settings)
            where name in ('parts_to_delay_insert', 'parts_to_throw_insert')
        )
    select
        coalesce(met.host, am.host, ss.host, mts.host) as host,
        sumIf(met.value, met.metric = 'Query') as current_queries,
        maxIf(ss.value, ss.name = 'max_concurrent_queries') as max_queries,
        sumIf(met.value, met.metric = 'ReadonlyReplica') as readonly_replicas,
        maxIf(am.value, am.metric = 'MaxPartCountForPartition') as max_parts,
        maxIf(mts.value, mts.name = 'parts_to_delay_insert') as delay_threshold,
        maxIf(mts.value, mts.name = 'parts_to_throw_insert') as throw_threshold,
        maxIf(am.value, am.metric like 'ReplicasMax%Delay') as max_delay,
        maxIf(am.value, am.metric = 'MemoryResident') as memory,
        maxIf(am.value, am.metric = 'OSMemoryTotal') as total_memory
    from met
    full outer join am on am.host = met.host
    full outer join ss on ss.host = coalesce(met.host, am.host)
    full outer join mts on mts.host = coalesce(met.host, am.host, ss.host)
    group by host
)

union all select
    host,
    'Readonly Replicas',
    readonly_replicas,
    toFloat64(0),
    toFloat64(0),
    if(readonly_replicas > 0, 'ALERT', 'OK')
from
(
    select
        hostName() as host,
        toFloat64(sumIf(value, metric = 'ReadonlyReplica')) as readonly_replicas
    from clusterAllReplicas('{cluster}', system.metrics)
    where metric = 'ReadonlyReplica'
    group by host
)

union all select
    p.host as host,
    'Max Parts in Partition',
    max_parts,
    delay_threshold,
    round(100.0 * max_parts / delay_threshold, 1),
    if(max_parts > throw_threshold, 'ALERT', if(max_parts > delay_threshold, 'WARN', 'OK'))
from
(
    select
        hostName() as host,
        toFloat64(maxIf(value, metric = 'MaxPartCountForPartition')) as max_parts
    from clusterAllReplicas('{cluster}', system.asynchronous_metrics)
    where metric = 'MaxPartCountForPartition'
    group by host
) p
left join
(
    select
        hostName() as host,
        toFloat64OrZero(maxIf(value, name = 'parts_to_delay_insert')) as delay_threshold,
        toFloat64OrZero(maxIf(value, name = 'parts_to_throw_insert')) as throw_threshold
    from clusterAllReplicas('{cluster}', system.merge_tree_settings)
    where name in ('parts_to_delay_insert', 'parts_to_throw_insert')
    group by host
) t on t.host = p.host

union all select
    host,
    'Replica Delay (sec)',
    max_delay,
    toFloat64(300),
    toFloat64(0),
    if(max_delay > 3600, 'ALERT', if(max_delay > 300, 'WARN', 'OK'))
from
(
    select
        hostName() as host,
        toFloat64(max(value)) as max_delay
    from clusterAllReplicas('{cluster}', system.asynchronous_metrics)
    where metric like 'ReplicasMax%Delay'
    group by host
)

union all select
    host,
    'Memory Usage',
    memory,
    total_memory * 0.9,
    round(100.0 * memory / total_memory, 1),
    if(100.0 * memory / total_memory > 90, 'ALERT', if(100.0 * memory / total_memory > 80, 'WARN', 'OK'))
from
(
    select
        hostName() as host,
        toFloat64(maxIf(value, metric = 'MemoryResident')) as memory,
        toFloat64(maxIf(value, metric = 'OSMemoryTotal')) as total_memory
    from clusterAllReplicas('{cluster}', system.asynchronous_metrics)
    where metric in ('MemoryResident', 'OSMemoryTotal')
    group by host
)
;

-- Disk IO Metrics
select
    hostName() as host,
    metric,
    value
from clusterAllReplicas('{cluster}', system.asynchronous_metrics)
where metric like 'BlockInFlightOps%'
   or metric like 'BlockReadOps%'
   or metric like 'BlockWriteOps%'
order by metric, host asc
;

-- Disk Queue Depth
select
    hostName() as host,
    metric,
    value,
    multiIf(value > 245, 'Critical', value > 200, 'High', value > 128, 'Moderate', 'OK') as status
from clusterAllReplicas('{cluster}', system.asynchronous_metrics)
where metric like 'BlockInFlightOps%'
  and value > 0
order by value desc, host asc
;

-- Uptime and Version
select
    o.host as host,
    o.uptime_seconds,
    o.uptime_human,
    o.version,
    bo.version_full
from
(
    select
        hostName() as host,
        uptime() as uptime_seconds,
        formatReadableTimeDelta(uptime()) as uptime_human,
        version() as version
    from clusterAllReplicas('{cluster}', system.one)
) o
left join
(
    select
        hostName() as host,
        anyIf(value, name = 'VERSION_DESCRIBE') as version_full
    from clusterAllReplicas('{cluster}', system.build_options)
    where name = 'VERSION_DESCRIBE'
    group by host
) bo on bo.host = o.host
;

-- Top Profile Events (from system.events)
select
    hostName() as host,
    event,
    value as total,
    description
from clusterAllReplicas('{cluster}', system.events)
where value > 0
order by value desc, host asc
limit 30
;

-- Check if Prometheus endpoint is enabled
select
    hostName() as host,
    name,
    value,
    changed,
    description
from clusterAllReplicas('{cluster}', system.server_settings)
where name like '%prometheus%'
order by name, host asc
;
