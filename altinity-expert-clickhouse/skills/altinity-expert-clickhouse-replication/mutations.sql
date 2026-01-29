/* 1) Stuck/failing mutations (cluster-wide, per host) */
SELECT
  database,
  table,
  mutation_id,
  create_time,
  is_done,
  parts_to_do,
  latest_failed_part,
  latest_fail_time,
  substring(latest_fail_reason, 1, 240) AS latest_fail_reason_240,
  command
FROM system.mutations
WHERE is_done = 0
ORDER BY latest_fail_time DESC, create_time DESC
LIMIT 200;
