-- Query 1: Spot tables with structural risk (parts + tiny parts)
SELECT
    database,
    table,
    parts,
    tiny_parts,
    round(100.0 * tiny_parts / nullIf(parts, 0), 1) AS tiny_pct,
    formatReadableSize(bytes_on_disk_sum) AS bytes_on_disk
FROM
(
    SELECT
        database,
        table,
        count() AS parts,
        countIf(bytes_on_disk < 16 * 1024 * 1024) AS tiny_parts,
        sum(bytes_on_disk) AS bytes_on_disk_sum
    FROM system.parts
    WHERE active
    GROUP BY database, table
)
WHERE parts >= 50
ORDER BY parts DESC
LIMIT 30;

-- Query 2: Wrong partitioning heuristic: too many tiny partitions
SELECT
    database,
    table,
    partitions,
    tiny_partitions,
    round(100.0 * tiny_partitions / nullIf(partitions, 0), 1) AS tiny_partitions_pct,
    p50_partition_bytes,
    p90_partition_bytes
FROM
(
    SELECT
        database,
        table,
        countDistinct(partition_id) AS partitions,
        countIf(partition_bytes < 16 * 1024 * 1024) AS tiny_partitions,
        formatReadableSize(quantile(0.5)(partition_bytes)) AS p50_partition_bytes,
        formatReadableSize(quantile(0.9)(partition_bytes)) AS p90_partition_bytes
    FROM
    (
        SELECT
            database,
            table,
            partition_id,
            sum(toUInt64(bytes_on_disk)) AS partition_bytes
        FROM system.parts
        WHERE active
        GROUP BY database, table, partition_id
    )
    GROUP BY database, table
)
WHERE partitions >= 20
ORDER BY tiny_partitions_pct DESC, partitions DESC
LIMIT 30;

-- Query 3: Partition size summary with engine-aware thresholds (heuristic)
WITH
    200 * 1024 * 1024 * 1024 AS max_bytes_mergetree,
    50 * 1024 * 1024 * 1024 AS max_bytes_heavy,
    max_bytes_mergetree / 50 AS min_bytes_mergetree,
    max_bytes_heavy / 50 AS min_bytes_heavy
SELECT
    t.database,
    t.name AS table,
    t.engine,
    countDistinct(p.partition_id) AS partitions,
    formatReadableSize(quantile(0.5)(p.partition_bytes)) AS p50_partition_bytes,
    formatReadableSize(quantile(0.9)(p.partition_bytes)) AS p90_partition_bytes,
    formatReadableSize(max(p.partition_bytes)) AS max_partition_bytes,
    countIf(p.partition_bytes < multiIf(t.engine LIKE '%ReplacingMergeTree%', min_bytes_heavy,
                                       t.engine LIKE '%AggregatingMergeTree%', min_bytes_heavy,
                                       t.engine LIKE '%CollapsingMergeTree%', min_bytes_heavy,
                                       t.engine LIKE '%VersionedCollapsingMergeTree%', min_bytes_heavy,
                                       t.engine LIKE '%SummingMergeTree%', min_bytes_heavy,
                                       min_bytes_mergetree)) AS too_small_partitions,
    countIf(p.partition_bytes > multiIf(t.engine LIKE '%ReplacingMergeTree%', max_bytes_heavy,
                                       t.engine LIKE '%AggregatingMergeTree%', max_bytes_heavy,
                                       t.engine LIKE '%CollapsingMergeTree%', max_bytes_heavy,
                                       t.engine LIKE '%VersionedCollapsingMergeTree%', max_bytes_heavy,
                                       t.engine LIKE '%SummingMergeTree%', max_bytes_heavy,
                                       max_bytes_mergetree)) AS too_big_partitions
FROM
(
    SELECT
        database,
        table,
        partition_id,
        sum(toUInt64(bytes_on_disk)) AS partition_bytes
    FROM system.parts
    WHERE active
    GROUP BY database, table, partition_id
) AS p
INNER JOIN system.tables AS t
    ON t.database = p.database AND t.name = p.table
WHERE t.engine LIKE '%MergeTree%'
GROUP BY t.database, t.name, t.engine
HAVING partitions >= 20
ORDER BY too_big_partitions DESC, too_small_partitions DESC, partitions DESC
LIMIT 50;

-- Query 4: Nullable-heavy tables (heuristic)
SELECT
    database,
    table,
    columns,
    nullable_columns,
    round(100.0 * nullable_columns / nullIf(columns, 0), 1) AS nullable_pct
FROM
(
    SELECT
        database,
        table,
        count() AS columns,
        countIf(type LIKE 'Nullable%') AS nullable_columns
    FROM system.columns
    GROUP BY database, table
)
WHERE columns >= 10
ORDER BY nullable_pct DESC, columns DESC
LIMIT 30;

-- Query 5: Materialized views overview (heuristic risk)
SELECT
    database,
    name AS view,
    engine,
    positionCaseInsensitive(create_table_query, ' to ') > 0 AS has_to_clause,
    positionCaseInsensitive(create_table_query, ' join ') > 0 AS mentions_join
FROM system.tables
WHERE engine = 'MaterializedView'
ORDER BY database, view
LIMIT 200;
