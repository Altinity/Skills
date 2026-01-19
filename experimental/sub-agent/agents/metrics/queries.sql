-- Query 1: Key metrics snapshot (common)
SELECT
    (SELECT value FROM system.metrics WHERE metric = 'Query') AS running_queries,
    (SELECT value FROM system.metrics WHERE metric = 'Merge') AS running_merges,
    (SELECT value FROM system.metrics WHERE metric = 'ReplicatedSend') AS replication_sends,
    (SELECT value FROM system.metrics WHERE metric = 'ReplicatedFetch') AS replication_fetches,
    (SELECT value FROM system.metrics WHERE metric = 'BackgroundFetchesPoolTask') AS bg_fetch_tasks,
    (SELECT value FROM system.metrics WHERE metric = 'BackgroundMergesAndMutationsPoolTask') AS bg_merge_mut_tasks;

-- Query 2: Top non-zero metrics (counters/gauges)
SELECT
    metric,
    value
FROM system.metrics
WHERE value != 0
ORDER BY value DESC
LIMIT 80;

-- Query 3: Top events by count (high-rate signals)
SELECT
    event,
    value
FROM system.events
WHERE value != 0
ORDER BY value DESC
LIMIT 80;

-- Query 4: Async metrics filtered to "interesting" strings
SELECT
    metric,
    value
FROM system.asynchronous_metrics
WHERE metric ILIKE '%Cache%'
   OR metric ILIKE '%Memory%'
   OR metric ILIKE '%Disk%'
   OR metric ILIKE '%Filesystem%'
ORDER BY metric ASC
LIMIT 200;

