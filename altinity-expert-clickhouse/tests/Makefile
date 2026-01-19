# Skills Test Suite Makefile
# Run tests for ClickHouse diagnostic skills

.PHONY: all test test-all test-all-codex test-all-claude test-all-gemini \
	test-memory test-memory-codex test-memory-claude test-memory-gemini \
	test-overview test-reporting test-ingestion test-merges test-mutations \
	test-storage test-caches test-dictionaries test-errors test-logs \
	test-metrics test-replication test-schema test-text-log test-expert \
	validate setup clean help expert expert-dry

RUNNER := ./runner/run-test.sh
LLM_PROVIDER ?= codex
CODEX_MODEL ?=
CODEX_VERIFY_MODEL ?=

# Default target
all: test

# Validate environment variables and connection
validate:
	@./runner/lib/common.sh validate_connection

# Run all skill tests (sequential)
test: test-all

test-all: validate test-memory test-overview test-reporting test-ingestion test-merges test-mutations \
	test-storage test-caches test-dictionaries test-errors test-logs test-metrics test-replication \
	test-schema test-text-log test-expert

# Run all skill tests with explicit LLM provider
test-all-codex:
	LLM_PROVIDER=codex CODEX_MODEL=$(CODEX_MODEL) CODEX_VERIFY_MODEL=$(CODEX_VERIFY_MODEL) $(MAKE) test-all

test-all-claude:
	LLM_PROVIDER=claude $(MAKE) test-all

test-all-gemini:
	LLM_PROVIDER=gemini $(MAKE) test-all

# Run memory skill test
test-memory: validate
	LLM_PROVIDER=$(LLM_PROVIDER) CODEX_MODEL=$(CODEX_MODEL) CODEX_VERIFY_MODEL=$(CODEX_VERIFY_MODEL) $(RUNNER) altinity-expert-clickhouse-memory

# Run memory skill test with Codex
test-memory-codex: validate
	LLM_PROVIDER=codex CODEX_MODEL=$(CODEX_MODEL) CODEX_VERIFY_MODEL=$(CODEX_VERIFY_MODEL) $(RUNNER) altinity-expert-clickhouse-memory

# Run memory skill test with Claude
test-memory-claude: validate
	LLM_PROVIDER=claude $(RUNNER) altinity-expert-clickhouse-memory

# Run memory skill test with Gemini (stub)
test-memory-gemini: validate
	LLM_PROVIDER=gemini $(RUNNER) altinity-expert-clickhouse-memory

test-overview: validate
	LLM_PROVIDER=$(LLM_PROVIDER) CODEX_MODEL=$(CODEX_MODEL) CODEX_VERIFY_MODEL=$(CODEX_VERIFY_MODEL) $(RUNNER) altinity-expert-clickhouse-overview

test-reporting: validate
	LLM_PROVIDER=$(LLM_PROVIDER) CODEX_MODEL=$(CODEX_MODEL) CODEX_VERIFY_MODEL=$(CODEX_VERIFY_MODEL) $(RUNNER) altinity-expert-clickhouse-reporting

test-ingestion: validate
	LLM_PROVIDER=$(LLM_PROVIDER) CODEX_MODEL=$(CODEX_MODEL) CODEX_VERIFY_MODEL=$(CODEX_VERIFY_MODEL) $(RUNNER) altinity-expert-clickhouse-ingestion

test-merges: validate
	LLM_PROVIDER=$(LLM_PROVIDER) CODEX_MODEL=$(CODEX_MODEL) CODEX_VERIFY_MODEL=$(CODEX_VERIFY_MODEL) $(RUNNER) altinity-expert-clickhouse-merges

test-mutations: validate
	LLM_PROVIDER=$(LLM_PROVIDER) CODEX_MODEL=$(CODEX_MODEL) CODEX_VERIFY_MODEL=$(CODEX_VERIFY_MODEL) $(RUNNER) altinity-expert-clickhouse-mutations

test-storage: validate
	LLM_PROVIDER=$(LLM_PROVIDER) CODEX_MODEL=$(CODEX_MODEL) CODEX_VERIFY_MODEL=$(CODEX_VERIFY_MODEL) $(RUNNER) altinity-expert-clickhouse-storage

test-caches: validate
	LLM_PROVIDER=$(LLM_PROVIDER) CODEX_MODEL=$(CODEX_MODEL) CODEX_VERIFY_MODEL=$(CODEX_VERIFY_MODEL) $(RUNNER) altinity-expert-clickhouse-caches

test-dictionaries: validate
	LLM_PROVIDER=$(LLM_PROVIDER) CODEX_MODEL=$(CODEX_MODEL) CODEX_VERIFY_MODEL=$(CODEX_VERIFY_MODEL) $(RUNNER) altinity-expert-clickhouse-dictionaries

test-errors: validate
	LLM_PROVIDER=$(LLM_PROVIDER) CODEX_MODEL=$(CODEX_MODEL) CODEX_VERIFY_MODEL=$(CODEX_VERIFY_MODEL) $(RUNNER) altinity-expert-clickhouse-errors

test-logs: validate
	LLM_PROVIDER=$(LLM_PROVIDER) CODEX_MODEL=$(CODEX_MODEL) CODEX_VERIFY_MODEL=$(CODEX_VERIFY_MODEL) $(RUNNER) altinity-expert-clickhouse-logs

