-- System Log Tables Overview
select
    hostName() as host,
    name as log_table,
    engine,
    formatReadableSize(total_bytes) as size,
    total_rows as rows,
    ifNull(p.parts, 0) as parts,
    create_table_query like '% TTL %' as has_ttl
from clusterAllReplicas('{cluster}', system.tables) t
left join
(
    select
        hostName() as host,
        table as log_table,
        count() as parts
    from clusterAllReplicas('{cluster}', system.parts)
    where database = 'system' and table like '%_log' and active
    group by host, log_table
) p on p.host = host and p.log_table = t.name
where database = 'system'
  and name like '%_log'
  and engine like '%MergeTree%'
order by total_bytes desc, host asc
;

-- TTL Configuration Audit
select
    hostName() as host,
    name as log_table,
    if(create_table_query like '% TTL %', 'Configured', 'MISSING') as ttl_status,
    multiIf(
        create_table_query not like '% TTL %', 'Major',
        'OK'
    ) as severity,
    if(severity = 'Major', 'System log should have TTL to prevent disk fill', 'OK') as note
from clusterAllReplicas('{cluster}', system.tables)
where database = 'system'
  and name like '%_log'
  and engine like '%MergeTree%'
order by severity, name, host asc
;

-- Log Disk Usage vs Free Space
select
    l.host as host,
    log_bytes / (log_bytes + free_bytes) as ratio,
    formatReadableSize(log_bytes) as log_usage,
    formatReadableSize(free_bytes) as free_space,
    round(100.0 * ratio, 2) as log_pct_of_used_disk,
    multiIf(ratio > 0.2, 'Critical', ratio > 0.1, 'Major', ratio > 0.05, 'Moderate', 'OK') as severity
from
(
    select
        hostName() as host,
        sum(bytes_on_disk) as log_bytes
    from clusterAllReplicas('{cluster}', system.parts)
    where database = 'system' and table like '%_log' and active
    group by host
) l
left join
(
	    select
	        hostName() as host,
	        max(arrayMin([free_space, unreserved_space])) as free_bytes
	    from clusterAllReplicas('{cluster}', system.disks)
	    where name = 'default'
	    group by host
	) d on d.host = l.host
;

-- Log Sizes by Table
select
    hostName() as host,
    table,
    formatReadableSize(sum(bytes_on_disk)) as size,
    sum(rows) as rows,
    count() as parts,
    min(min_date) as oldest_data,
    max(max_date) as newest_data,
    dateDiff('day', min(min_date), max(max_date)) as days_span
from clusterAllReplicas('{cluster}', system.parts)
where database = 'system'
  and table like '%_log'
  and active
group by host, table
order by sum(bytes_on_disk) desc, host asc
;

-- Log Freshness Check
select
    host,
    table,
    max(modification_time) as last_write,
    dateDiff('minute', max(modification_time), global_max_time) as minutes_behind,
    multiIf(
        minutes_behind > 240, 'Major - no recent data',
        minutes_behind > 60, 'Moderate - may be stale',
        'OK'
    ) as freshness
from
(
    select
        hostName() as host,
        *
    from clusterAllReplicas('{cluster}', system.parts)
) p
left join
(
    select
        hostName() as host,
        max(modification_time) as global_max_time
    from clusterAllReplicas('{cluster}', system.parts)
    group by host
) g on g.host = p.host
where database = 'system'
  and table like '%_log'
  and active
group by host, table, global_max_time
order by minutes_behind desc, host asc
;

-- Leftover Log Tables (Post-Upgrade)
select
    hostName() as host,
    name,
    engine,
    formatReadableSize(total_bytes) as size,
    total_rows as rows,
    'Minor - leftover from version upgrade, consider dropping' as note
from clusterAllReplicas('{cluster}', system.tables)
where database = 'system'
  and match(name, '\\w+_log_\\d+')
order by total_bytes desc, host asc
;

