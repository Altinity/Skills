-- Query 1: Disk free space
SELECT
    name,
    path,
    formatReadableSize(total_space) AS total,
    formatReadableSize(free_space) AS free,
    round(100.0 * free_space / nullIf(total_space, 0), 1) AS free_pct
FROM system.disks
ORDER BY free_space ASC;

-- Query 2: Biggest tables by bytes on disk
SELECT
    database,
    table,
    formatReadableSize(bytes_on_disk_sum) AS bytes_on_disk,
    parts,
    formatReadableSize(avg_part_size) AS avg_part_size
FROM
(
    SELECT
        database,
        table,
        sum(bytes_on_disk) AS bytes_on_disk_sum,
        count() AS parts,
        avg(bytes_on_disk) AS avg_part_size
    FROM system.parts
    WHERE active
    GROUP BY database, table
)
ORDER BY bytes_on_disk_sum DESC
LIMIT 30;

-- Query 3: Tiny parts hotlist (IO amplification risk)
SELECT
    database,
    table,
    tiny_parts,
    total_parts,
    round(100.0 * tiny_parts / nullIf(total_parts, 0), 1) AS tiny_pct
FROM
(
    SELECT
        database,
        table,
        countIf(bytes_on_disk < 16 * 1024 * 1024) AS tiny_parts,
        count() AS total_parts
    FROM system.parts
    WHERE active
    GROUP BY database, table
)
WHERE total_parts >= 50
ORDER BY tiny_pct DESC, total_parts DESC
LIMIT 30;

-- Query 4: System log tables disk usage
SELECT
    database,
    table,
    formatReadableSize(bytes_on_disk_sum) AS bytes_on_disk,
    parts,
    oldest_part,
    newest_part
FROM
(
    SELECT
        database,
        table,
        sum(bytes_on_disk) AS bytes_on_disk_sum,
        count() AS parts,
        min(modification_time) AS oldest_part,
        max(modification_time) AS newest_part
    FROM system.parts
    WHERE active
      AND database = 'system'
      AND table LIKE '%_log%'
    GROUP BY database, table
)
ORDER BY bytes_on_disk_sum DESC
LIMIT 20;
