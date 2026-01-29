-- system identification (per host)
with
    ident as
    (
        select
            hostName() as host,
            version() as version,
            uptime() as uptime_seconds
        from clusterAllReplicas('{cluster}', system.one)
    ),
    settings as
    (
        select
            hostName() as host,
            anyIf(value, name = 'max_memory_usage') as max_memory_usage
        from clusterAllReplicas('{cluster}', system.settings)
        where name = 'max_memory_usage'
        group by host
    ),
    async as
    (
        select
            hostName() as host,
            maxIf(value, metric = 'OSMemoryTotal') as os_memory_total
        from clusterAllReplicas('{cluster}', system.asynchronous_metrics)
        where metric = 'OSMemoryTotal'
        group by host
    )
	select
	    i.host as hostname,
	    i.version as version,
	    formatReadableTimeDelta(i.uptime_seconds) as uptime_human,
	    s.max_memory_usage as max_memory_usage,
	    a.os_memory_total as os_memory_total
	from ident i
	left join settings s on s.host = i.host
	left join async a on a.host = i.host
	order by hostname
	;

-- Object Counts Audit (per host)
select
    t.host as host,
    x.1 as check_name,
    x.2 as value,
    x.3 as severity,
    x.4 as note
from
(
    select
        hostName() as host,
        countIf(engine like 'Replicated%') as replicated_tables,
        countIf(engine like '%MergeTree%') as mergetree_tables
    from clusterAllReplicas('{cluster}', system.tables)
    group by host
) t
left join
(
    select
        hostName() as host,
        count() as databases
    from clusterAllReplicas('{cluster}', system.databases)
    group by host
) d on d.host = t.host
left join
(
    select
        hostName() as host,
        countIf(active) as active_parts
    from clusterAllReplicas('{cluster}', system.parts)
    group by host
) p on p.host = t.host
left join
(
    select
        hostName() as host,
        countIf(is_cancelled = 0) as current_queries
    from clusterAllReplicas('{cluster}', system.processes)
    group by host
) q on q.host = t.host
array join
[
    ('Replicated Tables', toFloat64(replicated_tables), multiIf(replicated_tables > 2000, 'Critical', replicated_tables > 900, 'Major', replicated_tables > 200, 'Moderate', 'OK'), 'Recommend: <200, tune background_schedule_pool_size if higher'),
    ('MergeTree Tables', toFloat64(mergetree_tables), multiIf(mergetree_tables > 10000, 'Critical', mergetree_tables > 3000, 'Major', mergetree_tables > 1000, 'Moderate', 'OK'), 'High count increases metadata overhead'),
    ('Databases', toFloat64(databases), multiIf(databases > 1000, 'Critical', databases > 300, 'Major', databases > 100, 'Moderate', 'OK'), 'Consider consolidating if >100'),
    ('Active Parts', toFloat64(active_parts), multiIf(active_parts > 120000, 'Critical', active_parts > 90000, 'Major', active_parts > 60000, 'Moderate', 'OK'), 'High count slows restarts and metadata ops'),
    ('Current Queries', toFloat64(current_queries), multiIf(current_queries > 100, 'Major', current_queries > 50, 'Moderate', 'OK'), 'Check max_concurrent_queries setting')
] as x
order by
    t.host asc,
    multiIf(severity = 'Critical', 1, severity = 'Major', 2, severity = 'Moderate', 3, 4),
    check_name
;

-- Resource Utilization (per host)
with
    am as
    (
        select hostName() as host, metric, value
        from clusterAllReplicas('{cluster}', system.asynchronous_metrics)
        where metric in ('OSMemoryTotal', 'MemoryResident')
    ),
    total_ram as (select host, maxIf(value, metric = 'OSMemoryTotal') as v from am group by host),
    used_ram as (select host, maxIf(value, metric = 'MemoryResident') as v from am group by host),
    pk as
    (
        select hostName() as host, sum(primary_key_bytes_in_memory) as v
        from clusterAllReplicas('{cluster}', system.parts)
        where active
        group by host
    ),
    dict as
    (
        select hostName() as host, sum(bytes_allocated) as v
        from clusterAllReplicas('{cluster}', system.dictionaries)
        group by host
    ),
    mem_tables as
    (
        select hostName() as host, assumeNotNull(sum(total_bytes)) as v
        from clusterAllReplicas('{cluster}', system.tables)
        where engine in ('Memory', 'Set', 'Join')
        group by host
    )
