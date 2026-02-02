#!/usr/bin/env bash
set -euo pipefail

THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$(cd "$THIS_DIR/.." && pwd)"

source "$TESTS_DIR/runner/lib/common.sh"

DB="altinity-expert-clickhouse-caches"
TS="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$TESTS_DIR/reports/altinity-expert-clickhouse-caches"
OUT_FILE="$OUT_DIR/report-$TS.md"

mkdir -p "$OUT_DIR"

validate_env
validate_connection >/dev/null

HOST_VER_UPTIME="$(run_query "SELECT hostName() AS host, version() AS version, uptime() AS uptime_s FORMAT TSVRaw" | tr -d '\r')"
HOST="$(cut -f1 <<<"$HOST_VER_UPTIME")"
VERSION="$(cut -f2 <<<"$HOST_VER_UPTIME")"
UPTIME_S="$(cut -f3 <<<"$HOST_VER_UPTIME")"
UPTIME_MIN="$(awk -v s="$UPTIME_S" 'BEGIN{printf("%.0f", s/60)}')"

DB_EXISTS="$(run_query "SELECT if(count() > 0, 1, 0) FROM system.databases WHERE name = '$DB' FORMAT TSVRaw" | tr -d '\r')"

MARK_CACHE_SQL="$(cat <<'SQL'
WITH
  m AS
  (
    SELECT
      toUInt64(maxIf(value, metric = 'MarkCacheBytes')) AS cache_bytes
    FROM system.metrics
    WHERE metric IN ('MarkCacheBytes')
  ),
  r AS
  (
    SELECT
      toUInt64(maxIf(value, metric = 'OSMemoryTotal')) AS total_ram
    FROM system.asynchronous_metrics
    WHERE metric IN ('OSMemoryTotal')
  ),
  e AS
  (
    SELECT
      toUInt64(maxIf(value, event = 'MarkCacheHits')) AS hits,
      toUInt64(maxIf(value, event = 'MarkCacheMisses')) AS misses
    FROM system.events
    WHERE event IN ('MarkCacheHits','MarkCacheMisses')
  ),
  s AS
  (
    SELECT
      any(value) AS mark_cache_size
    FROM system.server_settings
    WHERE name = 'mark_cache_size'
  )
SELECT
  cache,
  size,
  configured_max_size,
  total_ram_readable AS total_ram,
  pct_of_ram,
  hits,
  misses,
  hit_ratio,
  hit_severity,
  size_severity,
  multiIf(
    hit_severity = 'Critical' OR size_severity = 'Critical', 'Critical',
    hit_severity = 'Major' OR size_severity = 'Major', 'Major',
    hit_severity = 'Moderate' OR size_severity = 'Moderate', 'Moderate',
    'OK'
  ) AS overall_severity,
  recommendations
FROM
(
  SELECT
    'Mark cache' AS cache,
    formatReadableSize(cache_bytes) AS size,
    formatReadableSize(toUInt64OrZero(mark_cache_size)) AS configured_max_size,
    formatReadableSize(total_ram) AS total_ram_readable,
    round(if(total_ram = 0, 0.0, 100.0 * cache_bytes / total_ram), 2) AS pct_of_ram,
    hits,
    misses,
    round(if(hits + misses = 0, 0.0, hits / (hits + misses)), 3) AS hit_ratio,
    multiIf(hit_ratio < 0.3, 'Critical', hit_ratio < 0.5, 'Major', hit_ratio < 0.7, 'Moderate', 'OK') AS hit_severity,
    multiIf(pct_of_ram > 25, 'Critical', pct_of_ram > 20, 'Major', pct_of_ram > 15, 'Moderate', 'OK') AS size_severity,
    concat(
      multiIf(hit_ratio < 0.7, 'If performance is impacted, consider increasing mark_cache_size and/or improving query locality (filters aligned with ORDER BY). ', ''),
      multiIf(pct_of_ram > 15, 'If memory pressure exists, consider reducing mark_cache_size or mitigate via query/index tuning. ', '')
    ) AS recommendations
  FROM m
  CROSS JOIN r
  CROSS JOIN e
  CROSS JOIN s
)
SETTINGS system_events_show_zero_values = 1
FORMAT Markdown
SQL
)"

