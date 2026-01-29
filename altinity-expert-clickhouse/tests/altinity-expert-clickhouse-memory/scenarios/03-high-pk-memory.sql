-- Scenario 3: High Primary Key Memory
-- Goal: Primary keys consuming elevated RAM due to many parts and wide keys
-- Expected Finding: "Primary Keys" elevated in memory breakdown
-- Expected Severity: Moderate+

-- Keep parts from merging to maximize primary key memory
SYSTEM STOP MERGES wide_pk_table;

-- ============================================================
-- Insert data in small batches to create many parts
-- Each INSERT creates a new part, and parts have primary key indexes in memory
-- ============================================================

-- Insert rows with very wide, high-cardinality primary key columns and tiny index granularity.
-- Combined with daily partitioning and merges stopped, this reliably inflates PK index size.

INSERT INTO wide_pk_table
SELECT
    number % 100 AS tenant_id,
    number AS user_id,
    today() - toIntervalDay(number % 30) AS event_date,
    number % 24 AS event_hour,
    arrayElement(['click', 'view', 'purchase', 'login', 'logout'], (number % 5) + 1) AS event_type,
    generateUUIDv4() AS session_id,
    number % 1000 AS page_id,
    toFixedString(randomPrintableASCII(256), 256) AS col1,
    toFixedString(randomPrintableASCII(256), 256) AS col2,
    toFixedString(randomPrintableASCII(256), 256) AS col3,
    rand() / 1000000.0 AS value,
    randomPrintableASCII(50) AS metadata
FROM numbers(10000)
SETTINGS max_insert_block_size = 1000;

INSERT INTO wide_pk_table
SELECT
    number % 100 AS tenant_id,
    number + 250000 AS user_id,
    today() - toIntervalDay(number % 30) AS event_date,
    number % 24 AS event_hour,
    arrayElement(['click', 'view', 'purchase', 'login', 'logout'], (number % 5) + 1) AS event_type,
    generateUUIDv4() AS session_id,
    number % 1000 AS page_id,
    toFixedString(randomPrintableASCII(256), 256) AS col1,
    toFixedString(randomPrintableASCII(256), 256) AS col2,
    toFixedString(randomPrintableASCII(256), 256) AS col3,
    rand() / 1000000.0 AS value,
    randomPrintableASCII(50) AS metadata
FROM numbers(10000)
SETTINGS max_insert_block_size = 1000;

INSERT INTO wide_pk_table
SELECT
    number % 100 AS tenant_id,
    number + 300000 AS user_id,
    today() - toIntervalDay(number % 30) AS event_date,
    number % 24 AS event_hour,
    arrayElement(['click', 'view', 'purchase', 'login', 'logout'], (number % 5) + 1) AS event_type,
    generateUUIDv4() AS session_id,
    number % 1000 AS page_id,
    toFixedString(randomPrintableASCII(256), 256) AS col1,
    toFixedString(randomPrintableASCII(256), 256) AS col2,
    toFixedString(randomPrintableASCII(256), 256) AS col3,
    rand() / 1000000.0 AS value,
    randomPrintableASCII(50) AS metadata
FROM numbers(10000)
SETTINGS max_insert_block_size = 1000;

INSERT INTO wide_pk_table
SELECT
    number % 100 AS tenant_id,
    number + 350000 AS user_id,
    today() - toIntervalDay(number % 30) AS event_date,
    number % 24 AS event_hour,
    arrayElement(['click', 'view', 'purchase', 'login', 'logout'], (number % 5) + 1) AS event_type,
    generateUUIDv4() AS session_id,
    number % 1000 AS page_id,
    toFixedString(randomPrintableASCII(256), 256) AS col1,
    toFixedString(randomPrintableASCII(256), 256) AS col2,
    toFixedString(randomPrintableASCII(256), 256) AS col3,
    rand() / 1000000.0 AS value,
    randomPrintableASCII(50) AS metadata
FROM numbers(10000)
SETTINGS max_insert_block_size = 1000;

INSERT INTO wide_pk_table
SELECT
    number % 100 AS tenant_id,
    number + 400000 AS user_id,
    today() - toIntervalDay(number % 30) AS event_date,
    number % 24 AS event_hour,
    arrayElement(['click', 'view', 'purchase', 'login', 'logout'], (number % 5) + 1) AS event_type,
    generateUUIDv4() AS session_id,
    number % 1000 AS page_id,
    toFixedString(randomPrintableASCII(256), 256) AS col1,
    toFixedString(randomPrintableASCII(256), 256) AS col2,
    toFixedString(randomPrintableASCII(256), 256) AS col3,
    rand() / 1000000.0 AS value,
    randomPrintableASCII(50) AS metadata
