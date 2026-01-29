# altinity-expert-clickhouse-memory Skill Test

Tests for the `altinity-expert-clickhouse-memory` ClickHouse diagnostic skill.

## Purpose

This test creates various memory-pressure scenarios and verifies that the memory diagnostic skill correctly identifies and reports them.

## Scenarios

### 1. Large Dictionaries (`01-large-dictionaries.sql`)
- Creates a Hashed dictionary with ~500K entries
- Forces dictionary load into memory
- Expected to consume ~100MB+ of RAM
- Skill should detect elevated dictionary memory
- Note: Dictionary source uses only DATABASE/TABLE; connection/auth is implied by server config.

### 2. Memory Engine Tables (`02-memory-tables.sql`)
- Creates Memory, Set, and Join engine tables
- These tables store all data in RAM
- Skill should identify and size each memory table

### 3. High Primary Key Memory (`03-high-pk-memory.sql`)
- Creates a table with wide primary key (10 columns)
- Inserts data in small batches to create many parts
- Uses small index_granularity for more index entries
- Stops merges for the table to keep parts unmerged during analysis
- Skill should report elevated primary key memory

### 4. Memory-Heavy Queries (`04-memory-heavy-queries.sql`)
- Executes queries with high memory requirements:
  - High cardinality GROUP BY
  - Large JOINs
  - Array expansions
  - Large sorts
  - Window functions
- Skill should find these in query_log analysis

## Running the Test

```bash
# Set environment variables
export CLICKHOUSE_HOST=localhost
export CLICKHOUSE_PORT=9000
export CLICKHOUSE_USER=default

# Run the test
cd tests
make test-memory

# Or run without verification
make test-memory-no-verify

# Just setup the database (for manual testing)
make setup-memory
```

## Expected Results

The skill should produce a report identifying:
- Dictionary memory consumption (Moderate-Major severity)
- Memory tables present and sized (Moderate severity)
- Primary key memory elevated (Moderate severity)
- Memory-heavy queries in history (Minor-Moderate severity)

See `expected.md` for detailed pass/fail criteria.

## Files

- `dbschema.sql` - Base schema and table definitions
- `scenarios/` - SQL files that create problem conditions
- `prompt.md` - Prompt sent to Claude for analysis
- `expected.md` - Expected findings for verification
- `post.sql` - Post-run reset steps (re-enable merges)
- `config.d/memory-test.xml` - Optional server config snippet for deterministic logs/caches
- `reports/` - Generated reports (gitignored) live under `tests/reports/altinity-expert-clickhouse-memory/`

## Optional Server Tuning

For more deterministic query_log capture, you can install the config snippet:

```
sudo cp tests/altinity-expert-clickhouse-memory/config.d/memory-test.xml /etc/clickhouse-server/config.d/
sudo systemctl restart clickhouse-server
```

If you see authentication errors when loading dictionaries, install the user snippet:

```
sudo cp tests/altinity-expert-clickhouse-memory/users.d/default-no-password.xml /etc/clickhouse-server/users.d/
sudo systemctl restart clickhouse-server
```
