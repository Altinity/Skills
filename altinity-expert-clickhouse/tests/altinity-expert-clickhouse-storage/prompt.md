Analyze storage usage and compression.

Use the `altinity-expert-clickhouse-storage` skill instructions in:
`../skills/altinity-expert-clickhouse-storage/SKILL.md`

Focus on the `altinity-expert-clickhouse-storage` database and report compression ratios, top tables, and small-part issues.

Connect using clickhouse-client with CLICKHOUSE_* env vars (use --secure if CLICKHOUSE_SECURE=1).
Include disk usage summary from system.disks and severity ratings.
Include overall compression ratio from system.columns.
Include at least two recommendations for improving compression or reducing small parts.
