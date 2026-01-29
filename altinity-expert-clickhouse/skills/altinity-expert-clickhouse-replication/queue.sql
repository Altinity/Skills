/* Replication queue diagnostics (run after triage)
Usage:
- Replace `{cluster}` with your ClickHouse cluster name (DataGrip).
- Run statements one-by-one.
*/

/* 1) Queue size by table (per host)
Interpretation:
- Large queues + old tasks + retries/backoff usually means replication is stuck.
*/
WITH
  count() AS count_all,
  countIf(last_exception != '') AS count_err,
  countIf(num_postponed > 0) AS count_postponed,
  countIf(is_currently_executing) AS count_executing
SELECT
  database,
  table,
  count_all AS queue_size,
  count_err AS with_errors,
  count_postponed AS postponed,
  count_executing AS executing,
  multiIf(count_all > 500, 'Critical', count_all > 400, 'Major', count_all > 200, 'Moderate', 'OK') AS severity
FROM system.replication_queue
GROUP BY host, database, table
HAVING count_all > 50
ORDER BY severity ASC, queue_size DESC
LIMIT 200;

/* 2) Oldest tasks in queue (per host)
Interpretation:
- oldest_task_age_sec >> 0 means the queue has been non-empty for a long time.
*/
WITH
  dateDiff('second', min(create_time), now()) AS oldest_task_age_sec
SELECT
  database,
  table,
  oldest_task_age_sec,
  formatReadableTimeDelta(oldest_task_age_sec) AS oldest_task_age,
  multiIf(oldest_task_age_sec > 86400, 'Critical', oldest_task_age_sec > 7200, 'Major', oldest_task_age_sec > 1800, 'Moderate', 'OK') AS severity,
  count() AS tasks_in_queue
FROM  system.replication_queue
GROUP BY host, database, table
HAVING oldest_task_age_sec > 300
ORDER BY severity ASC, oldest_task_age_sec DESC
LIMIT 200;

/* 3) Stalled tasks detection (per host)
Stalled ~ no attempts and no postpones recently (last 10 minutes).
*/
WITH
  greatest(create_time, last_attempt_time, last_postpone_time) < now() - 600 AS no_activity
SELECT
  hostName() AS host,
  database,
  table,
  countIf(no_activity) AS stalled_tasks,
  count() AS total_tasks,
  round(100.0 * countIf(no_activity) / count(), 1) AS stalled_pct
FROM system.replication_queue
GROUP BY host, database, table
HAVING stalled_tasks > 0
ORDER BY stalled_tasks DESC
LIMIT 200;

/* 4) Queue tasks with errors/backoff (per host)
Use this to identify a table/type to drill down further.
*/
SELECT
  database,
  table,
  type,
  create_time,
  last_attempt_time,
  last_exception_time,
  num_tries,
  num_postponed,
  substring(postpone_reason, 1, 180) AS postpone_reason_180,
  substring(last_exception, 1, 240) AS last_exception_240,
  new_part_name,
  parts_to_merge,
  source_replica
FROM system.replication_queue
WHERE last_exception != '' OR postpone_reason != ''
ORDER BY last_exception_time DESC, num_tries DESC
LIMIT 200;
