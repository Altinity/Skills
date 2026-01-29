-- Current Merge Activity
-- Interpretation:
-- elapsed > 3600 (1 hour) → Investigate large parts or slow storage
-- num_parts > 100 → Merge backlog, check part creation rate
-- is_mutation = 1 → This is a mutation, not a regular merge
select
    hostName() as host,
    database,
    table,
    round(elapsed, 1) as elapsed_sec,
    round(progress * 100, 1) as progress_pct,
    num_parts,
    formatReadableSize(total_size_bytes_compressed) as size,
    result_part_name,
    is_mutation
from clusterAllReplicas('{cluster}', system.merges)
order by elapsed desc, host asc
limit 20
;

-- Part Count Health Check
-- Red flags:
-- part_count > 300 → Approaching "too many parts" error threshold
-- Many partitions with high counts → Ingestion batching problem
select
    hostName() as host,
    database,
    table,
    partition_id,
    count() as part_count,
    sum(rows) as total_rows,
    formatReadableSize(sum(bytes_on_disk)) as size
from clusterAllReplicas('{cluster}', system.parts)
where active
group by host, database, table, partition_id
having part_count > 50
order by part_count desc, host asc
limit 30
;

-- Recent Merge History (Last Hour)
select
    hostName() as host,
    database,
    table,
    toStartOfFiveMinutes(event_time) as ts,
    count() as merge_count,
    sum(rows) as rows_merged,
    round(avg(duration_ms)) as avg_duration_ms,
    round(max(duration_ms)) as max_duration_ms
from clusterAllReplicas('{cluster}', system.part_log)
where event_type = 'MergeParts'
  and event_time > now() - interval 1 hour
group by host, database, table, ts
order by ts desc, merge_count desc, host asc
limit 50
;

-- Merge Reasons Breakdown
-- Merge reasons:
-- RegularMerge → Normal background merges
-- TTLDeleteMerge → TTL expiration triggered
-- TTLRecompressMerge → TTL recompression
-- MutationMerge → ALTER UPDATE/DELETE
select
    hostName() as host,
    database,
    table,
    merge_reason,
    count() as merge_count,
    round(avg(duration_ms)) as avg_ms,
    sum(rows) as total_rows
from clusterAllReplicas('{cluster}', system.part_log)
where event_type = 'MergeParts'
  and event_date = today()
group by host, database, table, merge_reason
order by merge_count desc, host asc
limit 30
;

-- "Too Many Parts" Error Investigation
-- Step 1: Find the problematic table
select
    hostName() as host,
    database,
    table,
    count() as active_parts,
    uniq(partition_id) as partitions
from clusterAllReplicas('{cluster}', system.parts)
where active
group by host, database, table
order by active_parts desc, host asc
limit 10
;

-- Slow Merge Investigation
-- Find slowest merges
-- Correlate with storage (load altinity-expert-clickhouse-storage):
-- Slow merges + high disk IO → Storage bottleneck
-- Slow merges + normal disk → Large parts, consider partitioning
select
    hostName() as host,
    event_time,
    database,
    table,
    partition_id,
    duration_ms,
    formatReadableSize(size_in_bytes) as size,
    rows,
    part_name,
    merge_reason
from clusterAllReplicas('{cluster}', system.part_log)
where event_type = 'MergeParts'
  and event_date >= today() - 1
order by duration_ms desc, host asc
limit 20
;

-- Failed Merges
select
    hostName() as host,
    event_time,
    database,
    table,
    part_name,
    error,
    exception
from clusterAllReplicas('{cluster}', system.part_log)
where event_type = 'MergeParts'
  and error != 0
  and event_date >= today() - 7
order by event_time desc, host asc
limit 50
;

-- Query current merge_tree_settings values
select
    hostName() as host,
    name, value, changed, description
from clusterAllReplicas('{cluster}', system.merge_tree_settings)
where name in (
    'max_parts_to_merge_at_once',
    'parts_to_throw_insert',
    'parts_to_delay_insert'
)
;
