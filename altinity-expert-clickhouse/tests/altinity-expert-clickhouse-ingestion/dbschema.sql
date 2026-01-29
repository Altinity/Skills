-- Base schema for altinity-expert-clickhouse-ingestion skill test

DROP TABLE IF EXISTS ingest_events;

CREATE TABLE ingest_events
(
    event_time DateTime,
    user_id UInt64,
    event_type String,
    payload String
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_time)
ORDER BY (event_time, user_id)
SETTINGS index_granularity = 512;
