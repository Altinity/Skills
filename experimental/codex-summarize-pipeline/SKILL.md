---
name: codex-summarize-pipeline
description: Summarize huge articles (URL or local file) via a Codex CLI-driven chunk→reduce pipeline, keeping only the final short summary in context and saving it to summaries/*.md.
---

# Codex Summarize Pipeline

Use this skill to summarize long articles without loading the full text into the chat context.

## Guarantees / constraints

- Use only local tools and the `codex` CLI (no direct API calls in your code).
- Do not paste the full article into the conversation.
- Keep only the final short summary (and the output file path) in the assistant response.
- Always save the summary to a markdown file under `summaries/`.

See `README.md` in this skill for detailed usage and recommended defaults for HTML-extracted blogs/docs.

## Default flow (URL)

1. Pick a slug for filenames (short, filesystem-safe).
2. Fetch + extract text:
   - `python3 <skill>/tools/fetch_article_text.py --url "<URL>" --output .codex-pipeline/inputs/<slug>.txt`
3. Summarize (default `map-reduce`):
   - `python3 <skill>/tools/codex_summarize_pipeline.py --input .codex-pipeline/inputs/<slug>.txt --final-max-words 120 > summaries/<slug>.summary.md`
4. Respond with:
   - The path `summaries/<slug>.summary.md`
   - The final summary content only (short)

## Default flow (local file)

- `python3 <skill>/tools/codex_summarize_pipeline.py --input <path> --final-max-words 120 > summaries/<slug>.summary.md`

## Modes

- `map-reduce`: best general-purpose coverage.
- `extract-synthesize`: best when names/numbers/timeline matter.
- `question-led`: best when user has a specific goal (use `--goal`).

## Troubleshooting

- If extraction looks wrong, save the HTML and rerun:
  - `python3 <skill>/tools/fetch_article_text.py --input-html page.html --output .codex-pipeline/inputs/<slug>.txt`
- If `codex` is configured to run remote models and you want local-only, run with `--oss` + `--local-provider` (requires local LM server).
