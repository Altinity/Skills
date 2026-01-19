#!/bin/bash
# Common functions for skill tests

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Build clickhouse-client arguments from environment variables
build_client_args() {
    CLIENT_ARGS=(
        --host "${CLICKHOUSE_HOST:-localhost}"
        --port "${CLICKHOUSE_PORT:-9000}"
        --user "${CLICKHOUSE_USER:-default}"
    )

    if [[ -n "${CLICKHOUSE_PASSWORD:-}" ]]; then
        CLIENT_ARGS+=(--password "${CLICKHOUSE_PASSWORD}")
    fi

    case "${CLICKHOUSE_SECURE:-false}" in
        true|1|yes|on)
            CLIENT_ARGS+=(--secure)
            ;;
    esac
}

# Run a single query
run_query() {
    local query="$1"
    build_client_args
    clickhouse-client "${CLIENT_ARGS[@]}" --query "$query"
}

# Run a SQL script file
run_script() {
    local script="$1"
    build_client_args
    clickhouse-client "${CLIENT_ARGS[@]}" --multiquery < "$script"
}

# Run a SQL script with database context
run_script_in_db() {
    local script="$1"
    local db="$2"
    build_client_args
    clickhouse-client "${CLIENT_ARGS[@]}" --database "$db" --multiquery < "$script"
}

# Run a SQL script with database context, but continue on errors
run_script_in_db_ignore_errors() {
    local script="$1"
    local db="$2"
    build_client_args
    clickhouse-client "${CLIENT_ARGS[@]}" --database "$db" --multiquery --ignore-error < "$script"
}

# Validate environment variables are set
validate_env() {
    local missing=0

    if [[ -z "${CLICKHOUSE_HOST:-}" ]]; then
        log_error "CLICKHOUSE_HOST is not set"
        missing=1
    fi

    if [[ -z "${CLICKHOUSE_USER:-}" ]]; then
        log_warn "CLICKHOUSE_USER is not set, using 'default'"
    fi

    if [[ $missing -eq 1 ]]; then
        echo ""
        echo "Required environment variables:"
        echo "  CLICKHOUSE_HOST     - ClickHouse server hostname"
        echo ""
        echo "Optional environment variables:"
        echo "  CLICKHOUSE_PORT     - Native protocol port (default: 9000)"
        echo "  CLICKHOUSE_USER     - Database user (default: default)"
        echo "  CLICKHOUSE_PASSWORD - User password (default: empty)"
        echo "  CLICKHOUSE_SECURE   - Use TLS (default: false)"
        exit 1
    fi
}

# Validate connection to ClickHouse
validate_connection() {
    log_info "Validating ClickHouse connection..."

    local result
    if result=$(run_query "SELECT version()" 2>&1); then
        log_success "Connected to ClickHouse version: $result"
        return 0
    else
        log_error "Failed to connect to ClickHouse"
        log_error "$result"
        return 1
    fi
}

# Create database if not exists
create_database() {
    local db="$1"
    log_info "Creating database: $db"
    run_query "CREATE DATABASE IF NOT EXISTS \`$db\`"
    log_success "Database ready: $db"
}

# Drop database if exists
drop_database() {
    local db="$1"
    log_info "Dropping database: $db"
    run_query "DROP DATABASE IF EXISTS \`$db\`"
    log_success "Database dropped: $db"
}

# Get database name from skill path
get_db_name() {
    local skill="$1"
    # Convert path to database name: chaining/memory-to-merges -> test-memory-to-merges
    if [[ "$skill" == chaining/* ]]; then
        echo "test-$(basename "$skill")"
    else
        basename "$skill"
    fi
}

# If script is run directly (not sourced), execute validate_env
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        validate_env)
            validate_env
            ;;
        validate_connection)
            validate_env
            validate_connection
            ;;
        *)
            echo "Usage: $0 {validate_env|validate_connection}"
            exit 1
            ;;
    esac
fi
