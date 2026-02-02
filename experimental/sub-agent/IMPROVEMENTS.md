# Improvement Ideas

Discussion document for potential enhancements to the ClickHouse Expert skill.

## Short-term Improvements

### 1. Testing Automation
- **Current**: Manual dry-run tests via `scripts/run-all-dry.sh`
- **Proposed**:
  - Add CI workflow to test SQL syntax on each commit
  - Add mock ClickHouse responses for offline testing
  - Validate agent JSON output against `schemas/finding.json`
- **Effort**: Medium

### 2. Model Selection per Agent
- **Current**: Single `--llm-provider` for all agents
- **Proposed**: Allow `--llm-model <model>` to select specific models (e.g., faster/cheaper models for simple agents)
- **Why**: Overview agent could use a cheaper model; schema agent might benefit from a more capable one
- **Effort**: Low (already partially supported)

### 3. Output Streaming
- **Current**: Wait for full agent output before returning
- **Proposed**: Stream partial results for long-running agents (especially useful when running multiple agents)
- **Effort**: Medium (requires run-parallel.sh changes)

### 4. Error Recovery
- **Current**: If LLM returns invalid JSON, one repair attempt is made
- **Proposed**:
  - Add retry with exponential backoff for transient errors
  - Cache successful agent outputs to avoid re-running on coordinator restart
- **Effort**: Low-Medium

---

## Medium-term Improvements


### 6. Custom Agent Creation
- **Current**: Fixed set of 15 agents
- **Proposed**:
  - User-defined agents via `custom-agents/` directory
  - Simple template: `queries.sql` + `prompt.md`
  - Auto-discovery by run-agent.sh
- **Why**: Allows organization-specific checks (e.g., specific table patterns, business metrics)
- **Effort**: Low

### 7. Historical Comparison
- **Current**: Each run is independent
- **Proposed**:
  - Store baseline metrics per cluster
  - Compare current run against baseline
  - Alert on significant deviations
- **Effort**: Medium-High (needs storage backend)

### 8. MCP Backend Improvements
- **Current**: Basic MCP support with cluster detection
- **Proposed**:
  - Better error messages for MCP tool failures
  - Retry logic for transient MCP errors
  - Progress reporting during multi-statement execution
- **Effort**: Medium

---

## Longer-term Ideas

### 9. Interactive Mode
- **Current**: Run agents, get report
- **Proposed**: Interactive debugging session with follow-up queries
- **Why**: After RCA, users often want to drill down
- **Implementation**: REPL-style interface that remembers context
- **Effort**: High

### 10. Remediation Actions
- **Current**: Recommendations are text only
- **Proposed**:
  - Generate executable SQL for common fixes (e.g., `OPTIMIZE TABLE`, `DROP PARTITION`)
  - Require explicit confirmation before execution
  - Keep audit log of actions taken
- **Effort**: High (safety concerns)

### 11. Multi-cluster Support
- **Current**: One cluster per session
- **Proposed**:
  - Compare metrics across multiple clusters
  - Identify cluster-specific anomalies
  - Aggregate health dashboard
- **Effort**: High

### 12. Alerting Integration
- **Current**: Pull-based (user triggers investigation)
- **Proposed**:
  - Webhook/alert receiver mode
  - Auto-triage incoming alerts
  - Integrate with PagerDuty/Opsgenie/Slack
- **Effort**: High

---

## Agent-specific Improvements

### Schema Agent
- Add detection for:
  - Tables without TTL on log-like data
  - Overly wide tables (too many columns)
  - Missing codec recommendations

### Memory Agent
- Add:
  - Per-user memory consumption breakdown
  - Memory limit recommendations based on workload

### Ingestion Agent
- Add:
  - Batch size optimization suggestions
  - Async insert analysis

### Replication Agent
- Add:
  - Keeper latency metrics
  - Network partition detection patterns

---

## Questions for Discussion

1. **Priority**: Which improvements would provide the most value?
2. **Custom agents**: Is org-specific customization important?
3. **Remediation**: How cautious should we be about generating executable fixes?
4. **Multi-cluster**: Is this a common use case worth investing in?
5. **Historical baselines**: Where should baseline data be stored?

---

## Implementation Notes

When implementing any improvement:
- Keep backward compatibility with existing `run-agent.sh` interface
- Update CLAUDE.md and README.md
- Add tests to TESTING.md
- Consider both CLI and MCP backends