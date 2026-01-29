-- =============================================================================
-- INDEX EFFECTIVENESS ANALYSIS CHECKS
-- =============================================================================
-- Run these queries to assess whether indexes match actual query patterns
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. TABLES WITH SKIPPING INDEXES
-- -----------------------------------------------------------------------------
-- Lists all data skipping indexes across all tables
SELECT
    database,
    table,
    name AS index_name,
    type AS index_type,
    expr AS indexed_expression,
    granularity,
    formatReadableSize(data_compressed_bytes) AS index_size,
    formatReadableSize(data_uncompressed_bytes) AS index_uncompressed
FROM system.data_skipping_indices
ORDER BY database, table, name;

-- -----------------------------------------------------------------------------
-- 2. TABLES WITH PROJECTIONS
-- -----------------------------------------------------------------------------
-- Lists all projections and their ORDER BY keys
SELECT
    database,
    table,
    name AS projection_name,
    sorting_key,
    type
FROM system.projections
ORDER BY database, table, name;

-- -----------------------------------------------------------------------------
-- 3. TOP TABLES BY QUERY FREQUENCY (LAST 24H)
-- -----------------------------------------------------------------------------
-- Identifies most queried tables to prioritize index analysis
SELECT
    arrayJoin(tables) AS table_name,
    count() AS query_count,
    round(avg(query_duration_ms)) AS avg_duration_ms,
    round(avg(read_rows)) AS avg_rows_read,
    formatReadableSize(avg(read_bytes)) AS avg_bytes_read,
    round(avg(selected_marks)) AS avg_marks_selected
FROM system.query_log
WHERE event_time >= now() - INTERVAL 1 DAY
  AND query ILIKE 'SELECT%'
  AND type = 'QueryFinish'
GROUP BY table_name
ORDER BY query_count DESC
LIMIT 20;

-- -----------------------------------------------------------------------------
-- 4. QUERIES WITH POOR GRANULE SELECTIVITY (LAST 24H)
-- -----------------------------------------------------------------------------
-- Finds queries that read many granules relative to result size
-- High selected_marks with low result rows = index not effective
SELECT
    normalized_query_hash,
    any(query) AS sample_query,
    count() AS executions,
    round(avg(selected_marks)) AS avg_marks,
    round(avg(selected_parts)) AS avg_parts,
    round(avg(read_rows)) AS avg_rows_read,
    round(avg(result_rows)) AS avg_result_rows,
    round(avg(read_rows) / nullIf(avg(result_rows), 0), 1) AS read_amplification,
    round(avg(query_duration_ms)) AS avg_duration_ms
FROM system.query_log
WHERE event_time >= now() - INTERVAL 1 DAY
  AND query ILIKE 'SELECT%'
  AND type = 'QueryFinish'
  AND result_rows > 0
GROUP BY normalized_query_hash
HAVING avg_marks > 1000 AND read_amplification > 100
ORDER BY avg_marks DESC
LIMIT 20;

-- -----------------------------------------------------------------------------
-- 5. FREQUENTLY FILTERED COLUMNS (LAST 24H)
-- -----------------------------------------------------------------------------
-- Extracts columns used in WHERE clauses to compare against ORDER BY keys
WITH
    arrayJoin(extractAll(query, '\\b(?:PRE)?WHERE\\s+(.*?)\\s+(?:GROUP BY|ORDER BY|UNION|SETTINGS|FORMAT|$)')) AS w,
    arrayFilter(x -> (position(lower(w), lower(extract(x, '\\.(`[^`]+`|[^\\.]+)$'))) > 0), columns) AS c,
    arrayJoin(c) AS filtered_column
SELECT
    filtered_column,
    count() AS filter_count
FROM system.query_log
WHERE event_time >= now() - INTERVAL 1 DAY
  AND query ILIKE 'SELECT%'
  AND type = 'QueryFinish'
  AND length(columns) > 0
GROUP BY filtered_column
ORDER BY filter_count DESC
LIMIT 30;

