-- Query 1: Identify node + basic headroom
SELECT
    hostName() AS host,
    version() AS version,
    uptime() AS uptime_sec,
    formatReadableTimeDelta(uptime()) AS uptime,
    (SELECT value FROM system.asynchronous_metrics WHERE metric = 'OSMemoryTotal') AS os_mem_total,
    (SELECT value FROM system.asynchronous_metrics WHERE metric = 'MemoryResident') AS mem_resident,
    round(100.0 * mem_resident / nullIf(os_mem_total, 0), 1) AS resident_pct;

-- Query 2: Current activity summary
SELECT
    count() AS active_queries,
    formatReadableSize(sum(memory_usage)) AS total_query_memory,
    formatReadableSize(sum(read_bytes)) AS total_read_bytes,
    formatReadableSize(sum(written_bytes)) AS total_written_bytes
FROM system.processes
WHERE is_cancelled = 0;

-- Query 3: Top tables by parts count
SELECT
    database,
    table,
    parts,
    formatReadableSize(bytes_on_disk_sum) AS bytes_on_disk,
    last_part_time
FROM
(
    SELECT
        database,
        table,
        count() AS parts,
        sum(bytes_on_disk) AS bytes_on_disk_sum,
        max(modification_time) AS last_part_time
    FROM system.parts
    WHERE active
    GROUP BY database, table
)
ORDER BY parts DESC
LIMIT 20;

-- Query 4: Errors trend (last 24h)
SELECT
    toStartOfHour(event_time) AS hour,
    countIf(type > 2) AS exceptions,
    countIf(type = 'QueryFinish') AS finished
FROM clusterAllReplicas('{cluster}', system.query_log)
WHERE event_time > now() - INTERVAL 24 HOUR
GROUP BY hour
ORDER BY hour DESC
LIMIT 24;

-- Query 5: Disk space summary
SELECT
    name,
    formatReadableSize(total_space) AS total,
    formatReadableSize(free_space) AS free,
    round(100.0 * free_space / nullIf(total_space, 0), 1) AS free_pct
FROM system.disks
ORDER BY free_space ASC;

-- Query 6: Cluster mode detection
SELECT * FROM system.zookeeper_connection;

-- Query 7: Key metrics snapshot
SELECT
    (SELECT value FROM system.metrics WHERE metric = 'Query') AS running_queries,
    (SELECT value FROM system.metrics WHERE metric = 'Merge') AS running_merges,
    (SELECT value FROM system.metrics WHERE metric = 'ReplicatedSend') AS replication_sends,
    (SELECT value FROM system.metrics WHERE metric = 'ReplicatedFetch') AS replication_fetches,
    (SELECT value FROM system.asynchronous_metrics WHERE metric = 'MaxPartCountForPartition') AS max_parts_partition;