UNCOMPRESSED_CACHE_SQL="$(cat <<'SQL'
WITH
  m AS
  (
    SELECT
      toUInt64(maxIf(value, metric = 'UncompressedCacheBytes')) AS cache_bytes
    FROM system.metrics
    WHERE metric IN ('UncompressedCacheBytes')
  ),
  r AS
  (
    SELECT
      toUInt64(maxIf(value, metric = 'OSMemoryTotal')) AS total_ram
    FROM system.asynchronous_metrics
    WHERE metric IN ('OSMemoryTotal')
  ),
  e AS
  (
    SELECT
      toUInt64(maxIf(value, event = 'UncompressedCacheHits')) AS hits,
      toUInt64(maxIf(value, event = 'UncompressedCacheMisses')) AS misses
    FROM system.events
    WHERE event IN ('UncompressedCacheHits','UncompressedCacheMisses')
  ),
  s AS
  (
    SELECT
      any(value) AS uncompressed_cache_size
    FROM system.server_settings
    WHERE name = 'uncompressed_cache_size'
  )
SELECT
  cache,
  size,
  configured_max_size,
  pct_of_ram,
  hits,
  misses,
  hit_ratio,
  hit_severity,
  size_severity,
  multiIf(
    cache_bytes = 0 AND hits = 0 AND misses = 0, 'OK/NA',
    hit_severity = 'Moderate' OR size_severity = 'Moderate', 'Moderate',
    size_severity = 'Major', 'Major',
    size_severity = 'Critical', 'Critical',
    'OK'
  ) AS overall_severity,
  recommendations
FROM
(
  SELECT
    'Uncompressed cache' AS cache,
    cache_bytes,
    formatReadableSize(cache_bytes) AS size,
    toUInt64OrZero(uncompressed_cache_size) AS configured_bytes,
    formatReadableSize(configured_bytes) AS configured_max_size,
    round(if(total_ram = 0, 0.0, 100.0 * cache_bytes / total_ram), 2) AS pct_of_ram,
    hits,
    misses,
    round(if(hits + misses = 0, 0.0, hits / (hits + misses)), 3) AS hit_ratio,
    multiIf(hit_ratio < 0.01 AND (hits + misses) > 1000, 'Moderate', 'OK') AS hit_severity,
    multiIf(pct_of_ram > 25, 'Critical', pct_of_ram > 20, 'Major', pct_of_ram > 15, 'Moderate', 'OK') AS size_severity,
    concat(
      multiIf(configured_bytes = 0, 'Disabled (uncompressed_cache_size=0); this is often OK. ', cache_bytes = 0 AND hits = 0 AND misses = 0, 'Configured but unused (no reads using uncompressed cache); this is often OK. ', ''),
      multiIf(cache_bytes > 0 AND hit_ratio < 0.01 AND (hits + misses) > 1000, 'If intentionally enabled, validate workload benefits; otherwise disable or use selectively per-query. ', '')
    ) AS recommendations
  FROM m
  CROSS JOIN r
  CROSS JOIN e
  CROSS JOIN s
)
SETTINGS system_events_show_zero_values = 1
FORMAT Markdown
SQL
)"

QUERY_CACHE_SQL="$(cat <<'SQL'
WITH
  q AS
  (
    SELECT
      count() AS entries,
      sum(result_size) AS cached_bytes
    FROM system.query_cache
  ),
  s AS
  (
    SELECT
      toUInt64OrZero(maxIf(value, name = 'query_cache_max_size_in_bytes')) AS query_cache_max_size_in_bytes,
      maxIf(value, name = 'use_query_cache') AS use_query_cache
    FROM system.settings
    WHERE name IN ('query_cache_max_size_in_bytes','use_query_cache')
  ),
  m AS
  (
    SELECT
      toUInt64(maxIf(value, metric = 'QueryCacheBytes')) AS cache_bytes
    FROM system.metrics
    WHERE metric IN ('QueryCacheBytes')
  )
