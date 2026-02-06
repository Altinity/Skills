/* 1) Keeper/ZooKeeper average latency (per host)
Interpretation:
- Rising avg_latency_us often correlates with replication lag/readonly.
*/
WITH
  sumIf(value, event = 'ZooKeeperWaitMicroseconds') AS total_us,
  sumIf(value, event = 'ZooKeeperTransactions') AS transactions
SELECT
  hostName() AS host,
  total_us,
  transactions,
  round(total_us / nullIf(transactions, 0)) AS avg_latency_us
FROM clusterAllReplicas('{cluster}', system.events)
WHERE event IN ('ZooKeeperWaitMicroseconds', 'ZooKeeperTransactions')
GROUP BY host
ORDER BY avg_latency_us DESC
SETTINGS system_events_show_zero_values = 1;

-- in-depth analysis. Run only when needed. tune the interval to questionable
-- Recent Keeper/ZooKeeper errors
SELECT
  hostName() AS host,
  event_time,
  level,
  logger_name,
  substring(message, 1, 260) AS message_260
FROM clusterAllReplicas('{cluster}', system.text_log)
WHERE (logger_name ILIKE '%ZooKeeper%' OR logger_name ILIKE '%Keeper%')
  AND level IN ('Error', 'Warning')
  AND event_time between ... and ...
ORDER BY event_time DESC
LIMIT 200;

