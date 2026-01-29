-- Base schema for altinity-expert-clickhouse-overview skill test

DROP TABLE IF EXISTS overview_events;
DROP TABLE IF EXISTS overview_small_parts;

CREATE TABLE overview_events
(
    event_time DateTime,
    user_id UInt64,
    value UInt32
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_time)
ORDER BY (event_time, user_id);

CREATE TABLE overview_small_parts
(
    event_date Date,
    id UInt64,
    value UInt32
)
ENGINE = MergeTree()
PARTITION BY event_date
ORDER BY id;
