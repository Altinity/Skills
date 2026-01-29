-- Base schema for altinity-expert-clickhouse-metrics skill test

DROP TABLE IF EXISTS metrics_events;

CREATE TABLE metrics_events
(
    event_time DateTime,
    user_id UInt64,
    value UInt32
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_time)
ORDER BY (event_time, user_id);
