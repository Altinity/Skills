Run a system health overview.

Use the `altinity-expert-clickhouse-overview` skill instructions in:
`../skills/altinity-expert-clickhouse-overview/SKILL.md`

Focus on the test workload in `altinity-expert-clickhouse-overview` database and summarize object counts, resource utilization, and any findings. Use a last-24-hours timeframe for `system.errors` and `system.*_log` summaries.

Include severity ratings and explicitly mention the test database name.
Include log TTL status from system log tables and a short `system.errors` + `system.*_log` activity summary for the timeframe.
Include version age check and warnings (system.warnings), even if OK.
