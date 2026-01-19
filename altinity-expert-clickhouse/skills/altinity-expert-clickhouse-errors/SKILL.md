---
name: altinity-expert-clickhouse-errors
description: Investigate ClickHouse query failures, exceptions, crashes, and error patterns. Use for error analysis and failure investigation.
---

# Error Investigation and Exception Analysis

Investigate query failures, exceptions, crashes, and error patterns.

---

## Quick Diagnostics

### 1. Recent Errors Summary

```sql
select
    toStartOfHour(event_time) as hour,
    count() as error_count,
    uniq(exception_code) as unique_errors,
    uniq(user) as users_affected
from system.query_log
where type like 'Exception%'
  and event_date = today()
group by hour
order by hour desc
```

### 2. Error Distribution by Code

```sql
select
    exception_code,
    count() as occurrences,
    any(substring(exception, 1, 100)) as example_message,
    min(event_time) as first_seen,
    max(event_time) as last_seen
from system.query_log
where type like 'Exception%'
  and event_date >= today() - 1
group by exception_code
order by occurrences desc
limit 30
```

### 3. Recent Exceptions Detail

```sql
select
    event_time,
    user,
    exception_code,
    substring(exception, 1, 200) as exception,
    query_kind,
    substring(query, 1, 100) as query_preview
from system.query_log
where type like 'Exception%'
  and event_date = today()
order by event_time desc
limit 50
```

---

## Common Error Analysis

### Memory Errors (Code 241)

```sql
select
    event_time,
    user,
    formatReadableSize(memory_usage) as memory_at_failure,
    formatReadableSize(read_bytes) as read_bytes,
    substring(exception, 1, 150) as exception,
    substring(query, 1, 80) as query_preview
from system.query_log
where type like 'Exception%'
  and exception_code = 241  -- MEMORY_LIMIT_EXCEEDED
  and event_date >= today() - 1
order by event_time desc
limit 30
```

**Solutions:** See `altinity-expert-clickhouse-memory` for memory optimization.

### Too Many Parts (Code 252)

```sql
select
    event_time,
    user,
    arrayStringConcat(tables, ', ') as tables,
    substring(exception, 1, 150) as exception
from system.query_log
where type like 'Exception%'
  and exception_code = 252  -- TOO_MANY_PARTS
  and event_date >= today() - 1
order by event_time desc
limit 30
```

**Solutions:** See `altinity-expert-clickhouse-merges` and `altinity-expert-clickhouse-ingestion` for part management.

### Timeout Errors (Code 159)

```sql
select
    event_time,
    user,
    query_duration_ms,
    formatReadableSize(read_bytes) as read_bytes,
    substring(query, 1, 100) as query_preview
from system.query_log
where type like 'Exception%'
  and exception_code = 159  -- TIMEOUT_EXCEEDED
  and event_date >= today() - 1
order by event_time desc
limit 30
```

### Table/Column Not Found (Codes 60, 16)

```sql
select
    event_time,
    user,
    exception_code,
    substring(exception, 1, 150) as exception,
    substring(query, 1, 100) as query_preview
from system.query_log
where type like 'Exception%'
  and exception_code in (60, 16)  -- TABLE_DOESNT_EXIST, NO_SUCH_COLUMN_IN_TABLE
  and event_date = today()
order by event_time desc
limit 30
```

---

## Crash Analysis

### Recent Crashes

```sql
select
    event_time,
    signal,
    thread_id,
    query_id,
    substring(trace_full, 1, 500) as stack_trace,
    substring(query, 1, 100) as query_preview
from system.crash_log
where event_time > now() - interval 7 day
order by event_time desc
limit 20
```

### Crash Summary

```sql
select
    toDate(event_time) as day,
    count() as crashes,
    groupUniqArray(signal) as signals
from system.crash_log
where event_time > now() - interval 30 day
group by day
order by day desc
```

---

## Error Patterns by User/Client

### Errors by User

```sql
select
    user,
    count() as errors,
    groupUniqArray(exception_code) as error_codes,
    max(event_time) as last_error
from system.query_log
where type like 'Exception%'
  and event_date = today()
group by user
order by errors desc
```

### Errors by Client

