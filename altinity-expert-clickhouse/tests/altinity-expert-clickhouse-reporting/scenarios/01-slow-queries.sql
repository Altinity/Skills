-- Scenario: populate data and run heavy SELECT queries

INSERT INTO reporting_events
SELECT
    now() - toIntervalSecond(number % 604800) AS event_time,
    number % 100000 AS user_id,
    arrayElement(['electronics','books','food','sports'], (number % 4) + 1) AS category,
    concat('sub_', toString(number % 1000)) AS subcategory,
    (rand() % 10000) / 100.0 AS amount,
    randomPrintableASCII(200) AS payload
FROM numbers(400000);

-- High-cardinality group by
SELECT
    subcategory,
    user_id,
    count() AS cnt,
    sum(amount) AS total
FROM reporting_events
GROUP BY subcategory, user_id
ORDER BY total DESC
LIMIT 10000
FORMAT Null;

-- Large sort
SELECT *
FROM reporting_events
ORDER BY amount DESC, event_time DESC
LIMIT 200000
FORMAT Null;

SYSTEM FLUSH LOGS;
