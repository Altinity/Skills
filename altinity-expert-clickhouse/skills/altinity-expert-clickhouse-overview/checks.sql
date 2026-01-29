-- Object Counts Audit
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
;

-- Resource Utilization
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

;

-- Disk Health
select
    name as disk,
    path,
    formatReadableSize(total_space) as total,
    formatReadableSize(free_space) as free,
    round(100.0 * (total_space - free_space) / total_space, 1) as used_pct,
    multiIf(used_pct > 90, 'Critical', used_pct > 85, 'Major', used_pct > 80, 'Moderate', 'OK') as severity
from system.disks
where lower(type) = 'local'
order by used_pct desc
;

-- Replication Health
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

;

-- Background Pool Status
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
;

-- Version Check
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
;

-- System Log Health
select
    format('system.{}', name) as log_table,
    engine_full like '% TTL %' as has_ttl,
    if(not has_ttl, 'Major', 'OK') as severity,
    if(not has_ttl, 'System log should have TTL to prevent disk fill', 'TTL configured') as note
from system.tables
where database = 'system' and name like '%_log' and engine like '%MergeTree%'
order by has_ttl, name
;

-- Log disk usage
select
    table,
    formatReadableSize(sum(bytes_on_disk)) as size,
    count() as parts
from system.parts
where database = 'system' and table like '%_log' and active
group by table
order by sum(bytes_on_disk) desc
;

-- Recent Errors Summary (Timeframe-Based)
select
    toStartOfHour(event_time) as hour,
    countIf(type IN ('ExceptionBeforeStart', 'ExceptionWhileProcessing')) as failed_queries,
    count() as total_queries,
    round(100.0 * countIf(type IN ('ExceptionBeforeStart', 'ExceptionWhileProcessing')) / count(), 2) as error_rate_pct
from system.query_log
where event_time >= now() - interval 24 hour
group by hour
order by hour desc
limit 12
;

-- system.errors Summary (Timeframe-Based)
select
    code,
    name,
    value as count,
    last_error_time,
    substring(last_error_message, 1, 160) as last_error_message
from system.errors
where last_error_time >= now() - interval 24 hour
  and name not in ('NO_REPLICA_HAS_PART')
order by last_error_time desc
limit 20
;
