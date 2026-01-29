-- Scenario 2: Repeated queries to generate cache hits/misses
-- Expected: Mark cache hit ratio visible

SELECT count() FROM cache_events WHERE user_id = 12345 FORMAT Null;
SELECT count() FROM cache_events WHERE user_id = 12345 FORMAT Null;
SELECT count() FROM cache_events WHERE user_id = 12345 FORMAT Null;

SELECT sum(length(payload)) FROM cache_events WHERE category = 'alpha' FORMAT Null;
SELECT sum(length(payload)) FROM cache_events WHERE category = 'alpha' FORMAT Null;

SELECT user_id, avg(value)
FROM cache_events
GROUP BY user_id
ORDER BY avg(value) DESC
LIMIT 1000
FORMAT Null;
