-- Post-run cleanup/reset for altinity-expert-clickhouse-memory test
-- Re-enable merges for tables used in scenarios

SYSTEM START MERGES wide_pk_table;
