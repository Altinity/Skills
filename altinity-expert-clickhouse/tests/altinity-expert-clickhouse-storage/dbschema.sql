-- Base schema for altinity-expert-clickhouse-storage skill test

DROP TABLE IF EXISTS storage_random;
DROP TABLE IF EXISTS storage_small_parts;

CREATE TABLE storage_random
(
    event_time DateTime,
    id UInt64,
    payload String,
    extra String
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_time)
ORDER BY (event_time, id)
SETTINGS index_granularity = 512;

CREATE TABLE storage_small_parts
(
    event_date Date,
    id UInt64,
    payload String
)
ENGINE = MergeTree()
PARTITION BY event_date
ORDER BY id
SETTINGS index_granularity = 512;
