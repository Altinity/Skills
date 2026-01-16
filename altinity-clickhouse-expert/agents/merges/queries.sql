-- Query 1: Currently running merges
SELECT
    database,
    table,
    elapsed,
    progress,
    num_parts,
    formatReadableSize(total_size_bytes_compressed) AS total_size
FROM system.merges
ORDER BY elapsed DESC
LIMIT 50;

-- Query 2: Merge activity trend (last 24h)
SELECT
    toStartOfHour(event_time) AS hour,
    countIf(event_type = 'MergeParts') AS merges,
    countIf(event_type LIKE 'MergePartsFailed%') AS merge_failures
FROM clusterAllReplicas('{cluster}', system.part_log)
WHERE event_time > now() - INTERVAL 24 HOUR
GROUP BY hour
ORDER BY hour DESC
LIMIT 24;

-- Query 3: Hot tables by merge volume and failures (last 24h)
SELECT
    database,
    table,
    countIf(event_type = 'MergeParts') AS merges,
    countIf(event_type LIKE 'MergePartsFailed%') AS merge_failures
FROM clusterAllReplicas('{cluster}', system.part_log)
WHERE event_time > now() - INTERVAL 24 HOUR
  AND (event_type = 'MergeParts' OR event_type LIKE 'MergePartsFailed%')
GROUP BY database, table
HAVING merges > 0
ORDER BY merge_failures DESC, merges DESC
LIMIT 30;

-- Query 4: Parts count per table (for "too many parts" detection)
SELECT
    database,
    table,
    parts,
    formatReadableSize(bytes_on_disk_sum) AS bytes_on_disk,
    last_part_time
FROM
(
    SELECT
        database,
        table,
        count() AS parts,
        sum(bytes_on_disk) AS bytes_on_disk_sum,
        max(modification_time) AS last_part_time
    FROM system.parts
    WHERE active
    GROUP BY database, table
)
ORDER BY parts DESC
LIMIT 30;
