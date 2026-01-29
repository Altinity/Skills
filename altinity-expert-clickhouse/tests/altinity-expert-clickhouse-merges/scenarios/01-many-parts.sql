-- Scenario: many small parts in a single partition

SYSTEM STOP MERGES merge_events;

INSERT INTO merge_events
SELECT today(), number + 0, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 100, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 200, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 300, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 400, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 500, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 600, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 700, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 800, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 900, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 1000, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 1100, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 1200, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 1300, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 1400, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 1500, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 1600, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 1700, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 1800, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 1900, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 2000, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 2100, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 2200, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 2300, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 2400, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 2500, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 2600, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 2700, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 2800, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 2900, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 3000, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 3100, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 3200, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 3300, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 3400, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 3500, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 3600, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 3700, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 3800, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 3900, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 4000, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 4100, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 4200, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 4300, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 4400, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 4500, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 4600, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 4700, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 4800, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 4900, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 5000, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 5100, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 5200, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 5300, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 5400, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 5500, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 5600, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 5700, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 5800, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

INSERT INTO merge_events
SELECT today(), number + 5900, number % 100
FROM numbers(100) SETTINGS max_insert_block_size = 100;

SYSTEM FLUSH LOGS;
