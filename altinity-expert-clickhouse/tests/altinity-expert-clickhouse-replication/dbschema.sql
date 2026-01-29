-- Base schema for altinity-expert-clickhouse-replication skill test

DROP TABLE IF EXISTS replicated_events;

CREATE TABLE replicated_events
(
    event_time DateTime,
    id UInt64,
    value UInt32
)
ENGINE = ReplicatedMergeTree('/clickhouse/tables/altinity-expert-clickhouse-replication/replicated_events', 'replica1_${TEST_RUN_ID}')
PARTITION BY toYYYYMM(event_time)
ORDER BY (event_time, id);
