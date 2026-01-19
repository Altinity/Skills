---
name: github-triage
description: Use the GitHub CLI (gh) to find and summarize relevant GitHub issues/PRs from an error message or keywords, preferring exact-phrase searches scoped to a repo and returning issue/PR numbers + URLs.
---

# GitHub Triage (gh-first)

Use this skill when the task is “find upstream issues/PRs for this error”.

## Default flow

Prefer running the bundled script and paste the results back:

`/Users/bvt/.codex/skills/github-triage/scripts/gh_triage.sh --repo OWNER/REPO --phrase "exact error text" --limit 10 --prs`

## If you must do it manually

- Issues (exact): `gh search issues --repo OWNER/REPO --match title,body "..." --limit 10`
- Then expand: `gh issue view N --repo OWNER/REPO --comments`

## Output

- Always include `OWNER/REPO#N` and the URL.
