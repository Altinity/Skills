-- Scenario 4: Memory-Heavy Queries
-- Goal: Execute queries that consume significant memory (captured in query_log)
-- Expected Finding: High memory queries in historical analysis
-- Expected Severity: Moderate (memory-heavy queries identified)

-- Ensure query logging is enabled
SET log_queries = 1;

-- ============================================================
-- First, populate the query test table
-- ============================================================
INSERT INTO query_test_table
SELECT
    number AS id,
    arrayElement(['electronics', 'clothing', 'food', 'books', 'sports'], (number % 5) + 1) AS category,
    concat('sub_', toString(number % 1000)) AS subcategory,
    number % 100000 AS user_id,
    (rand() % 10000) / 100.0 AS amount,
    now() - toIntervalSecond(number % 604800) AS event_time,  -- Last 7 days
    arrayMap(x -> concat('tag_', toString(x)), range(number % 10)) AS tags,
    map('key1', toString(number % 100), 'key2', toString(number % 500)) AS properties
FROM numbers(500000);

-- ============================================================
-- Run memory-heavy queries that will be captured in query_log
-- ============================================================

-- Query 1: High cardinality GROUP BY (many distinct values)
-- This allocates memory for hash table in aggregation
SELECT
    subcategory,
    user_id,
    count() AS cnt,
    sum(amount) AS total,
    avg(amount) AS avg_amount
FROM query_test_table
GROUP BY subcategory, user_id
HAVING cnt > 1
FORMAT Null;

-- Query 2: Large JOIN operation
-- JOINs can consume significant memory for hash tables
SELECT
    t1.id,
    t1.category,
    t2.subcategory,
    t1.amount + t2.amount AS combined_amount
FROM query_test_table AS t1
INNER JOIN query_test_table AS t2 ON t1.user_id = t2.user_id AND t1.id != t2.id
LIMIT 100000
FORMAT Null;

-- Query 3: Array expansion with high cardinality
-- arrayJoin expands arrays and can use significant memory
SELECT
    id,
    category,
    arrayJoin(tags) AS tag,
    amount
FROM query_test_table
WHERE length(tags) > 5
FORMAT Null;

-- Query 4: Sorting large result set
-- ORDER BY on large datasets requires memory for sorting
SELECT *
FROM query_test_table
ORDER BY amount DESC, event_time DESC
LIMIT 100000
FORMAT Null;

-- Query 5: Window functions (memory for window state)
SELECT
    id,
    category,
    amount,
    sum(amount) OVER (PARTITION BY category ORDER BY event_time ROWS BETWEEN 1000 PRECEDING AND CURRENT ROW) AS running_sum
FROM query_test_table
LIMIT 50000
FORMAT Null;

-- Wait a moment for query_log to be flushed
SYSTEM FLUSH LOGS;
SELECT sleep(1);

-- Verify queries are captured in query_log
SELECT
    query_id,
    type,
    formatReadableSize(memory_usage) AS memory,
    query_duration_ms,
    substring(query, 1, 80) AS query_preview
FROM system.query_log
WHERE event_date = today()
  AND type = 'QueryFinish'
  AND query LIKE '%query_test_table%'
  AND query NOT LIKE '%system.query_log%'
ORDER BY memory_usage DESC
LIMIT 10;
