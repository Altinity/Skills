# Codex Summarize Pipeline (Skill)

Summarize huge articles (URL or local file) via a Codex CLI-driven chunk → reduce pipeline, while keeping only the final short summary in the chat context.

This is designed for HTML-extracted blogs and docs: fetch the page, extract “article-ish” text, then summarize without pasting the full article into the conversation.

## Quick start (URL → summary file)

From any working directory:

```bash
bash /Users/bvt/.codex/skills/codex-summarize-pipeline/scripts/summarize.sh \
  "https://example.com/post" \
  map-reduce \
  120
```

This writes:

- `summaries/<slug>.summary.md` (final summary)
- `.codex-pipeline/inputs/<slug>.txt` (extracted text)
- `.codex-pipeline/<slug>-<timestamp>/...` (intermediate artifacts)

## Quick start (local file → summary file)

```bash
bash /Users/bvt/.codex/skills/codex-summarize-pipeline/scripts/summarize.sh \
  path/to/article.txt \
  map-reduce \
  120
```

## Modes (what they do + examples)

### 1) `map-reduce` (default; best general coverage)

What happens:

- Map: each chunk → bullets (key points, key facts, implications).
- Reduce: repeatedly compresses those bullets until one short final summary remains.

Use when:

- You want broad coverage across the whole article.
- The article is mostly narrative or mixed prose + snippets.

Example:

```bash
bash /Users/bvt/.codex/skills/codex-summarize-pipeline/scripts/summarize.sh \
  "https://site/post" \
  map-reduce \
  120
```

### 2) `extract-synthesize` (best for names/numbers/timeline)

What happens:

- Extract: each chunk → compact JSON `{claims,numbers,timeline,entities,open_questions}`.
- Merge: merges/dedupes JSON fragments into `merged_facts.json`.
- Synthesize: writes final summary from the merged fact record.

Use when:

- The post is heavy on versions, benchmarks, config flags, dates.

Example:

```bash
bash /Users/bvt/.codex/skills/codex-summarize-pipeline/scripts/summarize.sh \
  "https://site/post" \
  extract-synthesize \
  140
```

### 3) `question-led` (goal-driven; smallest footprint)

What happens:

- Each chunk → notes *only relevant* to your goal.
- Reduce: compresses goal-notes into one short final summary.

Use when:

- You want a specific lens: “risks”, “action items”, “decision brief”, etc.

Example:

```bash
bash /Users/bvt/.codex/skills/codex-summarize-pipeline/scripts/summarize.sh \
  "https://site/post" \
  question-led \
  120 \
  "Action items + risks"
```


## Recipe: “extended how-to” for HTML-extracted docs

Use `question-led`, increase `max_words`, and provide a very explicit goal that asks for settings, examples, and verification while excluding non-practical sections.

Example:

```bash
bash /Users/bvt/.codex/skills/codex-summarize-pipeline/scripts/summarize.sh \
  "https://site/post" \
  question-led \
  650 \
  "Write an extended operator how-to: prerequisites, enabling flags/settings, safe rollout steps, example SQL, how to verify progress. Keep it practical; avoid deep design rationale, pictures, and proofs."
```

Comprehensive example:

  Write an operator-facing HOWTO from this article. Include: (1) prerequisites/compatibility (versions, feature flags), (2) step-by-step enablement/rollout checklist, (3) key settings/knobs with recommended values and what each affects, (4) 2–4 minimal example commands (fenced code blocks) covering the main workflows, (5) verification steps/queries to confirm it’s working, (6) 5–10 gotchas/limits and safe defaults. Exclude: deep design rationale, historical narrative, benchmarks, marketing, images, and proofs. Keep it concise but complete (roughly 500–800 words).

Please take this URL: https://example.com/post and produce an operator-facing HOWTO from it without pasting the full article into chat. Do it as a background pipeline: fetch the page, extract plain text, chunk it (chunk-chars=9000), run a goal-driven summarization pass, then reduce to a single howto (final-max-words=650). Goal: prerequisites/compatibility, enabling flags/settings, safe rollout checklist, 2–4 minimal example commands/SQL, verification steps/queries, and gotchas/limits. Exclude design rationale, benchmarks, images, proofs, and marketing fluff. Save to summaries/ example.howto.md and paste the final howto content into this chat.

Please take this URL: https://example.com/post and produce an operator-facing HOWTO from it without pasting the full article into chat. Do it as a background pipeline: fetch the page, extract plain text, chunk it (chunk-chars=9000), run a goal-driven summarization pass, then reduce to a single
  howto (final-max-words=650). Goal: prerequisites/compatibility, enabling flags/settings, safe rollout checklist, 2–4 minimal example commands/SQL, verification steps/queries, and gotchas/limits. Exclude design rationale, benchmarks, images, proofs, and marketing fluff. Save to summaries/example.howto.md and paste the final howto content into this chat.

## Why chunking is needed

- Articles can exceed a single model call’s practical context; chunking makes it scale.
- It prevents the full article from entering the chat context; only the final summary is returned.
- It reduces failure blast radius: you can rerun with different chunk sizes without redoing everything manually.

## Recommended chunk size (HTML-extracted blogs/docs)

The pipeline uses `--chunk-chars` (characters per chunk).

Recommended starting point:

- `12000` (default) for most HTML-extracted blogs/docs.

Adjustments:

- `8000–10000` if there are many code blocks, long lists, or dense technical detail and you notice missed specifics.
- `15000–18000` if it’s mostly prose and you notice the summary missing cross-section connections (fewer, larger chunks).

To preview chunking without calling Codex:

```bash
python3 /Users/bvt/.codex/skills/codex-summarize-pipeline/tools/codex_summarize_pipeline.py \
  --input .codex-pipeline/inputs/post.txt \
  --dry-run \
  --chunk-chars 12000
```

## Using the underlying tools directly

Fetch + extract text:

```bash
python3 /Users/bvt/.codex/skills/codex-summarize-pipeline/tools/fetch_article_text.py \
  --url "https://site/post" \
  --output .codex-pipeline/inputs/post.txt
```

Summarize:

```bash
python3 /Users/bvt/.codex/skills/codex-summarize-pipeline/tools/codex_summarize_pipeline.py \
  --input .codex-pipeline/inputs/post.txt \
  --mode map-reduce \
  --final-max-words 120 \
  > summaries/post.summary.md
```
