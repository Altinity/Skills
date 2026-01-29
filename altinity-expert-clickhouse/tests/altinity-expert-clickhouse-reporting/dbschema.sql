-- Base schema for altinity-expert-clickhouse-reporting skill test

DROP TABLE IF EXISTS reporting_events;

CREATE TABLE reporting_events
(
    event_time DateTime,
    user_id UInt64,
    category String,
    subcategory String,
    amount Float64,
    payload String
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_time)
ORDER BY (event_time, user_id)
SETTINGS index_granularity = 512;
