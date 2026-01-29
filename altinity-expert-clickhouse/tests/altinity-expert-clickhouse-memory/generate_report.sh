#!/bin/bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
tests_dir="$(cd -- "${script_dir}/.." && pwd)"

# shellcheck source=runner/lib/common.sh
source "${tests_dir}/runner/lib/common.sh"

report_dir="${tests_dir}/reports/altinity-expert-clickhouse-memory"
mkdir -p "${report_dir}"

now_utc="$(date -u +'%Y-%m-%d %H:%M:%S UTC')"
out="${report_dir}/memory-report-$(date -u +'%Y%m%d-%H%M%S').md"

validate_connection

server_info="$(run_query "SELECT hostName() AS host, version() AS version FORMAT TabSeparatedRaw")"
server_host="$(printf '%s' "${server_info}" | cut -f1)"
server_version="$(printf '%s' "${server_info}" | cut -f2)"

focus_db="altinity-expert-clickhouse-memory"
db_exists="$(run_query "SELECT count() FROM system.databases WHERE name='${focus_db}' FORMAT TabSeparatedRaw")"

q_md() {
    local title="$1"
    local query="$2"
    {
        echo
        echo "### ${title}"
        echo
        run_query "${query} FORMAT Markdown"
        echo
    } >>"${out}"
}

cat >"${out}" <<EOF
# ClickHouse Memory Diagnostic Report

