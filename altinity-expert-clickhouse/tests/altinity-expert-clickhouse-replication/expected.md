## Expected Findings

### Must Detect
- [ ] **Replicated table present** (`replicated_events`)
- [ ] **Replication overview** from system.replicas (delay/queue fields)

### Should Detect
- [ ] **Keeper/ZooKeeper status** (system.zookeeper_connection)
- [ ] **Queue size** and any errors (even if OK)

### Report Structure
- [ ] Replication overview section
- [ ] Severity ratings present
- [ ] Test database mentioned (`altinity-expert-clickhouse-replication`)
