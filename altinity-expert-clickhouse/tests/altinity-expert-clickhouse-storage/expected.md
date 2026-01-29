## Expected Findings

### Must Detect
- [ ] **Poor compression** on `storage_random` (low ratio)
- [ ] **Small parts** on `storage_small_parts`
- [ ] **Disk usage summary** from system.disks

### Should Detect
- [ ] **Top tables by size** include storage_random
- [ ] **Overall compression ratio** (system.columns aggregate)
- [ ] **Recommendations** for compression or small parts remediation

### Report Structure
- [ ] Storage overview section
- [ ] Severity ratings present
- [ ] Test database mentioned (`altinity-expert-clickhouse-storage`)