SELECT
  'Query cache' AS cache,
  entries,
  formatReadableSize(cached_bytes) AS cached_data,
  formatReadableSize(cache_bytes) AS cache_bytes_metric,
  formatReadableSize(query_cache_max_size_in_bytes) AS configured_max_size,
  use_query_cache,
  multiIf(
    query_cache_max_size_in_bytes = 0 AND use_query_cache = '0', 'OK/NA (disabled)',
    entries = 0 AND cached_bytes = 0, 'OK/NA',
    query_cache_max_size_in_bytes = 0, 'Moderate',
    'OK'
  ) AS severity,
  multiIf(
    entries = 0 AND cached_bytes = 0,
    'No cached entries observed. If you expect repeats, ensure query_cache_max_size_in_bytes > 0 and use_query_cache is enabled for workloads.',
    query_cache_max_size_in_bytes = 0,
    'Query cache is enabled/available but max size is 0; set query_cache_max_size_in_bytes to a non-zero value if you want caching.',
    'If using query cache heavily, monitor hit rate and invalidations (workload-dependent).'
  ) AS recommendations
FROM q
CROSS JOIN m
CROSS JOIN s
FORMAT Markdown
SQL
)"

MARKS_BY_TABLE_SQL="$(cat <<SQL
SELECT
  database,
  table,
  formatReadableSize(sum(marks_bytes)) AS marks_size,
  sum(marks) AS marks_count,
  count() AS active_parts
FROM system.parts
WHERE active
  AND database = '$DB'
GROUP BY
  database,
  table
ORDER BY
  sum(marks_bytes) DESC,
  table ASC
LIMIT 20
FORMAT Markdown
SQL
)"

QUERY_CACHE_EXISTS="$(run_query "EXISTS TABLE system.query_cache FORMAT TSVRaw" | tr -d '\r')"

{
  echo "# ClickHouse Cache Health Report"
  echo
  echo "**Scope**"
  echo "- Database focus: \`$DB\`"
  echo "- Server: \`$HOST\`, \`ClickHouse $VERSION\`, uptime ~${UPTIME_MIN} min"
  if [[ "$DB_EXISTS" == "1" ]]; then
    echo "- Database exists: yes"
  else
    echo "- Database exists: no (table-level marks section will be N/A)"
  fi
  echo

  echo "## Mark cache size and hit ratio"
  run_query "$MARK_CACHE_SQL"
  echo

  echo "## Uncompressed cache size and hit ratio (if available)"
  run_query "$UNCOMPRESSED_CACHE_SQL"
  echo

  echo "## Query cache summary (if available)"
  if [[ "$QUERY_CACHE_EXISTS" == "1" ]]; then
    run_query "$QUERY_CACHE_SQL"
  else
    echo "- Not available on this ClickHouse version (no system.query_cache)."
  fi
  echo

  echo "## Tables contributing most to marks"
  if [[ "$DB_EXISTS" == "1" ]]; then
    run_query "$MARKS_BY_TABLE_SQL"
  else
    echo "- N/A (database not found)"
  fi
  echo

  echo "## Recommendations"
  echo "- Mark cache: target ~5–10% of RAM for typical analytic workloads; tune based on hit ratio and memory pressure."
  echo "- Low mark cache hit ratio (<0.7): consider increasing mark_cache_size and/or reducing cold/random scans (filters aligned with ORDER BY, partition pruning)."
  echo "- High mark cache footprint (>15% RAM): if memory is tight, consider lowering mark_cache_size and review tables with large marks (index_granularity, many small parts)."
  echo "- Uncompressed cache: keep disabled unless you confirm benefit (uncompressed_cache_size=0 by default); enable selectively per query when needed."
  echo "- Query cache: if you expect repeated identical SELECTs, configure query_cache_max_size > 0 and enable use_query_cache where appropriate; monitor churn/invalidation."
} >"$OUT_FILE"

echo "$OUT_FILE"
