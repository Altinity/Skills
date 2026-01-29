-- Scenario 2: Many small parts in storage_small_parts

SYSTEM STOP MERGES storage_small_parts;

INSERT INTO storage_small_parts
SELECT today(), number, randomPrintableASCII(50)
FROM numbers(1000) SETTINGS max_insert_block_size = 1000;

INSERT INTO storage_small_parts
SELECT today(), number + 1000, randomPrintableASCII(50)
FROM numbers(1000) SETTINGS max_insert_block_size = 1000;

INSERT INTO storage_small_parts
SELECT today(), number + 2000, randomPrintableASCII(50)
FROM numbers(1000) SETTINGS max_insert_block_size = 1000;

INSERT INTO storage_small_parts
SELECT today(), number + 3000, randomPrintableASCII(50)
FROM numbers(1000) SETTINGS max_insert_block_size = 1000;

INSERT INTO storage_small_parts
SELECT today(), number + 4000, randomPrintableASCII(50)
FROM numbers(1000) SETTINGS max_insert_block_size = 1000;

SYSTEM FLUSH LOGS;
