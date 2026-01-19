-- Query 1: Log counts by level (last 1h)
SELECT
    level,
    count() AS rows
FROM clusterAllReplicas('{cluster}', system.text_log)
WHERE event_time > now() - INTERVAL 1 HOUR
  AND level IN ('Fatal', 'Critical', 'Error', 'Warning')
GROUP BY level
ORDER BY rows DESC;

-- Query 2: Top noisy loggers (errors, last 1h)
SELECT
    logger_name,
    count() AS rows,
    any(substring(message, 1, 220)) AS sample_message
FROM clusterAllReplicas('{cluster}', system.text_log)
WHERE event_time > now() - INTERVAL 1 HOUR
  AND level IN ('Fatal', 'Critical', 'Error')
GROUP BY logger_name
ORDER BY rows DESC
LIMIT 50;

-- Query 3: Recent server errors (last 1h)
SELECT
    event_time,
    level,
    logger_name,
    query_id,
    substring(message, 1, 240) AS message
FROM clusterAllReplicas('{cluster}', system.text_log)
WHERE event_time > now() - INTERVAL 1 HOUR
  AND level IN ('Fatal', 'Critical', 'Error')
ORDER BY event_time DESC
LIMIT 100;
