#!/bin/bash
# Main test orchestrator for skill tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# Parse arguments
SETUP_ONLY=false
CLEANUP_ONLY=false
SKIP_VERIFY=false
CLEANUP_AFTER=false
SKIP_LLM=false

usage() {
    echo "Usage: $0 [OPTIONS] SKILL"
    echo ""
    echo "Options:"
    echo "  --setup-only     Only create database and schema, don't run tests"
    echo "  --cleanup-only   Only drop the test database"
    echo "  --skip-verify    Skip LLM verification step"
    echo "  --skip-llm       Skip LLM analysis entirely (SQL only)"
    echo "  --cleanup        Drop database after test completes"
    echo "  -h, --help       Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 altinity-expert-clickhouse-memory"
    echo "  $0 --setup-only altinity-expert-clickhouse-memory"
    echo "  $0 chaining/memory-to-merges"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --setup-only)
            SETUP_ONLY=true
            shift
            ;;
        --cleanup-only)
            CLEANUP_ONLY=true
            shift
            ;;
        --skip-verify)
            SKIP_VERIFY=true
            shift
            ;;
        --skip-llm)
            SKIP_LLM=true
            shift
            ;;
        --cleanup)
            CLEANUP_AFTER=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            SKILL="$1"
            shift
            ;;
    esac
done

if [[ -z "${SKILL:-}" ]]; then
    log_error "SKILL argument required"
    usage
    exit 1
fi

SKILL_DIR="$TESTS_DIR/$SKILL"
DB_NAME=$(get_db_name "$SKILL")
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
export TEST_RUN_ID="$TIMESTAMP"

# Validate skill directory exists
if [[ ! -d "$SKILL_DIR" ]]; then
    log_error "Skill directory not found: $SKILL_DIR"
    exit 1
fi

# Validate environment and connection
validate_env
validate_connection

# Normalize defaults for envsubst use in SQL templates
export CLICKHOUSE_HOST="${CLICKHOUSE_HOST:-arm}"
export CLICKHOUSE_PORT="${CLICKHOUSE_PORT:-9000}"
export CLICKHOUSE_USER="${CLICKHOUSE_USER:-default}"
case "${CLICKHOUSE_SECURE:-0}" in
    true|1|yes|on)
        export CLICKHOUSE_SECURE="1"
        ;;
    *)
        export CLICKHOUSE_SECURE="0"
        ;;
esac

# Cleanup only mode
if [[ "$CLEANUP_ONLY" == "true" ]]; then
    drop_database "$DB_NAME"
    log_success "Cleanup complete"
    exit 0
fi

echo ""
echo "========================================"
echo "Testing skill: $SKILL"
echo "Database: $DB_NAME"
echo "========================================"
echo ""

# Step 1: Create database
create_database "$DB_NAME"

# Step 2: Create schema
if [[ -f "$SKILL_DIR/dbschema.sql" ]]; then
    log_info "Creating schema..."
    if command -v envsubst &> /dev/null; then
        TMP_SCHEMA=$(mktemp)
        envsubst < "$SKILL_DIR/dbschema.sql" > "$TMP_SCHEMA"
        run_script_in_db "$TMP_SCHEMA" "$DB_NAME"
        rm -f "$TMP_SCHEMA"
    else
        run_script_in_db "$SKILL_DIR/dbschema.sql" "$DB_NAME"
    fi
    log_success "Schema created"
else
    log_warn "No dbschema.sql found, skipping schema creation"
fi

# Step 3: Run scenarios
if [[ -d "$SKILL_DIR/scenarios" ]]; then
    for scenario in "$SKILL_DIR/scenarios/"*.sql; do
        if [[ -f "$scenario" ]]; then
            log_info "Running scenario: $(basename "$scenario")"
            RUNNER_FN="run_script_in_db"
            if [[ -f "$SKILL_DIR/.ignore-errors" ]]; then
                RUNNER_FN="run_script_in_db_ignore_errors"
            fi
            if command -v envsubst &> /dev/null; then
                TMP_SCENARIO=$(mktemp)
                envsubst < "$scenario" > "$TMP_SCENARIO"
                $RUNNER_FN "$TMP_SCENARIO" "$DB_NAME"
                rm -f "$TMP_SCENARIO"
            else
                $RUNNER_FN "$scenario" "$DB_NAME"
            fi
            log_success "Scenario complete: $(basename "$scenario")"
        fi
    done
else
    log_warn "No scenarios directory found"
fi

# Setup only mode - exit here
if [[ "$SETUP_ONLY" == "true" ]]; then
    log_success "Setup complete (--setup-only mode)"
    exit 0
fi

# Skip LLM mode - SQL-only tests
if [[ "$SKIP_LLM" == "true" ]]; then
    REPORTS_DIR="$TESTS_DIR/reports/$SKILL"
    mkdir -p "$REPORTS_DIR"
    REPORT="$REPORTS_DIR/report-$TIMESTAMP.md"
    {
        echo "# ${SKILL} (SQL-only test run)"
        echo ""
        echo "- ClickHouse: $(run_query "SELECT hostName(), version()")"
        echo "- Database: \`$DB_NAME\`"
        echo "- Timestamp: \`$TIMESTAMP\`"
        echo ""
        echo "LLM analysis skipped (--skip-llm)."
    } > "$REPORT"
    log_success "SQL-only test complete: $SKILL"
    echo "Report: $REPORT"
    exit 0
