---
name: altinity-expert-clickhouse-logs
description: Analyze ClickHouse system log table health including TTL configuration, disk usage, freshness, and cleanup. Use for system log issues and TTL configuration.
---

# System Log Table Health

Analyze system log table health: TTL configuration, disk usage, freshness, and cleanup.

---

## Diagnostics

Run all queries from the file checks.sql and analyze the results.

---

## TTL Recommendations

| Log Table | Recommended TTL | Notes |
|-----------|----------------|-------|
| query_log | 7-30 days | Balance debugging vs disk |
| query_thread_log | Disable or 3 days | Very verbose |
| part_log | 14-30 days | Important for RCA |
| trace_log | 3-7 days | Large, mostly for debugging |
| text_log | 7-14 days | Important for debugging |
| metric_log | 7-14 days | Useful for trending |
| asynchronous_metric_log | 7-14 days | Low volume |
| crash_log | 90+ days | Rare, keep longer |

### Add TTL Example

```sql
-- Example: Add 14-day TTL to query_log
-- ALTER TABLE system.query_log MODIFY TTL event_date + INTERVAL 14 DAY;
```

### Force TTL Cleanup

```sql
-- Force TTL evaluation and cleanup
-- OPTIMIZE TABLE system.query_log FINAL;
-- Or: ALTER TABLE system.query_log MATERIALIZE TTL;
```

---

## Cross-Module Triggers

| Finding | Load Module | Reason |
|---------|-------------|--------|
| Logs filling disk | `altinity-expert-clickhouse-storage` | Disk space analysis |
| query_log missing data | `altinity-expert-clickhouse-overview` | Error summary + routing |
| High log volume | `altinity-expert-clickhouse-ingestion` | Batch sizing (affects part_log) |
| No query_log entries | `altinity-expert-clickhouse-overview` | System configuration |

---

## Settings Reference

| Setting | Notes |
|---------|-------|
| `log_queries` | Enable query_log |
| `log_queries_min_query_duration_ms` | Minimum duration to log |
| `log_queries_min_type` | Minimum query type to log |
| `query_log_database` | Database for query_log |
| `part_log_database` | Database for part_log |
| `text_log_level` | Minimum level for text_log |