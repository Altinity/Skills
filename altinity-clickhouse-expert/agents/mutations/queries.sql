-- Query 1: Active/backlogged mutations (best-effort)
SELECT
    database,
    table,
    mutation_id,
    command,
    create_time,
    is_done,
    parts_to_do,
    latest_failed_part,
    latest_fail_time,
    latest_fail_reason
FROM system.mutations
WHERE is_done = 0
ORDER BY create_time ASC
LIMIT 100;

-- Query 2: Recent failed mutations (last 24h; schema varies)
SELECT *
FROM system.mutations
WHERE (latest_fail_time > now() - INTERVAL 24 HOUR)
  AND latest_fail_reason != ''
ORDER BY latest_fail_time DESC
LIMIT 100;