fi

# Step 4: Run skill analysis via LLM
REPORTS_DIR="$TESTS_DIR/reports/$SKILL"
mkdir -p "$REPORTS_DIR"
REPORT="$REPORTS_DIR/report-$TIMESTAMP.md"

if [[ -f "$SKILL_DIR/prompt.md" ]]; then
    log_info "Running LLM analysis (provider: ${LLM_PROVIDER:-codex})..."

    # Build prompt with environment variable substitution
    PROMPT=$(cat "$SKILL_DIR/prompt.md")
    PROMPT=$(echo "$PROMPT" | envsubst)
    BASE_PROMPT="Use tests/runner/lib/common.sh helpers (run_query, run_script_in_db) for ClickHouse queries so CLICKHOUSE_* and --secure are handled. Do not use MCP tools (e.g. ai-demo.execute_query) or curl."
    PROMPT=$(printf '%s\n\n%s' "$BASE_PROMPT" "$PROMPT")

    PROVIDER="${LLM_PROVIDER:-codex}"
    LLM_LOG="$REPORTS_DIR/$PROVIDER-$TIMESTAMP.log"
    case "$PROVIDER" in
        codex)
            CODEX_ARGS=(
                exec
                --dangerously-bypass-approvals-and-sandbox
                --skip-git-repo-check
                -C "$TESTS_DIR"
                -o "$REPORT"
            )
            if [[ -n "${CODEX_MODEL:-}" ]]; then
                CODEX_ARGS+=(-m "$CODEX_MODEL")
            fi
            if echo "$PROMPT" | codex "${CODEX_ARGS[@]}" > "$LLM_LOG" 2>&1; then
                if [[ -s "$REPORT" ]]; then
                    log_success "Report generated: $REPORT"
                else
                    log_error "LLM produced empty report"
                    cat "$LLM_LOG"
                    exit 1
                fi
            else
                # Common failure modes: account/model restrictions or usage limits.
                if rg -q "usage_limit_reached|Too Many Requests|HTTP 429|model is not supported|ChatGPT account" "$LLM_LOG" 2>/dev/null; then
                    log_warn "Codex unavailable (usage/model limits); skipping LLM analysis for this test"
                    {
                        echo "# ${SKILL} (LLM skipped)"
                        echo ""
                        echo "- ClickHouse: $(run_query "SELECT hostName(), version()")"
                        echo "- Database: \`$DB_NAME\`"
                        echo "- Timestamp: \`$TIMESTAMP\`"
                        echo ""
                        echo "LLM analysis skipped because Codex returned an availability/usage error."
                    } > "$REPORT"
                    SKIP_VERIFY=true
                else
                    log_error "Codex analysis failed"
                    cat "$LLM_LOG"
                    exit 1
                fi
            fi
            ;;
        claude)
            CLAUDE_ARGS=(
                --print
                --dangerously-skip-permissions
                --allowedTools "Bash,Read,Glob,Grep"
            )
            if [[ -n "${CLAUDE_MODEL:-}" ]]; then
                CLAUDE_ARGS+=(--model "$CLAUDE_MODEL")
            fi
            if echo "$PROMPT" | claude "${CLAUDE_ARGS[@]}" > "$REPORT" 2> "$LLM_LOG"; then
                if [[ -s "$REPORT" ]]; then
                    log_success "Report generated: $REPORT"
                else
                    log_error "Claude produced empty report"
                    cat "$LLM_LOG"
                    exit 1
                fi
            else
                log_error "Claude analysis failed"
                cat "$LLM_LOG"
                exit 1
            fi
            ;;
        gemini)
            log_error "Gemini provider stub: not enabled in this test suite yet"
            exit 1
            ;;
        *)
            log_error "Unknown LLM provider: ${LLM_PROVIDER}"
            exit 1
            ;;
    esac
else
    log_error "No prompt.md found in $SKILL_DIR"
    exit 1
fi

# Step 5: Verify report
if [[ "$SKIP_VERIFY" == "false" && -f "$SKILL_DIR/expected.md" ]]; then
    log_info "Verifying report..."
    if "$SCRIPT_DIR/verify-report.sh" "$REPORT" "$SKILL_DIR/expected.md"; then
        log_success "Verification passed"
    else
        log_warn "Verification failed or incomplete"
    fi
else
    if [[ "$SKIP_VERIFY" == "true" ]]; then
        log_info "Skipping verification (--skip-verify)"
    else
        log_warn "No expected.md found, skipping verification"
    fi
fi

# Optional post-run SQL (cleanup or reset state)
if [[ -f "$SKILL_DIR/post.sql" ]]; then
    log_info "Running post-run SQL..."
    if command -v envsubst &> /dev/null; then
        TMP_POST=$(mktemp)
        envsubst < "$SKILL_DIR/post.sql" > "$TMP_POST"
        run_script_in_db "$TMP_POST" "$DB_NAME"
        rm -f "$TMP_POST"
    else
        run_script_in_db "$SKILL_DIR/post.sql" "$DB_NAME"
    fi
    log_success "Post-run SQL complete"
fi

# Step 6: Cleanup if requested
if [[ "$CLEANUP_AFTER" == "true" ]]; then
    drop_database "$DB_NAME"
fi

echo ""
log_success "Test complete: $SKILL"
echo "Report: $REPORT"
