# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **ClickHouse diagnostic and troubleshooting agent system** designed to analyze ClickHouse server health, diagnose performance issues, and perform root cause analysis. The system uses a modular architecture where diagnostic knowledge is organized into specialized markdown modules.

## Architecture

### Core Components

1. **SKILL.md** - Main agent definition and **centralized router** (single source of truth)
   - Defines agent startup procedure (connectivity check, version reporting)
   - **Contains comprehensive Module Index table** mapping keywords/symptoms to modules
   - Routes user requests to appropriate diagnostic modules
   - Defines multi-module scenarios and module chaining rules
   - Contains global query rules (SQL style, time bounds, result size management)
   - Defines severity classification framework (Critical, Major, Moderate, Minor, OK)

2. **Diagnostic Modules (15 .md files)** - Pure query libraries and analysis patterns
   - **No routing information** - modules focus solely on diagnostic queries
   - Each module contains audit queries (severity-rated findings) and diagnostic queries (raw data)
   - Modules include "Cross-Module Triggers" section suggesting related modules based on findings
   - Modules are loaded on-demand based on SKILL.md routing logic
   - See "Module Structure" below for complete list

3. **ANALYSIS.md** - Architecture documentation
   - Explains the declarative audit pattern used across modules
   - Documents threshold logic, ratio-based checks, and cross-table correlation patterns
   - Maps audit check categories (A0: System-Level, A1: Storage/Parts, A2: Schema, A3: Runtime)

### Module Structure

All diagnostic modules follow this pattern in `*.md` files:

```
modules/
├── overview.md       # System health check, entry point, object counts, resource utilization
├── schema.md         # Table design, ORDER BY, partitioning, MVs, primary key analysis
├── reporting.md      # SELECT query performance, query_log analysis
├── ingestion.md      # INSERT patterns, part_log, batch analysis
├── merges.md         # Merge performance, part management, backlog issues
├── mutations.md      # ALTER UPDATE/DELETE tracking
├── memory.md         # RAM usage, MemoryTracker, OOM diagnostics
├── storage.md        # Disk usage, compression, part sizes
├── caches.md         # Mark cache, uncompressed cache, query cache
├── replication.md    # Keeper, replicas, replication queue
├── errors.md         # Exception patterns, failed queries
├── text_log.md       # Server logs, debug traces
├── dictionaries.md   # External dictionaries
├── logs.md           # System log table health (TTL, disk usage)
└── metrics.md        # Real-time async/sync metrics monitoring
```

### Module Loading Strategy

The agent uses a **centralized keyword-based routing system** defined in SKILL.md's Module Index table:
- **Single source of truth**: All routing logic lives in SKILL.md, not in individual modules
- **Module Index table** contains: module name, purpose, triggers (keywords), symptoms, and chaining information
- Single-module scenarios: Direct mapping from user keywords to specific modules
- Multi-module scenarios: Sequential loading based on symptom patterns (e.g., "inserts are slow" → ingestion.md → merges.md → storage.md)
- Module chaining: Each module has a "Cross-Module Triggers" section for findings-based navigation

## Key Design Patterns

### 1. Severity Classification
All audit findings use consistent severity levels:
- **Critical**: Immediate risk of failure/data loss (fix now)
- **Major**: Significant performance/stability impact (fix this week)
- **Moderate**: Suboptimal, will degrade over time (plan fix)
- **Minor**: Best practice violation, low impact (nice to have)
- **OK/None**: Passes check (no action needed)

### 2. Context-Aware Thresholds
Thresholds are ratio-based, not absolute:
- Parts vs `max_parts_in_total`
- Cache size vs total RAM
- Disk usage vs total disk space
- Memory usage vs `OSMemoryTotal`

Example from modules:
```sql
multiIf(value > 2000, 'Critical', value > 900, 'Major', value > 200, 'Moderate', 'OK')
```

### 3. Query Types in Modules

Each module contains three types of queries:

1. **Audit Queries** - Return `(object, severity, details, values)` for quick assessment
2. **Diagnostic Queries** - Raw data inspection without severity ratings
3. **Ad-Hoc Guidelines** - Rules for safe exploration (LIMIT, time bounds)

### 4. Global Query Rules (from SKILL.md)

All SQL queries must follow:
- Lowercase keywords: `select`, `from`, `where`, `order by`
- Explicit columns only (never `select *`)
- Default `limit 100` unless specified otherwise
- Time bounds required for `*_log` tables:
  ```sql
  where event_date = today()  -- default: last 24 hours
  where event_time > now() - interval 1 hour
  ```
