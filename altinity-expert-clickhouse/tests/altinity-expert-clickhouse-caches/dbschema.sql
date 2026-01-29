-- Base schema for altinity-expert-clickhouse-caches skill test
-- Creates database and base tables for cache scenarios

DROP TABLE IF EXISTS cache_events;

CREATE TABLE cache_events
(
    event_time DateTime,
    user_id UInt64,
    session_id UUID,
    category LowCardinality(String),
    payload String,
    value Float64
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_time)
ORDER BY (user_id, event_time)
SETTINGS index_granularity = 512;
