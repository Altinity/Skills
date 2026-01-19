-- Query 1: Top exceptions by code (last 24h)
SELECT
    exception_code,
    count() AS failures,
    any(substring(exception, 1, 160)) AS example_exception,
    any(substring(query, 1, 160)) AS example_query
FROM clusterAllReplicas('{cluster}', system.query_log)
WHERE event_time > now() - INTERVAL 24 HOUR
  AND type LIKE 'Exception%'
GROUP BY exception_code
ORDER BY failures DESC
LIMIT 20;

-- Query 2: Recent exceptions (last 1h)
SELECT
    event_time,
    user,
    exception_code,
    substring(exception, 1, 200) AS exception,
    substring(query, 1, 160) AS query_preview
FROM clusterAllReplicas('{cluster}', system.query_log)
WHERE event_time > now() - INTERVAL 1 HOUR
  AND type LIKE 'Exception%'
ORDER BY event_time DESC
LIMIT 50;

-- Query 3: Server error log (last 1h)
SELECT
    event_time,
    level,
    logger_name,
    query_id,
    substring(message, 1, 220) AS message
FROM clusterAllReplicas('{cluster}', system.text_log)
WHERE event_time > now() - INTERVAL 1 HOUR
  AND level IN ('Fatal', 'Critical', 'Error')
ORDER BY event_time DESC
LIMIT 50;

-- Query 4: Part-log failure signal (last 24h)
SELECT
    event_type,
    count() AS rows
FROM clusterAllReplicas('{cluster}', system.part_log)
WHERE event_time > now() - INTERVAL 24 HOUR
GROUP BY event_type
ORDER BY rows DESC
LIMIT 50;

-- Query 5: Exception trend by hour (last 24h)
SELECT
    toStartOfHour(event_time) AS hour,
    count() AS total_exceptions,
    countIf(exception_code = 241) AS memory_limit,
    countIf(exception_code = 252) AS timeout,
    countIf(exception_code = 159) AS readonly
FROM clusterAllReplicas('{cluster}', system.query_log)
WHERE event_time > now() - INTERVAL 24 HOUR
  AND type LIKE 'Exception%'
GROUP BY hour
ORDER BY hour DESC
LIMIT 24;
