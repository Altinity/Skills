Analyze SELECT query performance.

Use the `altinity-expert-clickhouse-reporting` skill instructions in:
`../skills/altinity-expert-clickhouse-reporting/SKILL.md`

Connect using clickhouse-client with CLICKHOUSE_* env vars (use --secure if CLICKHOUSE_SECURE=1).

Focus on the `altinity-expert-clickhouse-reporting` database and identify slow or heavy queries from system.query_log.
Include at least two queries involving `reporting_events` with durations and read_bytes/rows.

Include severity ratings and a section explicitly named "Reporting Overview".
Include at least two tuning recommendations (ORDER BY/projection or aggregation/materialized view).
Explicitly mention the test database name `altinity-expert-clickhouse-reporting`.
