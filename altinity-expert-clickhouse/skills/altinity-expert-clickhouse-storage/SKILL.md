---
name: altinity-expert-clickhouse-storage
description: Diagnose ClickHouse disk usage, compression efficiency, part sizes, and storage bottlenecks. Use for disk space issues and slow IO.
---

# Storage and Disk Usage Analysis

Diagnose disk usage, compression efficiency, part sizes, and storage bottlenecks.

---

## Quick Diagnostics

### 1. Disk Space Audit

```sql
select
    name as disk_name,
    path,
    type,
    formatReadableSize(total_space) as total,
    formatReadableSize(free_space) as free,
    formatReadableSize(unreserved_space) as unreserved,
    round(100.0 * (total_space - free_space) / total_space, 1) as used_pct,
    multiIf(used_pct > 90, 'Critical', used_pct > 85, 'Major', used_pct > 80, 'Moderate', 'OK') as severity
from system.disks
order by used_pct desc
```

### 2. Storage by Database

```sql
select
    database,
    count() as tables,
    sum(total_rows) as total_rows,
    formatReadableSize(sum(total_bytes)) as total_size,
    formatReadableSize(sum(total_bytes) / nullIf(sum(total_rows), 0)) as avg_row_size
from system.tables
where engine like '%MergeTree%'
group by database
order by sum(total_bytes) desc
```

### 3. Top Tables by Size

```sql
select
    database,
    name,
    engine,
    formatReadableSize(total_bytes) as size,
    formatReadableSize(total_rows) as rows,
    formatReadableSize(total_bytes / nullIf(total_rows, 0)) as avg_row_size,
    (select count() from system.parts where database = t.database and table = t.name and active) as parts
from system.tables t
where engine like '%MergeTree%'
order by total_bytes desc
limit 30
```

### 4. Disk Usage by Path

```sql
select
    substr(path, 1, position(path, '/store/')) as disk_path,
    formatReadableSize(sum(bytes_on_disk)) as used,
    count() as parts,
    uniq(database, table) as tables
from system.parts
where active
group by disk_path
order by sum(bytes_on_disk) desc
```

---

## Compression Analysis

### Overall Compression Ratio

```sql
select
    formatReadableSize(sum(data_compressed_bytes)) as compressed,
    formatReadableSize(sum(data_uncompressed_bytes)) as uncompressed,
    round(sum(data_uncompressed_bytes) / nullIf(sum(data_compressed_bytes), 0), 2) as ratio
from system.columns
where database not in ('system', 'INFORMATION_SCHEMA', 'information_schema')
```

### Compression by Table

```sql
select
    database,
    table,
    formatReadableSize(sum(data_compressed_bytes)) as compressed,
    formatReadableSize(sum(data_uncompressed_bytes)) as uncompressed,
    round(sum(data_uncompressed_bytes) / nullIf(sum(data_compressed_bytes), 0), 2) as ratio,
    if(ratio < 2, 'Poor', if(ratio < 5, 'OK', 'Good')) as compression_quality
from system.columns
where database not in ('system', 'INFORMATION_SCHEMA', 'information_schema')
group by database, table
having sum(data_compressed_bytes) > 100000000  -- > 100MB
order by sum(data_compressed_bytes) desc
limit 30
```

### Columns with Poor Compression

```sql
select
    database,
    table,
    name as column,
    type,
    compression_codec,
    formatReadableSize(data_compressed_bytes) as compressed,
    formatReadableSize(data_uncompressed_bytes) as uncompressed,
    round(data_uncompressed_bytes / nullIf(data_compressed_bytes, 0), 2) as ratio
from system.columns
where database not in ('system', 'INFORMATION_SCHEMA', 'information_schema')
  and data_compressed_bytes > 100000000  -- > 100MB
  and data_uncompressed_bytes / nullIf(data_compressed_bytes, 0) < 2
order by data_compressed_bytes desc
limit 30
```

**Solutions for poor compression:**
- Add explicit codec: `CODEC(ZSTD(3))`
- For sequential integers: `CODEC(Delta, ZSTD)`
- For timestamps: `CODEC(DoubleDelta, ZSTD)`
- For low-cardinality strings: `LowCardinality(String)`

---

## Part Size Analysis

### Part Size Distribution

```sql
select
    database,
    table,
    count() as parts,
    formatReadableSize(min(bytes_on_disk)) as min_part,
    formatReadableSize(median(bytes_on_disk)) as median_part,
    formatReadableSize(max(bytes_on_disk)) as max_part,
    formatReadableSize(sum(bytes_on_disk)) as total_size
from system.parts
where active and database not in ('system', 'INFORMATION_SCHEMA', 'information_schema')
group by database, table
order by sum(bytes_on_disk) desc
limit 30
```

### Small Parts Detection

```sql
select
    database,
    table,
    countIf(bytes_on_disk < 1000000) as tiny_parts_under_1mb,
    countIf(bytes_on_disk < 10000000) as small_parts_under_10mb,
    count() as total_parts,
    round(100.0 * countIf(bytes_on_disk < 10000000) / count(), 1) as small_pct
from system.parts
where active and database not in ('system', 'INFORMATION_SCHEMA', 'information_schema')
group by database, table
having small_pct > 50 and count() > 10
order by small_pct desc
limit 30
```

### Wide vs Compact Parts

