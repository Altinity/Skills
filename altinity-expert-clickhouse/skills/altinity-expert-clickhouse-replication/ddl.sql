/* Stuck distributed DDL can stall schema changes and trigger ALTER_METADATA backlog. */
SELECT
  entry,
  host,
  port,
  status,
  query_create_time,
  exception_code
FROM system.distributed_ddl_queue
WHERE status != 'Finished'
ORDER BY query_create_time DESC
LIMIT 200;

