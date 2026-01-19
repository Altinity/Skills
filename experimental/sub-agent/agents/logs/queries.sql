-- Query 1: System log tables disk usage (top by bytes)
SELECT
    database,
    table,
    formatReadableSize(bytes_on_disk_sum) AS bytes_on_disk,
    parts
FROM
(
    SELECT
        database,
        table,
        sum(bytes_on_disk) AS bytes_on_disk_sum,
        count() AS parts
    FROM system.parts
    WHERE active
      AND database = 'system'
      AND table LIKE '%_log%'
    GROUP BY database, table
)
ORDER BY bytes_on_disk_sum DESC
LIMIT 50;

-- Query 2: Oldest/newest parts for system log tables (retention hints)
SELECT
    table,
    min(modification_time) AS oldest_part,
    max(modification_time) AS newest_part
FROM system.parts
WHERE active
  AND database = 'system'
  AND table LIKE '%_log%'
GROUP BY table
ORDER BY oldest_part ASC
LIMIT 50;

-- Query 3: System log tables with many parts (churn)
SELECT
    table,
    parts,
    round(avg_part_bytes) AS avg_part_bytes
FROM
(
    SELECT
        table,
        count() AS parts,
        avg(bytes_on_disk) AS avg_part_bytes
    FROM system.parts
    WHERE active
      AND database = 'system'
      AND table LIKE '%_log%'
    GROUP BY table
)
ORDER BY parts DESC
LIMIT 50;
