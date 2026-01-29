/* Replication health heuristics (optional)
Usage:
- Replace `{cluster}` with your ClickHouse cluster name (DataGrip).
*/

/* Quick heuristic; always validate with replication_queue / mutations. */
WITH
  sum(is_readonly) AS readonly_replicas,
  sum(is_session_expired) AS expired_sessions,
  sum(queue_size) AS total_queue,
  max(absolute_delay) AS max_delay_sec,
  countIf(absolute_delay > 300) AS lagging_replicas
SELECT
  hostName() AS host,
  readonly_replicas,
  expired_sessions,
  total_queue,
  max_delay_sec,
  lagging_replicas,
  multiIf(
    readonly_replicas > 0 OR expired_sessions > 0, 'Critical',
    max_delay_sec > 3600 OR total_queue > 1000, 'Major',
    max_delay_sec > 300 OR total_queue > 200, 'Moderate',
    'OK'
  ) AS overall_health
FROM clusterAllReplicas('{cluster}', system.replicas)
GROUP BY host
ORDER BY overall_health ASC, max_delay_sec DESC;

