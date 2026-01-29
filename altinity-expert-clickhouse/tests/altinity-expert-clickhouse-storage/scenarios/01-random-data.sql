-- Scenario 1: Large random strings for poor compression

INSERT INTO storage_random
SELECT
    now() - toIntervalSecond(number % 86400) AS event_time,
    number AS id,
    randomPrintableASCII(500) AS payload,
    randomPrintableASCII(200) AS extra
FROM numbers(200000);
