-- Query 1: Replica health status
SELECT
    database,
    table,
    replica_name,
    is_readonly,
    is_session_expired,
    future_parts,
    parts_to_check,
    queue_size,
    inserts_in_queue,
    merges_in_queue,
    log_max_index - log_pointer AS log_gap
FROM system.replicas
ORDER BY is_readonly DESC, is_session_expired DESC, queue_size DESC
LIMIT 50;

-- Query 2: Stuck/old replication queue items
SELECT
    database,
    table,
    type,
    create_time,
    required_quorum,
    source_replica,
    new_part_name,
    last_exception
FROM system.replication_queue
WHERE last_exception != ''
   OR now() - create_time > INTERVAL 10 MINUTE
ORDER BY create_time
LIMIT 50;

-- Query 3: Replication queue summary by type
SELECT
    type,
    count() AS queue_items,
    min(create_time) AS oldest_item,
    countIf(last_exception != '') AS with_errors
FROM system.replication_queue
GROUP BY type
ORDER BY queue_items DESC;

-- Query 4: Recent Keeper/ZooKeeper errors (last 1h)
SELECT
    toStartOfMinute(event_time) AS minute,
    count() AS errors,
    any(substring(message, 1, 200)) AS sample_message
FROM clusterAllReplicas('{cluster}', system.text_log)
WHERE event_time > now() - INTERVAL 1 HOUR
  AND level IN ('Error', 'Fatal')
  AND (logger_name LIKE '%Keeper%' OR logger_name LIKE '%ZooKeeper%' OR message LIKE '%Keeper%' OR message LIKE '%ZooKeeper%')
GROUP BY minute
ORDER BY minute DESC
LIMIT 20;
