#!/bin/bash
# Run all agents in dry-run mode (SQL only, no LLM).
# Usage:
#   ./run-all-dry.sh [--timeout <secs>] [-- <clickhouse-client args...>]

set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")/../altinity-clickhouse-expert/scripts" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PARALLEL_TIMEOUT="${CH_ANALYST_PARALLEL_TIMEOUT_SEC:-300}"
CH_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --timeout)
            PARALLEL_TIMEOUT="${2:-}"; shift 2 || true ;;
        --)
            shift
            CH_ARGS=("$@")
            break
            ;;
        *)
            echo "Error: unknown argument: $1" >&2
            echo "Usage: $0 [--timeout <secs>] [-- <clickhouse-client args...>]" >&2
            exit 2
            ;;
    esac
done

AGENTS_RAW="$("$SKILL_ROOT/scripts/run-agent.sh" --list-agents)"
read -r -a AGENTS <<<"$AGENTS_RAW"

if [[ ${#AGENTS[@]} -eq 0 ]]; then
    echo "Error: no agents found" >&2
    exit 1
fi

"$SKILL_ROOT/scripts/run-parallel.sh" \
    "dry run" \
    --dry-run \
    --timeout "$PARALLEL_TIMEOUT" \
    -- ${CH_ARGS[@]+"${CH_ARGS[@]}"} \
    --agents "${AGENTS[@]}"
