---
name: altinity-expert-clickhouse-replication
description: Diagnose ClickHouse replication health, Keeper connectivity, replica lag, and queue issues. Use for replication lag and read-only replica problems.
---

## Primary query set

- Queries are stored in `.sql` files:
  - `triage.sql` (run first)
  - `queue.sql`
  - `mutations.sql`
  - `no-replica-has-part.sql`
  - `keeper.sql`
  - `fetches.sql`
  - `ddl.sql`
  - `health.sql` (optional heuristic)
- Run statements **one-by-one** for MCP mode.

## Workflow (short)

1) Triage: `replicas` + `zookeeper_connection`
2) Queue + mutations: `replication_queue` + `mutations` (+ optional `errors`)
3) `NO_REPLICA_HAS_PART`: detect from `replication_queue`, then drill down to `text_log` only if available

## Schema-safe rule (tiny)

If a query fails with `UNKNOWN_IDENTIFIER`, run `DESCRIBE TABLE system.<table>` and drop/adjust only the missing columns.
