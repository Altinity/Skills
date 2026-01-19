---
name: altinity-expert-clickhouse-schema
description: Analyze ClickHouse table structure, partitioning, ORDER BY keys, materialized views, and identify schema design anti-patterns. Use for table design issues and optimization.
---

# Table Schema and Design Analysis

Analyze table structure, partitioning, ORDER BY, materialized views, and identify design anti-patterns.

---

## Quick Audits (Run First)

These queries return severity-rated findings. Run relevant ones based on symptoms.

### 1. Partition Health Audit

```sql
with
    median(b) as median_partition_size_bytes,
    median(r) as median_partition_size_rows,
    count() as partition_count
select
    format('{}.{}', database, table) as object,
    multiIf(
        partition_count > 1500 and (median_partition_size_bytes < 16000000 or median_partition_size_rows < 250000), 'Critical',
        partition_count > 500 and (median_partition_size_bytes < 16000000 or median_partition_size_rows < 250000), 'Major',
        partition_count > 500 and (median_partition_size_bytes < 100000000 or median_partition_size_rows < 10000000), 'Moderate',
        partition_count > 100 and (median_partition_size_bytes < 16000000 or median_partition_size_rows < 250000), 'Moderate',
        partition_count > 1 and (median_partition_size_bytes < 16000000 or median_partition_size_rows < 250000), 'Minor',
        'OK'
    ) as severity,
    format('Partitions: {}, median size: {}, median rows: {}',
        toString(partition_count),
        formatReadableSize(median_partition_size_bytes),
        formatReadableQuantity(median_partition_size_rows)
    ) as details
from (
    select database, table, partition,
        sum(bytes_on_disk) as b,
        sum(rows) as r
    from system.parts
    where active and database not in ('system', 'INFORMATION_SCHEMA', 'information_schema')
    group by database, table, partition
)
group by database, table
having severity != 'OK'
order by
    multiIf(severity='Critical',1, severity='Major',2, severity='Moderate',3, 4),
    median_partition_size_bytes
limit 30
```

**Interpretation:**
- `Critical`: >1500 partitions with tiny median size - partitioning key too granular
- `Major`: >500 small partitions - consider coarser partitioning
- Ideal: Partitions 1-10GB each, hundreds not thousands of partitions

### 2. Oversized Partitions (for *MergeTree engines)

```sql
with
    (select max(toUInt64(value)) from system.merge_tree_settings where name = 'max_bytes_to_merge_at_max_space_in_pool') as max_merge_size,
    max(partition_bytes) as max_partition_bytes
select
    format('{}.{}', database, table) as object,
    multiIf(
        max_partition_bytes > max_merge_size * 0.95, 'Critical',
        max_partition_bytes > max_merge_size * 0.75, 'Major',
        max_partition_bytes > max_merge_size * 0.55, 'Moderate',
        'Minor'
    ) as severity,
    format('Max partition: {} (limit: {})',
        formatReadableSize(max_partition_bytes),
        formatReadableSize(max_merge_size)
    ) as details
from (
    select database, table, partition, sum(bytes_on_disk) as partition_bytes
    from system.parts
    where active
      and database not in ('system', 'INFORMATION_SCHEMA', 'information_schema')
      and (database, table) in (
          select database, name from system.tables
          where engine like '%Aggregating%' or engine like '%Collapsing%'
             or engine like '%Summing%' or engine like '%Replacing%' or engine like '%Graphite%'
      )
    group by database, table, partition
)
group by database, table
having max_partition_bytes > max_merge_size * 0.33 and max_partition_bytes > 20000000000
order by max_partition_bytes desc
limit 20
```

**Why it matters:** Aggregating/Replacing/etc engines need to merge entire partitions to collapse rows. Oversized partitions = incomplete deduplication.

### 3. Primary Key Analysis

