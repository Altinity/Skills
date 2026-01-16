
# Requires ClickHouse connectivity (use CLICKHOUSE_* env vars or -- args).
# Example: make expert-dry CLICKHOUSE_HOST=prod-ch CLICKHOUSE_USER=admin
expert-dry:
	./run-all-dry.sh

# Full LLM run (single-shot prompt via Codex).
expert:
	echo "Review the table design for the largest tables in clickhouse. Looking for partitioning issues, bad ORDER BY choices, or problematic materialized views" | codex -a never exec -s workspace-write --skip-git-repo-check