-- Estimated Retention by Table
select
    hostName() as host,
    table,
    min(min_date) as oldest_date,
    max(max_date) as newest_date,
    dateDiff('day', min(min_date), max(max_date)) as retention_days,
    formatReadableSize(sum(bytes_on_disk)) as total_size,
    formatReadableSize(sum(bytes_on_disk) / nullIf(dateDiff('day', min(min_date), max(max_date)), 0)) as size_per_day
from clusterAllReplicas('{cluster}', system.parts)
where database = 'system'
  and table like '%_log'
  and active
group by host, table
having retention_days > 0
order by retention_days desc, host asc
;

-- Log Growth Rate
select
    hostName() as host,
    table,
    toDate(modification_time) as day,
    count() as new_parts,
    sum(rows) as new_rows,
    formatReadableSize(sum(bytes_on_disk)) as new_bytes
from clusterAllReplicas('{cluster}', system.parts)
where database = 'system'
  and table like '%_log'
  and modification_time > now() - interval 7 day
group by host, table, day
order by host, table, day desc
;

-- query_log Health
select
    'query_log' as log_table,
    q.host as host,
    today_queries,
    yesterday_queries,
    oldest_date,
    newest_date,
    formatReadableSize(size_bytes) as size
from
(
    select
        hostName() as host,
        countIf(event_date = today()) as today_queries,
        countIf(event_date = yesterday()) as yesterday_queries,
        min(event_date) as oldest_date,
        max(event_date) as newest_date
    from clusterAllReplicas('{cluster}', system.query_log)
    group by host
) q
left join
(
    select
        hostName() as host,
        sum(bytes_on_disk) as size_bytes
    from clusterAllReplicas('{cluster}', system.parts)
    where database = 'system' and table = 'query_log' and active
    group by host
) qs on qs.host = q.host
;

-- part_log Health
select
    'part_log' as log_table,
    p.host as host,
    today_events,
    yesterday_events,
    oldest_date,
    newest_date,
    formatReadableSize(size_bytes) as size
from
(
    select
        hostName() as host,
        countIf(event_date = today()) as today_events,
        countIf(event_date = yesterday()) as yesterday_events,
        min(event_date) as oldest_date,
        max(event_date) as newest_date
    from clusterAllReplicas('{cluster}', system.part_log)
    group by host
) p
left join
(
    select
        hostName() as host,
        sum(bytes_on_disk) as size_bytes
    from clusterAllReplicas('{cluster}', system.parts)
    where database = 'system' and table = 'part_log' and active
    group by host
) ps on ps.host = p.host
;

-- query_thread_log Warning
select
    hostName() as host,
    name,
    formatReadableSize(total_bytes) as size,
    'Major - query_thread_log should be disabled in production (high overhead)' as warning
from clusterAllReplicas('{cluster}', system.tables)
where database = 'system' and name = 'query_thread_log'
;

-- Current TTL Extraction
select
    hostName() as host,
    name,
    extract(create_table_query, 'TTL [^\\n]+') as ttl_clause
from clusterAllReplicas('{cluster}', system.tables)
where database = 'system'
  and name like '%_log'
  and create_table_query like '% TTL %'
;

-- Parts to Drop After TTL
select
    hostName() as host,
    table,
    count() as expired_parts,
    formatReadableSize(sum(bytes_on_disk)) as expired_size
from clusterAllReplicas('{cluster}', system.parts)
where database = 'system'
  and table like '%_log'
  and active
  and max_date < today() - 30
group by host, table
order by sum(bytes_on_disk) desc, host asc
;

-- Current Log Settings
select
    hostName() as host,
    name,
    value
from clusterAllReplicas('{cluster}', system.server_settings)
where name like '%log%'
  and name not like '%path%'
order by name, host asc
;

-- Log Flush Intervals
select
    hostName() as host,
    name,
    value
from clusterAllReplicas('{cluster}', system.server_settings)
where name like '%flush%'
order by name, host asc
;
