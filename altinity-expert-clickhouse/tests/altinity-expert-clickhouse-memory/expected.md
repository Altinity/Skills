## Expected Findings

This document defines what the `altinity-expert-clickhouse-memory` skill should detect in the test scenarios.

### Must Detect (Critical/Major)

These findings are required for the test to pass:

- [ ] **Dictionary memory usage identified**: The report must identify the `large_hash_dict` dictionary and report its memory consumption. Expected to find ~100MB+ allocated to dictionaries.

- [ ] **Memory tables identified**: The report must detect the Memory, Set, and Join engine tables (`memory_table_large`, `set_table_test`, `join_table_test`) and report their sizes.

- [ ] **Primary key memory reported**: The report must include primary key memory statistics, showing the `wide_pk_table` with elevated PK memory due to wide keys and multiple parts.

### Should Detect (Moderate/Minor)

These findings strengthen the report but are not strictly required:

- [ ] **Memory-heavy queries in query_log**: The report should identify recent queries with high memory usage from the query_log analysis.

- [ ] **Memory breakdown percentages**: The report should show what percentage of RAM each component (dictionaries, memory tables, PK memory, caches) consumes.

- [ ] **Cache memory usage**: Mark cache, uncompressed cache, or query cache statistics should be mentioned.

- [ ] **Recommendations provided**: For each issue found, the report should include actionable recommendations.

### Report Structure

The report should contain these sections:

- [ ] **Overview/Summary section**: High-level memory status
- [ ] **Memory breakdown section**: Component-by-component analysis
- [ ] **Severity ratings present**: Each finding should have a severity level
- [ ] **Specific metrics included**: Actual byte/MB/GB values, not just "high" or "low"
- [ ] **Test database mentioned**: Reference to `altinity-expert-clickhouse-memory` database

### Severity Expectations

Based on test scenarios:

| Component | Expected Severity | Reason |
|-----------|-------------------|--------|
| Dictionaries | Moderate-Major | Large dictionary consuming significant RAM |
| Memory Tables | Moderate | Multiple in-memory tables present |
| Primary Keys | Moderate | Wide PK with many parts |
| Query Memory | Minor-Moderate | Historical high-memory queries |

### Not Expected

The following should NOT be flagged as issues (if present, it indicates over-sensitivity):

- System databases and tables (expected to exist)
- Normal cache usage within thresholds
- Standard ClickHouse processes
