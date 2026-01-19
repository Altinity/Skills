# Altinity Expert ClickHouse Skills

This package contains the modular `altinity-expert-clickhouse-*` ClickHouse diagnostic skills and a dedicated test suite.

## Layout

- `skills/` — all `altinity-expert-clickhouse-*` skill definitions (each has its own `SKILL.md`).
- `tests/` — test suite and scenarios. Do not modify structure without updating prompts/runner.
- `../releases/` — built zip packages for distribution.

## Run Tests

From `altinity-expert-clickhouse/tests`:

```sh
export CLICKHOUSE_HOST=localhost
export CLICKHOUSE_PORT=9000
export CLICKHOUSE_USER=altinity-expert
export CLICKHOUSE_PASSWORD=...     # if set
export CLICKHOUSE_SECURE=0         # or 1 if native TLS

make test-all
# or per-skill
make test-memory
```

Notes:
- The test runner uses `tests/runner/lib/common.sh` helpers and `CLICKHOUSE_*` env vars for connectivity.
- Provider-specific targets exist in `tests/Makefile` (Codex is the default; Claude is supported; Gemini is a stub).
- Reports are written under `tests/reports/<skill-name>/`.

## Build Release Zips

From repo root (`/Users/bvt/work/Skills`):

```sh
make
```

Outputs:
- `releases/<skill-name>.zip`

To list detected skills:

```sh
make list
```
