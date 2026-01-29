-- Scenario: generate some activity

INSERT INTO metrics_events
SELECT
    now() - toIntervalSecond(number % 3600) AS event_time,
    number % 10000 AS user_id,
    number % 100 AS value
FROM numbers(100000);

SELECT count() FROM metrics_events WHERE user_id = 42 FORMAT Null;
SELECT count() FROM metrics_events WHERE user_id = 42 FORMAT Null;

SYSTEM FLUSH LOGS;
