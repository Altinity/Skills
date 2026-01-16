#!/bin/bash
# Run a single ClickHouse analyst sub-agent
# 1. Execute SQL queries directly via clickhouse-client
# 2. Pass results to selected LLM for analysis (default: Codex)
#
# Usage:
#   ./run-agent.sh <agent-name> <context> [--llm-provider <claude|codex|gemini>] [--llm-model <name>] [--query-timeout-sec <secs>] [--dry-run] [-- <clickhouse-client args...>]
#   ./run-agent.sh --list-agents
#   ./run-agent.sh --test-connection [-- <clickhouse-client args...>]
#
# Environment variables for ClickHouse connection (used if no explicit args after --):
#   CLICKHOUSE_HOST     - ClickHouse server hostname (default: localhost)
#   CLICKHOUSE_PORT     - ClickHouse native port (default: 9000)
#   CLICKHOUSE_USER     - Username for authentication
#   CLICKHOUSE_PASSWORD - Password for authentication
#   CLICKHOUSE_SECURE   - Set to 1 for TLS connection (--secure flag)
#   CLICKHOUSE_DATABASE - Default database
#
# Examples:
#   ./run-agent.sh memory "OOM at 14:30" -- --host=prod-ch --user=admin
#   ./run-agent.sh reporting "p95 spike" --llm-provider gemini -- --host=prod-ch
#   ./run-agent.sh reporting "p95 spike" --dry-run -- --host=prod-ch
#   ./run-agent.sh --list-agents
#
#   # Using environment variables (no -- needed):
#   CLICKHOUSE_HOST=prod-ch CLICKHOUSE_USER=admin ./run-agent.sh memory "OOM"

set -euo pipefail

# Resolve paths relative to the skill root so the script works from any CWD.
SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENTS_DIR="$SKILL_ROOT/agents"

# All writes should stay under the invocation directory (PWD).
WORK_ROOT="$PWD"
AGENTS_HOME="${WORK_ROOT}/.agents"
mkdir -p "$AGENTS_HOME/tmp"

usage() {
    echo "Usage: $0 <agent-name> <context> [--llm-provider <claude|codex|gemini>] [--llm-model <name>] [--query-timeout-sec <secs>] [--dry-run] [-- <clickhouse-client args...>]" >&2
    echo "       $0 --list-agents" >&2
    echo "       $0 --test-connection [-- <clickhouse-client args...>]" >&2
    echo "" >&2
    echo "Connection can be configured via CLICKHOUSE_HOST, CLICKHOUSE_USER, CLICKHOUSE_PASSWORD," >&2
    echo "CLICKHOUSE_PORT, CLICKHOUSE_DATABASE, CLICKHOUSE_SECURE environment variables." >&2
}