```sql
select
    client_hostname,
    client_name,
    count() as errors,
    groupUniqArray(exception_code) as error_codes
from system.query_log
where type like 'Exception%'
  and event_date = today()
group by client_hostname, client_name
order by errors desc
limit 20
```

---

## Error Log from text_log

### Critical/Error Level Messages

```sql
select
    event_time,
    level,
    logger_name,
    substring(message, 1, 200) as message
from system.text_log
where level in ('Fatal', 'Critical', 'Error')
  and event_time > now() - interval 1 hour
order by event_time desc
limit 50
```

### Errors by Component

```sql
select
    logger_name,
    count() as errors,
    max(event_time) as last_seen
from system.text_log
where level in ('Fatal', 'Critical', 'Error')
  and event_time > now() - interval 24 hour
group by logger_name
order by errors desc
limit 30
```

---

## System Warnings

```sql
select message as warning
from system.warnings
```

---

## Error Code Reference

| Code | Name | Common Cause |
|------|------|--------------|
| 60 | TABLE_DOESNT_EXIST | Wrong table name or database |
| 62 | SYNTAX_ERROR | Invalid SQL |
| 159 | TIMEOUT_EXCEEDED | Query too slow |
| 241 | MEMORY_LIMIT_EXCEEDED | Query uses too much RAM |
| 252 | TOO_MANY_PARTS | Insert too fast, merges behind |
| 319 | UNKNOWN_PACKET | Network/client issues |
| 341 | UNFINISHED | Operation interrupted |
| 16 | NO_SUCH_COLUMN | Column doesn't exist |
| 36 | CANNOT_READ_ALL_DATA | Corruption or network |
| 164 | READONLY | Replica in readonly mode |
| 242 | TABLE_IS_READ_ONLY | Table locked |
| 243 | TABLE_IS_DROPPED | Concurrent DROP |
| 254 | RECEIVED_ERROR_FROM_REMOTE | Distributed query failure |

---

## Distributed Query Errors

```sql
select
    event_time,
    initial_query_id,
    exception_code,
    substring(exception, 1, 150) as exception,
    substring(query, 1, 80) as query_preview
from system.query_log
where type like 'Exception%'
  and event_date = today()
  and (exception_code = 254 or query ilike '%distributed%')
order by event_time desc
limit 30
```

---

## Error Rate Analysis

### Error Rate Over Time

```sql
select
    toStartOfFiveMinutes(event_time) as ts,
    count() as total_queries,
    countIf(type like 'Exception%') as errors,
    round(100.0 * countIf(type like 'Exception%') / count(), 2) as error_rate_pct
from system.query_log
where event_time > now() - interval 6 hour
group by ts
order by ts desc
```

### Error Rate by Query Type

```sql
select
    query_kind,
    count() as total,
    countIf(type like 'Exception%') as errors,
    round(100.0 * countIf(type like 'Exception%') / count(), 2) as error_rate_pct
from system.query_log
where event_date = today()
group by query_kind
order by errors desc
```

---

## Ad-Hoc Query Guidelines

### Required Safeguards
```sql
-- Time bound
where event_date >= today() - 1
-- or
where event_time > now() - interval 1 hour

-- Limit results
limit 100
```

### Key Tables
- `system.query_log` (type like 'Exception%') - Query failures
- `system.text_log` (level in Error/Critical/Fatal) - Server errors
- `system.crash_log` - Server crashes
- `system.warnings` - Active warnings

---

## Cross-Module Triggers

| Finding | Load Module | Reason |
|---------|-------------|--------|
| Memory errors | `altinity-expert-clickhouse-memory` | Memory analysis |
| TOO_MANY_PARTS | `altinity-expert-clickhouse-merges`, `altinity-expert-clickhouse-ingestion` | Part management |
| Replication errors | `altinity-expert-clickhouse-replication` | Replica status |
| Distributed errors | `altinity-expert-clickhouse-replication` | Cluster health |
| Unknown errors | `altinity-expert-clickhouse-text-log` | Deep log analysis |
| Crashes | `altinity-expert-clickhouse-text-log` | Stack trace analysis |

---

## Alerting Recommendations

Set alerts for:
- Error rate > 5%
- Memory errors > 10/hour
- Any crashes
- Readonly replica errors
- TOO_MANY_PARTS errors
