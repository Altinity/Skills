-- Base schema for altinity-expert-clickhouse-memory skill test
-- This file creates the database and base tables needed for memory testing scenarios
-- Must be idempotent (safe to run multiple times)

-- Note: Database is created by the test runner, we just use it
-- USE `altinity-expert-clickhouse-memory` is handled by run_script_in_db

-- Clean up any existing test objects
DROP DICTIONARY IF EXISTS large_hash_dict;
DROP TABLE IF EXISTS memory_source_for_dict;
DROP TABLE IF EXISTS memory_table_large;
DROP TABLE IF EXISTS set_table_test;
DROP TABLE IF EXISTS join_table_test;
DROP TABLE IF EXISTS wide_pk_table;
DROP TABLE IF EXISTS query_test_table;

-- ============================================================
-- Source table for dictionary (Scenario 1)
-- ============================================================
CREATE TABLE memory_source_for_dict
(
    id UInt64,
    value1 String,
    value2 String,
    value3 String,
    value4 String,
    value5 Float64,
    value6 Float64
)
ENGINE = MergeTree()
ORDER BY id;

-- ============================================================
-- Base table for wide primary key test (Scenario 3)
-- ============================================================
CREATE TABLE wide_pk_table
(
    tenant_id UInt32,
    user_id UInt64,
    event_date Date,
    event_hour UInt8,
    event_type String,
    session_id UUID,
    page_id UInt32,
    -- Wide primary key columns
    col1 FixedString(256),
    col2 FixedString(256),
    col3 FixedString(256),
    -- Data columns
    value Float64,
    metadata String
)
ENGINE = MergeTree()
-- Partition by day to create many parts quickly across 30 distinct partitions (used by scenario 3).
PARTITION BY toYYYYMMDD(event_date)
ORDER BY (tenant_id, user_id, event_date, event_hour, event_type, session_id, page_id, col1, col2, col3)
SETTINGS index_granularity = 1;  -- Stress primary key index size/memory deterministically

-- ============================================================
-- Base table for memory-heavy queries (Scenario 4)
-- ============================================================
CREATE TABLE query_test_table
(
    id UInt64,
    category LowCardinality(String),
    subcategory String,
    user_id UInt64,
    amount Float64,
    event_time DateTime,
    tags Array(String),
    properties Map(String, String)
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_time)
ORDER BY (category, event_time, id);
