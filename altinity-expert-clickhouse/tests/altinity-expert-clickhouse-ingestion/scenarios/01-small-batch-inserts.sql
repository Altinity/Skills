-- Scenario: many small inserts to create micro-parts

SYSTEM STOP MERGES ingest_events;

INSERT INTO ingest_events
SELECT now(), number, 'click', randomPrintableASCII(50)
FROM numbers(500) SETTINGS max_insert_block_size = 500;

INSERT INTO ingest_events
SELECT now(), number + 500, 'view', randomPrintableASCII(50)
FROM numbers(500) SETTINGS max_insert_block_size = 500;

INSERT INTO ingest_events
SELECT now(), number + 1000, 'purchase', randomPrintableASCII(50)
FROM numbers(500) SETTINGS max_insert_block_size = 500;

INSERT INTO ingest_events
SELECT now(), number + 1500, 'click', randomPrintableASCII(50)
FROM numbers(500) SETTINGS max_insert_block_size = 500;

INSERT INTO ingest_events
SELECT now(), number + 2000, 'view', randomPrintableASCII(50)
FROM numbers(500) SETTINGS max_insert_block_size = 500;

INSERT INTO ingest_events
SELECT now(), number + 2500, 'purchase', randomPrintableASCII(50)
FROM numbers(500) SETTINGS max_insert_block_size = 500;

INSERT INTO ingest_events
SELECT now(), number + 3000, 'click', randomPrintableASCII(50)
FROM numbers(500) SETTINGS max_insert_block_size = 500;

INSERT INTO ingest_events
SELECT now(), number + 3500, 'view', randomPrintableASCII(50)
FROM numbers(500) SETTINGS max_insert_block_size = 500;

INSERT INTO ingest_events
SELECT now(), number + 4000, 'purchase', randomPrintableASCII(50)
FROM numbers(500) SETTINGS max_insert_block_size = 500;

INSERT INTO ingest_events
SELECT now(), number + 4500, 'click', randomPrintableASCII(50)
FROM numbers(500) SETTINGS max_insert_block_size = 500;

SYSTEM FLUSH LOGS;
