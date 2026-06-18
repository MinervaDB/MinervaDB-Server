# MinervaDB Server Kafka Integration

## Architecture Overview

MinervaDB Server integrates with Apache Kafka using the Kafka table engine. Data flows through three components: a Kafka queue table (reads from Kafka), a target MergeTree table (stores data), and a materialized view (auto-moves data from queue to target).

This pattern provides exactly-once delivery semantics via Kafka consumer group offsets, automatic retry on ClickHouse restart, and parallel consumption across multiple ClickHouse nodes.

## Prerequisites

- Apache Kafka 2.6+ (or Confluent Platform, Amazon MSK, Redpanda)
- Topics created with appropriate retention and replication settings
- ClickHouse nodes can reach Kafka brokers on port 9092

## Configuration

```xml
<clickhouse>
    <kafka>
        <debug>cgrp</debug>
        <auto_offset_reset>earliest</auto_offset_reset>
        <session_timeout_ms>45000</session_timeout_ms>
        <max_poll_interval_ms>300000</max_poll_interval_ms>
    </kafka>
</clickhouse>
```

## Deploying the Kafka Tables

```bash
clickhouse-client --host localhost \
    --user minervadb_admin --password secret \
    < configs/kafka/kafka_tables.sql
```

## Monitoring Kafka Consumption

```sql
-- Consumer status
SELECT table, assignmentCount, messagesProcessed FROM system.kafka_consumers;

-- Kafka-related errors in system log
SELECT event_time, database, table, level, message
FROM system.text_log
WHERE message LIKE "%kafka%" AND event_time > now() - INTERVAL 1 HOUR
ORDER BY event_time DESC;
```

## Scaling Kafka Consumers

The `kafka_num_consumers` setting controls how many consumer threads each ClickHouse node uses. This should not exceed the number of Kafka partitions. Across a 4-node cluster with `kafka_num_consumers = 4` and 16 partitions, each partition is consumed by exactly one thread.

## Handling Schema Changes

When Kafka message schema changes, drop the old materialized view first, then recreate the queue table and materialized view. The consumer will resume from the last committed offset.

## Performance Tuning

| Setting | Default | Recommended | Notes |
|---------|---------|-------------|-------|
| kafka_num_consumers | 1 | 4-8 | Match to partition count |
| kafka_max_block_size | 65536 | 65536-262144 | Larger = fewer, bigger inserts |
| kafka_skip_broken_messages | 0 | 100 | Tolerate malformed records |
| kafka_poll_max_batch_size | 65536 | 65536 | Max records per poll |
