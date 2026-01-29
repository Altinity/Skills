---
name: altinity-expert-clickhouse-merges
description: Diagnose ClickHouse merge performance, part backlog, and 'too many parts' errors. Use for merge issues and part management problems.
---

# Merge Performance and Part Management

Diagnose merge performance, backlog issues, and part management problems.

---

## Diagnostics

Run all queries from the file checks.sql and analyze the results.

---

## Problem-Specific Investigation

### "Too Many Parts" Error Investigation

For deep investigation of a specific table, use these ad-hoc queries:

```sql
-- Check part creation rate (should be < 1/second)
select
    toStartOfMinute(event_time) as minute,
    count() as new_parts,
    round(avg(rows)) as avg_rows_per_part
from system.part_log
where event_type = 'NewPart'
  and database = '{database}'
  and table = '{table}'
  and event_time > now() - interval 1 hour
group by minute
order by minute desc
limit 30
```

```sql
-- Check if merges are keeping up
select
    toStartOfMinute(event_time) as minute,
    countIf(event_type = 'NewPart') as new_parts,
    countIf(event_type = 'MergeParts') as merges,
    countIf(event_type = 'MergeParts') - countIf(event_type = 'NewPart') as net_reduction
from system.part_log
where database = '{database}'
  and table = '{table}'
  and event_time > now() - interval 1 hour
group by minute
order by minute desc
limit 30
```

**If `net_reduction` is negative consistently** → Inserts outpace merges. Solutions:
- Increase batch size
- Check `max_parts_to_merge_at_once` setting
- Verify sufficient CPU for background merges

---

## Ad-Hoc Query Guidelines

### Required Safeguards

```sql
-- Always include LIMIT
limit 100

-- Always time-bound historical queries
where event_date >= today() - 7

-- For part_log, always filter event_type
where event_type in ('NewPart', 'MergeParts', 'MutatePart')
```

### Safe Exploration Patterns

```sql
-- Discover available merge_reason values
select distinct merge_reason
from system.part_log
where event_type = 'MergeParts'
  and event_date = today()
limit 100

-- Check table engine
select
    database,
    name,
    engine,
    partition_key,
    sorting_key
from system.tables
where database = '{database}'
  and name = '{table}'
```

### Avoid
- `select * from system.part_log` → Huge, crashes context
- Queries without time bounds on `*_log` tables
- Joining large result sets in context (do aggregation in SQL)

---

## Cross-Module Triggers

| Finding | Load Module | Reason |
|---------|-------------|--------|
| Slow merges, normal disk | `altinity-expert-clickhouse-schema` | Check ORDER BY, partitioning |
| Slow merges, high disk IO | `altinity-expert-clickhouse-storage` | Storage bottleneck analysis |
| Merges blocked by mutations | `altinity-expert-clickhouse-mutations` | Stuck mutation investigation |
| High memory during merges | `altinity-expert-clickhouse-memory` | Memory limits, settings |
| Replication lag + merge issues | `altinity-expert-clickhouse-replication` | Replica queue analysis |

---

## Key Settings Reference

| Setting | Default | Impact |
|---------|---------|--------|
| `max_parts_to_merge_at_once` | 100 | Max parts in single merge |
| `number_of_free_entries_in_pool_to_lower_max_size_of_merge` | 8 | Throttles large merges when busy |
| `background_pool_size` | 16 | Merge threads |
| `parts_to_throw_insert` | 300 | Error threshold |
| `parts_to_delay_insert` | 150 | Delay threshold |
| `max_bytes_to_merge_at_max_space_in_pool` | 150GB | Max merge size |