test-metrics: validate
	LLM_PROVIDER=$(LLM_PROVIDER) CODEX_MODEL=$(CODEX_MODEL) CODEX_VERIFY_MODEL=$(CODEX_VERIFY_MODEL) $(RUNNER) altinity-expert-clickhouse-metrics

test-replication: validate
	LLM_PROVIDER=$(LLM_PROVIDER) CODEX_MODEL=$(CODEX_MODEL) CODEX_VERIFY_MODEL=$(CODEX_VERIFY_MODEL) $(RUNNER) altinity-expert-clickhouse-replication

test-schema: validate
	LLM_PROVIDER=$(LLM_PROVIDER) CODEX_MODEL=$(CODEX_MODEL) CODEX_VERIFY_MODEL=$(CODEX_VERIFY_MODEL) $(RUNNER) altinity-expert-clickhouse-schema

test-text-log: validate
	LLM_PROVIDER=$(LLM_PROVIDER) CODEX_MODEL=$(CODEX_MODEL) CODEX_VERIFY_MODEL=$(CODEX_VERIFY_MODEL) $(RUNNER) altinity-expert-clickhouse-text-log

test-expert: validate
	LLM_PROVIDER=$(LLM_PROVIDER) CODEX_MODEL=$(CODEX_MODEL) CODEX_VERIFY_MODEL=$(CODEX_VERIFY_MODEL) $(RUNNER) altinity-expert-clickhouse-expert

# Run memory skill test without verification
test-memory-no-verify: validate
	LLM_PROVIDER=$(LLM_PROVIDER) CODEX_MODEL=$(CODEX_MODEL) $(RUNNER) --skip-verify altinity-expert-clickhouse-memory

# Setup test databases only (no Claude analysis)
setup: validate
	$(RUNNER) --setup-only altinity-expert-clickhouse-memory

# Setup and keep database for manual testing
setup-memory: validate
	$(RUNNER) --setup-only altinity-expert-clickhouse-memory

# Clean up test databases
clean-db:
	$(RUNNER) --cleanup-only altinity-expert-clickhouse-memory 2>/dev/null || true

# Clean up generated files
clean: clean-db
	rm -rf reports/*/*.md reports/*/*.json
	rm -rf results/*

# Show help
help:
	@echo "Skills Test Suite"
	@echo ""
	@echo "Prerequisites:"
	@echo "  - clickhouse-client installed"
	@echo "  - claude CLI installed"
	@echo "  - Environment variables set:"
	@echo "      CLICKHOUSE_HOST (required)"
	@echo "      CLICKHOUSE_PORT (default: 9000)"
	@echo "      CLICKHOUSE_USER (default: default)"
	@echo "      CLICKHOUSE_PASSWORD"
	@echo "      CLICKHOUSE_SECURE (default: false)"
	@echo ""
	@echo "Targets:"
	@echo "  make test              Run all skill tests"
	@echo "  make test-all          Run all skill tests"
	@echo "  make test-all-codex    Run all skill tests with Codex"
	@echo "  make test-all-claude   Run all skill tests with Claude"
	@echo "  make test-all-gemini   Run all skill tests with Gemini (stub)"
	@echo "  make test-memory       Run memory skill test"
	@echo "  make test-overview     Run overview skill test"
	@echo "  make test-reporting    Run reporting skill test"
	@echo "  make test-ingestion    Run ingestion skill test"
	@echo "  make test-merges       Run merges skill test"
	@echo "  make test-mutations    Run mutations skill test"
	@echo "  make test-storage      Run storage skill test"
	@echo "  make test-caches       Run caches skill test"
	@echo "  make test-dictionaries Run dictionaries skill test"
	@echo "  make test-errors       Run errors skill test"
	@echo "  make test-logs         Run logs skill test"
	@echo "  make test-metrics      Run metrics skill test"
	@echo "  make test-replication  Run replication skill test"
	@echo "  make test-schema       Run schema skill test"
	@echo "  make test-text-log     Run text-log skill test"
	@echo "  make test-expert       Run coordinator skill test"
	@echo "  make test-memory-codex Run memory skill test with Codex"
	@echo "  make test-memory-claude Run memory skill test with Claude"
	@echo "  make test-memory-gemini Run memory skill test with Gemini (stub)"
	@echo "  make test-memory-no-verify  Run without LLM verification"
	@echo "  make validate          Check environment and connection"
	@echo "  make setup             Setup test databases only"
	@echo "  make setup-memory      Setup memory test database"
	@echo "  make clean             Clean databases and reports"
	@echo "  make clean-db          Clean databases only"
	@echo "  make help              Show this help"
	@echo ""
	@echo "Example:"
	@echo "  export CLICKHOUSE_HOST=localhost"
	@echo "  make test-memory"
	@echo ""
	@echo "LLM Options:"
	@echo "  LLM_PROVIDER=codex|claude|gemini (default: codex)"
	@echo "  CODEX_MODEL=<model> (optional)"
	@echo "  CODEX_VERIFY_MODEL=<model> (optional, overrides auto-selection)"

# ============================================================
# Legacy targets (existing tests)
# ============================================================

# Requires ClickHouse connectivity (use CLICKHOUSE_* env vars or -- args).
# Example: make expert-dry CLICKHOUSE_HOST=prod-ch CLICKHOUSE_USER=admin
expert-dry:
	./run-all-dry.sh

# Full LLM run (single-shot prompt via Codex).
expert:
	echo "Review the table design for the largest tables in clickhouse eth database. Look for partitioning issues, bad ORDER BY choices, or problematic materialized views" | codex -a never exec -s workspace-write --skip-git-repo-check
