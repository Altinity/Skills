/* NO_REPLICA_HAS_PART workflow (3rd stage)
Goal: distinguish benign churn (_0.._3) from suspicious merge-level failures (>=_4).

Usage:
- Replace `{cluster}` with your ClickHouse cluster name (DataGrip).
- Default timeframe: last 24 hours (adjust `since` if needed).
*/

/* 1) Detector: ignore benign part levels _0.._3, flag >=_4 (from replication_queue)
Interpretation:
- part_level >= 4 non-trivial and growing => suspicious (merge churn, cleanup race, disk pressure, fetch lag).
*/
WITH
  (now() - INTERVAL 24 HOUR) AS since,
  if(new_part_name != '',
     new_part_name,
     replaceRegexpAll(extract(last_exception, 'has part ([^ ]+)'), '[^0-9A-Za-z_]+$', '')
  ) AS part_name,
  toUInt32OrNull(arrayElement(splitByChar('_', part_name), -1)) AS part_level
SELECT
  database,
  table,
  part_level,
  count() AS cnt,
  countDistinct(part_name) AS distinct_parts,
  max(last_exception_time) AS max_last_exception_time,
  anyHeavy(substring(last_exception, 1, 240)) AS sample_last_exception_240
FROM system.replication_queue
WHERE last_exception LIKE '%NO_REPLICA_HAS_PART%'
  AND last_exception_time >= since
  AND part_name != ''
  AND part_level >= 4
GROUP BY database, table, part_level
ORDER BY cnt DESC, max_last_exception_time DESC
LIMIT 200;

/* 2) Drill-down: verify via text_log when available
If system.text_log doesn't exist, skip and rely on replication_queue exceptions above.
*/
WITH
  (now() - INTERVAL 24 HOUR) AS since
SELECT
  hostName() AS host,
  event_time,
  level,
  logger_name,
  substring(message, 1, 260) AS message_260
FROM clusterAllReplicas('{cluster}', system.text_log)
WHERE event_time >= since
  AND message ILIKE '%No active replica has part%'
ORDER BY event_time DESC
LIMIT 200;
