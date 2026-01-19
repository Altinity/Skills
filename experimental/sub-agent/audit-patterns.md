# Analysis of Existing Audit System

## Architecture Insights

Your audit system follows a **declarative audit pattern**:
1. Run queries that evaluate conditions
2. Insert findings into `audit_results` table with severity classification
3. Structured output: `id`, `object`, `severity`, `details`, `values` (map for metrics)

This is powerful because:
- Results are queryable/filterable
- Severity levels enable prioritization
- `values` map preserves numeric data for dashboards/trending
- Idempotent execution (can re-run audits)

---

## Key Patterns to Incorporate

### 1. Severity Classification Logic
Your `multiIf` chains define clear thresholds:
```sql
multiIf(count > 2000, 'Critical', count > 900, 'Major', count > 200, 'Moderate', 'None')
```

**Incorporate into skills:** Each module should define threshold tables for its domain.

### 2. Ratio-Based Checks (not just absolutes)
You check ratios against system capacity, not just raw numbers:
- Parts vs max_parts_in_total
- Cache size vs total RAM
- Used disk vs total disk
- Memory tables vs OSMemoryTotal

**Principle:** Context-aware thresholds are more reliable than fixed numbers.

### 3. Time-Decay Analysis
Your `old_parts_lifetime` usage to calculate parts creation rate:
```sql
parts_created_count / old_parts_lifetime as parts_created_per_second
```

**Incorporate:** Use system settings as time windows for rate calculations.

### 4. Cross-Table Correlation
Example: Checking part files vs available inodes:
```sql
column_files_in_parts_count / total_inodes as ratio
```

**Incorporate:** Modules should correlate across system tables.

### 5. Version-Aware Recommendations
The `A2.1_obsolete_versions.sql` fetches live data from GitHub to compare versions.

**Incorporate:** Skills can reference external sources for recommendations.

---

## Extracted Check Categories

### A0: System-Level Health
| Check ID | What It Detects | Thresholds |
|----------|-----------------|------------|
| A0.0.6 | Long names (db/table/column) | >64 Moderate, >128 Major, >196 Critical |
| A0.1.01 | Too many replicated tables | >200 Moderate, >900 Major, >2000 Critical |
| A0.1.02 | Too many MergeTree tables | >1000 Moderate, >3000 Major, >10000 Critical |
| A0.1.03 | Too many databases | >100 Moderate, >300 Major, >1000 Critical |
| A0.1.04 | Parts columns vs inodes | >60% Moderate, >70% Major, >80% Critical |
| A0.1.05 | Total parts count | >60K Moderate, >90K Major, >120K Critical |
| A0.1.06 | Obsolete inactive parts | >500 Moderate, >2000 Major, >5000 Critical |
| A0.1.07 | Too many tiny tables | >85% tiny/small = Major |
| A0.2.* | System log health | TTL, freshness, disk usage |
| A0.3.* | Part creation rates | >10/sec Moderate, >30 Major, >50 Critical |

### A1: Storage & Parts
| Check ID | What It Detects | Key Insight |
|----------|-----------------|-------------|
| A1.1.01 | Small partitions | Median size < 16MB or 250K rows |
| A1.1.03 | Oversized partitions | >max_bytes_to_merge threshold |
| A1.1.05 | Too fast inserts | >1/sec per table |
| A1.1.06 | Wide rows | >3KB avg row size |
| A1.1.07 | Detached parts | Orphaned data |
| A1.2.* | Mark cache health | Hit ratio, memory ratio |
| A1.4.* | Background pools | Load ratio vs capacity |
| A1.5.* | Uncompressed cache | Hit ratio, size ratio |
| A1.6.* | Replication queue | Backlog, age, stalled tasks |
| A1.7.* | Memory allocation | Dictionaries + memory tables vs RAM |
| A1.8.* | Disk space | Free space ratio |

### A2: Schema Design
| Check ID | What It Detects | Recommendation |
|----------|-----------------|----------------|
| A2.1.* | Old ClickHouse version | Upgrade path |
| A2.2 | MV without TO syntax | Use explicit target table |
| A2.3 | MV with JOIN | Avoid JOINs in MVs |
| A2.3 | Long dependency chains | >10 dependencies |
| A2.4.01 | Poor PK choice | ID-like, wide types, bad compression |
| A2.4.02 | Excessive Nullables | >10% nullable columns |
| A2.4.03 | No compression codecs | Consider codecs for heavy columns |

