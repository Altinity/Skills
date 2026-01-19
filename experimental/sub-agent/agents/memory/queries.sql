-- Query 1: Memory headroom
SELECT
    hostName() AS host,
    (SELECT value FROM system.asynchronous_metrics WHERE metric = 'OSMemoryTotal') AS os_mem_total,
    (SELECT value FROM system.asynchronous_metrics WHERE metric = 'MemoryResident') AS mem_resident,
    round(100.0 * mem_resident / nullIf(os_mem_total, 0), 1) AS resident_pct;

-- Query 2: Top memory queries (current)
SELECT
    query_id,
    user,
    round(elapsed, 1) AS elapsed_sec,
    formatReadableSize(memory_usage) AS memory,
    formatReadableSize(read_bytes) AS read_bytes,
    read_rows,
    substring(query, 1, 140) AS query_preview
FROM system.processes
WHERE is_cancelled = 0
ORDER BY memory_usage DESC
LIMIT 10;

-- Query 3: Top memory queries (last 24h)
SELECT
    normalized_query_hash,
    count() AS executions,
    formatReadableSize(max(memory_usage)) AS max_memory,
    round(quantile(0.95)(memory_usage)) AS p95_memory_bytes,
    any(substring(query, 1, 140)) AS query_sample
FROM clusterAllReplicas('{cluster}', system.query_log)
WHERE event_time > now() - INTERVAL 24 HOUR
  AND type IN ('QueryFinish', 'ExceptionWhileProcessing')
GROUP BY normalized_query_hash
ORDER BY max(memory_usage) DESC
LIMIT 20;

-- Query 4: Memory from dictionaries and memory engines
SELECT
    formatReadableSize((SELECT sum(bytes_allocated) FROM system.dictionaries)) AS dictionaries_bytes,
    formatReadableSize((SELECT sum(total_bytes) FROM system.tables WHERE engine IN ('Memory', 'Set', 'Join'))) AS memory_engines_bytes;
