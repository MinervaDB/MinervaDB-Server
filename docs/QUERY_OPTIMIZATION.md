# MinervaDB Server Query Optimization Guide

## Understanding the ClickHouse Execution Model

ClickHouse uses a vectorized execution engine processing data in columns. Operations that scan fewer columns and rows are exponentially faster. Understanding this model is fundamental to writing efficient queries.

## Table Design Principles

**Primary Key / ORDER BY selection** is the most impactful design decision. The primary key determines physical sort order and enables sparse index lookups. Choose columns that appear in WHERE clauses most frequently, have low cardinality as leading columns, and provide good data clustering.

```sql
-- Good: date is the primary filter, user_id narrows results
CREATE TABLE events (
    event_date Date,
    user_id UInt64,
    event_type String,
    properties String
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_date)
ORDER BY (event_date, user_id, event_type);
```

**Partitioning** reduces data scanned for time-ranged queries. Partition by month for most use cases. Avoid over-partitioning (e.g. daily partitions for multi-year data).

## Using EXPLAIN

```sql
-- Check query plan
EXPLAIN SELECT count() FROM events WHERE event_date >= today() - 7;

-- Check pipeline (shows parallelism)
EXPLAIN PIPELINE SELECT count() FROM events WHERE event_date >= today() - 7;

-- Check indexes used
EXPLAIN indexes = 1 SELECT count() FROM events WHERE event_date = today();
```

## Identifying Slow Queries

```sql
SELECT query_id, user, query_duration_ms/1000 AS duration_sec,
    formatReadableSize(memory_usage) AS memory, read_rows,
    substring(query, 1, 200) AS query_snippet
FROM system.query_log
WHERE event_time > now() - INTERVAL 1 HOUR
    AND type = 2 AND query_duration_ms > 1000
ORDER BY query_duration_ms DESC LIMIT 10;
```

## Materialized Views for Pre-Aggregation

```sql
CREATE MATERIALIZED VIEW events_hourly_mv
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(hour)
ORDER BY (hour, event_type)
AS SELECT toStartOfHour(event_time) AS hour, event_type, count() AS cnt
FROM events GROUP BY hour, event_type;
```

## Projections

```sql
ALTER TABLE events ADD PROJECTION events_by_type (
    SELECT * ORDER BY event_type, event_date
);
ALTER TABLE events MATERIALIZE PROJECTION events_by_type;
```

## Data Type Optimization

Use the smallest data type that fits your data. Use `LowCardinality(String)` for string columns with fewer than 10,000 distinct values — this applies dictionary encoding and can improve speed by 2-10x. Use `UInt32` instead of `UInt64` for values under 4 billion.