- Generated: ${now_utc}
- Server: \`${server_host}\`
- ClickHouse: \`${server_version}\`
- Focus database: \`${focus_db}\` (exists: ${db_exists})

This report follows the \`altinity-expert-clickhouse-memory\` workflow (run checks.sql-style diagnostics, then interpret results).
EOF

q_md "Current Memory Overview" "
WITH
    (SELECT value FROM system.asynchronous_metrics WHERE metric = 'OSMemoryTotal') AS total,
    (SELECT value FROM system.asynchronous_metrics WHERE metric = 'MemoryResident') AS resident,
    (SELECT value FROM system.metrics WHERE metric = 'MemoryTracking') AS tracked,
    (SELECT value FROM system.asynchronous_metrics WHERE metric = 'OSMemoryFreeWithoutCached') AS free_wo_cached,
    (SELECT value FROM system.asynchronous_metrics WHERE metric = 'OSMemoryCached') AS cached,
    (SELECT value FROM system.asynchronous_metrics WHERE metric = 'OSMemoryBuffers') AS buffers
SELECT
    formatReadableSize(total) AS total_ram,
    formatReadableSize(resident) AS clickhouse_rss,
    formatReadableSize(tracked) AS clickhouse_tracked,
    formatReadableSize(free_wo_cached) AS os_free_without_cached,
    formatReadableSize(cached) AS os_cached,
    formatReadableSize(buffers) AS os_buffers,
    round(100.0 * resident / total, 1) AS rss_pct_of_ram,
    round(100.0 * tracked / total, 1) AS tracked_pct_of_ram,
    multiIf(resident > total * 0.90, 'Critical', resident > total * 0.80, 'Major', resident > total * 0.70, 'Moderate', resident > total * 0.60, 'Minor', 'OK') AS rss_severity,
    multiIf(free_wo_cached < total * 0.05, 'Critical', free_wo_cached < total * 0.10, 'Major', free_wo_cached < total * 0.15, 'Moderate', free_wo_cached < total * 0.20, 'Minor', 'OK') AS free_severity
"

q_md "Memory Settings (Server/User Defaults)" "
SELECT
    name,
    value,
    changed,
    description
FROM system.settings
WHERE name IN
(
    'max_server_memory_usage',
    'max_server_memory_usage_to_ram_ratio',
    'max_memory_usage',
    'max_memory_usage_for_user',
    'max_memory_usage_for_all_queries',
    'max_bytes_before_external_group_by',
    'max_bytes_before_external_sort',
    'max_bytes_in_join',
    'join_algorithm'
)
ORDER BY name
"

q_md "Memory Breakdown by Component (Global)" "
WITH (SELECT toUInt64(value) FROM system.asynchronous_metrics WHERE metric = 'OSMemoryTotal') AS total
SELECT
    component,
    formatReadableSize(bytes) AS size,
    round(100.0 * bytes / total, 2) AS pct_of_ram,
    items AS count,
    multiIf(bytes > total * 0.30, 'Critical', bytes > total * 0.20, 'Major', bytes > total * 0.10, 'Moderate', bytes > total * 0.05, 'Minor', 'OK') AS severity
FROM
(
    SELECT 'Dictionaries' AS component, toUInt64(sum(bytes_allocated)) AS bytes, toUInt64(count()) AS items FROM system.dictionaries
    UNION ALL
    SELECT 'Memory/Set/Join Tables' AS component, toUInt64(assumeNotNull(sum(total_bytes))) AS bytes, toUInt64(count()) AS items FROM system.tables WHERE engine IN ('Memory','Set','Join')
    UNION ALL
    SELECT 'Primary Keys In Memory' AS component, toUInt64(sum(primary_key_bytes_in_memory)) AS bytes, toUInt64(count()) AS items FROM system.parts WHERE active
    UNION ALL
    SELECT 'InMemory Parts (uncompressed bytes)' AS component, toUInt64(sumIf(data_uncompressed_bytes, part_type = 'InMemory')) AS bytes, toUInt64(countIf(part_type = 'InMemory')) AS items FROM system.parts WHERE active
    UNION ALL
    SELECT 'Active Merges (memory_usage)' AS component, toUInt64(sum(memory_usage)) AS bytes, toUInt64(count()) AS items FROM system.merges
    UNION ALL
    SELECT 'Running Queries (memory_usage)' AS component, toUInt64(sum(memory_usage)) AS bytes, toUInt64(count()) AS items FROM system.processes
    UNION ALL
    SELECT 'Mark Cache' AS component, toUInt64(ifNull((SELECT value FROM system.asynchronous_metrics WHERE metric = 'MarkCacheBytes'), 0)) AS bytes, toUInt64(0) AS items
    UNION ALL
    SELECT 'Uncompressed Cache' AS component, toUInt64(ifNull((SELECT value FROM system.asynchronous_metrics WHERE metric = 'UncompressedCacheBytes'), 0)) AS bytes, toUInt64(0) AS items
)
ORDER BY bytes DESC
"

q_md "Memory Allocation Audit (Global)" "
WITH
    (SELECT toUInt64(sum(bytes_allocated)) FROM system.dictionaries) AS dictionaries,
    (SELECT toUInt64(assumeNotNull(sum(total_bytes))) FROM system.tables WHERE engine IN ('Memory','Set','Join')) AS mem_tables,
    (SELECT toUInt64(sum(primary_key_bytes_in_memory)) FROM system.parts WHERE active) AS pk_memory,
    (SELECT toUInt64(ifNull((SELECT value FROM system.asynchronous_metrics WHERE metric = 'MarkCacheBytes'), 0))) AS mark_cache,
    (SELECT toUInt64(ifNull((SELECT value FROM system.asynchronous_metrics WHERE metric = 'UncompressedCacheBytes'), 0))) AS uncompressed_cache,
    (SELECT toUInt64(value) FROM system.asynchronous_metrics WHERE metric = 'OSMemoryTotal') AS total_ram
SELECT
    check_name,
    formatReadableSize(used) AS used_hr,
    round(100.0 * used / total_ram, 2) AS pct_of_ram,
    multiIf(pct_of_ram > 30, 'Critical', pct_of_ram > 25, 'Major', pct_of_ram > 20, 'Moderate', pct_of_ram > 10, 'Minor', 'OK') AS severity
FROM
(
    SELECT 'Dictionaries + Memory Tables' AS check_name, toUInt64(dictionaries + mem_tables) AS used
    UNION ALL
    SELECT 'Primary Keys' AS check_name, toUInt64(pk_memory) AS used
    UNION ALL
    SELECT 'Caches (Mark + Uncompressed)' AS check_name, toUInt64(mark_cache + uncompressed_cache) AS used
)
ORDER BY used DESC
"

q_md "Top Memory-Using Running Queries (system.processes)" "
SELECT
    initial_query_id,
    user,
    round(elapsed, 1) AS elapsed_sec,
    formatReadableSize(memory_usage) AS memory,
    formatReadableSize(peak_memory_usage) AS peak_memory,
    substring(query, 1, 120) AS query_preview
FROM system.processes
ORDER BY peak_memory_usage DESC
LIMIT 15
"

q_md "Recent Memory-Heavy Queries (system.query_log, last 1 day)" "
SELECT
    event_time,
    initial_query_id,
    user,
    formatReadableSize(memory_usage) AS memory,
    round(query_duration_ms / 1000, 2) AS duration_sec,
    formatReadableSize(read_bytes) AS read_bytes,
    substring(query, 1, 140) AS query_preview
FROM system.query_log
WHERE event_date >= today() - 1
  AND type = 'QueryFinish'
ORDER BY memory_usage DESC
LIMIT 20
"

q_md "Memory Exceptions (code 241, last 1 day)" "
SELECT
    event_time,
    user,
    exception_code,
    substring(exception, 1, 200) AS exception,
    substring(query, 1, 140) AS query_preview
FROM system.query_log
WHERE event_date >= today() - 1
  AND type IN ('ExceptionBeforeStart','ExceptionWhileProcessing')
  AND exception_code = 241
ORDER BY event_time DESC
LIMIT 50
"

q_md "Top Memory-Using Dictionaries (Global)" "
SELECT
    database,
    name,
    status,
    formatReadableSize(bytes_allocated) AS memory,
    element_count AS elements,
    origin,
    type,
    source
FROM system.dictionaries
ORDER BY bytes_allocated DESC
LIMIT 25
"

q_md "Top Memory/Set/Join Tables (Global)" "
SELECT
    database,
    name,
    engine,
    formatReadableSize(total_bytes) AS size,
    total_rows AS rows
FROM system.tables
WHERE engine IN ('Memory', 'Set', 'Join')
ORDER BY total_bytes DESC
LIMIT 25
"

q_md "Top Primary Key Memory by Table (Global)" "
SELECT
    database,
    table,
    formatReadableSize(sum(primary_key_bytes_in_memory)) AS pk_memory,
    formatReadableSize(sum(primary_key_bytes_in_memory_allocated)) AS pk_allocated,
    sum(marks) AS marks,
    count() AS active_parts
FROM system.parts
WHERE active
GROUP BY database, table
ORDER BY sum(primary_key_bytes_in_memory) DESC
LIMIT 25
"

if [[ "${db_exists}" == "1" ]]; then
    q_md "Focus DB: Tables Summary" "
    SELECT
        database,
        name,
        engine,
        formatReadableSize(total_bytes) AS total_bytes,
        total_rows AS rows
    FROM system.tables
    WHERE database = '${focus_db}'
    ORDER BY total_bytes DESC
    LIMIT 50
    "

    q_md "Focus DB: Memory/Set/Join Tables" "
    SELECT
        database,
        name,
        engine,
        formatReadableSize(total_bytes) AS size,
        total_rows AS rows
    FROM system.tables
    WHERE database = '${focus_db}'
      AND engine IN ('Memory', 'Set', 'Join')
    ORDER BY total_bytes DESC
    LIMIT 25
    "

    q_md "Focus DB: Primary Key Memory by Table" "
    SELECT
        database,
        table,
        formatReadableSize(sum(primary_key_bytes_in_memory)) AS pk_memory,
        formatReadableSize(sum(primary_key_bytes_in_memory_allocated)) AS pk_allocated,
        sum(marks) AS marks,
        count() AS active_parts
    FROM system.parts
    WHERE active
      AND database = '${focus_db}'
    GROUP BY database, table
    ORDER BY sum(primary_key_bytes_in_memory) DESC
    LIMIT 25
    "

    q_md "Focus DB: Dictionaries" "
    SELECT
        database,
        name,
        status,
        formatReadableSize(bytes_allocated) AS memory,
        element_count AS elements,
        origin,
        type
    FROM system.dictionaries
    WHERE database = '${focus_db}'
    ORDER BY bytes_allocated DESC
    LIMIT 25
    "
fi

q_md "Memory Resident Over Time (system.asynchronous_metric_log, last 4h)" "
SELECT
    toStartOfFiveMinutes(event_time) AS ts,
    formatReadableSize(max(value)) AS peak_rss
FROM system.asynchronous_metric_log
WHERE metric = 'MemoryResident'
  AND event_time > now() - INTERVAL 4 HOUR
GROUP BY ts
ORDER BY ts
"

{
    echo
    echo "---"
    echo
    echo "Report file: \`${out}\`"
} >>"${out}"

echo "${out}"
