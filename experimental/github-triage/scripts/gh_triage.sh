#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  gh_triage.sh --repo OWNER/REPO --phrase "exact error text" [--limit N] [--prs]
  gh_triage.sh --repo OWNER/REPO --keywords "k1 k2 ..." [--limit N] [--prs]

Notes:
  - Requires: gh (authenticated), jq
EOF
  exit 2
}

REPO=""
PHRASE=""
KEYWORDS=""
LIMIT="10"
INCLUDE_PRS="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2-}"; shift 2 ;;
    --phrase) PHRASE="${2-}"; shift 2 ;;
    --keywords) KEYWORDS="${2-}"; shift 2 ;;
    --limit) LIMIT="${2-}"; shift 2 ;;
    --prs) INCLUDE_PRS="1"; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
done

if [[ -z "$REPO" ]]; then
  echo "--repo is required" >&2
  usage
fi
if [[ -n "$PHRASE" && -n "$KEYWORDS" ]]; then
  echo "Use only one of --phrase or --keywords" >&2
  usage
fi
if [[ -z "$PHRASE" && -z "$KEYWORDS" ]]; then
  echo "Provide --phrase or --keywords" >&2
  usage
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh not found in PATH" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found in PATH" >&2
  exit 1
fi

json_fields="number,title,url,state,updatedAt,labels,repository"

search_issues_json() {
  local repo="$1"
  local mode="$2" # phrase|keywords
  local query="$3"
  local limit="$4"

  if [[ "$mode" == "phrase" ]]; then
    gh search issues --repo "$repo" --match title,body "$query" --limit "$limit" --json "$json_fields"
  else
    gh search issues --repo "$repo" "$query" --limit "$limit" --json "$json_fields"
  fi
}

format_issues_md() {
  jq -r '
    if length == 0 then
      "(no results)"
    else
      .[] |
      "- " +
      (.repository.nameWithOwner + "#" + (.number|tostring)) +
      " — " + (.title | gsub("[\\r\\n]+";" ")) +
      " — " + (.state|ascii_downcase) +
      " — updated " + (.updatedAt[0:10]) +
      (if (.labels|length) > 0 then " — labels: " + ((.labels|map(.name)|join(", "))) else "" end) +
      "\n  " + .url
    end
  '
}

echo "repo: $REPO" >&2
if [[ -n "$PHRASE" ]]; then
  echo "issues: exact phrase" >&2
  echo "query: $PHRASE" >&2
  issues_json="$(search_issues_json "$REPO" "phrase" "$PHRASE" "$LIMIT")"
  if [[ "$(printf '%s' "$issues_json" | jq 'length')" -eq 0 ]]; then
    kw="$(printf '%s' "$PHRASE" | tr -cs '[:alnum:]' ' ' | awk '{for (i=1;i<=NF && i<=10;i++) printf (i==1?$i:" "$i)}')"
    if [[ -n "$kw" ]]; then
      echo "issues: no exact hits; fallback keywords: $kw" >&2
      issues_json="$(search_issues_json "$REPO" "keywords" "$kw" "$LIMIT")"
    fi
  fi
else
  echo "issues: keywords" >&2
  echo "query: $KEYWORDS" >&2
  issues_json="$(search_issues_json "$REPO" "keywords" "$KEYWORDS" "$LIMIT")"
fi

echo "## Issues" 
printf '%s' "$issues_json" | format_issues_md

if [[ "$INCLUDE_PRS" == "1" ]]; then
  pr_fields="number,title,url,state,updatedAt,labels,repository"
  echo
  echo "## PRs"
  # Use "gh search prs" for PRs; keep query simple (phrase/keywords) and let GitHub handle matching.
  if [[ -n "$PHRASE" ]]; then
    pr_query="$PHRASE"
  else
    pr_query="$KEYWORDS"
  fi
  prs_json="$(gh search prs --repo "$REPO" "$pr_query" --limit "$LIMIT" --json "$pr_fields")"
  printf '%s' "$prs_json" | jq -r '
    if length == 0 then
      "(no results)"
    else
      .[] |
      "- " +
      (.repository.nameWithOwner + "#" + (.number|tostring)) +
      " — " + (.title | gsub("[\\r\\n]+";" ")) +
      " — " + (.state|ascii_downcase) +
      " — updated " + (.updatedAt[0:10]) +
      (if (.labels|length) > 0 then " — labels: " + ((.labels|map(.name)|join(", "))) else "" end) +
      "\n  " + .url
    end
  '
fi
