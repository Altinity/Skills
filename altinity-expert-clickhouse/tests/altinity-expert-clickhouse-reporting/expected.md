## Expected Findings

### Must Detect
- [ ] **Slow queries** in query_log involving `reporting_events`
- [ ] **High read bytes/rows** or long duration for SELECTs
- [ ] **Reporting overview** with time window and query counts/latency stats

### Should Detect
- [ ] **Most frequent/slow query patterns**
- [ ] **Recommendations** for ORDER BY or aggregation tuning
- [ ] **Severity ratings** for slow/heavy queries or findings

### Report Structure
- [ ] Reporting overview section
- [ ] Severity ratings present
- [ ] Test database mentioned (`altinity-expert-clickhouse-reporting`)
