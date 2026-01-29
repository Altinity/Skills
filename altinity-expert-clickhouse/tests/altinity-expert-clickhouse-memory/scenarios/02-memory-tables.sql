-- Scenario 2: Memory Engine Tables
-- Goal: Create Memory, Set, and Join tables consuming RAM
-- Expected Finding: Memory tables flagged in breakdown
-- Expected Severity: Moderate (memory tables present and sized)

-- ============================================================
-- Large Memory table
-- Memory tables store all data in RAM
-- ============================================================
CREATE TABLE memory_table_large
(
    id UInt64,
    user_id UInt64,
    session_id String,
    event_type String,
    event_data String,
    timestamp DateTime
)
ENGINE = Memory;

-- Populate with ~200K rows of session-like data
INSERT INTO memory_table_large
SELECT
    number AS id,
    number % 50000 AS user_id,
    generateUUIDv4() AS session_id,
    arrayElement(['click', 'view', 'scroll', 'hover', 'submit'], (number % 5) + 1) AS event_type,
    concat('{"page":"', toString(number % 1000), '","data":"', randomPrintableASCII(100), '"}') AS event_data,
    now() - toIntervalSecond(number % 86400) AS timestamp
FROM numbers(200000);

-- ============================================================
-- Set table for deduplication lookups
-- Set tables store unique values in RAM
-- ============================================================
CREATE TABLE set_table_test
(
    user_id UInt64,
    blocked_reason String
)
ENGINE = Set;

-- Populate with user IDs (Set stores unique values in memory)
INSERT INTO set_table_test
SELECT
    number AS user_id,
    concat('reason_', toString(number % 100)) AS blocked_reason
FROM numbers(100000);

-- ============================================================
-- Join table for in-memory lookups
-- Join tables store key-value data in RAM
-- ============================================================
CREATE TABLE join_table_test
(
    key UInt64,
    name String,
    category String,
    metadata String
)
ENGINE = Join(ANY, LEFT, key);

-- Populate with lookup data
INSERT INTO join_table_test
SELECT
    number AS key,
    concat('item_', toString(number)) AS name,
    concat('cat_', toString(number % 100)) AS category,
    randomPrintableASCII(200) AS metadata
FROM numbers(50000);

-- Verify memory tables are created
-- This helps confirm scenario setup
SELECT
    database,
    name AS table_name,
    engine,
    formatReadableSize(total_bytes) AS size
FROM system.tables
WHERE database = currentDatabase()
  AND engine IN ('Memory', 'Set', 'Join')
ORDER BY total_bytes DESC;