select
    host,
    'Memory Usage' as resource,
    formatReadableSize(used) as used_human,
    formatReadableSize(total) as total_human,
    round(100.0 * used / nullIf(total, 0), 1) as pct,
    multiIf(pct > 90, 'Critical', pct > 80, 'Major', pct > 70, 'Moderate', 'OK') as severity
from
(
	    select
	        t.host as host,
	        toUInt64(ifNull(u.v, 0)) as used,
	        toUInt64(ifNull(t.v, 0)) as total
	    from total_ram t
	    left join used_ram u on u.host = t.host
	)

union all

select
    host,
    'Primary Keys in RAM' as resource,
    formatReadableSize(used) as used_human,
    formatReadableSize(total) as total_human,
    round(100.0 * used / nullIf(total, 0), 1) as pct,
    multiIf(pct > 30, 'Critical', pct > 25, 'Major', pct > 20, 'Moderate', 'OK') as severity
from
(
	    select
	        t.host as host,
	        toUInt64(ifNull(pk.v, 0)) as used,
	        toUInt64(ifNull(t.v, 0)) as total
	    from total_ram t
	    left join pk on pk.host = t.host
	)

union all

select
    host,
    'Dictionaries + MemTables' as resource,
    formatReadableSize(used) as used_human,
    formatReadableSize(total) as total_human,
    round(100.0 * used / nullIf(total, 0), 1) as pct,
    multiIf(pct > 30, 'Critical', pct > 25, 'Major', pct > 20, 'Moderate', 'OK') as severity
from
(
	    select
	        t.host as host,
	        toUInt64(ifNull(d.v, 0)) + toUInt64(ifNull(mt.v, 0)) as used,
	        toUInt64(ifNull(t.v, 0)) as total
	    from total_ram t
	    left join dict d on d.host = t.host
	    left join mem_tables mt on mt.host = t.host
	)
order by host asc, severity asc
;

-- Disk Health (per host, local disks only)
select
    hostName() as host,
    name as disk,
    path,
    formatReadableSize(total_space) as total,
    formatReadableSize(free_space) as free,
    round(100.0 * (total_space - free_space) / nullIf(total_space, 0), 1) as used_pct,
    multiIf(used_pct > 90, 'Critical', used_pct > 85, 'Major', used_pct > 80, 'Moderate', 'OK') as severity
from clusterAllReplicas('{cluster}', system.disks)
where lower(type) = 'local'
order by used_pct desc, host asc
;

-- Replication Health (per host)
with
    m as
    (
        select hostName() as host, metric, toFloat64(value) as value
        from clusterAllReplicas('{cluster}', system.metrics)
        where metric = 'ReadonlyReplica'
    ),
    am as
    (
        select hostName() as host, metric, toFloat64(value) as value
        from clusterAllReplicas('{cluster}', system.asynchronous_metrics)
        where metric in ('ReplicasSumQueueSize', 'ReplicasMaxAbsoluteDelay', 'ReplicasMaxRelativeDelay')
    )
select
    host,
    x.1 as check_name,
    x.2 as value,
    x.3 as severity
from
(
    select
        coalesce(m.host, am.host) as host,
        arrayJoin(
            [
                ('Readonly Replicas', sumIf(m.value, m.metric = 'ReadonlyReplica'), if(sumIf(m.value, m.metric = 'ReadonlyReplica') > 0, 'Critical', 'OK')),
                ('Max Replica Delay', maxIf(am.value, am.metric in ('ReplicasMaxAbsoluteDelay', 'ReplicasMaxRelativeDelay')), multiIf(maxIf(am.value, am.metric in ('ReplicasMaxAbsoluteDelay', 'ReplicasMaxRelativeDelay')) > 86400, 'Critical', maxIf(am.value, am.metric in ('ReplicasMaxAbsoluteDelay', 'ReplicasMaxRelativeDelay')) > 10800, 'Major', maxIf(am.value, am.metric in ('ReplicasMaxAbsoluteDelay', 'ReplicasMaxRelativeDelay')) > 1800, 'Moderate', 'OK')),
                ('Replication Queue Size', sumIf(am.value, am.metric = 'ReplicasSumQueueSize'), multiIf(sumIf(am.value, am.metric = 'ReplicasSumQueueSize') > 500, 'Major', sumIf(am.value, am.metric = 'ReplicasSumQueueSize') > 200, 'Moderate', 'OK'))
            ]
        ) as x
    from m
    full outer join am on am.host = m.host
    group by coalesce(m.host, am.host)
)
order by host asc, check_name
;

