## Expected Findings

### Must Detect
- [ ] **Small batch inserts**: low avg rows per part for `ingest_events`
- [ ] **High part creation rate** relative to inserted rows
- [ ] **Ingestion overview** with time window and total inserts/rows/bytes

### Should Detect
- [ ] **Part log evidence** (system.part_log new parts)
- [ ] **Insert performance stats** (avg/p95 insert duration)
- [ ] **Merge balance** (new parts vs merges) with severity note

### Report Structure
- [ ] Severity ratings present
- [ ] Test database mentioned (`altinity-expert-clickhouse-ingestion`)
