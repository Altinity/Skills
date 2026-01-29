## Expected Findings

### Must Detect
- [ ] **Many small partitions** in `schema_daily_partitions`
- [ ] **Wide/high-cardinality ORDER BY** in `schema_wide_pk`
- [ ] **Nullable columns** in `schema_nullable`
- [ ] **Long column names** in `schema_long_names`

### Should Detect
- [ ] **Partition severity** based on count/size
- [ ] **PK compression concerns** for UUID-first ORDER BY
- [ ] **Schema Overview** section present

### Report Structure
- [ ] Severity ratings present
- [ ] Test database mentioned (`altinity-expert-clickhouse-schema`)
