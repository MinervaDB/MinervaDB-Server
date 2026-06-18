# MinervaDB Server Capacity Planning

## Hardware Recommendations

**CPU**: ClickHouse is CPU-bound for analytical queries. Modern server CPUs with AVX-512 support provide best performance. Recommended: 32+ cores per node. ClickHouse uses all available cores for parallel query processing.

**Memory**: Baseline recommendation is 1 GB RAM per 1 TB of raw (uncompressed) data, with a minimum of 64 GB per node. For high-concurrency workloads (50+ simultaneous queries), scale to 256 GB or more. The memory config in `configs/production/config.d/00-memory.xml` sets ClickHouse to use 80% of available system RAM.

**Storage**: NVMe SSDs for hot data. The tiered storage configuration in `01-storage.xml` supports hot/warm/cold tiers.

| Tier | Type | Use Case |
|------|------|----------|
| hot | NVMe SSD | Recent data (last 30-90 days) |
| warm | SATA SSD | Data 90 days to 1 year |
| cold | HDD/S3 | Archive data older than 1 year |

Plan for 3-5x raw data size: replication factor (2x), MergeTree overhead (1.2-2x), and backup storage.

**Network**: 10 Gbps minimum between nodes. For high insert rates or frequent distributed queries, 25-100 Gbps is recommended.

## Cluster Sizing Formula

- Nodes = ceil(total_data_tb / data_per_node_tb)
- Shards = ceil(nodes / replication_factor)
- Replication factor: 2 (minimum for HA), 3 (recommended for critical workloads)

Example: 20 TB dataset, 10 TB per node, replication factor 2 = 4 nodes, 2 shards x 2 replicas.

## Monitoring Capacity

```sql
-- Data size per table
SELECT database, table,
    formatReadableSize(sum(data_compressed_bytes)) AS compressed,
    formatReadableSize(sum(data_uncompressed_bytes)) AS uncompressed,
    round(sum(data_uncompressed_bytes) / sum(data_compressed_bytes), 2) AS ratio
FROM system.parts WHERE active = 1
GROUP BY database, table ORDER BY sum(data_compressed_bytes) DESC;

-- Daily write volume
SELECT toStartOfDay(event_time) AS day,
    formatReadableSize(sum(written_bytes)) AS written_per_day
FROM system.query_log
WHERE type = 2 AND event_time > now() - INTERVAL 30 DAY AND query_kind = "Insert"
GROUP BY day ORDER BY day;
```

## When to Scale

Scale vertically (larger nodes) when query parallelism within a single node is the bottleneck. Scale horizontally (more shards) when data volume exceeds single-node capacity or write throughput requires distribution.