list_agents() {
    for d in "$AGENTS_DIR"/*/; do
        if [[ -f "$d/queries.sql" && -f "$d/prompt.md" ]]; then
            basename "$d"
        fi
    done | sort | tr '\n' ' '
    echo
}

# Build clickhouse-client args from environment variables
build_ch_args_from_env() {
    local -a args=()
    [[ -n "${CLICKHOUSE_HOST:-}" ]] && args+=("--host=${CLICKHOUSE_HOST}")
    [[ -n "${CLICKHOUSE_PORT:-}" ]] && args+=("--port=${CLICKHOUSE_PORT}")
    [[ -n "${CLICKHOUSE_USER:-}" ]] && args+=("--user=${CLICKHOUSE_USER}")
    [[ -n "${CLICKHOUSE_PASSWORD:-}" ]] && args+=("--password=${CLICKHOUSE_PASSWORD}")
    [[ -n "${CLICKHOUSE_DATABASE:-}" ]] && args+=("--database=${CLICKHOUSE_DATABASE}")
    [[ "${CLICKHOUSE_SECURE:-0}" == "1" ]] && args+=("--secure")
    echo "${args[@]+"${args[@]}"}"
}

run_clickhouse() {
    HOME="$AGENTS_HOME" clickhouse-client ${CH_ARGS[@]+"${CH_ARGS[@]}"} "$@"
}

# Handle --list-agents before other argument parsing
if [[ "${1:-}" == "--list-agents" ]]; then
    list_agents
    exit 0
fi

# Handle --test-connection
if [[ "${1:-}" == "--test-connection" ]]; then
    shift
    # Parse optional -- <ch-args>
    TEST_CH_ARGS=()
    if [[ "${1:-}" == "--" ]]; then
        shift
        TEST_CH_ARGS=("$@")
    else
        # Use env vars
        CH_ARGS_FROM_ENV="$(build_ch_args_from_env)"
        [[ -n "$CH_ARGS_FROM_ENV" ]] && read -r -a TEST_CH_ARGS <<<"$CH_ARGS_FROM_ENV"
    fi

    TEST_QUERY="SELECT hostName() AS host, version() AS version, uptime() AS uptime_sec, formatReadableTimeDelta(uptime()) AS uptime"
    if OUTPUT=$(HOME="$AGENTS_HOME" clickhouse-client ${TEST_CH_ARGS[@]+"${TEST_CH_ARGS[@]}"} --format=PrettyCompactNoEscapes --query "$TEST_QUERY" 2>&1); then
        echo "Connection OK"
        echo "$OUTPUT"
        exit 0
    else
        echo "Connection FAILED" >&2
        echo "$OUTPUT" >&2
        echo "" >&2
        echo "Configure connection via environment variables:" >&2
        echo "  export CLICKHOUSE_HOST=<hostname>" >&2
        echo "  export CLICKHOUSE_USER=<username>" >&2
        echo "  export CLICKHOUSE_PASSWORD=<password>" >&2
        echo "  export CLICKHOUSE_SECURE=1  # for TLS" >&2
        echo "" >&2
        echo "Or provide explicit args:" >&2
        echo "  $0 --test-connection -- --host=<host> --user=<user> --password=<pass>" >&2
        exit 1
    fi
fi

AGENT_NAME="${1:-}"
CONTEXT="${2:-}"
if [[ -z "${AGENT_NAME}" ]]; then usage; exit 1; fi
shift 2 || true

LLM_PROVIDER="${CH_ANALYST_LLM_PROVIDER:-codex}"
LLM_MODEL="${CH_ANALYST_LLM_MODEL:-}"
DRY_RUN=0
MAX_RETRIES="${CH_ANALYST_LLM_RETRIES:-1}"
PROMPT_SIZE_WARN="${CH_ANALYST_PROMPT_SIZE_WARN:-100000}"
QUERY_TIMEOUT_SEC=""

# Initialize CH_ARGS from environment variables (can be overridden by explicit args after --)
CH_ARGS_FROM_ENV="$(build_ch_args_from_env)"
CH_ARGS=()
[[ -n "$CH_ARGS_FROM_ENV" ]] && read -r -a CH_ARGS <<<"$CH_ARGS_FROM_ENV"
CH_ARGS_EXPLICIT=0

# Create temp dir early (needed by run_llm for codex). Keep it under WORK_ROOT.
TMP_DIR="$(mktemp -d "${AGENTS_HOME}/tmp/run-agent.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

while [[ $# -gt 0 ]]; do
    case "$1" in
        --llm-provider)
            LLM_PROVIDER="${2:-}"; shift 2 || true ;;
        --llm-model)
            LLM_MODEL="${2:-}"; shift 2 || true ;;
        --query-timeout-sec)
            QUERY_TIMEOUT_SEC="${2:-}"; shift 2 || true ;;
        --dry-run)
            DRY_RUN=1; shift ;;
        --)
            shift
            if [[ $# -gt 0 ]]; then
                # Explicit args override env-based defaults
                CH_ARGS=("$@")
                CH_ARGS_EXPLICIT=1
            fi
            break
            ;;
        *)
            echo "Error: unknown argument: $1" >&2
            usage
            exit 2
            ;;
    esac
done

AGENT_DIR="$AGENTS_DIR/${AGENT_NAME}"
SQL_FILE="$AGENT_DIR/queries.sql"
PROMPT_FILE="$AGENT_DIR/prompt.md"

# Validate files exist
if [[ ! -f "$SQL_FILE" ]]; then
    echo "Error: SQL file not found: $SQL_FILE" >&2
    exit 1
fi
if [[ ! -f "$PROMPT_FILE" ]]; then
    echo "Error: Prompt file not found: $PROMPT_FILE" >&2
    exit 1
fi

run_llm_once() {
    local provider="$1"
    local model="$2"
    local prompt="$3"

    case "$provider" in
        claude)
            # Keep current invocation (known-good).
            claude --print --dangerously-skip-permissions -p "$prompt" 2>/dev/null
            ;;
        codex)
            # Run Codex with a writable HOME in the current working directory so it can create
            # session files under $HOME/.codex/sessions even in sandboxed environments.
            local codex_home="${CH_ANALYST_CODEX_HOME:-$PWD/.agents}"
            mkdir -p "$codex_home/.codex/sessions" 2>/dev/null || true
            if [[ -d "$HOME/.codex" ]]; then
                [[ -f "$HOME/.codex/auth.json" && ! -f "$codex_home/.codex/auth.json" ]] && cp "$HOME/.codex/auth.json" "$codex_home/.codex/auth.json" 2>/dev/null || true
                [[ -f "$HOME/.codex/config.toml" && ! -f "$codex_home/.codex/config.toml" ]] && cp "$HOME/.codex/config.toml" "$codex_home/.codex/config.toml" 2>/dev/null || true
                [[ -f "$HOME/.codex/version.json" && ! -f "$codex_home/.codex/version.json" ]] && cp "$HOME/.codex/version.json" "$codex_home/.codex/version.json" 2>/dev/null || true
                if [[ -d "$HOME/.codex/rules" && ! -d "$codex_home/.codex/rules" ]]; then
                    cp -R "$HOME/.codex/rules" "$codex_home/.codex/" 2>/dev/null || true
                fi
            fi

            if ! command -v codex >/dev/null 2>&1; then
                echo "Error: codex CLI not found in PATH" >&2
                return 127
            fi

            local tmp_out tmp_err
            tmp_out="$TMP_DIR/codex_last_message.txt"
            tmp_err="$TMP_DIR/codex.stderr.txt"
            rm -f "$tmp_out" "$tmp_err"

            local -a codex_cmd=(codex -a never -s workspace-write exec --skip-git-repo-check --output-last-message "$tmp_out")
            [[ -n "$model" ]] && codex_cmd+=( -m "$model" )

            # Run Codex non-interactively and capture the final assistant message.
            if ! printf '%s' "$prompt" | HOME="$codex_home" "${codex_cmd[@]}" - >/dev/null 2>"$tmp_err"; then
                echo "Error: codex exec failed" >&2
                [[ -s "$tmp_err" ]] && sed -n '1,80p' "$tmp_err" >&2
                return 3
            fi

            if [[ -s "$tmp_out" ]]; then
                cat "$tmp_out"
                return 0
            fi
            echo "Error: codex exec did not produce an output message" >&2
            return 3
            ;;
        gemini)
            # Stub: call `gemini` with prompt on stdin and no parameters.
            if ! command -v gemini >/dev/null 2>&1; then
                echo "Error: gemini CLI not found in PATH" >&2
                return 127
            fi
            printf '%s' "$prompt" | gemini
            ;;
        *)
            echo "Error: unknown --llm-provider '$provider' (expected: claude|codex|gemini)" >&2
            return 2
            ;;
    esac
}

run_llm() {
    local provider="$1"
    local model="$2"
    local prompt="$3"
    local retries="${4:-$MAX_RETRIES}"
    local attempt=1
    local output=""
    local rc=0

    while [[ $attempt -le $retries ]]; do
        output="$(run_llm_once "$provider" "$model" "$prompt")" && rc=0 || rc=$?
        if [[ $rc -eq 0 && -n "$output" ]]; then
            echo "$output"
            return 0
        fi
        if [[ $attempt -lt $retries ]]; then
            local delay=$((attempt * 2))
            echo "LLM attempt $attempt failed, retrying in ${delay}s..." >&2
            sleep "$delay"
        fi
        attempt=$((attempt + 1))
    done

    echo "$output"
    return $rc
}

call_llm() {
    # Capture stdout while preserving non-zero exit status (works under set -e).
    local provider="$1"
    local model="$2"
    local prompt="$3"
    local out
    set +e
    out="$(run_llm "$provider" "$model" "$prompt")"
    local rc=$?
    set -e
    printf '%s' "$out"
    return $rc
}

validate_json() {
    local json="$1"
    command -v jq >/dev/null 2>&1 && echo "$json" | jq -e . >/dev/null 2>&1
}

normalize_llm_output() {
    # Many models wrap JSON in ```json fences; strip those and trim whitespace.
    # This keeps the "JSON-only" contract while being tolerant of common formatting.
    local s="$1"
    s="$(printf '%s\n' "$s" | sed '/^[[:space:]]*```/d')"
    s="$(printf '%s' "$s" | awk 'BEGIN{RS=""; ORS="";} {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0); print $0}')"
    printf '%s' "$s"
}

validate_agent_output() {
    local expected_agent="$1"
    local json="$2"

    echo "$json" | jq -e --arg agent "$expected_agent" '
      type == "object"
      and (.agent? == $agent)
      and (.status? | type == "string" and IN("critical","major","moderate","ok"))
      and (.findings? | type == "array")
      and (all(.findings[]?;
            (type == "object")
            and (.severity? | type == "string" and IN("critical","major","moderate","minor"))
            and (.title? | type == "string")
            and (.evidence? | type == "string")
            and (.recommendation? | type == "string")
            and ((.values? | type == "object") or (.values? == null) or (has("values") | not))
          ))
    ' >/dev/null 2>&1
}

emit_error_json() {
    local error_type="$1"
    local message="$2"
    local raw_chars="${3:-0}"
    printf '{"error": "%s", "agent": "%s", "provider": "%s", "message": "%s", "raw_output_chars": %s}\n' \
        "$error_type" "$AGENT_NAME" "$LLM_PROVIDER" "$message" "$raw_chars"
}

run_sql_file() {
    local file="$1"
    local max_execution_time="${2:-}"
    local -a args=(--format=JSONCompact --multiquery --queries-file "$file")

    if [[ -n "${max_execution_time}" ]] && [[ "${max_execution_time}" != "0" ]]; then
        args+=("--max_execution_time=${max_execution_time}")
    fi

    run_clickhouse "${args[@]}"
}

# Step 1: Execute SQL queries as-is
RUNS_ROOT="$PWD/runs"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-${AGENT_NAME}"
ARTIFACTS_DIR=""
if [[ "${CH_ANALYST_KEEP_ARTIFACTS:-0}" == "1" ]]; then
    ARTIFACTS_DIR="$RUNS_ROOT/$RUN_ID"
    mkdir -p "$ARTIFACTS_DIR"
fi

if [[ -n "$ARTIFACTS_DIR" ]]; then
    cp "$SQL_FILE" "$ARTIFACTS_DIR/queries.original.sql" 2>/dev/null || true
    {
        echo "agent=$AGENT_NAME"
        echo "llm_provider=$LLM_PROVIDER"
        echo "llm_model=${LLM_MODEL:-}"
        echo "dry_run=$DRY_RUN"
        echo "query_timeout_sec=${QUERY_TIMEOUT_SEC:-}"
        echo "clickhouse_args=${CH_ARGS[*]-}"
        echo "clickhouse_args_source=$( [[ $CH_ARGS_EXPLICIT -eq 1 ]] && echo "explicit" || echo "env" )"
        echo "time=$(date -Iseconds)"
    } >"$ARTIFACTS_DIR/meta.txt" 2>/dev/null || true
fi

STATIC_MAX_TIME="$QUERY_TIMEOUT_SEC"
QUERY_OUT="$TMP_DIR/query_results.out"
QUERY_ERR="$TMP_DIR/query_results.err"
QUERY_STATUS=0

if ! run_sql_file "$SQL_FILE" "$STATIC_MAX_TIME" >"$QUERY_OUT" 2>"$QUERY_ERR"; then
    QUERY_STATUS=$?
fi

QUERY_RESULTS="$(cat "$QUERY_OUT")"
QUERY_ERRORS="$(cat "$QUERY_ERR")"

if [[ -n "$ARTIFACTS_DIR" ]]; then
    printf '%s' "$QUERY_RESULTS" >"$ARTIFACTS_DIR/query_results.txt" 2>/dev/null || true
    printf '%s' "$QUERY_ERRORS" >"$ARTIFACTS_DIR/query_errors.txt" 2>/dev/null || true
fi

# Dry-run mode: output query results and exit
if [[ "$DRY_RUN" == "1" ]]; then
    echo "=== DRY RUN: Query Results (no LLM) ===" >&2
    echo "$QUERY_RESULTS"
    if [[ -n "$QUERY_ERRORS" ]]; then
        echo "=== DRY RUN: Query Errors (stderr) ===" >&2
        echo "$QUERY_ERRORS" >&2
    fi
    exit 0
fi

# Step 2: Build prompt with query results
ANALYSIS_PROMPT="$(cat "$PROMPT_FILE")

---
## Runtime Context
- Problem: $CONTEXT
- Agent: $AGENT_NAME
- Time: $(date -Iseconds)
- Query exit code: $QUERY_STATUS

## Query Results (JSONCompact)
$QUERY_RESULTS"

if [[ -n "$QUERY_ERRORS" ]]; then
    ANALYSIS_PROMPT="$ANALYSIS_PROMPT

## Query Errors (stderr)
$QUERY_ERRORS"
fi

ANALYSIS_PROMPT="$ANALYSIS_PROMPT

---
Analyze the query results above and return JSON findings."

if [[ -n "$ARTIFACTS_DIR" ]]; then
    printf '%s' "$ANALYSIS_PROMPT" >"$ARTIFACTS_DIR/prompt.txt" 2>/dev/null || true
fi

# Prompt size warning
PROMPT_SIZE=${#ANALYSIS_PROMPT}
if [[ $PROMPT_SIZE -gt $PROMPT_SIZE_WARN ]]; then
    echo "Warning: prompt size ($PROMPT_SIZE chars) may exceed LLM context limit" >&2
fi

# Step 3: Run LLM + validate/repair JSON once
if ! RAW_OUTPUT="$(call_llm "$LLM_PROVIDER" "$LLM_MODEL" "$ANALYSIS_PROMPT")"; then
    emit_error_json "llm_failed" "LLM provider '$LLM_PROVIDER' failed to run" "0" >&2
    exit 4
fi
if [[ -n "$ARTIFACTS_DIR" ]]; then
    printf '%s' "$RAW_OUTPUT" >"$ARTIFACTS_DIR/llm_output.raw.txt" 2>/dev/null || true
fi
RAW_OUTPUT_CLEAN="$(normalize_llm_output "$RAW_OUTPUT")"
if [[ -n "$ARTIFACTS_DIR" ]]; then
    printf '%s' "$RAW_OUTPUT_CLEAN" >"$ARTIFACTS_DIR/llm_output.cleaned.txt" 2>/dev/null || true
fi
if validate_json "$RAW_OUTPUT_CLEAN" && validate_agent_output "$AGENT_NAME" "$RAW_OUTPUT_CLEAN"; then
    echo "$RAW_OUTPUT_CLEAN"
    [[ -n "$ARTIFACTS_DIR" ]] && printf '%s' "$RAW_OUTPUT_CLEAN" >"$ARTIFACTS_DIR/output.json" 2>/dev/null || true
    exit 0
fi

REPAIR_PROMPT="You produced invalid JSON. Return ONLY valid JSON matching the required output format. No prose.

Agent: $AGENT_NAME
Problem: $CONTEXT

Invalid output:
$RAW_OUTPUT"

if ! REPAIRED_OUTPUT="$(call_llm "$LLM_PROVIDER" "$LLM_MODEL" "$REPAIR_PROMPT")"; then
    emit_error_json "llm_failed" "LLM provider '$LLM_PROVIDER' failed to run (repair pass)" "0" >&2
    exit 4
fi
if [[ -n "$ARTIFACTS_DIR" ]]; then
    printf '%s' "$REPAIRED_OUTPUT" >"$ARTIFACTS_DIR/llm_output.repaired.txt" 2>/dev/null || true
fi
REPAIRED_OUTPUT_CLEAN="$(normalize_llm_output "$REPAIRED_OUTPUT")"
if [[ -n "$ARTIFACTS_DIR" ]]; then
    printf '%s' "$REPAIRED_OUTPUT_CLEAN" >"$ARTIFACTS_DIR/llm_output.repaired.cleaned.txt" 2>/dev/null || true
fi
if validate_json "$REPAIRED_OUTPUT_CLEAN" && validate_agent_output "$AGENT_NAME" "$REPAIRED_OUTPUT_CLEAN"; then
    echo "$REPAIRED_OUTPUT_CLEAN"
    [[ -n "$ARTIFACTS_DIR" ]] && printf '%s' "$REPAIRED_OUTPUT_CLEAN" >"$ARTIFACTS_DIR/output.json" 2>/dev/null || true
    exit 0
fi

RAW_CHARS=${#RAW_OUTPUT}
emit_error_json "invalid_json" "LLM output failed validation after repair attempt" "$RAW_CHARS" >&2
echo "$RAW_OUTPUT" >&2
exit 3
