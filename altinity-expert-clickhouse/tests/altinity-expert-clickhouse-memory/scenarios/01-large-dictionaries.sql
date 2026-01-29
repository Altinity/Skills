-- Scenario 1: Large Dictionaries
-- Goal: Create a large in-memory dictionary and force it to load
-- Expected Finding: Dictionary memory usage identified
-- Expected Severity: Moderate (significant dictionary memory)

-- Populate source table with substantial data
-- This creates ~500K rows with wide string columns
INSERT INTO memory_source_for_dict
SELECT
    number AS id,
    concat('value_', toString(number), '_', randomPrintableASCII(50)) AS value1,
    concat('data_', toString(number % 1000), '_', randomPrintableASCII(100)) AS value2,
    concat('info_', toString(number % 10000), '_', randomPrintableASCII(80)) AS value3,
    concat('text_', randomPrintableASCII(60)) AS value4,
    rand() / 1000000.0 AS value5,
    rand() / 1000000.0 AS value6
FROM numbers(500000);

-- Create dictionary from the source table (hashed layout)
DROP DICTIONARY IF EXISTS large_hash_dict;
CREATE DICTIONARY large_hash_dict
(
    id UInt64,
    value1 String,
    value2 String,
    value3 String,
    value4 String,
    value5 Float64,
    value6 Float64
)
PRIMARY KEY id
SOURCE(CLICKHOUSE(
    DATABASE 'altinity-expert-clickhouse-memory'
    TABLE 'memory_source_for_dict'
))
LIFETIME(MIN 0 MAX 0)
LAYOUT(HASHED());

-- Force dictionary load into memory
SELECT dictGetString('large_hash_dict', 'value1', toUInt64(1)) FORMAT Null;

-- Force data to be read into memory (mark cache, etc)
SELECT count(), sum(length(value1) + length(value2) + length(value3))
FROM memory_source_for_dict
FORMAT Null;

-- Verify table size
SELECT
    'memory_source_for_dict' AS table_name,
    formatReadableSize(sum(bytes_on_disk)) AS disk_size,
    formatReadableSize(sum(data_compressed_bytes)) AS compressed,
    formatReadableSize(sum(data_uncompressed_bytes)) AS uncompressed,
    sum(rows) AS rows
FROM system.parts
WHERE database = currentDatabase()
  AND table = 'memory_source_for_dict'
  AND active;