-- Background Pool Status (per host)
with
    metrics as
    (
        select hostName() as host, metric, value
        from clusterAllReplicas('{cluster}', system.metrics)
        where metric like 'Background%PoolTask'
    ),
    settings as
    (
        select hostName() as host, name, value
        from clusterAllReplicas('{cluster}', system.settings)
        where name like 'background_%_pool_size'
    ),
    map_pool as
    (
        select
            host,
            metric,
            value as active_tasks,
            concat('background_', lower(
                transform(extract(metric, '^Background(.*)PoolTask'),
                    ['MergesAndMutations', 'Fetches', 'Move', 'Common', 'Schedule', 'BufferFlushSchedule', 'MessageBrokerSchedule', 'DistributedSchedule'],
                    ['mergesandmutations', 'fetches', 'move', 'common', 'schedule', 'bufferflushschedule', 'messagebrokerschedule', 'distributedschedule'],
                    ''
                )
            ), '_pool_size') as setting_name
        from metrics
    )
select
    m.host as host,
    extract(m.metric, '^Background(.*)Task') as pool_name,
    m.active_tasks,
    toFloat64OrZero(s.value) as pool_size,
    round(100.0 * m.active_tasks / nullIf(pool_size, 0), 1) as utilization_pct,
    multiIf(utilization_pct > 99, 'Major', utilization_pct > 90, 'Moderate', 'OK') as severity
from map_pool m
left join settings s on s.host = m.host and s.name = m.setting_name
where pool_size > 0
order by utilization_pct desc, host asc
;

-- Version Check (per host)
select
    hostName() as host,
    anyIf(value, name = 'VERSION_DESCRIBE') as version,
    anyIf(value, name = 'BUILD_DATE') as build_date
from clusterAllReplicas('{cluster}', system.build_options)
where name in ('VERSION_DESCRIBE', 'BUILD_DATE')
group by host
order by host
;

-- System Log Health (TTL presence) (per host)
select
    hostName() as host,
    format('system.{}', name) as log_table,
    engine_full like '% TTL %' as has_ttl,
    if(not has_ttl, 'Major', 'OK') as severity,
    if(not has_ttl, 'System log should have TTL to prevent disk fill', 'TTL configured') as note
from clusterAllReplicas('{cluster}', system.tables)
where database = 'system' and name like '%_log' and engine like '%MergeTree%'
order by has_ttl, name, host
;

-- Log disk usage (per host)
select
    hostName() as host,
    table,
    formatReadableSize(sum(bytes_on_disk)) as size,
    count() as parts
from clusterAllReplicas('{cluster}', system.parts)
where database = 'system' and table like '%_log' and active
group by host, table
order by sum(bytes_on_disk) desc, host asc
;

-- Recent Errors Summary (last 24h) (per host)
select
    hostName() as host,
    toStartOfHour(event_time) as hour,
    countIf(type IN ('ExceptionBeforeStart', 'ExceptionWhileProcessing')) as failed_queries,
    count() as total_queries,
    round(100.0 * countIf(type IN ('ExceptionBeforeStart', 'ExceptionWhileProcessing')) / nullIf(count(), 0), 2) as error_rate_pct
from clusterAllReplicas('{cluster}', system.query_log)
where event_time >= now() - interval 24 hour
group by host, hour
order by hour desc, host asc
limit 200
;

-- system.errors Summary (last 24h) (per host)
select
    hostName() as host,
    code,
    name,
    value as count,
    last_error_time,
    substring(last_error_message, 1, 160) as last_error_message
from clusterAllReplicas('{cluster}', system.errors)
where last_error_time >= now() - interval 24 hour
order by last_error_time desc, host asc
limit 200
;

-- Warnings from ClickHouse (per host)
select
    hostName() as host,
    message as warning
from clusterAllReplicas('{cluster}', system.warnings)
order by host, warning
;
