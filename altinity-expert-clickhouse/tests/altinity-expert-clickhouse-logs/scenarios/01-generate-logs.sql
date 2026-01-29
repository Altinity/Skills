-- Scenario: generate activity to populate system logs

INSERT INTO logs_events
SELECT
    now() - toIntervalSecond(number % 3600) AS event_time,
    number AS id,
    number % 100 AS value
FROM numbers(50000);

SELECT count() FROM logs_events WHERE id % 10 = 0 FORMAT Null;

SYSTEM FLUSH LOGS;
