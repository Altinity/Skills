-- Scenario: create many small daily partitions and wide PK table

INSERT INTO schema_daily_partitions
SELECT
    toDate(today() - number) AS event_date,
    number AS user_id,
    number % 100 AS value
FROM numbers(200)
SETTINGS max_partitions_per_insert_block = 300;  -- allow 200 partitions

INSERT INTO schema_wide_pk
SELECT
    now() - toIntervalSecond(number % 86400) AS event_time,
    number % 100000 AS user_id,
    generateUUIDv4() AS session_id,
    number % 10000 AS page_id,
    concat('c1_', toString(number % 1000)) AS col1,
    concat('c2_', toString(number % 1000)) AS col2,
    concat('c3_', toString(number % 1000)) AS col3,
    rand() / 1000000.0 AS metric
FROM numbers(200000);

INSERT INTO schema_nullable
SELECT
    number,
    if(number % 2 = 0, toString(number), NULL),
    if(number % 3 = 0, toString(number), NULL),
    if(number % 4 = 0, toString(number), NULL),
    if(number % 5 = 0, toString(number), NULL),
    if(number % 6 = 0, toString(number), NULL),
    if(number % 7 = 0, toString(number), NULL),
    if(number % 8 = 0, toString(number), NULL),
    if(number % 9 = 0, toString(number), NULL),
    if(number % 10 = 0, toString(number), NULL),
    if(number % 11 = 0, toString(number), NULL)
FROM numbers(10000);
