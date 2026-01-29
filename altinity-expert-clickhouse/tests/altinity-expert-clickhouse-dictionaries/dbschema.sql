-- Base schema for altinity-expert-clickhouse-dictionaries skill test

DROP DICTIONARY IF EXISTS user_dict;
DROP TABLE IF EXISTS dict_source;

CREATE TABLE dict_source
(
    id UInt64,
    name String,
    country String,
    score Float64
)
ENGINE = MergeTree()
ORDER BY id;