```sql
select
    database,
    table,
    countIf(part_type = 'Wide') as wide_parts,
    countIf(part_type = 'Compact') as compact_parts,
    countIf(part_type = 'InMemory') as memory_parts,
    formatReadableSize(sumIf(bytes_on_disk, part_type = 'Wide')) as wide_size,
    formatReadableSize(sumIf(bytes_on_disk, part_type = 'Compact')) as compact_size
from system.parts
where active
group by database, table
having wide_parts > 0 or compact_parts > 0
order by wide_parts + compact_parts desc
limit 30
```

---

## IO Analysis

### Disk IO Metrics

```sql
select
    metric,
    value,
    description
from system.asynchronous_metrics
where metric like '%Disk%' or metric like '%IO%' or metric like '%Read%' or metric like '%Write%'
order by metric
```

### Recent IO Activity from Query Log

```sql
select
    toStartOfFiveMinutes(event_time) as ts,
    count() as queries,
    formatReadableSize(sum(read_bytes)) as read_bytes,
    formatReadableSize(sum(written_bytes)) as written_bytes,
    sum(read_rows) as read_rows,
    sum(written_rows) as written_rows
from system.query_log
where type = 'QueryFinish'
  and event_time > now() - interval 1 hour
group by ts
order by ts desc
```

### Queries with High IO

```sql
select
    query_id,
    user,
    formatReadableSize(read_bytes) as read_bytes,
    formatReadableSize(written_bytes) as written_bytes,
    round(query_duration_ms / 1000, 1) as duration_sec,
    substring(query, 1, 80) as query_preview
from system.query_log
where type = 'QueryFinish'
  and event_date = today()
order by read_bytes + written_bytes desc
limit 20
```

---

## System Logs Disk Usage

```sql
with
    sum(bytes_on_disk) as log_bytes,
    (select arrayMin([free_space, unreserved_space]) from system.disks where name = 'default' limit 1) as free_bytes,
    log_bytes / (log_bytes + free_bytes) as ratio
select
    table,
    formatReadableSize(sum(bytes_on_disk)) as size,
    count() as parts,
    round(100.0 * sum(bytes_on_disk) / log_bytes, 1) as pct_of_logs
from system.parts
where database = 'system' and table like '%_log' and active
group by table
order by sum(bytes_on_disk) desc
```

**Check:** If system logs > 5% of disk, add TTL or reduce retention.

---

## Detached Parts

```sql
select
    database,
    table,
    reason,
    count() as count,
    formatReadableSize(sum(bytes_on_disk)) as size
from system.detached_parts
group by database, table, reason
order by sum(bytes_on_disk) desc
```

**Common reasons:**
- `broken` - Data corruption
- `noquorum` - Replication quorum not reached
- `unexpected` - Orphaned after failed operation
- `clone` - Leftover from ATTACH

---

## Storage Policies

```sql
select
    policy_name,
    volume_name,
    volume_priority,
    disks,
    max_data_part_size,
    move_factor
from system.storage_policies
order by policy_name, volume_priority
```

### Tables by Storage Policy

```sql
select
    storage_policy,
    count() as tables,
    formatReadableSize(sum(total_bytes)) as total_size
from system.tables
where engine like '%MergeTree%'
group by storage_policy
order by sum(total_bytes) desc
```

---

## Problem Investigation

### Disk Filling Up

```sql
-- What's growing fastest?
select
    database,
    table,
    count() as new_parts,
    formatReadableSize(sum(bytes_on_disk)) as new_data
from system.parts
where modification_time > now() - interval 1 hour
  and active
group by database, table
order by sum(bytes_on_disk) desc
limit 20
```

### Slow Disk Detection

```sql
-- Check merge speeds as proxy for disk performance
select
    database,
    table,
    count() as merges,
    round(avg(duration_ms)) as avg_ms,
    formatReadableSize(sum(size_in_bytes)) as merged_bytes,
    round(sum(size_in_bytes) / nullIf(sum(duration_ms), 0) * 1000) as bytes_per_sec,
    formatReadableSize(bytes_per_sec) as speed
from system.part_log
where event_type = 'MergeParts'
  and event_date = today()
group by database, table
having count() > 5
order by bytes_per_sec asc
limit 20
```

---

## Ad-Hoc Query Guidelines

### Required Safeguards
```sql
-- Always limit results
limit 100

-- For part_log
where event_date >= today() - 1
```

### Key Tables
- `system.disks` - Disk configuration
- `system.parts` - Part storage details
- `system.columns` - Column compression
- `system.storage_policies` - Tiered storage
- `system.detached_parts` - Orphaned parts

---

## Cross-Module Triggers

| Finding | Load Module | Reason |
|---------|-------------|--------|
| Poor compression | `altinity-expert-clickhouse-schema` | Codec recommendations |
| Many small parts | `altinity-expert-clickhouse-merges` | Merge backlog |
| High write IO | `altinity-expert-clickhouse-ingestion` | Batch sizing |
| System logs large | `altinity-expert-clickhouse-logs` | TTL configuration |
| Slow disk + merges | `altinity-expert-clickhouse-merges` | Merge optimization |

---

## Settings Reference

| Setting | Notes |
|---------|-------|
| `min_bytes_for_wide_part` | Threshold for Wide vs Compact parts |
| `min_rows_for_wide_part` | Row threshold for Wide parts |
| `max_bytes_to_merge_at_max_space_in_pool` | Max merge size |
| `prefer_not_to_merge` | Disable merges (emergency) |
