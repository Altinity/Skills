-- Scenario: create multiple tables and small parts

INSERT INTO overview_events
SELECT
    now() - toIntervalSecond(number % 3600) AS event_time,
    number % 10000 AS user_id,
    number % 100 AS value
FROM numbers(100000);

SYSTEM STOP MERGES overview_small_parts;

INSERT INTO overview_small_parts
SELECT today(), number, number % 10
FROM numbers(1000) SETTINGS max_insert_block_size = 1000;

INSERT INTO overview_small_parts
SELECT today(), number + 1000, number % 10
FROM numbers(1000) SETTINGS max_insert_block_size = 1000;

INSERT INTO overview_small_parts
SELECT today(), number + 2000, number % 10
FROM numbers(1000) SETTINGS max_insert_block_size = 1000;

SYSTEM FLUSH LOGS;
