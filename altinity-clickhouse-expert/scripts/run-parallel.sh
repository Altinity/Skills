#!/bin/bash
# Run multiple ClickHouse analyst agents in parallel
# Usage:
#   ./run-parallel.sh <context> [--llm-provider <claude|codex|gemini>] [--llm-model <name>] [--dry-run] [--timeout <secs>] [-- <clickhouse-client args...>] --agents <agent1> [agent2...]
#
# Back-compat (legacy, stringly args):
#   ./run-parallel.sh <context> "<ch-args>" <agent1> [agent2...]
#
# Environment:
#   CH_ANALYST_PARALLEL_TIMEOUT_SEC: Overall timeout for all agents (default: 300)
#
# ClickHouse connection can also be configured via environment variables
# (inherited by run-agent.sh): CLICKHOUSE_HOST, CLICKHOUSE_USER, CLICKHOUSE_PASSWORD,
# CLICKHOUSE_PORT, CLICKHOUSE_DATABASE, CLICKHOUSE_SECURE

set -euo pipefail

# All writes should stay under the invocation directory (PWD).
WORK_ROOT="$PWD"
AGENTS_HOME="${WORK_ROOT}/.agents"
mkdir -p "$AGENTS_HOME/tmp"

usage() {
    echo "Usage: $0 <context> [--llm-provider <claude|codex|gemini>] [--llm-model <name>] [--dry-run] [--timeout <secs>] -- <clickhouse-client args...> --agents <agent1> [agent2...]" >&2
}

CONTEXT="${1:-}"
if [[ -z "${CONTEXT}" ]]; then usage; exit 1; fi
shift 1 || true

LLM_PROVIDER=""
LLM_MODEL=""
DRY_RUN=0
PARALLEL_TIMEOUT="${CH_ANALYST_PARALLEL_TIMEOUT_SEC:-300}"
CH_ARGS=()
AGENTS=()

if [[ $# -ge 2 ]] && [[ "${1:-}" != --* ]] && [[ "${2:-}" != "--" ]]; then
    # Legacy mode: context + "ch-args string" + agents...
    LEGACY_CH_ARGS="${1:-}"
    shift 1 || true
    AGENTS=("$@")
    # Split legacy string on whitespace (best-effort).
    read -r -a CH_ARGS <<<"${LEGACY_CH_ARGS}"
else
    # New mode: optional llm flags, then -- <ch args...> --agents <agents...>
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --llm-provider) LLM_PROVIDER="${2:-}"; shift 2 || true ;;
            --llm-model) LLM_MODEL="${2:-}"; shift 2 || true ;;
            --dry-run) DRY_RUN=1; shift ;;
            --timeout) PARALLEL_TIMEOUT="${2:-}"; shift 2 || true ;;
            --)
                shift
                # Consume clickhouse args until --agents
                while [[ $# -gt 0 ]] && [[ "${1:-}" != "--agents" ]]; do
                    CH_ARGS+=("$1")
                    shift
                done
                ;;
            --agents)
                shift
                AGENTS=("$@")
                break
                ;;
            *)
                echo "Error: unknown argument: $1" >&2
                usage
                exit 2
                ;;
        esac
    done
fi

if [[ ${#AGENTS[@]} -eq 0 ]]; then
    echo "Error: no agents specified" >&2
    usage
    exit 2
fi

	# Resolve paths relative to the skill root so the script works from any CWD.
		SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
		SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
		SKILL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
		OUTPUT_DIR=$(mktemp -d "${AGENTS_HOME}/tmp/run-parallel.XXXXXX")
		trap 'rm -rf "$OUTPUT_DIR"' EXIT
		PIDS=()
		START_TIME=$(date +%s)

# Spawn agents in background
for AGENT in "${AGENTS[@]}"; do
    OUT_FILE="$OUTPUT_DIR/${AGENT}.out"
    ERR_FILE="$OUTPUT_DIR/${AGENT}.err"
    STATUS_FILE="$OUTPUT_DIR/${AGENT}.status"

    (
        set +e
	        cmd=( "$SKILL_ROOT/scripts/run-agent.sh" "$AGENT" "$CONTEXT" )
        [[ -n "$LLM_PROVIDER" ]] && cmd+=( --llm-provider "$LLM_PROVIDER" )
        [[ -n "$LLM_MODEL" ]] && cmd+=( --llm-model "$LLM_MODEL" )
        [[ "$DRY_RUN" == "1" ]] && cmd+=( --dry-run )
        cmd+=( -- ${CH_ARGS[@]+"${CH_ARGS[@]}"} )
        "${cmd[@]}" >"$OUT_FILE" 2>"$ERR_FILE"
        echo $? >"$STATUS_FILE"
    ) &
    PIDS+=($!)
    echo "Started $AGENT agent (PID $!)" >&2
done

# Wait for all agents with timeout
FAILED=0
TIMED_OUT=0
for i in "${!PIDS[@]}"; do
    pid="${PIDS[$i]}"
    agent="${AGENTS[$i]}"

    # Check if we've exceeded overall timeout
    ELAPSED=$(( $(date +%s) - START_TIME ))
    if [[ $ELAPSED -ge $PARALLEL_TIMEOUT ]]; then
        echo "Timeout exceeded, killing remaining agents..." >&2
        for j in "${!PIDS[@]}"; do
            kill "${PIDS[$j]}" 2>/dev/null || true
        done
        TIMED_OUT=1
        break
    fi

    # Calculate remaining time for this wait
    REMAINING=$(( PARALLEL_TIMEOUT - ELAPSED ))

    # Wait with timeout (bash 4.3+ supports wait -t, fallback to simple wait)
    if ! wait "$pid" 2>/dev/null; then
        echo "Agent $agent failed" >&2
        FAILED=$((FAILED + 1))
    fi
done

# Emit always-valid JSON (escape raw outputs)
json_escape() {
    # Read stdin and emit a JSON string value.
    jq -Rs .
}

echo "{"
echo "  \"agents\": ["
first=true
for AGENT in "${AGENTS[@]}"; do
    out_file="$OUTPUT_DIR/${AGENT}.out"
    err_file="$OUTPUT_DIR/${AGENT}.err"
    status_file="$OUTPUT_DIR/${AGENT}.status"
    exit_code="1"
    [[ -f "$status_file" ]] && exit_code="$(cat "$status_file")"

    $first || echo ","
    first=false

    echo "    {"
    echo "      \"name\": $(printf '%s' "$AGENT" | json_escape),"
    echo "      \"exit_code\": $exit_code,"
    if [[ "$DRY_RUN" == "1" ]] && [[ "$exit_code" == "0" ]]; then
        echo "      \"ok\": true,"
        echo "      \"output\": null,"
        echo "      \"output_raw\": $(cat "$out_file" 2>/dev/null | json_escape),"
    elif [[ "$exit_code" == "0" ]] && jq -e . >/dev/null 2>&1 <"$out_file"; then
        echo "      \"ok\": true,"
        echo "      \"output\": $(cat "$out_file"),"
        echo "      \"output_raw\": null,"
    else
        echo "      \"ok\": false,"
        echo "      \"output\": null,"
        echo "      \"output_raw\": $(cat "$out_file" 2>/dev/null | json_escape),"
    fi
    echo "      \"stderr\": $(cat "$err_file" 2>/dev/null | json_escape)"
    echo "    }"
done
echo "  ],"
echo "  \"failed_count\": $FAILED,"
echo "  \"timed_out\": $( [[ $TIMED_OUT -eq 1 ]] && echo "true" || echo "false" ),"
echo "  \"elapsed_sec\": $(( $(date +%s) - START_TIME ))"
echo "}"
