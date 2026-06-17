# Disaster Recovery & High Availability — MinervaDB Server for ClickHouse

Backup strategies, recovery procedures, and HA architecture for production ClickHouse deployments.

---

## Table of Contents

1. [Backup Strategy Overview](#backup-strategy-overview)
2. [clickhouse-backup Tool](#clickhouse-backup-tool)
3. [Backup to Object Storage](#backup-to-object-storage)
4. [Incremental Backups](#incremental-backups)
5. [Restore Procedures](#restore-procedures)
6. [High Availability Architecture](#high-availability-architecture)
7. [ClickHouse Keeper (HA Coordination)](#clickhouse-keeper-ha-coordination)
8. [Load Balancing](#load-balancing)
9. [Rolling Upgrades](#rolling-upgrades)
10. [Failover Procedures](#failover-procedures)
11. [Cross-Region DR](#cross-region-dr)
12. [DR Runbooks](#dr-runbooks)

---

## Backup Strategy Overview

### RPO / RTO Targets

| Scenario | RPO Target | RTO Target | Method |
|----------|-----------|-----------|--------|
| Single replica failure | 0 (real-time replication) | < 30s | Automatic failover |
| Full cluster failure | < 1 hour | < 2 hours | clickhouse-backup restore |
| Ransomware / corruption | < 24 hours | < 4 hours | Offsite backup restore |
| Cross-region DR | < 1 hour | < 1 hour | Async replica promotion |

### Backup Types

| Type | Frequency | Retention | Tool |
|------|-----------|-----------|------|
| Full backup | Daily | 30 days | clickhouse-backup |
| Incremental | Hourly | 7 days | clickhouse-backup diff |
| Partition freeze | On-demand | Manual | FREEZE PARTITION |
| Replica | Continuous | N/A | ReplicatedMergeTree |

---

## clickhouse-backup Tool

### Installation

```bash
# Latest release
wget https://github.com/Altinity/clickhouse-backup/releases/latest/download/clickhouse-backup-linux-amd64.tar.gz
tar xzf clickhouse-backup-linux-amd64.tar.gz
mv clickhouse-backup /usr/local/bin/
chmod +x /usr/local/bin/clickhouse-backup

# Verify
clickhouse-backup version
```

### Configuration

```yaml
# /etc/clickhouse-backup/config.yml
general:
  remote_storage: s3
  max_file_size: 10737418240  # 10GB
  disable_progress_bar: false
  backups_to_keep_local: 3
  backups_to_keep_remote: 30
  log_level: info
  allow_empty_backups: false

clickhouse:
  username: backup_user
  password: backup_password
  host: localhost
  port: 9000
  data_path: /var/lib/clickhouse
  skip_tables:
    - system.*
    - information_schema.*
  timeout: 5m
  freeze_by_part: false

s3:
  access_key: YOUR_ACCESS_KEY
  secret_key: YOUR_SECRET_KEY
  bucket: minervadb-clickhouse-backups
  region: us-east-1
  path: clickhouse-backups/{hostname}
  disable_ssl: false
  part_size: 134217728  # 128MB
  compression_level: 1
  compression_format: gzip
  sse: AES256
  storage_class: STANDARD_IA
```

---

## Backup to Object Storage

### Full Backup

```bash
# Create full backup locally
clickhouse-backup create --config /etc/clickhouse-backup/config.yml full_backup_$(date +%Y%m%d)

# Upload to S3
clickhouse-backup upload --config /etc/clickhouse-backup/config.yml full_backup_$(date +%Y%m%d)

# Create and upload in one step
clickhouse-backup create_remote --config /etc/clickhouse-backup/config.yml full_backup_$(date +%Y%m%d)

# List remote backups
clickhouse-backup list remote --config /etc/clickhouse-backup/config.yml
```

### Automated Backup Schedule (cron)

```bash
# /etc/cron.d/clickhouse-backup
# Full backup daily at 2 AM
0 2 * * * clickhouse /usr/local/bin/clickhouse-backup create_remote --config /etc/clickhouse-backup/config.yml full_$(date +\%Y\%m\%d) >> /var/log/clickhouse-backup.log 2>&1

# Cleanup old local backups daily at 3 AM
0 3 * * * clickhouse /usr/local/bin/clickhouse-backup clean --config /etc/clickhouse-backup/config.yml >> /var/log/clickhouse-backup.log 2>&1

# Delete old remote backups (keep 30 days)
0 4 * * * clickhouse /usr/local/bin/clickhouse-backup delete remote $(clickhouse-backup list remote --config /etc/clickhouse-backup/config.yml | awk 'NR>30{print $1}') >> /var/log/clickhouse-backup.log 2>&1
```

### Kubernetes CronJob

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: clickhouse-backup
  namespace: clickhouse
spec:
  schedule: "0 2 * * *"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: clickhouse-backup
              image: altinity/clickhouse-backup:latest
              command:
                - clickhouse-backup
                - create_remote
                - --config=/config/backup.yml
                - "full_$(date +%Y%m%d_%H%M%S)"
              volumeMounts:
                - name: backup-config
                  mountPath: /config
                - name: clickhouse-data
                  mountPath: /var/lib/clickhouse
          volumes:
            - name: backup-config
              configMap:
                name: backup-config
            - name: clickhouse-data
              persistentVolumeClaim:
                claimName: clickhouse-data
          restartPolicy: OnFailure
```

---

## Incremental Backups

```bash
# Create diff (incremental) backup since last full
clickhouse-backup create --config /etc/clickhouse-backup/config.yml \
  --diff-from full_20240101 \
  incremental_20240102

# Upload incremental
clickhouse-backup upload --config /etc/clickhouse-backup/config.yml incremental_20240102

# Restore incremental (downloads full + all incrementals automatically)
clickhouse-backup restore_remote --config /etc/clickhouse-backup/config.yml incremental_20240102
```

---

## Restore Procedures

### Full Restore

```bash
# Step 1: List available backups
clickhouse-backup list remote --config /etc/clickhouse-backup/config.yml

# Step 2: Download backup
clickhouse-backup download --config /etc/clickhouse-backup/config.yml full_20240101

# Step 3: Restore all databases
clickhouse-backup restore --config /etc/clickhouse-backup/config.yml full_20240101

# Restore specific databases
clickhouse-backup restore --config /etc/clickhouse-backup/config.yml \
  --tables "mydb.*" full_20240101

# Restore specific tables
clickhouse-backup restore --config /etc/clickhouse-backup/config.yml \
  --tables "mydb.events,mydb.users" full_20240101
```

### Partition-Level Restore

```sql
-- Freeze partition for point-in-time snapshot
ALTER TABLE mydb.events FREEZE PARTITION '2024-01';
-- Creates: /var/lib/clickhouse/shadow/<N>/data/mydb/events/

-- To restore from freeze, copy parts to detached:
-- cp -r /var/lib/clickhouse/shadow/<N>/data/mydb/events/* /var/lib/clickhouse/data/mydb/events/detached/
-- Then attach:
ALTER TABLE mydb.events ATTACH PARTITION '2024-01';
```

### Backup Verification

```bash
# Verify backup integrity
clickhouse-backup check --config /etc/clickhouse-backup/config.yml full_20240101

# Test restore to separate instance
clickhouse-backup restore --config /etc/clickhouse-backup/config.yml \
  --restore-schema-only full_20240101
clickhouse-client -q "SHOW TABLES FROM mydb"
```

---

## High Availability Architecture

### 3-Node HA Cluster (Single Shard)

```
         ┌───────────────────────────────────────┐
         │         HAProxy / chproxy             │
         │         (Load Balancer)               │
         └──────────┬──────────┬─────────────────┘
                    │          │
         ┌──────────▼──┐  ┌───▼─────────┐
         │  CH Node 1  │  │  CH Node 2  │
         │  (Leader)   │  │  (Follower) │
         └─────────────┘  └─────────────┘
                    │          │
              ┌─────▼──────────▼─────┐
              │  ClickHouse Keeper   │
              │   (3-node quorum)    │
              │  K1  |  K2  |  K3   │
              └─────────────────────┘
```

### ReplicatedMergeTree Configuration

```sql
-- Tables must use ReplicatedMergeTree for HA
CREATE TABLE events (
    event_date Date,
    user_id UInt64,
    event_type String,
    value Float64
) ENGINE = ReplicatedMergeTree(
    '/clickhouse/tables/{shard}/mydb/events',  -- Unique ZK path per shard
    '{replica}'                                 -- Unique per node (from macros)
)
PARTITION BY toYYYYMM(event_date)
ORDER BY (user_id, event_date);
```

### Node Macros (per-node configuration)

```xml
<!-- Node 1: config.d/macros.xml -->
<clickhouse>
  <macros>
    <cluster>minervadb_cluster</cluster>
    <shard>01</shard>
    <replica>ch-node1</replica>
  </macros>
</clickhouse>

<!-- Node 2: config.d/macros.xml -->
<clickhouse>
  <macros>
    <cluster>minervadb_cluster</cluster>
    <shard>01</shard>
    <replica>ch-node2</replica>
  </macros>
</clickhouse>
```

---

## ClickHouse Keeper (HA Coordination)

### 3-Node Keeper Configuration

```xml
<!-- /etc/clickhouse-keeper/keeper_config.xml -->
<clickhouse>
  <logger>
    <level>information</level>
    <log>/var/log/clickhouse-keeper/keeper.log</log>
    <errorlog>/var/log/clickhouse-keeper/keeper.err.log</errorlog>
    <size>500M</size>
    <count>10</count>
  </logger>

  <keeper_server>
    <tcp_port>9181</tcp_port>
    <server_id>1</server_id>  <!-- 1, 2, 3 for each node -->
    <log_storage_path>/var/lib/clickhouse-keeper/coordination/log</log_storage_path>
    <snapshot_storage_path>/var/lib/clickhouse-keeper/coordination/snapshots</snapshot_storage_path>

    <coordination_settings>
      <operation_timeout_ms>10000</operation_timeout_ms>
      <session_timeout_ms>30000</session_timeout_ms>
      <raft_logs_level>warning</raft_logs_level>
      <rotate_log_storage_interval>100000</rotate_log_storage_interval>
      <snapshot_distance>100000</snapshot_distance>
      <max_stored_snapshots>3</max_stored_snapshots>
    </coordination_settings>

    <raft_configuration>
      <server>
        <id>1</id>
        <hostname>keeper-1.internal</hostname>
        <port>9234</port>
      </server>
      <server>
        <id>2</id>
        <hostname>keeper-2.internal</hostname>
        <port>9234</port>
      </server>
      <server>
        <id>3</id>
        <hostname>keeper-3.internal</hostname>
        <port>9234</port>
      </server>
    </raft_configuration>
  </keeper_server>
</clickhouse>
```

### ClickHouse → Keeper Connection

```xml
<!-- config.d/04-zookeeper.xml (on ClickHouse nodes) -->
<clickhouse>
  <zookeeper>
    <node>
      <host>keeper-1.internal</host>
      <port>9181</port>
    </node>
    <node>
      <host>keeper-2.internal</host>
      <port>9181</port>
    </node>
    <node>
      <host>keeper-3.internal</host>
      <port>9181</port>
    </node>
    <session_timeout_ms>30000</session_timeout_ms>
    <operation_timeout_ms>10000</operation_timeout_ms>
  </zookeeper>
</clickhouse>
```

### Keeper Health Check

```bash
# 4-letter commands
echo "ruok" | nc keeper-1 9181     # Returns: imok (alive)
echo "stat" | nc keeper-1 9181     # Statistics
echo "mntr" | nc keeper-1 9181     # Monitoring metrics
echo "isro" | nc keeper-1 9181     # rw (leader/follower) or ro (read-only)
echo "conf" | nc keeper-1 9181     # Configuration

# From ClickHouse
SELECT * FROM system.zookeeper WHERE path = '/clickhouse';
SELECT * FROM system.keeper_map;
```

---

## Load Balancing

### HAProxy Configuration

```haproxy
# /etc/haproxy/haproxy.cfg
global
    daemon
    maxconn 50000

defaults
    timeout connect 5s
    timeout client 300s
    timeout server 300s
    option tcp-check

# Native TCP protocol (port 9000)
frontend clickhouse_native
    bind *:9000
    default_backend clickhouse_native_backend

backend clickhouse_native_backend
    balance roundrobin
    option tcp-check
    tcp-check connect port 8123
    tcp-check send GET\ /ping\ HTTP/1.0\r\nHost:\ localhost\r\n\r\n
    tcp-check expect string Ok.
    server ch-node1 ch-node1:9000 check inter 5s rise 2 fall 3
    server ch-node2 ch-node2:9000 check inter 5s rise 2 fall 3

# HTTP interface (port 8123)
frontend clickhouse_http
    bind *:8123
    default_backend clickhouse_http_backend

backend clickhouse_http_backend
    balance roundrobin
    option httpchk GET /ping
    http-check expect string Ok.
    server ch-node1 ch-node1:8123 check inter 5s rise 2 fall 3
    server ch-node2 ch-node2:8123 check inter 5s rise 2 fall 3

# Stats page
frontend stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 30s
```

### chproxy Configuration

```yaml
# /etc/chproxy/config.yml
server:
  http:
    listen_addr: ":9090"
    allowed_networks: ["10.0.0.0/8", "172.16.0.0/12"]

users:
  - name: "default"
    password: ""
    to_cluster: "minervadb_cluster"
    to_user: "default"
    max_concurrent_queries: 100
    max_execution_time: 5m
    request_timeout: 10m

  - name: "analytics"
    password: "analytics_password"
    to_cluster: "minervadb_cluster"
    to_user: "analytics"
    max_concurrent_queries: 20
    max_execution_time: 30m

clusters:
  - name: "minervadb_cluster"
    scheme: "http"
    nodes:
      - "ch-node1:8123"
      - "ch-node2:8123"
    heartbeat:
      interval: 5s
      timeout: 3s
      request: "/?query=SELECT+1"
      response: "1"
    kill_query_on_timeout: true
```

---

## Rolling Upgrades

```bash
# Step 1: Check replication queue is empty
clickhouse-client -q "SELECT max(queue_size) FROM system.replicas"
# Wait for 0

# Step 2: Stop one replica
systemctl stop clickhouse-server

# Step 3: Upgrade packages
apt-get install -y clickhouse-server=24.3.x.xx clickhouse-client=24.3.x.xx

# Step 4: Start upgraded node
systemctl start clickhouse-server

# Step 5: Verify new version
clickhouse-client -q "SELECT version()"

# Step 6: Verify replication synced
clickhouse-client -q "SELECT database, table, absolute_delay FROM system.replicas ORDER BY absolute_delay DESC LIMIT 5"

# Step 7: Repeat for next replica
# Repeat Steps 2-6 for each node
```

---

## Failover Procedures

### Single Node Failure

```bash
# ClickHouse handles this automatically via ReplicatedMergeTree
# Reads automatically go to the surviving replica
# Verify reads are working:
clickhouse-client -q "SELECT count() FROM mydb.events WHERE event_date = today()"

# Monitor replica catch-up after failed node comes back:
clickhouse-client -q "SELECT database, table, absolute_delay FROM system.replicas ORDER BY absolute_delay DESC"
```

### Full Cluster Failover to DR Region

```bash
# Step 1: Verify DR replica is up-to-date
# (Check replication lag < 60s before proceeding)
clickhouse-client --host dr-ch-node1 -q "SELECT max(absolute_delay) FROM system.replicas"

# Step 2: Promote DR replica to primary
# Update DNS to point to DR region
# Route53 / Cloudflare / Internal DNS update:
# clickhouse.internal -> dr-ch-node1.internal

# Step 3: Restart application connections (they will reconnect to DR)

# Step 4: Enable writes on DR region
# (In HA setup, DR replicas can already accept writes if configured with internal_replication=true)

# Step 5: Verify cluster is operational
clickhouse-client --host dr-ch-node1 -q "SELECT 'DR cluster operational', version(), uptime()"
```

---

## Cross-Region DR

### Async Replication Setup

```xml
<!-- config.d/remote_servers.xml — Primary Region -->
<clickhouse>
  <remote_servers>
    <minervadb_cluster>
      <shard>
        <internal_replication>true</internal_replication>
        <!-- Primary replicas -->
        <replica>
          <host>ch-primary-1.us-east.internal</host>
          <port>9000</port>
        </replica>
        <replica>
          <host>ch-primary-2.us-east.internal</host>
          <port>9000</port>
        </replica>
        <!-- DR replica (async, different data center) -->
        <replica>
          <host>ch-dr-1.us-west.internal</host>
          <port>9000</port>
        </replica>
      </shard>
    </minervadb_cluster>
  </remote_servers>
</clickhouse>
```

### DR Monitoring

```sql
-- Monitor cross-region replication lag
SELECT
    replica_host,
    database,
    table,
    absolute_delay,
    is_readonly
FROM system.replicas
WHERE replica_host LIKE '%us-west%'
ORDER BY absolute_delay DESC;
```

---

## DR Runbooks

### Runbook: Restore Single Table from Backup

```bash
#!/bin/bash
TABLE=$1
BACKUP_NAME=$2
DB=${3:-mydb}

echo "Restoring table: $DB.$TABLE from backup: $BACKUP_NAME"

# Download backup if not local
clickhouse-backup download --config /etc/clickhouse-backup/config.yml $BACKUP_NAME

# Restore specific table
clickhouse-backup restore --config /etc/clickhouse-backup/config.yml \
  --tables "$DB.$TABLE" \
  --restore-schema-only \
  $BACKUP_NAME

clickhouse-backup restore --config /etc/clickhouse-backup/config.yml \
  --tables "$DB.$TABLE" \
  --schema-only=false \
  $BACKUP_NAME

echo "Restore complete. Verifying..."
clickhouse-client -q "SELECT count() FROM $DB.$TABLE"
```

### Runbook: Emergency Disk Recovery

```bash
#!/bin/bash
# When disk is >90% full

echo "=== Emergency Disk Recovery ==="

# 1. Find largest partitions
clickhouse-client -q "
SELECT database, table, partition,
       formatReadableSize(sum(bytes_on_disk)) AS size
FROM system.parts WHERE active=1
GROUP BY database, table, partition
ORDER BY sum(bytes_on_disk) DESC LIMIT 10 FORMAT Pretty"

# 2. Drop oldest partition from largest table (requires manual confirmation)
# clickhouse-client -q "ALTER TABLE <db>.<table> DROP PARTITION '<oldest_partition>'"

# 3. Clean up detached parts
clickhouse-client -q "
SELECT 'ALTER TABLE ' || database || '.' || table || ' DROP DETACHED PART ''' || name || ''';'
FROM system.detached_parts
WHERE modification_time < now() - INTERVAL 7 DAY
FORMAT TSV" | clickhouse-client --multiquery

echo "Recovery complete. Check disk usage:"
clickhouse-client -q "SELECT name, formatReadableSize(free_space), round((1-free_space/total_space)*100,1) AS used_pct FROM system.disks"
```

---

*See also:*
- [OBSERVABILITY.md](OBSERVABILITY.md) — Backup monitoring and alerting
- [SCALABILITY.md](SCALABILITY.md) — Cluster topology
- [Back to README](../README.md)
