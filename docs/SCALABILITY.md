# Scalability Guide — MinervaDB Server for ClickHouse

Comprehensive horizontal and vertical scaling strategies for ClickHouse clusters.

---

## Table of Contents

1. [Cluster Architecture Topologies](#cluster-architecture-topologies)
2. [Sharding Strategy](#sharding-strategy)
3. [Replication Configuration](#replication-configuration)
4. [Distributed Tables](#distributed-tables)
5. [Vertical Scaling](#vertical-scaling)
6. [Cloud-Native Scaling (Kubernetes)](#cloud-native-scaling-kubernetes)
7. [Insert Scalability](#insert-scalability)
8. [Multi-Tenant Architectures](#multi-tenant-architectures)
9. [Capacity Planning](#capacity-planning)

---

## Cluster Architecture Topologies

### Topology 1: Single-Shard, Multi-Replica (HA Focus)

Best for: workloads up to ~10TB, where HA is more important than write throughput scale-out.

```
          ┌─────────────┐
          │   Clients   │
          └──────┬──────┘
                 │
         ┌───────▼────────┐
         │   Load Balancer │
         │  (HAProxy/Nginx)│
         └───┬──────────┬─┘
             │          │
    ┌────────▼──┐    ┌───▼────────┐
    │ Replica 1  │    │ Replica 2  │
    │ (Leader)   │    │ (Follower) │
    └────────────┘    └────────────┘
             │               │
         ┌───▼───────────────▼───┐
         │   ClickHouse Keeper   │
         │   (3-node ensemble)   │
         └───────────────────────┘
```

### Topology 2: Multi-Shard, Multi-Replica (Full Scale-Out)

Best for: petabyte-scale datasets with high write and query throughput requirements.

```
          ┌─────────────┐
          │   Clients   │
          └──────┬──────┘
                 │
         ┌───────▼────────┐
         │   chproxy /    │
         │   Load Balancer│
         └──┬─────────┬───┘
            │         │
    ┌────────▼──┐   ┌──▼────────┐
    │  Shard 1  │   │  Shard 2  │   ... Shard N
    │ R1  │  R2 │   │ R1  │  R2 │
    └─────┴─────┘   └─────┴─────┘
```

### Cluster Configuration

```xml
<!-- config.d/remote_servers.xml -->
<clickhouse>
  <remote_servers>
    <minervadb_cluster>
      <shard>
        <internal_replication>true</internal_replication>
        <replica>
          <host>ch-shard1-replica1</host>
          <port>9000</port>
          <user>replicator</user>
          <password>secret</password>
        </replica>
        <replica>
          <host>ch-shard1-replica2</host>
          <port>9000</port>
        </replica>
      </shard>
      <shard>
        <internal_replication>true</internal_replication>
        <replica>
          <host>ch-shard2-replica1</host>
          <port>9000</port>
        </replica>
        <replica>
          <host>ch-shard2-replica2</host>
          <port>9000</port>
        </replica>
      </shard>
    </minervadb_cluster>
  </remote_servers>
</clickhouse>
```

---

## Sharding Strategy

### Shard Key Selection

```sql
-- Option 1: Hash-based sharding (uniform distribution)
CREATE TABLE events ON CLUSTER minervadb_cluster (
    event_date Date,
    user_id UInt64,
    event_type String,
    value Float64
) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/events', '{replica}')
PARTITION BY toYYYYMM(event_date)
ORDER BY (user_id, event_date);

CREATE TABLE events_distributed ON CLUSTER minervadb_cluster AS events
ENGINE = Distributed(minervadb_cluster, currentDatabase(), events, cityHash64(user_id));

-- Option 2: Range-based sharding (time-based)
ENGINE = Distributed(minervadb_cluster, currentDatabase(), events, toYYYYMM(event_date) % 4);

-- Option 3: Tenant-aware sharding
ENGINE = Distributed(minervadb_cluster, currentDatabase(), events, cityHash64(tenant_id));
```

### Macros Configuration

```xml
<!-- config.d/macros.xml — different on each node -->
<clickhouse>
  <macros>
    <cluster>minervadb_cluster</cluster>
    <shard>01</shard>      <!-- 01, 02, 03... per shard -->
    <replica>replica1</replica>  <!-- replica1, replica2 per replica -->
  </macros>
</clickhouse>
```

### Resharding (Online)

```bash
# 1. Add new shard to cluster config
# 2. Create tables on new shard
# 3. Use clickhouse-copier to migrate data
cat > copier_task.xml << 'EOF'
<yandex>
  <tables>
    <table_events>
      <cluster_pull>minervadb_cluster_old</cluster_pull>
      <database_pull>mydb</database_pull>
      <table_pull>events</table_pull>
      <cluster_push>minervadb_cluster_new</cluster_push>
      <database_push>mydb</database_push>
      <table_push>events</table_push>
      <engine>
        ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/events', '{replica}')
        PARTITION BY toYYYYMM(event_date)
        ORDER BY (user_id, event_date)
      </engine>
      <sharding_key>cityHash64(user_id)</sharding_key>
    </table_events>
  </tables>
</yandex>
EOF

clickhouse-copier --config /etc/clickhouse-server/config.xml \
  --task-path /clickhouse/copier/task1 \
  --task-file copier_task.xml \
  --base-dir /tmp/copier
```

---

## Replication Configuration

### ZooKeeper Path Design

```sql
-- Pattern: /clickhouse/tables/{shard}/{database}/{table}
CREATE TABLE events (
    ...
) ENGINE = ReplicatedMergeTree(
    '/clickhouse/tables/{shard}/mydb/events',  -- ZK path (unique per shard)
    '{replica}'                                 -- replica name (unique per node)
)
```

### Replication Health Monitoring

```sql
-- Overall replication status
SELECT
    database,
    table,
    is_leader,
    is_readonly,
    is_session_expired,
    future_parts,
    parts_to_check,
    queue_size,
    inserts_in_queue,
    merges_in_queue,
    absolute_delay,
    total_replicas,
    active_replicas
FROM system.replicas
ORDER BY absolute_delay DESC;

-- Replication queue details
SELECT
    database,
    table,
    replica_name,
    type,
    create_time,
    num_tries,
    last_exception,
    source_replica,
    new_part_name
FROM system.replication_queue
WHERE last_exception != ''
ORDER BY create_time;
```

---

## Distributed Tables

### Query Routing and Load Balancing

```sql
-- Set load balancing policy
SET load_balancing = 'random';              -- Default
SET load_balancing = 'nearest_hostname';   -- Prefer local shard
SET load_balancing = 'in_order';           -- Use replicas in config order
SET load_balancing = 'first_or_random';    -- First available, then random
SET load_balancing = 'round_robin';        -- Round-robin across replicas
```

### GLOBAL IN / GLOBAL JOIN for Cross-Shard Queries

```sql
-- Without GLOBAL: subquery executes on each shard (N times)
SELECT count() FROM events_distributed
WHERE user_id IN (SELECT user_id FROM vip_users_distributed WHERE is_active = 1);

-- With GLOBAL: subquery executes once, result broadcast to all shards
SELECT count() FROM events_distributed
WHERE user_id GLOBAL IN (SELECT user_id FROM vip_users_distributed WHERE is_active = 1);

-- GLOBAL JOIN
SELECT e.user_id, u.name, count() AS event_count
FROM events_distributed e
GLOBAL JOIN users_distributed u ON e.user_id = u.user_id
GROUP BY e.user_id, u.name;
```

### Distributed DDL

```sql
-- Execute DDL on all cluster nodes simultaneously
CREATE TABLE new_table ON CLUSTER minervadb_cluster (
    id UInt64,
    data String
) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/mydb/new_table', '{replica}')
ORDER BY id;

-- Monitor DDL task progress
SELECT * FROM system.distributed_ddl_queue
WHERE cluster = 'minervadb_cluster'
ORDER BY entry_time DESC;
```

---

## Vertical Scaling

### CPU Scaling

```xml
<clickhouse>
  <!-- Scale query parallelism with available cores -->
  <max_threads>0</max_threads>  <!-- 0 = auto (number of CPU cores) -->
  <max_insert_threads>0</max_insert_threads>
  <background_pool_size>32</background_pool_size>

  <!-- NUMA-aware settings -->
  <numa_node_preference>0</numa_node_preference>
</clickhouse>
```

### Memory Scaling Formula

```
Total RAM = Query Memory + OS Cache + ClickHouse Overhead

Recommended allocation:
- Query memory: 50% of RAM  (max_server_memory_usage_to_ram_ratio = 0.5)
- Mark cache: 5-10% of RAM
- OS page cache: 30-40% of RAM (critical for I/O performance)
- Overhead (OS, other): 5%

For 256GB RAM:
- max_server_memory_usage: 128GB
- mark_cache_size: 10GB
- uncompressed_cache_size: 4GB (only if hit rate > 50%)
```

---

## Cloud-Native Scaling (Kubernetes)

### ClickHouse Operator Deployment

```yaml
# clickhouse-cluster.yaml
apiVersion: clickhouse.altinity.com/v1
kind: ClickHouseInstallation
metadata:
  name: minervadb-cluster
  namespace: clickhouse
spec:
  configuration:
    zookeeper:
      nodes:
        - host: zookeeper-0.zookeeper-headless.clickhouse.svc.cluster.local
        - host: zookeeper-1.zookeeper-headless.clickhouse.svc.cluster.local
        - host: zookeeper-2.zookeeper-headless.clickhouse.svc.cluster.local

    clusters:
      - name: minervadb_cluster
        layout:
          shardsCount: 3
          replicasCount: 2

    settings:
      max_concurrent_queries: 200
      max_server_memory_usage_to_ram_ratio: 0.8

  templates:
    podTemplates:
      - name: clickhouse-pod
        spec:
          containers:
            - name: clickhouse
              image: clickhouse/clickhouse-server:24.3
              resources:
                requests:
                  memory: "32Gi"
                  cpu: "8"
                limits:
                  memory: "64Gi"
                  cpu: "16"
    volumeClaimTemplates:
      - name: data-storage
        spec:
          accessModes:
            - ReadWriteOnce
          storageClassName: fast-nvme
          resources:
            requests:
              storage: 2Ti
```

### Horizontal Pod Autoscaler (Read Replicas)

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: clickhouse-read-replicas
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: StatefulSet
    name: clickhouse-read-replica
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

---

## Insert Scalability

### Streaming Ingestion with Kafka

```sql
-- Kafka source table
CREATE TABLE kafka_events (
    event_time DateTime,
    user_id UInt64,
    event_type String,
    value Float64
) ENGINE = Kafka()
SETTINGS
    kafka_broker_list = 'kafka-1:9092,kafka-2:9092,kafka-3:9092',
    kafka_topic_list = 'events',
    kafka_group_name = 'clickhouse_consumer',
    kafka_format = 'JSONEachRow',
    kafka_num_consumers = 4,
    kafka_max_block_size = 65536,
    kafka_skip_broken_messages = 100;

-- Materialized view to persist data
CREATE MATERIALIZED VIEW kafka_events_mv TO events AS
SELECT event_time, user_id, event_type, value
FROM kafka_events;
```

### Async Insert Configuration for High-Frequency Clients

```xml
<profiles>
  <high_frequency_insert>
    <async_insert>1</async_insert>
    <wait_for_async_insert>0</wait_for_async_insert>
    <async_insert_max_data_size>10485760</async_insert_max_data_size>
    <async_insert_busy_timeout_ms>200</async_insert_busy_timeout_ms>
    <async_insert_stale_timeout_ms>0</async_insert_stale_timeout_ms>
  </high_frequency_insert>
</profiles>
```

---

## Multi-Tenant Architectures

### Tenant Isolation Strategies

```sql
-- Strategy 1: Database-per-tenant
CREATE DATABASE tenant_abc;
USE tenant_abc;
CREATE TABLE events (...) ENGINE = MergeTree() ...;

-- Strategy 2: Partition-per-tenant
CREATE TABLE events (
    tenant_id LowCardinality(String),
    event_date Date,
    ...
) ENGINE = MergeTree()
PARTITION BY (tenant_id, toYYYYMM(event_date))
ORDER BY (tenant_id, event_date);

-- Strategy 3: Row-level security
CREATE ROW POLICY tenant_policy ON mydb.events
    USING tenant_id = currentUser()
    AS PERMISSIVE FOR SELECT TO tenant_role;
```

### Resource Quotas Per Tenant

```xml
<quotas>
  <tenant_standard>
    <interval>
      <duration>3600</duration>
      <queries>1000</queries>
      <query_selects>900</query_selects>
      <query_inserts>100</query_inserts>
      <errors>100</errors>
      <result_rows>1000000000</result_rows>
      <read_rows>10000000000</read_rows>
      <execution_time>3600</execution_time>
    </interval>
  </tenant_standard>
</quotas>
```

---

## Capacity Planning

### Storage Sizing Formula

```
Raw data size = avg_row_size_bytes * rows_per_day * retention_days

Compressed size = Raw data size / compression_ratio
  (typical compression_ratio = 5-10x for structured data)

Disk size = Compressed size * 2.5
  (factor for: replication, parts overhead, temp files, OS)

Example: 1KB avg row, 100M rows/day, 365 days retention
  Raw: 1KB * 100M * 365 = 36.5TB
  Compressed (8x): 36.5TB / 8 = 4.6TB
  Disk per replica: 4.6TB * 2.5 = 11.5TB
  With 2 replicas: 23TB total disk
```

### Query Throughput Planning

```
Concurrent queries = CPU_cores * 0.8
                   / avg_parallelism_per_query

Memory per concurrent query = max_server_memory / max_concurrent_queries

Recommended limits:
  OLAP heavy queries: 4-8 concurrent
  Mixed workload: 20-50 concurrent
  Light dashboard queries: 100-200 concurrent
```

---

*Back to [MinervaDB Server Documentation](../README.md)*