-- -----------------------------------------------------------------------------
-- 6. PRIMARY KEY COLUMN ANALYSIS
-- -----------------------------------------------------------------------------
-- Shows ORDER BY keys and their effectiveness indicators
SELECT
    database,
    table,
    sorting_key,
    primary_key,
    partition_key,
    sampling_key,
    formatReadableSize(sum(primary_key_bytes_in_memory)) AS pk_memory,
    sum(rows) AS total_rows,
    count() AS parts,
    round(sum(rows) / nullIf(count(), 0) / 8192, 1) AS avg_granules_per_part
FROM system.parts
WHERE active
GROUP BY database, table, sorting_key, primary_key, partition_key, sampling_key
ORDER BY total_rows DESC
LIMIT 20;

-- -----------------------------------------------------------------------------
-- 7. SKIP INDEX EFFECTIVENESS ESTIMATE
-- -----------------------------------------------------------------------------
-- Compares index size to column size - oversized indexes may not be helpful
SELECT
    dsi.database,
    dsi.table,
    dsi.name AS index_name,
    dsi.type AS index_type,
    dsi.expr,
    formatReadableSize(dsi.data_compressed_bytes) AS index_size,
    c.name AS column_name,
    formatReadableSize(c.data_compressed_bytes) AS column_size,
    round(dsi.data_compressed_bytes / nullIf(c.data_compressed_bytes, 0) * 100, 1) AS index_to_column_pct
FROM system.data_skipping_indices AS dsi
LEFT JOIN system.columns AS c 
    ON dsi.database = c.database 
    AND dsi.table = c.table 
    AND dsi.expr = c.name
WHERE dsi.data_compressed_bytes > 0
ORDER BY dsi.data_compressed_bytes DESC
LIMIT 20;

-- -----------------------------------------------------------------------------
-- 8. QUERIES THAT BYPASS PRIMARY KEY (LAST 24H)
-- -----------------------------------------------------------------------------
-- Finds queries that don't use primary key filtering effectively
SELECT
    normalized_query_hash,
    any(query) AS sample_query,
    count() AS executions,
    arrayJoin(tables) AS table_name,
    round(avg(selected_parts)) AS avg_parts,
    round(avg(selected_marks)) AS avg_marks,
    round(avg(read_rows)) AS avg_read_rows,
    formatReadableSize(avg(read_bytes)) AS avg_read_bytes
FROM system.query_log
WHERE event_time >= now() - INTERVAL 1 DAY
  AND query ILIKE 'SELECT%'
  AND type = 'QueryFinish'
  AND ProfileEvents['SelectedMarksTotal'] > 10000
GROUP BY normalized_query_hash, table_name
ORDER BY avg_marks DESC
LIMIT 20;

-- -----------------------------------------------------------------------------
-- 9. PARTITION PRUNING EFFECTIVENESS
-- -----------------------------------------------------------------------------
-- Shows how well queries prune partitions
SELECT
    arrayJoin(tables) AS table_name,
    count() AS query_count,
    round(avg(selected_parts)) AS avg_selected_parts,
    (
        SELECT count()
        FROM system.parts
        WHERE active 
          AND concat(database, '.', table) = table_name
    ) AS total_active_parts,
    round(avg(selected_parts) / nullIf(total_active_parts, 0) * 100, 1) AS pct_parts_scanned
FROM system.query_log
WHERE event_time >= now() - INTERVAL 1 DAY
  AND query ILIKE 'SELECT%'
  AND type = 'QueryFinish'
GROUP BY table_name
HAVING total_active_parts > 10
ORDER BY pct_parts_scanned DESC
LIMIT 20;

-- -----------------------------------------------------------------------------
-- 10. WHERE CONDITION PATTERNS BY TABLE (LAST 3 DAYS)
-- -----------------------------------------------------------------------------
-- Shows normalized WHERE patterns to understand common filter combinations
WITH
    arrayJoin(extractAll(normalizeQuery(query), '\\b(?:PRE)?WHERE\\s+(.*?)\\s+(?:GROUP BY|ORDER BY|UNION|SETTINGS|FORMAT|$)')) AS where_pattern
SELECT
    arrayJoin(tables) AS table_name,
    where_pattern,
    count() AS frequency
FROM system.query_log
WHERE event_time >= now() - INTERVAL 3 DAY
  AND query ILIKE 'SELECT%'
  AND type = 'QueryFinish'
GROUP BY table_name, where_pattern
ORDER BY table_name, frequency DESC
LIMIT 50;
