## Expected Findings

### Must Detect
- [ ] **Dictionary present**: `user_dict` is listed in system.dictionaries.
- [ ] **Dictionary memory usage**: Report bytes allocated for `user_dict`.
- [ ] **Dictionary status**: Status is LOADED/OK with no error.

### Should Detect
- [ ] **Total dictionary memory** as % of RAM
- [ ] **Total RAM** reported
- [ ] **Dictionary element count** for `user_dict`

### Report Structure
- [ ] Dictionary overview section
- [ ] Severity ratings present
- [ ] Test database mentioned (`altinity-expert-clickhouse-dictionaries`)