```sql
with
    tables as (
        select format('{}.{}', database, name) as object,
            splitByChar(',', primary_key)[1] as pkey,
            total_rows
        from system.tables
        where engine like '%MergeTree' and total_rows > 10000000
    ),
    columns as (
        select format('{}.{}', database, table) as object,
            name, type,
            data_compressed_bytes / nullIf(data_uncompressed_bytes, 0) as ratio
        from system.columns
    )
select
    tables.object,
    'Minor' as severity,
    concat('First PK column (', pkey, ') issue: ',
        multiIf(
            pkey ilike '%id%', 'appears to be an ID (high cardinality)',
            type in ('UUID','UInt64','Int64','IPv4','IPv6','UInt32','Int32','UInt128') or type like 'DateTime%',
                concat('wide datatype (', type, ')'),
            ratio > 0.5, concat('poor compression (', toString(round(ratio, 2)), ')'),
            'unknown'
        )
    ) as details,
    round(ratio, 3) as compression_ratio
from tables
join columns on tables.object = columns.object and tables.pkey = columns.name
where ratio > 0.5 or pkey ilike '%id%'
   or type in ('UUID','UInt64','Int64','IPv4','IPv6','UInt32','Int32','UInt128')
   or type like 'DateTime%'
order by tables.total_rows desc
limit 30
```

**Red flags:**
- First ORDER BY column is high-cardinality ID → poor data locality
- Wide datatypes (UUID, DateTime64) → bloated primary key index
- Poor compression on PK column → indicates high cardinality

### 4. Column Count Check

```sql
with count() as columns
select
    object,
    multiIf(columns > 1500, 'Critical', columns > 1000, 'Major', columns > 800, 'Moderate', 'Minor') as severity,
    format('Too many columns: {}', toString(columns)) as details
from (
    select format('{}.{}', database, table) as object, column
    from system.parts_columns
    where modification_time > now() - interval 5 day
      and database not in ('system', 'INFORMATION_SCHEMA', 'information_schema')
    limit 1 by object, column
)
group by object
having columns > 600
order by columns desc
```

### 5. Nullable Columns Audit

```sql
with
    countIf(type like '%Nullable%') as nullable_columns,
    count() as total_columns
select
    format('{}.{}', database, table) as object,
    'Minor' as severity,
    format('Nullable columns: {} of {} ({}%)',
        toString(nullable_columns),
        toString(total_columns),
        toString(round(100.0 * nullable_columns / total_columns, 1))
    ) as details
from system.columns
where database not in ('system', 'information_schema', 'INFORMATION_SCHEMA')
group by database, table
having nullable_columns > 0.1 * total_columns or nullable_columns > 10
order by nullable_columns desc
limit 30
```

**Why avoid Nullable:** Storage overhead, query complexity, NULL handling bugs.

### 6. Long Names Check

```sql
select
    format('{}.{}', database, name) as object,
    multiIf(length(name) > 196, 'Critical', length(name) > 128, 'Major', length(name) > 64, 'Moderate', 'Minor') as severity,
    format('Table name too long: {} chars', toString(length(name))) as details
from system.tables
where length(name) > 32

union all

select
    format('{}.{}.{}', database, table, name) as object,
    multiIf(length(name) > 196, 'Critical', length(name) > 128, 'Major', length(name) > 64, 'Moderate', 'Minor') as severity,
    format('Column name too long: {} chars', toString(length(name))) as details
from system.columns
where length(name) > 32

order by severity, object
limit 50
```

---

## Materialized View Audits

### MV Design Issues

```sql
select
    format('{}.{}', database, name) as object,
    multiIf(
        create_table_query ilike '%JOIN%', 'Moderate - JOIN in MV (only left table triggers updates)',
        splitByChar(' ', create_table_query)[5] != 'TO', 'Moderate - TO syntax not used (implicit target table)',
        'OK'
    ) as issue
from system.tables
where engine = 'MaterializedView'
  and issue != 'OK'
```

### MV Dependency Chain

```sql
with count() as deps
select
    referenced_database || '.' || referenced_table as parent_object,
    'Moderate' as severity,
    format('Long dependency chain: {} dependents', toString(deps)) as details
from system.tables t
array join arrayConcat(dependencies_database, [database]) as referenced_database,
           arrayConcat(dependencies_table, [name]) as referenced_table
where length(dependencies_table) > 0
group by referenced_database, referenced_table
having deps > 10
order by deps desc
```

---

## Diagnostic Queries

### Table Overview

