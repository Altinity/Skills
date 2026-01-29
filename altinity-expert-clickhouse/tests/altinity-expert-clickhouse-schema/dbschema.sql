-- Base schema for altinity-expert-clickhouse-schema skill test

DROP TABLE IF EXISTS schema_daily_partitions;
DROP TABLE IF EXISTS schema_wide_pk;
DROP TABLE IF EXISTS schema_nullable;
DROP TABLE IF EXISTS schema_long_names;

CREATE TABLE schema_daily_partitions
(
    event_date Date,
    user_id UInt64,
    value UInt32
)
ENGINE = MergeTree()
PARTITION BY event_date
ORDER BY (event_date, user_id);

CREATE TABLE schema_wide_pk
(
    event_time DateTime,
    user_id UInt64,
    session_id UUID,
    page_id UInt64,
    col1 String,
    col2 String,
    col3 String,
    metric Float64
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_time)
ORDER BY (session_id, user_id, event_time, page_id, col1, col2, col3);

CREATE TABLE schema_nullable
(
    id UInt64,
    n1 Nullable(String),
    n2 Nullable(String),
    n3 Nullable(String),
    n4 Nullable(String),
    n5 Nullable(String),
    n6 Nullable(String),
    n7 Nullable(String),
    n8 Nullable(String),
    n9 Nullable(String),
    n10 Nullable(String)
)
ENGINE = MergeTree()
ORDER BY id;

CREATE TABLE schema_long_names
(
    this_is_a_very_long_column_name_for_testing_schema_rules_001 String,
    this_is_a_very_long_column_name_for_testing_schema_rules_002 String
)
ENGINE = MergeTree()
ORDER BY this_is_a_very_long_column_name_for_testing_schema_rules_001;
