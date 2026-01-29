---
name: altinity-expert-clickhouse-replication
description: Diagnose ClickHouse replication health, Keeper connectivity, replica lag, and queue issues. Use for replication lag and read-only replica problems.
---

## Workflow 

Read files below run queries and analyse results:
  - `triage.sql` 
  - `queue.sql`
  - `mutations.sql`
  - `keeper.sql`
  - `fetches.sql`
  - `ddl.sql`
  - `health.sql`

## Schema-safe rule 

If a query fails with `UNKNOWN_IDENTIFIER`, run `DESCRIBE TABLE system.<table>` and drop/adjust only the missing columns.
