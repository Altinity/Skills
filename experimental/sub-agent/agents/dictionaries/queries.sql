-- Query 1: Dictionary inventory (schema varies by version; keep bounded)
SELECT *
FROM system.dictionaries
LIMIT 200;

-- Query 2: Total allocated bytes (if column exists; otherwise may error and still be visible to the model)
SELECT
    sum(bytes_allocated) AS dictionaries_bytes_allocated
FROM system.dictionaries;

-- Query 3: Recent dictionary-related errors (last 1h)
SELECT
    event_time,
    level,
    logger_name,
    query_id,
    substring(message, 1, 240) AS message
FROM clusterAllReplicas('{cluster}', system.text_log)
WHERE event_time > now() - INTERVAL 1 HOUR
  AND (logger_name ILIKE '%dict%' OR message ILIKE '%dict%')
  AND level IN ('Fatal', 'Critical', 'Error')
ORDER BY event_time DESC
LIMIT 50;
