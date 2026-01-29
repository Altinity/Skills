Analyze insert performance and part creation.

Use the `altinity-expert-clickhouse-ingestion` skill instructions in:
`../skills/altinity-expert-clickhouse-ingestion/SKILL.md`

Focus on the `altinity-expert-clickhouse-ingestion` database and report batch sizes, part creation rate, and any ingestion bottlenecks.

Connect using clickhouse-client with CLICKHOUSE_* env vars (use --secure if CLICKHOUSE_SECURE=1).
Include severity ratings, insert duration stats (avg/p95), and explicitly compare part creation rate vs rows inserted.
In the "Ingestion Overview", include total inserts, total rows, and total bytes written.
Explicitly cite system.part_log for new parts/merges evidence.
Include a section titled "Ingestion Overview".
