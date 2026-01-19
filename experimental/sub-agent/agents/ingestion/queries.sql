-- Query 1: Current inserts running
SELECT
    query_id,
    user,
    round(elapsed, 1) AS elapsed_sec,
    written_rows,
    formatReadableSize(written_bytes) AS written_bytes,
    formatReadableSize(memory_usage) AS memory,
    substring(query, 1, 120) AS query_preview
FROM system.processes
WHERE is_cancelled = 0
  AND query_kind = 'Insert'
ORDER BY elapsed DESC
LIMIT 20;

-- Query 2: Insert throughput/latency trend (last 1h)
SELECT
    toStartOfFiveMinutes(event_time) AS ts,
    count() AS inserts,
    round(avg(query_duration_ms)) AS avg_ms,
    round(quantile(0.95)(query_duration_ms)) AS p95_ms,
    sum(written_rows) AS rows,
    formatReadableSize(sum(written_bytes)) AS bytes
FROM clusterAllReplicas('{cluster}', system.query_log)
WHERE event_time > now() - INTERVAL 1 HOUR
  AND type = 'QueryFinish'
  AND query_kind = 'Insert'
GROUP BY ts
ORDER BY ts DESC;

-- Query 3: Part creation rate with severity (last 1h)
SELECT
    database,
    table,
    count() AS new_parts,
    round(new_parts / 3600.0, 3) AS new_parts_per_sec,
    formatReadableSize(quantile(0.5)(size_in_bytes)) AS p50_part_size,
    formatReadableSize(quantile(0.9)(size_in_bytes)) AS p90_part_size,
    multiIf(new_parts_per_sec > 5, 'Critical', new_parts_per_sec > 1, 'Major', new_parts_per_sec > 0.5, 'Moderate', 'OK') AS severity
FROM clusterAllReplicas('{cluster}', system.part_log)
WHERE event_time > now() - INTERVAL 1 HOUR
  AND event_type = 'NewPart'
GROUP BY database, table
HAVING new_parts > 10
ORDER BY
    multiIf(severity = 'Critical', 1, severity = 'Major', 2, severity = 'Moderate', 3, 4),
    new_parts DESC
LIMIT 50;

-- Query 4: Part size distribution for hot tables (last 24h)
SELECT
    database,
    table,
    count() AS new_parts,
    formatReadableSize(quantile(0.5)(size_in_bytes)) AS p50_part_size,
    formatReadableSize(quantile(0.9)(size_in_bytes)) AS p90_part_size
FROM clusterAllReplicas('{cluster}', system.part_log)
WHERE event_time > now() - INTERVAL 24 HOUR
  AND event_type = 'NewPart'
GROUP BY database, table
HAVING new_parts > 50
ORDER BY new_parts DESC
LIMIT 30;

-- Query 5: Part-log event type distribution (last 24h)
SELECT
    event_type,
    count() AS rows
FROM clusterAllReplicas('{cluster}', system.part_log)
WHERE event_time > now() - INTERVAL 24 HOUR
GROUP BY event_type
ORDER BY rows DESC
LIMIT 50;

-- Query 6: query_views_log schema discovery (versions vary)
SELECT
    name,
    type
FROM system.columns
WHERE database = 'system'
  AND table = 'query_views_log'
ORDER BY name
LIMIT 200;

-- Query 7: Is query_views_log populated recently? (MV attribution signal)
SELECT
    max(event_time) AS last_event_time,
    countIf(event_time > now() - INTERVAL 1 HOUR) AS rows_last_1h
FROM clusterAllReplicas('{cluster}', system.query_views_log);