FROM numbers(10000)
SETTINGS max_insert_block_size = 1000;

INSERT INTO wide_pk_table
SELECT
    number % 100 AS tenant_id,
    number + 450000 AS user_id,
    today() - toIntervalDay(number % 30) AS event_date,
    number % 24 AS event_hour,
    arrayElement(['click', 'view', 'purchase', 'login', 'logout'], (number % 5) + 1) AS event_type,
    generateUUIDv4() AS session_id,
    number % 1000 AS page_id,
    toFixedString(randomPrintableASCII(256), 256) AS col1,
    toFixedString(randomPrintableASCII(256), 256) AS col2,
    toFixedString(randomPrintableASCII(256), 256) AS col3,
    rand() / 1000000.0 AS value,
    randomPrintableASCII(50) AS metadata
FROM numbers(10000)
SETTINGS max_insert_block_size = 1000;

INSERT INTO wide_pk_table
SELECT
    number % 100 AS tenant_id,
    number + 50000 AS user_id,
    today() - toIntervalDay(number % 30) AS event_date,
    number % 24 AS event_hour,
    arrayElement(['click', 'view', 'purchase', 'login', 'logout'], (number % 5) + 1) AS event_type,
    generateUUIDv4() AS session_id,
    number % 1000 AS page_id,
    toFixedString(randomPrintableASCII(256), 256) AS col1,
    toFixedString(randomPrintableASCII(256), 256) AS col2,
    toFixedString(randomPrintableASCII(256), 256) AS col3,
    rand() / 1000000.0 AS value,
    randomPrintableASCII(50) AS metadata
FROM numbers(10000)
SETTINGS max_insert_block_size = 1000;

INSERT INTO wide_pk_table
SELECT
    number % 100 AS tenant_id,
    number + 100000 AS user_id,
    today() - toIntervalDay(number % 30) AS event_date,
    number % 24 AS event_hour,
    arrayElement(['click', 'view', 'purchase', 'login', 'logout'], (number % 5) + 1) AS event_type,
    generateUUIDv4() AS session_id,
    number % 1000 AS page_id,
    toFixedString(randomPrintableASCII(256), 256) AS col1,
    toFixedString(randomPrintableASCII(256), 256) AS col2,
    toFixedString(randomPrintableASCII(256), 256) AS col3,
    rand() / 1000000.0 AS value,
    randomPrintableASCII(50) AS metadata
FROM numbers(10000)
SETTINGS max_insert_block_size = 1000;

INSERT INTO wide_pk_table
SELECT
    number % 100 AS tenant_id,
    number + 150000 AS user_id,
    today() - toIntervalDay(number % 30) AS event_date,
    number % 24 AS event_hour,
    arrayElement(['click', 'view', 'purchase', 'login', 'logout'], (number % 5) + 1) AS event_type,
    generateUUIDv4() AS session_id,
    number % 1000 AS page_id,
    toFixedString(randomPrintableASCII(256), 256) AS col1,
    toFixedString(randomPrintableASCII(256), 256) AS col2,
    toFixedString(randomPrintableASCII(256), 256) AS col3,
    rand() / 1000000.0 AS value,
    randomPrintableASCII(50) AS metadata
FROM numbers(10000)
SETTINGS max_insert_block_size = 1000;

INSERT INTO wide_pk_table
SELECT
    number % 100 AS tenant_id,
    number + 200000 AS user_id,
    today() - toIntervalDay(number % 30) AS event_date,
    number % 24 AS event_hour,
    arrayElement(['click', 'view', 'purchase', 'login', 'logout'], (number % 5) + 1) AS event_type,
    generateUUIDv4() AS session_id,
    number % 1000 AS page_id,
    toFixedString(randomPrintableASCII(256), 256) AS col1,
    toFixedString(randomPrintableASCII(256), 256) AS col2,
    toFixedString(randomPrintableASCII(256), 256) AS col3,
    rand() / 1000000.0 AS value,
    randomPrintableASCII(50) AS metadata
FROM numbers(10000)
SETTINGS max_insert_block_size = 1000;

-- Check part count and primary key memory
SELECT
    database,
    table,
    count() AS parts,
    formatReadableSize(sum(primary_key_bytes_in_memory)) AS pk_memory,
    formatReadableSize(sum(primary_key_bytes_in_memory_allocated)) AS pk_memory_allocated
FROM system.parts
WHERE database = currentDatabase()
  AND table = 'wide_pk_table'
  AND active
GROUP BY database, table;
