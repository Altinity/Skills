-- Base schema for altinity-expert-clickhouse-merges skill test

DROP TABLE IF EXISTS merge_events;

CREATE TABLE merge_events
(
    event_date Date,
    user_id UInt64,
    value UInt32
)
ENGINE = MergeTree()
PARTITION BY event_date
ORDER BY (event_date, user_id)
SETTINGS index_granularity = 512;
