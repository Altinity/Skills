## Expected Findings

### Must Detect
- [ ] **Object counts** (MergeTree tables, active parts)
- [ ] **Resource utilization** (memory and disk) summary
- [ ] **Test database referenced** (`altinity-expert-clickhouse-overview`)

### Should Detect
- [ ] **Recent errors summary** from query_log
- [ ] **system.errors summary** for the timeframe
- [ ] **system.*_log activity summary** for the timeframe
- [ ] **Log TTL status** for system logs
- [ ] **Version age check** (upgrade recommendation if old)
- [ ] **Warnings** from system.warnings (or explicitly none)

### Report Structure
- [ ] Overview summary section
- [ ] Severity ratings present
