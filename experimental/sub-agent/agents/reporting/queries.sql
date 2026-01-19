-- Query 1: Slow queries running right now
SELECT
    query_id,
    user,
    round(elapsed, 1) AS elapsed_sec,
    formatReadableSize(read_bytes) AS read_bytes,
    formatReadableSize(memory_usage) AS memory,
    read_rows,
    substring(query, 1, 120) AS query_preview
FROM system.processes
WHERE is_cancelled = 0
ORDER BY elapsed DESC
LIMIT 20;

-- Query 2: Latency trend (last 1h, 5-minute buckets)
SELECT
    toStartOfFiveMinutes(event_time) AS ts,
    count() AS queries,
    countIf(type LIKE 'Exception%') AS failed,
    round(avg(query_duration_ms)) AS avg_ms,
    round(quantile(0.95)(query_duration_ms)) AS p95_ms,
    round(max(query_duration_ms)) AS max_ms,
    formatReadableSize(sum(read_bytes)) AS read_bytes,
    formatReadableSize(sum(memory_usage)) AS memory
FROM clusterAllReplicas('{cluster}', system.query_log)
WHERE event_time > now() - INTERVAL 1 HOUR
  AND type IN ('QueryFinish', 'ExceptionWhileProcessing')
GROUP BY ts
ORDER BY ts DESC;

-- Query 3: Top query patterns by read volume (last 24h)
SELECT
    normalized_query_hash,
    count() AS executions,
    round(avg(query_duration_ms)) AS avg_ms,
    round(quantile(0.95)(query_duration_ms)) AS p95_ms,
    formatReadableSize(sum(read_bytes)) AS total_read,
    formatReadableSize(sum(memory_usage)) AS total_memory,
    any(substring(query, 1, 140)) AS query_sample
FROM clusterAllReplicas('{cluster}', system.query_log)
WHERE event_time > now() - INTERVAL 24 HOUR
  AND type = 'QueryFinish'
  AND query_kind = 'Select'
GROUP BY normalized_query_hash
HAVING executions > 5
ORDER BY sum(read_bytes) DESC
LIMIT 30;

-- Query 4: Top failing queries (last 24h)
SELECT
    exception_code,
    count() AS failures,
    any(substring(exception, 1, 140)) AS example_exception,
    any(substring(query, 1, 140)) AS example_query
FROM clusterAllReplicas('{cluster}', system.query_log)
WHERE event_time > now() - INTERVAL 24 HOUR
  AND type LIKE 'Exception%'
GROUP BY exception_code
ORDER BY failures DESC
LIMIT 20;
