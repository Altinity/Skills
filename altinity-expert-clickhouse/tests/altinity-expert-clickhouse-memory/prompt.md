Analyze the ClickHouse server for memory-related issues.

## Connection

Connect using clickhouse-client with these environment variables:
- Host: ${CLICKHOUSE_HOST}
- Port: ${CLICKHOUSE_PORT} (default: 9000)
- User: ${CLICKHOUSE_USER}
- Password: ${CLICKHOUSE_PASSWORD}
- Secure: ${CLICKHOUSE_SECURE} (if 1, add --secure)

## Task

Use the `altinity-expert-clickhouse-memory` skill instructions in:
`../skills/altinity-expert-clickhouse-memory/SKILL.md`
Produce a comprehensive memory diagnostic report following that workflow.

Focus your analysis on:
1. **Current Memory Overview** - Total RAM, used memory, memory pressure indicators
2. **Memory Breakdown by Component** - Dictionaries, Memory tables, Primary keys, Caches
3. **Memory Allocation Audit** - Check for oversized components, identify memory hogs
4. **Top Memory Consumers** - Tables, dictionaries, and queries using the most memory

Pay special attention to the `altinity-expert-clickhouse-memory` database which contains test data designed to stress memory subsystems.

## Expected Components to Analyze

- **Dictionaries**: Check `system.dictionaries` for large dictionaries loaded in RAM
- **Memory Tables**: Check for Memory, Set, and Join engine tables
- **Primary Key Memory**: Check `primary_key_bytes_in_memory` in `system.parts`
- **Query Memory**: Check `system.query_log` for memory-heavy queries

## Output Format

Produce a markdown report with:
1. Clear section headers for each analysis area
2. Severity ratings (Critical, Major, Moderate, Minor, OK) for each finding
3. Specific metrics with human-readable sizes
4. Recommendations for any issues found

Use the standard severity classification:
- **Critical**: Immediate risk of OOM or failure
- **Major**: Significant memory pressure, needs attention
- **Moderate**: Elevated usage, monitor and plan
- **Minor**: Best practice suggestions
- **OK**: No issues
