---
name: altinity-expert-clickhouse-mutations
description: Track and diagnose ClickHouse ALTER UPDATE, ALTER DELETE, and other mutation operations. Use for stuck mutations and mutation performance issues.
---

# Mutation Tracking and Analysis

Track and diagnose ALTER UPDATE, ALTER DELETE, and other mutation operations.

---

## Quick Diagnostics

### 1. Current Mutations Status

```sql
select
    database,
    table,
    mutation_id,
    command,
    create_time,
    is_done,
    parts_to_do,
    latest_failed_part,
    latest_fail_time,
    latest_fail_reason
from system.mutations
where not is_done
order by create_time
```

### 2. Mutation Summary by Table

```sql
select
    database,
    table,
    countIf(not is_done) as pending,
    countIf(is_done) as completed,
    countIf(latest_fail_reason != '') as failed,
    min(create_time) as oldest_pending
from system.mutations
group by database, table
having pending > 0
order by pending desc
```

### 3. Stuck Mutations Detection

```sql
with
    now() as current_time,
    dateDiff('minute', create_time, current_time) as age_minutes
select
    database,
    table,
    mutation_id,
    substring(command, 1, 60) as command,
    create_time,
    age_minutes,
    parts_to_do,
    multiIf(age_minutes > 1440, 'Critical', age_minutes > 360, 'Major', age_minutes > 60, 'Moderate', 'OK') as severity,
    latest_fail_reason
from system.mutations
where not is_done
  and age_minutes > 30
order by create_time
```

---

## Mutation History

### Recent Completed Mutations

```sql
select
    event_time,
    database,
    table,
    mutation_id,
    duration_ms,
    formatReadableSize(size_in_bytes) as size,
    rows,
    formatReadableSize(peak_memory_usage) as peak_memory
from system.part_log
where event_type = 'MutatePart'
  and event_date >= today() - 1
order by event_time desc
limit 30
```

### Mutation Performance by Table

```sql
select
    database,
    table,
    count() as mutations,
    round(avg(duration_ms)) as avg_ms,
    round(max(duration_ms)) as max_ms,
    formatReadableSize(sum(size_in_bytes)) as total_size,
    sum(rows) as total_rows
from system.part_log
where event_type = 'MutatePart'
  and event_date >= today() - 7
group by database, table
order by count() desc
limit 30
```

### Failed Mutations in Part Log

```sql
select
    event_time,
    database,
    table,
    part_name,
    duration_ms,
    error,
    exception
from system.part_log
where event_type = 'MutatePart'
  and error != 0
  and event_date >= today() - 7
order by event_time desc
limit 30
```

---

## Mutation Impact Analysis

### Mutations Running Now

```sql
select
    database,
    table,
    elapsed,
    progress,
    is_mutation,
    num_parts,
    formatReadableSize(total_size_bytes_compressed) as size,
    formatReadableSize(memory_usage) as memory,
    result_part_name
from system.merges
where is_mutation = 1
order by elapsed desc
```

### Parts Awaiting Mutation

```sql
select
    m.database,
    m.table,
    m.mutation_id,
    m.parts_to_do,
    m.command,
    (select count() from system.parts where database = m.database and table = m.table and active) as total_active_parts,
    round(100.0 * m.parts_to_do / total_active_parts, 1) as pct_remaining
from system.mutations m
where not m.is_done
order by m.parts_to_do desc
```

---

## Problem Investigation

### Why Is Mutation Stuck?

Check for competing operations:

```sql
-- Active merges on same table
select
    database,
    table,
    is_mutation,
    elapsed,
    progress,
    num_parts
from system.merges
where database = '{database}' and table = '{table}'
```

```sql
-- Replication queue for same table
select
    type,
    create_time,
    is_currently_executing,
    num_tries,
    last_exception
from system.replication_queue
where database = '{database}' and table = '{table}'
order by create_time
limit 20
```

```sql
-- Part mutations status
select
    name,
    active,
    mutation_version,
    modification_time
from system.parts
where database = '{database}' and table = '{table}'
order by mutation_version desc
limit 30
```

### Mutation vs Merge Competition

```sql
-- Check background pool saturation
select
    metric,
    value
from system.metrics
where metric like 'Background%'
```

Mutations and merges share the same pool. If pool is saturated, mutations wait.

---

## Mutation Rate Analysis

### Mutation Creation Rate

```sql
select
    toStartOfHour(create_time) as hour,
    count() as mutations_created,
    countIf(is_done) as completed,
    countIf(not is_done) as pending
from system.mutations
where create_time > now() - interval 7 day
group by hour
order by hour desc
```

**Red flag:** >1 mutation per 5 minutes sustained = mutation overload.

### Mutation Types

```sql
select
    multiIf(
        command ilike '%DELETE%', 'DELETE',
        command ilike '%UPDATE%', 'UPDATE',
        command ilike '%MATERIALIZE%', 'MATERIALIZE',
        command ilike '%DROP COLUMN%', 'DROP COLUMN',
        command ilike '%ADD COLUMN%', 'ADD COLUMN',
        command ilike '%MODIFY%', 'MODIFY',
        'OTHER'
    ) as mutation_type,
    count() as total,
    countIf(not is_done) as pending,
    countIf(latest_fail_reason != '') as failed
from system.mutations
group by mutation_type
order by total desc
```

---

## Canceling Mutations

To kill a stuck mutation:

```sql
-- Find mutation_id first
select mutation_id, command from system.mutations
where database = '{database}' and table = '{table}' and not is_done;

-- Then kill it
-- KILL MUTATION WHERE database = '{database}' AND table = '{table}' AND mutation_id = '{mutation_id}';
```

**Warning:** Killed mutations leave table in partially-mutated state.

---

## Best Practices

### Mutation Anti-Patterns

| Anti-Pattern | Problem | Solution |
|-------------|---------|----------|
| Frequent small UPDATEs | Creates many mutations | Batch updates together |
| DELETE without WHERE | Full table rewrite | Use TTL instead |
| UPDATE on high-cardinality column | Slow, lots of IO | Restructure data model |
| Many concurrent mutations | Queue builds up | Serialize mutations |

### Monitoring Mutations

Set alerts for:
- Mutations pending > 10
- Mutation age > 1 hour
- `latest_fail_reason` not empty

---

## Ad-Hoc Query Guidelines

### Required Safeguards
```sql
-- For part_log
where event_date >= today() - 7

limit 100
```

### Key Tables
- `system.mutations` - Current mutation state
- `system.part_log` (event_type = 'MutatePart') - Mutation history
- `system.merges` (is_mutation = 1) - Running mutations
- `system.replication_queue` - Pending replicated mutations

---

## Cross-Module Triggers

| Finding | Load Module | Reason |
|---------|-------------|--------|
| Mutation blocked by merge | `altinity-expert-clickhouse-merges` | Merge backlog |
| Mutation OOM | `altinity-expert-clickhouse-memory` | Memory limits |
| Mutation slow due to disk | `altinity-expert-clickhouse-storage` | IO bottleneck |
| Replicated mutation stuck | `altinity-expert-clickhouse-replication` | Replication issues |

---

## Settings Reference

| Setting | Notes |
|---------|-------|
| `mutations_sync` | 0=async, 1=wait current replica, 2=wait all |
| `max_mutations_in_flight` | Max concurrent mutations |
| `number_of_mutations_to_delay` | Delay INSERTs threshold |
| `number_of_mutations_to_throw` | Throw error threshold |
