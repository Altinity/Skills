-- Base schema for altinity-expert-clickhouse-audit skill test

DROP TABLE IF EXISTS ae_events;

CREATE TABLE ae_events
(
    event_date Date,
    id UInt64,
    value UInt32
)
ENGINE = MergeTree()
PARTITION BY event_date
ORDER BY id;
