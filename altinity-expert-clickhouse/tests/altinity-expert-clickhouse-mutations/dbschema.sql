-- Base schema for altinity-expert-clickhouse-mutations skill test

DROP TABLE IF EXISTS mutation_events;

CREATE TABLE mutation_events
(
    event_date Date,
    user_id UInt64,
    status String,
    value UInt32
)
ENGINE = MergeTree()
PARTITION BY event_date
ORDER BY (event_date, user_id)
SETTINGS index_granularity = 512;