```sql
select
    database,
    name,
    engine,
    partition_key,
    sorting_key,
    primary_key,
    total_rows,
    formatReadableSize(total_bytes) as size,
    formatReadableSize(total_bytes / nullIf(total_rows, 0)) as avg_row_size
from system.tables
where database not in ('system', 'INFORMATION_SCHEMA', 'information_schema')
  and engine like '%MergeTree%'
order by total_bytes desc
limit 50
```

### Partition Distribution

```sql
select
    database,
    table,
    count() as partitions,
    sum(rows) as total_rows,
    formatReadableSize(sum(bytes_on_disk)) as total_size,
    formatReadableSize(median(bytes_on_disk)) as median_partition_size,
    min(partition) as oldest_partition,
    max(partition) as newest_partition
from system.parts
where active and database = '{database}' and table = '{table}'
group by database, table, partition
order by partition desc
limit 100
```

### Column Compression Analysis

```sql
select
    name,
    type,
    formatReadableSize(data_compressed_bytes) as compressed,
    formatReadableSize(data_uncompressed_bytes) as uncompressed,
    round(data_uncompressed_bytes / nullIf(data_compressed_bytes, 0), 2) as ratio,
    compression_codec
from system.columns
where database = '{database}' and table = '{table}'
order by data_compressed_bytes desc
limit 50
```

**Look for:**
- Columns with ratio < 2 → consider better codec or data transformation
- Large columns without codec → add CODEC(ZSTD) or LZ4HC
- String columns with low cardinality → consider LowCardinality(String)

### Index Usage Analysis

```sql
select
    database,
    table,
    name as index_name,
    type,
    expr,
    granularity
from system.data_skipping_indices
where database = '{database}'
order by database, table
```

---

## Schema Design Recommendations

### Partition Key Guidelines

| Data Volume | Recommended Granularity | Example |
|-------------|------------------------|---------|
| < 10GB/month | No partitioning or yearly | `toYear(ts)` |
| 10-100GB/month | Monthly | `toYYYYMM(ts)` |
| 100GB-1TB/month | Weekly or daily | `toMonday(ts)` |
| > 1TB/month | Daily | `toDate(ts)` |

### ORDER BY Guidelines

1. **First column**: Low cardinality, frequently filtered (e.g., `tenant_id`, `region`)
2. **Second column**: Time-based if range queries common
3. **Subsequent**: Other filter columns by selectivity (most selective last)

**Anti-patterns:**
- UUID/hash as first column
- High-cardinality ID without tenant prefix
- DateTime64 with microseconds as first column

### Compression Codec Recommendations

| Data Type | Recommended Codec |
|-----------|-------------------|
| Integers (sequential) | `Delta, ZSTD` |
| Integers (random) | `ZSTD` or `LZ4HC` |
| Floats | `Gorilla, ZSTD` |
| Timestamps | `DoubleDelta, ZSTD` |
| Strings (long) | `ZSTD(3)` |
| Strings (repetitive) | `LowCardinality` + `ZSTD` |

---

## Cross-Module Triggers

| Finding | Load Module | Reason |
|---------|-------------|--------|
| Many small partitions | `altinity-expert-clickhouse-ingestion` | Check batch sizing |
| Oversized partitions | `altinity-expert-clickhouse-merges` | Merge can't complete |
| High PK memory | `altinity-expert-clickhouse-memory` | Memory pressure |
| MV performance issues | `altinity-expert-clickhouse-reporting` | Query analysis |
| Too many parts per partition | `altinity-expert-clickhouse-merges` | Merge backlog |

---

## Settings Reference

```sql
-- Check table-level settings
select name, value, changed, description
from system.merge_tree_settings
where name in (
    'index_granularity',
    'min_bytes_for_wide_part',
    'min_rows_for_wide_part',
    'ttl_only_drop_parts',
    'max_bytes_to_merge_at_max_space_in_pool'
)
```

| Setting | Default | Recommendation |
|---------|---------|----------------|
| `index_granularity` | 8192 | Lower for point lookups, higher for scans |
| `ttl_only_drop_parts` | 0 | Set to 1 if TTL deletes entire partitions |
| `min_bytes_for_wide_part` | 10MB | Increase if many small parts |
