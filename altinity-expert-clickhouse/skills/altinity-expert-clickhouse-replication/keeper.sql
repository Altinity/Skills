/* Keeper/ZooKeeper diagnostics (supporting)
Usage:
- Replace `{cluster}` with your ClickHouse cluster name (DataGrip).
*/

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

/* 2) Recent Keeper/ZooKeeper errors (optional; requires system.text_log) */
SELECT
  hostName() AS host,
  event_time,
  level,
  logger_name,
  substring(message, 1, 260) AS message_260
FROM clusterAllReplicas('{cluster}', system.text_log)
WHERE (logger_name ILIKE '%ZooKeeper%' OR logger_name ILIKE '%Keeper%')
  AND level IN ('Error', 'Warning')
  AND event_time > now() - INTERVAL 1 HOUR
ORDER BY event_time DESC
LIMIT 200;

/* 3) Async replication metrics (per host) */
SELECT
  hostName() AS host,
  metric,
  value
FROM clusterAllReplicas('{cluster}', system.asynchronous_metrics)
WHERE metric IN (
  'ReplicasMaxQueueSize',
  'ReplicasSumQueueSize',
  'ReplicasMaxInsertsInQueue',
  'ReplicasSumInsertsInQueue',
  'ReplicasMaxMergesInQueue',
  'ReplicasSumMergesInQueue',
  'ReplicasMaxAbsoluteDelay',
  'ReplicasMaxRelativeDelay'
)
ORDER BY host, metric;

