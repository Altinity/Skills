-- Scenario 1: Populate cache_events with enough data to generate marks
-- Expected: Mark cache and uncompressed cache have activity

INSERT INTO cache_events
SELECT
    now() - toIntervalSecond(number % 86400) AS event_time,
    number % 50000 AS user_id,
    generateUUIDv4() AS session_id,
    arrayElement(['alpha','beta','gamma','delta'], (number % 4) + 1) AS category,
    randomPrintableASCII(200) AS payload,
    rand() / 1000000.0 AS value
FROM numbers(300000);
