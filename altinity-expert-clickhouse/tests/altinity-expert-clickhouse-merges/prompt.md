Analyze merge performance and part management.

Use the `altinity-expert-clickhouse-merges` skill instructions in:
`../skills/altinity-expert-clickhouse-merges/SKILL.md`

Connect using clickhouse-client with CLICKHOUSE_* env vars (use --secure if CLICKHOUSE_SECURE=1).

Focus on the `altinity-expert-clickhouse-merges` database and identify part count/backlog issues. Include:
- Part count by partition for `merge_events`
- Evidence from `system.part_log` (NewPart vs MergeParts)
- Whether active merges are running
- Severity ratings and recommendations
