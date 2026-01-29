-- Base schema for altinity-expert-clickhouse-logs skill test

DROP TABLE IF EXISTS logs_events;

CREATE TABLE logs_events
(
    event_time DateTime,
    id UInt64,
    value UInt32
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_time)
ORDER BY (event_time, id);
