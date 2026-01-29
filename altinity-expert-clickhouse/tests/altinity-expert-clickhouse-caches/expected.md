## Expected Findings

### Must Detect
- [ ] **Mark cache statistics**: Report mark cache size and hit ratio (or state unavailable).
- [ ] **Uncompressed cache statistics**: Report uncompressed cache size/hit ratio (or state unavailable/disabled).
- [ ] **Tables with most marks**: Mention `altinity-expert-clickhouse-caches.cache_events` in mark cache/marks breakdown.

### Should Detect
- [ ] **Query cache summary** if `system.query_cache` is present
- [ ] **Cache sizing recommendation** based on RAM or marks size
- [ ] **Hit ratio interpretation** (e.g., healthy/low and why)

### Report Structure
- [ ] Cache overview section
- [ ] Severity ratings present
- [ ] Specific metrics (sizes, ratios)
- [ ] Test database mentioned (`altinity-expert-clickhouse-caches`)