### A3: Runtime Metrics
| Check ID | What It Detects | Thresholds |
|----------|-----------------|------------|
| A3.0.1 | Running queries | vs max_concurrent_queries |
| A3.0.2 | Connections | vs max_connections |
| A3.0.3 | Readonly replicas | Any = Critical |
| A3.0.4 | Block in-flight ops | >200 Moderate, >245 Major |
| A3.0.5 | Load average | vs CPU count |
| A3.0.6 | Replica delay | >30min Moderate, >3h Major, >24h Critical |
| A3.0.7-12 | Queue sizes | Inserts, merges, tasks in queue |
| A3.0.14 | MaxPartCountForPartition | vs parts_to_delay/throw |
| A3.0.15 | Memory resident | >80% Major, >90% Critical |
| A3.0.16 | Memory by other processes | vs max_server_memory_usage_to_ram_ratio |

---

## Advanced Queries Worth Preserving

### 1. RAM Usage Retrospection (from ate_memory.sql)
Reconstructs memory timeline from query_log + part_log:
```sql
-- Shows memory peaks by operation type over time
-- Uses window functions to track cumulative memory
```

### 2. Insert Rate with Lag Analysis (from A1_1_partitions.sql)
```sql
dateDiff(second, lagInFrame(modification_time) OVER (...), modification_time) as lag
```

### 3. Version Comparison with Live Data (from A2_1_obsolete_versions.sql)
Fetches from GitHub, computes bugfixes_behind using window functions.

### 4. Partition Size Distribution (from A1_1_partitions.sql)
Uses `median()` to assess typical partition size, not just max.

---

## Suggested Module Mapping

Based on your audit files, here's how they map to the proposed modules:

| Audit File | Target Module(s) |
|------------|------------------|
| A0_0_long_names | `schema.md` |
| A0_1_system_counts | `overview.md` (new), `schema.md` |
| A0_2_system_logs | `logs.md` (new - system log health) |
| A0_3_rates | `ingestion.md`, `merges.md` |
| A1_1_partitions | `schema.md`, `ingestion.md` |
| A1_2_marks | `caches.md` (new) |
| A1_3_tables | `schema.md` |
| A1_4_pools | `pools.md` (new) or `overview.md` |
| A1_5_uncompressed_cache | `caches.md` |
| A1_6_replication_queue | `replication.md` |
| A1_7_memory | `memory.md` |
| A1_8_disk | `storage.md` |
| A2_1_obsolete_versions | `versions.md` (new) or `overview.md` |
| A2_2_mat_views | `schema.md` |
| A2_3_dependencies | `schema.md` |
| A2_4_primary_key | `schema.md` |
| A3_0_metrics | `metrics.md` (new) - real-time health |
| ate_cpu | `reporting.md`, `merges.md`, `mutations.md` |
| ate_memory | `memory.md` |

---

## New Modules to Add

Based on your audit system, I recommend adding:

1. **`overview.md`** - System-wide health check entry point
   - Table/database/part counts
   - Version check
   - Pool status
   - Quick severity summary

2. **`caches.md`** - Mark cache, uncompressed cache, query cache
   - Hit ratios
   - Size vs RAM
   - Recommendations

3. **`logs.md`** - System log table health
   - TTL configuration
   - Disk usage by logs
   - Freshness checks
   - Leftover *_logN tables

4. **`metrics.md`** - Real-time async/sync metrics
   - Load average
   - Connections
   - Queue sizes
   - Replica delays

5. **`versions.md`** - Version analysis
   - Current version age
   - Bugfixes behind
   - Upgrade recommendations

---

## Severity Framework to Standardize

Adopt consistent severity definitions across all modules:

| Severity | Meaning | Action |
|----------|---------|--------|
| Critical | Immediate risk of failure/data loss | Fix now |
| Major | Significant performance/stability impact | Fix this week |
| Moderate | Suboptimal, will degrade over time | Plan fix |
| Minor | Best practice violation, low impact | Nice to have |
| None | Passes check | No action |

---

## Ideas for Hybrid Query Structure

### Predefined Audit Queries
Each module includes queries that output severity-rated findings:
```sql
-- In module, marked as "Audit Query"
-- Returns: object, severity, details, values
```

### Diagnostic Queries
Current state inspection without severity rating:
```sql
-- In module, marked as "Diagnostic Query"  
-- Returns: raw data for analysis
```

### Exploration Guidelines
Rules for ad-hoc investigation when audit/diagnostic don't answer the question.

This three-tier approach matches your existing system's intent.
