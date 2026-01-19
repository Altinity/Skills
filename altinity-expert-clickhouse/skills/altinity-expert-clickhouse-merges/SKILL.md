---
name: altinity-expert-clickhouse-merges
description: Diagnose ClickHouse merge performance, part backlog, and 'too many parts' errors. Use for merge issues and part management problems.
---

# Merge Performance and Part Management

Diagnose merge performance, backlog issues, and part management problems.

---

## Quick Diagnostics (Run First)

Execute these standard queries before ad-hoc exploration.

### 1. Current Merge Activity

```sql
select
    database,
    table,
    round(elapsed, 1) as elapsed_sec,
    round(progress * 100, 1) as progress_pct,
    num_parts,
    formatReadableSize(total_size_bytes_compressed) as size,
    result_part_name,
    is_mutation
from system.merges
order by elapsed desc
limit 20
```

**Interpretation:**
- `elapsed > 3600` (1 hour) → Investigate large parts or slow storage
- `num_parts > 100` → Merge backlog, check part creation rate
- `is_mutation = 1` → This is a mutation, not a regular merge

### 2. Part Count Health Check

```sql
select
    database,
    table,
    partition_id,
    count() as part_count,
    sum(rows) as total_rows,
    formatReadableSize(sum(bytes_on_disk)) as size
from system.parts
where active
group by database, table, partition_id
having part_count > 50
order by part_count desc
limit 30
```

**Red flags:**
- `part_count > 300` → Approaching "too many parts" error threshold
- Many partitions with high counts → Ingestion batching problem

### 3. Recent Merge History (Last Hour)

```sql
select
    database,
    table,
    toStartOfFiveMinutes(event_time) as ts,
    count() as merge_count,
    sum(rows) as rows_merged,
    round(avg(duration_ms)) as avg_duration_ms,
    round(max(duration_ms)) as max_duration_ms
from system.part_log
where event_type = 'MergeParts'
  and event_time > now() - interval 1 hour
group by database, table, ts
order by ts desc, merge_count desc
limit 50
```

### 4. Merge Reasons Breakdown

```sql
select
    database,
    table,
    merge_reason,
    count() as merge_count,
    round(avg(duration_ms)) as avg_ms,
    sum(rows) as total_rows
from system.part_log
where event_type = 'MergeParts'
  and event_date = today()
group by database, table, merge_reason
order by merge_count desc
limit 30
```

**Merge reasons:**
- `RegularMerge` → Normal background merges
- `TTLDeleteMerge` → TTL expiration triggered
- `TTLRecompressMerge` → TTL recompression
- `MutationMerge` → ALTER UPDATE/DELETE

---

## Problem-Specific Queries

### "Too Many Parts" Error Investigation

Run in sequence:

```sql
-- Step 1: Find the problematic table
select
    database,
    table,
    count() as active_parts,
    uniq(partition_id) as partitions
from system.parts
where active
group by database, table
order by active_parts desc
limit 10
```

```sql
-- Step 2: Check part creation rate (should be < 1/second)
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
-- Step 3: Check if merges are keeping up
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

### Slow Merge Investigation

```sql
-- Find slowest merges
select
    event_time,
    database,
    table,
    partition_id,
    duration_ms,
    formatReadableSize(size_in_bytes) as size,
    rows,
    part_name,
    merge_reason
from system.part_log
where event_type = 'MergeParts'
  and event_date >= today() - 1
order by duration_ms desc
limit 20
```

**Correlate with storage (load `altinity-expert-clickhouse-storage`):**
- Slow merges + high disk IO → Storage bottleneck
- Slow merges + normal disk → Large parts, consider partitioning

### Failed Merges

```sql
select
    event_time,
    database,
    table,
    part_name,
    error,
    exception
from system.part_log
where event_type = 'MergeParts'
  and error != 0
  and event_date >= today() - 7
order by event_time desc
limit 50
```

---

## Ad-Hoc Query Guidelines

When standard queries don't answer the question, follow these rules:

### Required Safeguards

```sql
-- Always include LIMIT
limit 100  -- default, increase only if needed

-- Always time-bound historical queries
where event_date >= today() - 7
-- or
where event_time > now() - interval 24 hour

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

-- Check table engine (merges behave differently by engine)
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

After merge analysis, consider loading:

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

Query current values:
```sql
select name, value, changed, description
from system.merge_tree_settings
where name in (
    'max_parts_to_merge_at_once',
    'parts_to_throw_insert',
    'parts_to_delay_insert'
)
```