- Use formatting functions: `formatReadableSize()`, `formatReadableQuantity()`
- Schema discovery before querying unfamiliar tables: `desc system.{table_name}`

## Common Workflows

### Health Check Entry Point
When user asks for "health check", "audit", or "status":
1. Verify connectivity: `select hostname(), version()`
2. Report hostname and version
3. Run overview.md standard diagnostics (system overview, current activity, part health, recent errors)
4. Route to specific modules based on findings

### Multi-Module Analysis
Example: "inserts are slow"
1. Load ingestion.md (check insert patterns, batch sizes, part creation rate)
2. Load merges.md (check merge backlog, merge duration)
3. Load storage.md (check disk IO, space constraints)

### Typical Diagnostic Flow
1. Start with quick audit queries (severity-rated findings)
2. If issues found, run detailed diagnostic queries
3. Use ad-hoc queries for deeper investigation
4. Chain to related modules as findings suggest

## Working with This Codebase

### Reading Modules
- Each `.md` file is a pure query library focused on diagnostic content
- Modules start with a brief title and description (no routing information)
- SQL queries are the primary content; explanatory text is minimal
- Each module ends with a "Cross-Module Triggers" table suggesting related modules based on findings

### Module Interdependencies
Common chains documented in SKILL.md's Module Index and multi-module scenarios:
- Merge issues → storage.md or schema.md
- Ingestion backlog → merges.md
- Query performance → memory.md, caches.md, schema.md
- Replication lag → replication.md → merges.md → storage.md

### Modifying Routing Logic
- **All routing changes happen in SKILL.md only**
- Update the Module Index table to change keywords, symptoms, or chaining rules
- Individual modules should never contain routing information
- This prevents duplication and ensures consistency

### Information Sources Priority
1. System tables via MCP (primary)
2. Module-specific queries (predefined patterns)
3. ClickHouse docs: https://clickhouse.com/docs/
4. Altinity KB: https://kb.altinity.com/
5. GitHub issues: https://github.com/ClickHouse/ClickHouse/issues

## Response Style

When using this agent:
- Direct, professional, concise responses
- State uncertainty explicitly: "Based on available data..." or "Cannot determine without..."
- Provide specific metrics and time ranges
- Reference documentation or KB articles when suggesting fixes
- Summarize large result sets (>50 rows) before presenting
- Aggregate in SQL rather than loading raw data for large datasets

## Module Routing Quick Reference

| User Mentions | Primary Module | Secondary Modules |
|--------------|----------------|-------------------|
| health check, audit, overview | overview.md | Route based on findings |
| slow query, SELECT performance | reporting.md | memory.md, caches.md |
| slow inserts, ingestion | ingestion.md | merges.md, storage.md |
| merges, too many parts | merges.md | storage.md, schema.md |
| mutations, ALTER stuck | mutations.md | merges.md, errors.md |
| memory, OOM | memory.md | merges.md, schema.md |
| disk, storage, space | storage.md | - |
| cache hit ratio | caches.md | schema.md, memory.md |
| errors, exceptions | errors.md | - |
| logs, text_log | text_log.md | - |
| schema, ORDER BY, partition | schema.md | merges.md, ingestion.md |
| dictionary | dictionaries.md | - |
| replication, keeper, lag | replication.md | merges.md, storage.md |
| system log TTL | logs.md | storage.md |
| metrics, connections | metrics.md | - |

## Important Guidelines

### Routing Architecture
- **SKILL.md is the single source of truth for routing** - all module mapping lives there
- Individual modules are pure query libraries with no routing logic
- To add/modify routing: update SKILL.md Module Index table only
- To add queries: update the relevant module .md file

### Files and Their Roles
- **SKILL.md**: Agent behavior + routing logic (Module Index table)
- **Module .md files**: Query libraries + diagnostic patterns
- **ANALYSIS.md**: Architecture documentation and design patterns

### Adding New Modules
When adding a new diagnostic module:
1. Create the module .md file with queries
2. Add entry to SKILL.md Module Index table with triggers/symptoms
3. Update multi-module scenarios in SKILL.md if needed
4. Do NOT add routing info inside the module itself

## Agent Behavior Notes

- Agent always starts with connectivity check: `select hostname(), version()`
- Agent stops immediately if connection fails
- Agent loads modules dynamically based on user queries (not all at once)
- SQL queries use time bounds to prevent scanning entire log tables
- Results are formatted using ClickHouse functions (`formatReadableSize`, etc.)