-- Scenario: create a pending mutation

SYSTEM STOP MERGES mutation_events;

INSERT INTO mutation_events
SELECT today(), number, 'open', number % 10
FROM numbers(50000) SETTINGS max_insert_block_size = 5000;

ALTER TABLE mutation_events UPDATE status = 'closed' WHERE value = 1;

SYSTEM FLUSH LOGS;
