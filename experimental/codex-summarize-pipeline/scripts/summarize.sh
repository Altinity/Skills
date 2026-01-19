#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <url-or-path> [mode] [max_words] [goal]" >&2
  exit 2
fi

input="$1"
mode="${2:-map-reduce}"
max_words="${3:-120}"
goal="${4:-}"

SKILL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIPELINE_PY="$SKILL_ROOT/tools/codex_summarize_pipeline.py"
FETCH_PY="$SKILL_ROOT/tools/fetch_article_text.py"

mkdir -p summaries .codex-pipeline/inputs

slug="$(
  python3 - "$input" <<'PY'
import re, sys
from urllib.parse import urlparse
s = sys.argv[1]
if "://" in s:
  p = urlparse(s)
  base = (p.path.split("/")[-1] or p.netloc or "article")
else:
  base = s.split("/")[-1]
base = re.sub(r"\.[a-zA-Z0-9]+$", "", base)
base = re.sub(r"[^a-zA-Z0-9_.-]+", "_", base).strip("_")[:60] or "article"
print(base)
PY
)"

text_path=".codex-pipeline/inputs/${slug}.txt"
out_path="summaries/${slug}.summary.md"

if [[ "$input" == http://* || "$input" == https://* ]]; then
  python3 "$FETCH_PY" --url "$input" --output "$text_path"
  input_path="$text_path"
else
  input_path="$input"
fi

args=(--input "$input_path" --mode "$mode" --final-max-words "$max_words")
if [[ -n "$goal" ]]; then
  args+=(--goal "$goal")
fi

python3 "$PIPELINE_PY" "${args[@]}" > "$out_path"
echo "$out_path"
