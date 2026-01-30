WITH
    value as v
SELECT
    'A3.0.3' AS id,
    'System' AS object,
    'Critical' AS severity,
    'Some replicas are read-only' AS details,
    map('readonly_replicas', v) as values
FROM system.metrics WHERE metric='ReadonlyReplica'
AND v > 1;

WITH
    value as v
SELECT
    'A3.0.4' AS id,
    metric AS object,
    multiIf(v > 245, 'Major', v > 200, 'Moderate', 'Minor') AS severity,
    'Block in-flight ops is high ' AS details,
    map('in_flight_ops', v) as values
FROM system.asynchronous_metrics
WHERE metric like 'BlockInFlightOps%' and v > 128;

WITH
    coalesce(
        nullIf(toUInt32(floor((SELECT value FROM system.asynchronous_metrics WHERE metric = 'CGroupMaxCPU'))), 0),
        nullIf(toUInt32((SELECT value FROM system.asynchronous_metrics WHERE metric = 'OSCPUCount')), 0),
        (SELECT max(toInt32(extract(metric, '(\\d+)$'))) + 1 FROM system.asynchronous_metrics WHERE metric LIKE 'OSIdleTimeCPU%'),
        1
      ) AS cpu_count,
    value as v
SELECT
    'A3.0.5' AS id,
    metric AS object,
    multiIf(v > 10 * cpu_count, 'Critical', v > 2 * cpu_count, 'Major', v > cpu_count, 'Moderate', 'Minor') AS severity,
    format('Load average is high ({} {}, {} cores)', metric, toString(v), toString(cpu_count)) AS details,
    map('load', toString(v), 'cpu_count', toString(cpu_count)) as values
FROM system.asynchronous_metrics
WHERE metric like 'LoadAverage15'
  and severity != 'Minor'
;

WITH
    value AS v
SELECT
    'A3.0.6' AS id,
    metric AS object,
    multiIf(v > 24*3600, 'Critical', v > 3*3600, 'Major', v>1800, 'Moderate', 'Minor') AS severity,
    format('Replica delay is too big ({}, {})', metric, formatReadableTimeDelta(v)) AS details,
    map('delay', v) as values
FROM system.asynchronous_metrics
WHERE metric IN ('ReplicasMaxAbsoluteDelay', 'ReplicasMaxRelativeDelay') and v > 300;

WITH
    value AS v
SELECT
    'A3.0.7' AS id,
    metric AS object,
    'Minor' AS severity,
    format('Too many inserts in queue ({}, {})', metric, toString(v)) AS details,
    map('max_inserts_in_queue', v) as values
FROM system.asynchronous_metrics
WHERE metric IN ('ReplicasMaxInsertsInQueue') and v > 100;

WITH
    value AS v
SELECT
    'A3.0.8' AS id,
    metric AS object,
    'Minor' AS severity,
    format('Too many inserts in queue ({}, {})', metric, toString(v)) AS details,
    map('sum_inserts_in_queue', v) as values
FROM system.asynchronous_metrics
WHERE metric IN ('ReplicasSumInsertsInQueue') and v > 300;

-- see also
-- max_replicated_merges_in_queue, max_replicated_mutations_in_queue
WITH
    value AS v
SELECT
    'A3.0.9' AS id,
    metric AS object,
    'Minor' AS severity,
    format('Too many merges in queue ({}, {})', metric, toString(v)) AS details,
    map('max_merges_in_queue', v) as values
FROM system.asynchronous_metrics
WHERE metric IN ('ReplicasMaxMergesInQueue') and v > 80;


WITH
    value AS v
SELECT
    'A3.0.10' AS id,
    metric AS object,
    'Minor' AS severity,
    format('Too many inserts in queue ({}, {})', metric, toString(v)) AS details,
    map('sum_merges_in_queue', v) as values
FROM system.asynchronous_metrics
WHERE metric IN ('ReplicasSumMergesInQueue') and v > 200;


WITH
    value AS v
SELECT
    'A3.0.11' AS id,
    metric AS object,
    'Minor' AS severity,
    format('Too many tasks in queue ({}, {})', metric, toString(v)) AS details,
    map('max_merges_in_queue', v) as values
FROM system.asynchronous_metrics
WHERE metric IN ('ReplicasMaxQueueSize') and v > 200;

WITH
    value AS v
SELECT
    'A3.0.12' AS id,
    metric AS object,
    'Minor' AS severity,
    format('Too many tasks in queue ({}, {})', metric, toString(v)) AS details,
    map('sum_merges_in_queue', v) as values
FROM system.asynchronous_metrics
WHERE metric IN ('ReplicasSumQueueSize') and v > 500;

WITH
    value AS v
SELECT
    'A3.0.13' AS id,
    metric AS object,
    'Minor' AS severity,
    format('Too many tasks in queue ({}, {})', metric, toString(v)) AS details,
    map('sum_merges_in_queue', v) as values
FROM system.asynchronous_metrics
WHERE metric IN ('ReplicasSumQueueSize') and v > 500;

WITH
    (select toUInt32(value) from system.merge_tree_settings where name='parts_to_delay_insert') as parts_to_delay_insert,
    (select toUInt32(value) from system.merge_tree_settings where name='parts_to_throw_insert') as parts_to_throw_insert,
    value as v
SELECT
    'A3.0.14' AS id,
    metric AS object,
    multiIf(v > parts_to_throw_insert, 'Critical', v > parts_to_delay_insert, 'Major', 'Minor') AS severity,
    format('Too many parts in partition ({}, {})', metric, toString(v)) AS details,
    map('max_parts_in_partition', v) as values
FROM system.asynchronous_metrics
WHERE metric IN ('MaxPartCountForPartition') and v > parts_to_delay_insert*0.9;

WITH
    (SELECT value FROM system.asynchronous_metrics WHERE metric = 'OSMemoryTotal') as Total,
    value as MemoryResident
SELECT
    'A3.0.15' AS id,
    'Memory' AS object,
    multiIf(MemoryResident > Total*0.9, 'Critical', MemoryResident > Total*0.8, 'Major', 'Minor') AS severity,
    format('Memory usage is high ({} of {})', formatReadableSize(MemoryResident), formatReadableSize(Total)) AS details,
    map('memory_resident', MemoryResident, 'memory_total', Total) as values
FROM system.asynchronous_metrics
WHERE metric IN ('MemoryResident') and MemoryResident > Total*0.8;
