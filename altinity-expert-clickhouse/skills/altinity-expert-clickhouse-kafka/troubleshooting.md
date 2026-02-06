# Kafka Troubleshooting Reference

## Topic Authorization Failed (ACL Errors)

Error: `Broker: Topic authorization failed`

Indicates missing Kafka ACLs. Common with AWS MSK or Confluent using SCRAM auth where `allow.everyone.if.no.acl.found = false`.

**Fix:** Create ACLs granting `read` and `describe` operations for the ClickHouse user on the topic:

```bash
kafka-acls --bootstrap-server <broker>:9096 \
  --command-config adminclient-configs.conf \
  --add \
  --allow-principal User:<username> \
  --allow-host <clickhouse-host> \
  --operation read \
  --operation describe \
  --topic <topic-name>
```

## Application Maximum Poll Interval Exceeded

Error: `Application maximum poll interval (300000ms) exceeded`

The consumer is too slow to process messages within `max.poll.interval.ms` (default: 300s), causing it to be kicked from the consumer group. Common with large messages, complex MVs, or slow disks.

**Fix 1 — Optimize slow MVs (check first):** If `checks.sql` shows MV avg duration > 30s, the MV is likely the bottleneck. The most common cause is multiple `JSONExtract` calls that each re-parse the same JSON blob.

Rewrite the MV to parse JSON in one pass using a Tuple:

```sql
-- BAD: parses the JSON string 3 separate times
SELECT
    JSONExtractString(message, 'user_id') AS user_id,
    JSONExtractString(message, 'event') AS event,
    JSONExtractInt(message, 'timestamp') AS ts
FROM kafka_source

-- GOOD: parses the JSON string once, extracts fields from the tuple
SELECT
    tupleElement(parsed, 'user_id') AS user_id,
    tupleElement(parsed, 'event') AS event,
    tupleElement(parsed, 'timestamp') AS ts
FROM kafka_source
WHERE JSONExtract(message, 'Tuple(user_id String, event String, timestamp Int64)') AS parsed
```

For deeply nested JSON, parse level-by-level rather than the entire document at once. Use `clickhouse-local` with schema inference on a sample file to auto-generate the correct Tuple definition.

**Reference:** https://kb.altinity.com/altinity-kb-queries-and-syntax/jsonextract-to-parse-many-attributes-at-a-time/

**Fix 2 — Increase poll interval:** If the MV is already optimized but still slow (complex transforms, slow disks), increase `max.poll.interval.ms` (start with small increments):

```xml
<kafka>
    <max_poll_interval_ms>480000</max_poll_interval_ms>
</kafka>
```

**References:**
- librdkafka configuration: https://github.com/confluentinc/librdkafka/blob/master/CONFIGURATION.md
- Altinity KB: https://kb.altinity.com/altinity-kb-integrations/altinity-kb-kafka/altinity-kb-adjusting-librdkafka-settings/

## Thread Pool Starvation

Consumers disconnect or poll interval warnings occur **not because ClickHouse fails to poll, but because no threads are available**.

**Symptoms:**
- `BackgroundMessageBrokerSchedulePoolTask` equals `BackgroundMessageBrokerSchedulePoolSize`
- Poll interval exceeded despite correct `max.poll.interval.ms`

**Fix:** Increase `background_message_broker_schedule_pool_size` (default: 16):

```xml
<clickhouse>
    <background_message_broker_schedule_pool_size>32</background_message_broker_schedule_pool_size>
</clickhouse>
```

**Reference:** https://kb.altinity.com/altinity-kb-integrations/altinity-kb-kafka/background_message_broker_schedule_pool_size/

## Parsing Errors and Dead Letter Queue

For handling malformed messages without stopping consumption:

- **Version 21.6+:** Use `kafka_handle_error_mode='stream'` — route errors to a separate table via MV filtering on `length(_error) > 0`
- **Version 25.8+:** Use `kafka_handle_error_mode='dead_letter'` — native dead letter queue support

**Reference:** https://kb.altinity.com/altinity-kb-integrations/altinity-kb-kafka/error-handling/

## Data Loss with Multiple Materialized Views

Multiple MVs on one Kafka table can cause data loss if early-starting MVs consume data before others load.

- **Pre-25.5:** Disable async loading (`<async_load_databases>false</async_load_databases>`) or use intermediate Null table pattern: `KafkaTable → MV → NullTable → [MV1, MV2, ...] → [Table1, Table2, ...]`
- **Version 25.5+:** Native fix included

**Reference:** https://kb.altinity.com/altinity-kb-integrations/altinity-kb-kafka/altinity-kb-kafka-mv-consuming/

## Rewind / Replay Offsets

To replay messages or skip to latest:

1. `DETACH TABLE kafka_table;`
2. Reset offsets via Kafka CLI: `kafka-consumer-groups.sh --bootstrap-server kafka:9092 --topic my_topic --group clickhouse --reset-offsets --to-earliest --execute`
3. `ATTACH TABLE kafka_table;`

Offset options: `--to-earliest`, `--to-latest`, `--to-offset <N>`, `--shift-by <N>`

**Reference:** https://kb.altinity.com/altinity-kb-integrations/altinity-kb-kafka/altinity-kb-rewind-fast-forward-replay/

## Parallel Consumption

For high-throughput topics, use `kafka_num_consumers` with `kafka_thread_per_consumer = 1`:

- `kafka_num_consumers` limited by physical cores (override with `kafka_disable_num_consumers_limit`)
- Topic must have >= `kafka_num_consumers` partitions
- Ensure `background_message_broker_schedule_pool_size` >= total consumers

**Reference:** https://kb.altinity.com/altinity-kb-integrations/altinity-kb-kafka/altinity-kb-kafka-parallel-consuming/

## Common librdkafka Settings

```xml
<kafka>
    <!-- Timeouts -->
    <max_poll_interval_ms>300000</max_poll_interval_ms>
    <session_timeout_ms>60000</session_timeout_ms>
    <heartbeat_interval_ms>10000</heartbeat_interval_ms>

    <!-- Message size -->
    <message_max_bytes>20971520</message_max_bytes>

    <!-- Debugging -->
    <debug>all</debug>

    <!-- SASL/SCRAM (AWS MSK) -->
    <security_protocol>sasl_ssl</security_protocol>
    <sasl_mechanism>SCRAM-SHA-512</sasl_mechanism>
    <sasl_username>user</sasl_username>
    <sasl_password>pass</sasl_password>
</kafka>
```

**Reference:** https://github.com/confluentinc/librdkafka/blob/master/CONFIGURATION.md
