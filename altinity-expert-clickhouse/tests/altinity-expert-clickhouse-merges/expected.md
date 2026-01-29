## Expected Findings

### Must Detect
- [ ] **High part count** for `merge_events` (many parts in same partition)
- [ ] **No active merges** for `merge_events` (system.merges empty or 0 merges)
- [ ] **NewPart without MergeParts** in recent part_log
- [ ] **Merge backlog risk** due to inserts outpacing merges (merges stopped)

### Should Detect
- [ ] **Part log evidence** of NewPart events
- [ ] **Recommendation** to increase batch size or enable merges
- [ ] **Settings recommendation** (e.g., max_parts_to_merge_at_once or parts_to_delay_insert)

### Report Structure
- [ ] Merge overview section
- [ ] Severity ratings present
- [ ] Test database mentioned (`altinity-expert-clickhouse-merges`)
