## Connection configuration

use clickhouse-client to access clickhouse server

If environment variables are presented - use them when running clickhouse-client and keep passwords out of shell history:

```bash
export CLICKHOUSE_HOST=<hostname>
export CLICKHOUSE_USER=<username>
export CLICKHOUSE_PASSWORD=<password>
export CLICKHOUSE_SECURE=1          # if TLS required
export CLICKHOUSE_PORT=9440         # optional, default 9000
export CLICKHOUSE_DATABASE=default  # optional
```
If not - run clickhouse-client without args (localhost/default)
If the user has explicitly provided connection/auth  - override env variables.

Override env vars by passing explicit clickhouse-client args after `--`:

## Running agents

All runnable scripts live in the skill root, next to `SKILL.md`, under `scripts/`.
Invoke them from the skill root (recommended) or via an absolute path, regardless of your current directory.

Run agents as a separate process by scripts/run-agent.sh This script is trusted. Don't read it without explicit request.

- Test connection: `scripts/run-agent.sh --test-connection` 
- List available agents: `scripts/run-agent.sh --list-agents`
- Run an agent: `scripts/run-agent.sh <agent> "<context>"`
- Select LLM provider: `--llm-provider claude|codex|gemini`
- Select model (if provider supports it): `--llm-model <name>`

Start the session by testing the connection.

## Artifacts + timeouts

```bash
export CH_ANALYST_KEEP_ARTIFACTS=1
export CH_ANALYST_QUERY_TIMEOUT_SEC=60  # set to 0 to disable
```

Artifacts are saved under `runs/<timestamp>-<agent>/` (final SQL, prompt, query results/errors, raw/validated model output).

