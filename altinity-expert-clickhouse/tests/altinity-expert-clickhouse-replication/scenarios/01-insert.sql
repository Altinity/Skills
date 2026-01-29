-- Scenario: insert data into replicated table

INSERT INTO replicated_events
SELECT
    now() - toIntervalSecond(number % 3600) AS event_time,
    number AS id,
    number % 100 AS value
FROM numbers(10000);

SYSTEM FLUSH LOGS;
