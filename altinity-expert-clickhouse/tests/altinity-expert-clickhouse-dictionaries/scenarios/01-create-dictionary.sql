-- Scenario: Create and load dictionary

INSERT INTO dict_source
SELECT
    number AS id,
    concat('user_', toString(number)) AS name,
    arrayElement(['us','uk','de','fr','es'], (number % 5) + 1) AS country,
    rand() / 1000000.0 AS score
FROM numbers(200000);

DROP DICTIONARY IF EXISTS user_dict;
CREATE DICTIONARY user_dict
(
    id UInt64,
    name String,
    country String,
    score Float64
)
PRIMARY KEY id
SOURCE(CLICKHOUSE(DATABASE 'altinity-expert-clickhouse-dictionaries' TABLE 'dict_source'))
LIFETIME(MIN 0 MAX 0)
LAYOUT(HASHED());

-- Force dictionary load
SELECT dictGetString('user_dict', 'name', toUInt64(1)) FORMAT Null;
