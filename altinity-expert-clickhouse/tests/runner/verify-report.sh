#!/bin/bash
# Verify a skill report against expected findings using LLM

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 REPORT_FILE EXPECTED_FILE [OUTPUT_DIR]"
    exit 1
fi

REPORT_FILE="$1"
EXPECTED_FILE="$2"
OUTPUT_DIR="${3:-$(dirname "$REPORT_FILE")}"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
VERIFICATION_FILE="$OUTPUT_DIR/verification-$TIMESTAMP.json"
CODEX_VERIFY_MODEL="${CODEX_VERIFY_MODEL:-}"

# Validate files exist
if [[ ! -f "$REPORT_FILE" ]]; then
    log_error "Report file not found: $REPORT_FILE"
    exit 1
fi

if [[ ! -f "$EXPECTED_FILE" ]]; then
    log_error "Expected file not found: $EXPECTED_FILE"
    exit 1
fi

# Read file contents
REPORT_CONTENT=$(cat "$REPORT_FILE")
EXPECTED_CONTENT=$(cat "$EXPECTED_FILE")

# Build verification prompt
VERIFY_PROMPT=$(cat <<'EOF'
You are verifying a ClickHouse diagnostic report against expected findings.

## Report to Verify

```markdown
REPORT_PLACEHOLDER
```

## Expected Findings

```markdown
EXPECTED_PLACEHOLDER
```

## Task

Compare the report against expected findings. Evaluate:
1. Were the "Must Detect" findings identified?
2. Were the "Should Detect" findings identified?
3. Does the report have the expected structure?

Return ONLY valid JSON (no markdown, no explanation):
{
  "passed": boolean,
  "score": number,
  "must_detect_found": ["list of must-detect items found"],
  "must_detect_missed": ["list of must-detect items missed"],
  "should_detect_found": ["list of should-detect items found"],
  "should_detect_missed": ["list of should-detect items missed"],
  "structure_ok": boolean,
  "notes": "brief observations"
}

Scoring guidelines:
- Each "Must Detect" item found: +15 points
- Each "Should Detect" item found: +5 points
- Proper report structure: +10 points
- Base score: 0
- Maximum: 100

A test passes if:
- score >= 70
- All "Must Detect" items are found
EOF
)

# Substitute placeholders
VERIFY_PROMPT="${VERIFY_PROMPT//REPORT_PLACEHOLDER/$REPORT_CONTENT}"
VERIFY_PROMPT="${VERIFY_PROMPT//EXPECTED_PLACEHOLDER/$EXPECTED_CONTENT}"

log_info "Running LLM verification (provider: codex)..."

LLM_LOG="${VERIFICATION_FILE}.log"

run_codex_verify() {
    local model="$1"
    local args=(
        exec
        --dangerously-bypass-approvals-and-sandbox
        --skip-git-repo-check
        -C "$SCRIPT_DIR"
        -o "$VERIFICATION_FILE"
    )

    if [[ -n "$model" ]]; then
        args+=(-m "$model")
        echo "Using codex model for verification: $model" >> "$LLM_LOG"
    else
        echo "Using codex default model for verification" >> "$LLM_LOG"
    fi

    echo "$VERIFY_PROMPT" | codex "${args[@]}" >> "$LLM_LOG" 2>&1
}

if [[ -n "$CODEX_VERIFY_MODEL" ]]; then
    if run_codex_verify "$CODEX_VERIFY_MODEL"; then
        log_success "Verification complete: $VERIFICATION_FILE"
    else
        log_warn "Verification failed with CODEX_VERIFY_MODEL=$CODEX_VERIFY_MODEL; retrying with default model"
        if run_codex_verify ""; then
            log_success "Verification complete: $VERIFICATION_FILE"
        else
            log_error "Verification failed"
            cat "$LLM_LOG"
            exit 1
        fi
    fi
else
    # Try cheaper models first, fall back to default
    MODEL_CANDIDATES=("gpt-5.2-codex-mini" "gpt-4o-mini" "o4-mini" "")
    SUCCESS=false
    for model in "${MODEL_CANDIDATES[@]}"; do
        if run_codex_verify "$model"; then
            SUCCESS=true
            break
        fi
    done

    if [[ "$SUCCESS" == "true" ]]; then
        log_success "Verification complete: $VERIFICATION_FILE"
    else
        log_error "Verification failed"
        cat "$LLM_LOG"
        exit 1
    fi
fi

# Normalize JSON output (strip markdown fences if present)
PARSE_FILE="$VERIFICATION_FILE"
if command -v python3 &> /dev/null; then
    TMP_JSON="${VERIFICATION_FILE}.clean"
    python3 - "$VERIFICATION_FILE" "$TMP_JSON" <<'PY'
import sys

src = sys.argv[1]
dst = sys.argv[2]
text = open(src, "r", encoding="utf-8", errors="ignore").read()

# Extract first JSON object if possible
start = text.find("{")
end = text.rfind("}")
if start != -1 and end != -1 and end > start:
    text = text[start:end+1]

with open(dst, "w", encoding="utf-8") as f:
    f.write(text)
PY
    PARSE_FILE="$TMP_JSON"
fi

# Try to parse the JSON result
if command -v jq &> /dev/null; then
    # Extract key fields
    PASSED=$(jq -r '.passed // false' "$PARSE_FILE" 2>/dev/null || echo "unknown")
    SCORE=$(jq -r '.score // 0' "$PARSE_FILE" 2>/dev/null || echo "0")
    MUST_MISSED=$(jq -r '.must_detect_missed | length // 0' "$PARSE_FILE" 2>/dev/null || echo "0")

    echo ""
    echo "========================================"
    echo "Verification Results"
    echo "========================================"
    echo "Passed: $PASSED"
    echo "Score: $SCORE"
    echo "Must-detect items missed: $MUST_MISSED"
    echo ""

    # Show details if available
    jq -r '
        "Must Detect Found: " + (.must_detect_found | join(", ")),
        "Must Detect Missed: " + (.must_detect_missed | join(", ")),
        "Should Detect Found: " + (.should_detect_found | join(", ")),
        "Should Detect Missed: " + (.should_detect_missed | join(", ")),
        "Notes: " + .notes
    ' "$PARSE_FILE" 2>/dev/null || true

    echo "========================================"
    echo ""

    # Return exit code based on pass/fail
    if [[ "$PASSED" == "true" ]]; then
        exit 0
    else
        exit 1
    fi
else
    log_warn "jq not installed, cannot parse verification results"
    echo "Raw verification output:"
    cat "$VERIFICATION_FILE"
    exit 0
fi
