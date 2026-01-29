-- Scenario: create many parts for merges analysis

SYSTEM STOP MERGES ae_events;

INSERT INTO ae_events
SELECT today(), number, number % 10
FROM numbers(1000) SETTINGS max_insert_block_size = 1000;

INSERT INTO ae_events
SELECT today(), number + 1000, number % 10
FROM numbers(1000) SETTINGS max_insert_block_size = 1000;

INSERT INTO ae_events
SELECT today(), number + 2000, number % 10
FROM numbers(1000) SETTINGS max_insert_block_size = 1000;

INSERT INTO ae_events
SELECT today(), number + 3000, number % 10
FROM numbers(1000) SETTINGS max_insert_block_size = 1000;

SYSTEM FLUSH LOGS;
