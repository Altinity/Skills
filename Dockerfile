FROM oven/bun:latest
RUN bun install -g @openai/codex@latest
RUN bun install -g @anthropic-ai/claude-code@latest
