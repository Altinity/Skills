## ClickHouse connectivity 

- **Preferred (default):** Use the ClickHouse MCP tool (`mcp__clickhouse__execute_query`) when available.
- **Alternative:** Use `clickhouse-client` when explicitly provide connection details

Run `select hostName(), version()` query to test.

If probe fails:
- Stop immediately (do not proceed with audit queries and don't try to write scripts).
- Ask for the missing connection context (target host/cluster, mode, credentials/profile), or return a clear failure.

