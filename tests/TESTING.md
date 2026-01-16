# Testing: ClickHouse Analyst Skill

This repo has two layers to test:

1. **Runner scripts** (`scripts/run-agent.sh`, `scripts/run-parallel.sh`) that execute ClickHouse SQL and enforce “JSON-only” output.
2. **Coordinator behavior** (adaptive chaining): choose agents, run `run-agent.sh` directly (often in waves), and stop when root cause is clear.

Below are practical checks and scenario prompts to validate both layers.

## Prerequisites

```bash
# Test connection (shows hostname, version, uptime)
scripts/run-agent.sh --test-connection

# Or with explicit args
scripts/run-agent.sh --test-connection -- --host=<host> --user=<user>

# Rare: override connection for a specific run (single-node investigations)
# scripts/run-agent.sh overview "health check" -- --host=<node> --user=<user>
```

---

## Quick Smoke Checks (No Incident Needed)

### 1) Script sanity

```bash
bash -n scripts/run-agent.sh scripts/run-parallel.sh scripts/run-all-dry.sh
jq -e . schemas/finding.json >/dev/null
```

### 2) Single agent run (recommended default path)

```bash
scripts/run-agent.sh overview "health check"
```

### 3) Parallel fan-out (LLM-independent option)

```bash
scripts/run-parallel.sh "health check" -- --agents overview metrics
```

### 4) All agents (dry-run, SQL only)

```bash
scripts/run-all-dry.sh
```

Or with Make:
```bash
make test
```

### 5) Artifacts + timeout knobs

```bash
export CH_ANALYST_KEEP_ARTIFACTS=1
export CH_ANALYST_QUERY_TIMEOUT_SEC=60   # set to 0 to disable

scripts/run-agent.sh reporting "smoke test"
# Inspect runs/<timestamp>-reporting/ for prompt, raw output, final JSON, and query results/errors.
```

---

## Basic Functionality (Prompts)

### 1. Health Check (Overview Agent)
```
Run a health check on my ClickHouse
```

### 2. Single Agent Test
```
Check memory usage on ClickHouse
```

---

## Incident Response Scenarios

### 4. OOM / Memory Pressure
```
ClickHouse is OOMing. Started about 30 minutes ago. Help me investigate.
```

### 5. Slow Queries
```
Users are reporting slow queries on our ClickHouse cluster. P95 latency jumped from 200ms to 5s in the last hour.
```

### 6. Slow Inserts
```
INSERT queries are timing out. We're seeing 30s+ insert times when it's usually under 1s.
```

### 7. Too Many Parts
```
Getting "too many parts" errors on table events.clicks.
```

### 8. Replication Lag
```
One of our ClickHouse replicas is showing as readonly.
```

### 9. Disk Full
```
Disk is 95% full on our ClickHouse server. Need to understand what's consuming space and what to clean up.
```

### 10. Exception Spike
```
We're seeing a spike in query failures. Error rate went from <1% to 15% in the last 2 hours.
```

---

## Audit Scenarios

### 11. Weekly Health Audit
```
Run a health audit on our ClickHouse cluster. Check for schema issues, storage problems, and performance risks.
```

### 12. Schema Review
```
Review the table design for our largest tables in clickhouse. Looking for partitioning issues, bad ORDER BY choices, or problematic materialized views.
```

### 13. Cache Efficiency
```
Analyze cache hit rates on ClickHouse. Want to know if we should tune mark_cache_size or uncompressed_cache_size.
```

---

## Specific Subsystem Scenarios

### 14. Mutations Stuck
```
ALTER UPDATE queries are stuck on table user_events. They've been running for 3+ hours.
```

### 15. Dictionary Issues
```
External dictionaries are failing to load. Getting "dictionary not found" errors intermittently.
```

### 16. Materialized View Performance
```
Inserts are slow and I suspect materialized views. Can you check MV execution times?
```

### 17. System Log Tables Growing
```
The system.query_log table is consuming 500GB of disk. How do I check retention settings and clean it up?
```

### 18. Keeper/ZooKeeper Issues
```
Seeing Keeper connection errors in the logs. Replicated tables are intermittently readonly.
```

---

## Multi-Step Investigation

### 19. Complex Issue (Chaining Test)
```
ClickHouse is generally slow. Queries are slow, inserts are slow, and we're seeing occasional OOMs. Not sure where to start.
```

### 20. Performance Degradation Over Time
```
Performance has been gradually degrading over the past month. Nothing specific changed. Need a comprehensive investigation.
```

---

## Edge Cases

### 21. Empty/New Cluster
```
Run diagnostics on a fresh ClickHouse install with no data yet.
```

### 22. Single Node vs Cluster
```
Check if this ClickHouse instance is standalone or part of a cluster, then run appropriate diagnostics.
```

### 23. Connection Issues
```
I can't connect to ClickHouse (connection refused / timeout). What diagnostics can we run?
```

### 24. Single-Node Special Case (explicit override)
```
We suspect only one node is unhealthy. Run diagnostics specifically against node ch-node-3 (override host explicitly).
```

---

## LLM Provider Tests

### 25. Different LLM Provider
```
Run memory diagnostics using Gemini instead of Claude for analysis
```

### 26. Codex Provider
```
Use Codex to analyze query performance
```

---

## Coordinator Tests (Adaptive Chaining)

These are “behavior” tests for the coordinator (human or LLM) rather than the bash runner:

1. Pick 2–3 initial agents from symptom mapping (often `overview` + one specialist).
2. Run them via `run-agent.sh` (not `run-parallel.sh`) so you can decide what to run next.
3. Use `chain_to` + evidence to spawn a second wave (max 1–2 extra waves).
4. Stop early when a clear high-severity root cause + actions exist.

Example flow (manual):

```bash
scripts/run-agent.sh overview "general slowness" > /tmp/overview.json
scripts/run-agent.sh reporting "general slowness" > /tmp/reporting.json
# Decide next wave based on findings / chain_to
```

## Expected Behaviors

| Scenario | Expected Agents | Expected chain_to |
|----------|-----------------|-------------------|
| OOM | memory, reporting | schema if design/scan issues found; dictionaries if dict pressure suspected |
| Slow queries | reporting, memory | merges if many parts; schema if bad design; caches if cache symptoms |
| Slow inserts | ingestion, merges, storage | schema if tiny parts; logs if system logs are choking disk |
| Too many parts | merges, ingestion, storage | schema for partitioning review |
| Replication lag | replication, merges, storage | errors/text_log if failures found |
| Disk full | storage, ingestion | logs if system tables large |
| Mutations stuck | mutations, merges, storage | errors/text_log if failing |
| Dictionary issues | dictionaries, errors | memory if dictionary bytes high |
| Health check | overview, metrics | varies based on findings |

---

## Validation Checklist

For each test:
- [ ] Agent selection matches symptom
- [ ] Runner can reach ClickHouse (or fails with clear stderr)
- [ ] SQL runs in order; later query errors don't erase earlier results (e.g. `query_views_log` issues)
- [ ] JSON output is valid and structurally correct (required keys; `.agent` matches the agent)
- [ ] Severity ratings are reasonable
- [ ] `chain_to` suggestions are relevant
- [ ] Recommendations are actionable
- [ ] No sensitive data leaked in output
