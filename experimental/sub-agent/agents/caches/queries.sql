-- Query 1: Cache-related events (best-effort, names vary)
SELECT
    event,
    value
FROM system.events
WHERE event ILIKE '%Cache%'
ORDER BY value DESC
LIMIT 200;

-- Query 2: Cache-related metrics (best-effort)
SELECT
    metric,
    value
FROM system.metrics
WHERE metric ILIKE '%Cache%'
ORDER BY value DESC
LIMIT 200;

-- Query 3: Cache-related async metrics (best-effort)
SELECT
    metric,
    value
FROM system.asynchronous_metrics
WHERE metric ILIKE '%Cache%'
ORDER BY metric ASC
LIMIT 300;

