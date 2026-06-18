-- MinervaDB Server: kafka_tables.sql
-- Kafka integration: queue tables, target tables, and materialized views

-- Kafka queue table (reads from Kafka)
CREATE TABLE IF NOT EXISTS kafka_events_queue
(
    event_time   DateTime,
    event_type   String,
    user_id      UInt64,
    session_id   String,
    properties   String
)
ENGINE = Kafka
SETTINGS
    kafka_broker_list     = "kafka1:9092,kafka2:9092,kafka3:9092",
    kafka_topic_list      = "events",
    kafka_group_name      = "clickhouse-events-consumer",
    kafka_format          = "JSONEachRow",
    kafka_num_consumers   = 4,
    kafka_max_block_size  = 65536,
    kafka_skip_broken_messages = 100;

-- Target table (stores processed data)
CREATE TABLE IF NOT EXISTS events
(
    event_date   Date      DEFAULT toDate(event_time),
    event_time   DateTime,
    event_type   String,
    user_id      UInt64,
    session_id   String,
    properties   String
)
ENGINE = ReplicatedMergeTree(
    "/clickhouse/tables/{shard}/events",
    "{replica}"
)
PARTITION BY toYYYYMM(event_date)
ORDER BY (event_date, event_type, user_id)
TTL event_date + INTERVAL 90 DAY DELETE
SETTINGS
    index_granularity = 8192,
    storage_policy = "tiered_storage";

-- Materialized view to move data from queue to target
CREATE MATERIALIZED VIEW IF NOT EXISTS events_mv TO events AS
SELECT event_time, event_type, user_id, session_id, properties
FROM kafka_events_queue;

-- Metrics table
CREATE TABLE IF NOT EXISTS kafka_metrics_queue
(
    metric_time  DateTime,
    metric_name  String,
    metric_value Float64,
    tags         String
)
ENGINE = Kafka
SETTINGS
    kafka_broker_list     = "kafka1:9092,kafka2:9092,kafka3:9092",
    kafka_topic_list      = "metrics",
    kafka_group_name      = "clickhouse-metrics-consumer",
    kafka_format          = "JSONEachRow",
    kafka_num_consumers   = 2;

CREATE TABLE IF NOT EXISTS metrics
(
    metric_date  Date     DEFAULT toDate(metric_time),
    metric_time  DateTime,
    metric_name  String,
    metric_value Float64,
    tags         String
)
ENGINE = ReplicatedMergeTree(
    "/clickhouse/tables/{shard}/metrics",
    "{replica}"
)
PARTITION BY toYYYYMM(metric_date)
ORDER BY (metric_date, metric_name)
TTL metric_date + INTERVAL 30 DAY DELETE;

CREATE MATERIALIZED VIEW IF NOT EXISTS metrics_mv TO metrics AS
SELECT metric_time, metric_name, metric_value, tags
FROM kafka_metrics_queue;
