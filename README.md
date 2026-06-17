# MinervaDB Server for ClickHouse

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![ClickHouse](https://img.shields.io/badge/ClickHouse-Fork-orange.svg)](https://github.com/ClickHouse/ClickHouse)
[![MinervaDB](https://img.shields.io/badge/MinervaDB-Server-green.svg)](https://minervadb.xyz)

> **MinervaDB Server for ClickHouse** is an enterprise-grade distribution and fork of [ClickHouse](https://clickhouse.com/) — the world's fastest open-source real-time analytics database — enhanced with curated extensions, operational tooling, and comprehensive documentation covering Performance Engineering, Scalability, Troubleshooting, Observability & Monitoring, Disaster Recovery (DR), and High Availability (HA).
>
> ---
>
> ## Table of Contents
>
> - [Overview](#overview)
> - - [Architecture](#architecture)
>   - - [Key Features](#key-features)
>     - - [Performance Engineering](#performance-engineering)
>       - - [Scalability](#scalability)
>         - - [Observability & Monitoring](#observability--monitoring)
>           - - [Troubleshooting](#troubleshooting)
>             - - [Disaster Recovery (DR)](#disaster-recovery-dr)
>               - - [High Availability (HA)](#high-availability-ha)
>                 - - [Extensions & Integrations](#extensions--integrations)
>                   - - [Tools Bundled](#tools-bundled)
>                     - - [Installation](#installation)
>                       - - [Configuration Reference](#configuration-reference)
>                         - - [Documentation Index](#documentation-index)
>                           - - [Contributing](#contributing)
>                             - - [License](#license)
>                              
>                               - ---
>
> ## Overview
>
> MinervaDB Server for ClickHouse is built on top of the upstream ClickHouse DBMS and extends it with:
>
> - **Production-hardened configurations** for OLAP workloads at petabyte scale
> - - **Observability stack integrations** (Prometheus, Grafana, OpenTelemetry, Vector)
>   - - **Automated backup and recovery tooling** (Clickhouse-backup, S3/GCS/Azure integration)
>     - - **Replication and HA orchestration** (ClickHouse Keeper, ZooKeeper migration guides)
>       - - **Performance profiling and query analysis tools**
>         - - **Security hardening** (RBAC templates, TLS, audit logging)
>           - - **Kubernetes-native deployment** (Helm charts, operators)
>             - - **Comprehensive runbooks** for every operational scenario
>              
>               - MinervaDB Server targets data engineering teams, database administrators, and platform engineers who run ClickHouse in mission-critical production environments.
>              
>               - ---
>
> ## Architecture
>
> ```
> ┌──────────────────────────────────────────────────────────────────────┐
> │                    MinervaDB Server for ClickHouse                   │
> ├──────────────┬──────────────┬───────────────┬────────────────────────┤
> │  Performance │  Scalability │ Observability │   DR & HA              │
> │  Extensions  │  Extensions  │   Stack       │   Tooling              │
> ├──────────────┴──────────────┴───────────────┴────────────────────────┤
> │                   ClickHouse Core (Upstream Fork)                    │
> │         MergeTree · ReplicatedMergeTree · Distributed Tables         │
> ├──────────────────────────────────────────────────────────────────────┤
> │              ClickHouse Keeper (Consensus & Coordination)            │
> ├───────────────────────┬──────────────────────────────────────────────┤
> │   Storage Layer       │  Network & Security Layer                    │
> │ (Local/S3/GCS/Azure)  │  (TLS, RBAC, Audit, VPC)                    │
> └───────────────────────┴──────────────────────────────────────────────┘
> ```
>
> ---
>
> ## Key Features
>
> ### Core Database Engine
> - Full upstream ClickHouse compatibility — every ClickHouse SQL feature, function, and table engine is preserved
> - - MergeTree family: MergeTree, ReplacingMergeTree, SummingMergeTree, AggregatingMergeTree, CollapsingMergeTree, VersionedCollapsingMergeTree, GraphiteMergeTree
>   - - Distributed query execution across shards and replicas
>     - - Tiered storage: hot/warm/cold with automatic data migration policies
>       - - Object storage integration (S3, GCS, Azure Blob) as primary or secondary storage
>        
>         - ### Operational Enhancements
>         - - Pre-tuned `config.xml` and `users.xml` profiles for production workloads
>           - - Automated merge tree settings optimizer based on workload profiling
>             - - Query complexity limits and resource group enforcement
>               - - Adaptive query scheduler with priority queues
>                
>                 - ---
>
> ## Performance Engineering
>
> See full documentation: [docs/PERFORMANCE.md](docs/PERFORMANCE.md)
>
> ### MergeTree Storage Optimization
> - Granule size tuning (`index_granularity`, `index_granularity_bytes`)
> - - Adaptive compression codec selection (LZ4, ZSTD, ZSTD with dictionaries, Delta, DoubleDelta, Gorilla, FPC)
>   - - Skipping indexes: `minmax`, `set`, `ngrambf_v1`, `tokenbf_v1`, `bloom_filter`, `full_text`
>     - - Primary key and sorting key design patterns
>       - - Partition design for time-series, multi-tenant, and high-cardinality workloads
>        
>         - ### Query Performance
>         - - `EXPLAIN` pipeline analysis and query plan inspection
>           - - `system.query_log` analysis queries and automated slow-query detection
>             - - Projection usage for pre-aggregated data access patterns
>               - - Materialized views for real-time aggregation pipelines
>                 - - Query cache configuration and eviction policies
>                  
>                   - ### Memory Management
>                   - - Memory limits per user, query, and server (`max_memory_usage`, `max_server_memory_usage`)
>                     - - External aggregation and external sorting for large datasets
>                       - - Buffer table engine for high-frequency inserts
>                         - - Jemalloc tuning for production environments
>                          
>                           - ### I/O Optimization
>                           - - Asynchronous I/O and prefetch settings
>                             - - MergeTree read-ahead tuning
>                               - - Disk-level striping and RAID configuration guides
>                                 - - Page cache utilization monitoring
>                                  
>                                   - ### Hardware-Specific Tuning
>                                   - - NVMe SSD tuning (scheduler, queue depth, read-ahead)
>                                     - - NUMA-aware memory allocation
>                                       - - CPU affinity and thread pool sizing
>                                         - - Network tuning for inter-shard and inter-replica traffic
>                                          
>                                           - ---
>
> ## Scalability
>
> See full documentation: [docs/SCALABILITY.md](docs/SCALABILITY.md)
>
> ### Horizontal Scaling — Sharding
> - Shard key selection strategy (by hash, by range, by expression)
> - - `Distributed` table engine configuration
>   - - `cluster` macro and remote server definitions
>     - - Resharding and rebalancing procedures
>       - - Cross-shard joins and `GLOBAL IN` / `GLOBAL JOIN` patterns
>        
>         - ### Vertical Scaling
>         - - CPU and memory capacity planning formulas
>           - - Concurrent insert and query slot sizing
>             - - Background merge thread pool scaling
>               - - Mark cache and uncompressed cache sizing
>                
>                 - ### Multi-Tier Cluster Topologies
>                 - - Single-shard, multi-replica (HA-only)
>                   - - Multi-shard, multi-replica (full scale-out)
>                     - - Hierarchical cluster (data center–aware routing)
>                       - - Read replicas with `load_balancing` policies
>                        
>                         - ### Cloud-Native Scaling
>                         - - ClickHouse on Kubernetes with the Altinity Operator or ClickHouse Operator
>                           - - Helm chart values for MinervaDB Server
>                             - - Horizontal Pod Autoscaler integration
>                               - - Spot/preemptible node handling with graceful drain
>                                
>                                 - ### Insert Scalability
>                                 - - Async inserts configuration (`async_insert`, `wait_for_async_insert`)
>                                   - - Native protocol bulk inserts vs HTTP interface
>                                     - - Kafka, Kinesis, and Pulsar engine integration for streaming ingestion
>                                       - - ClickHouse-kafka-connect and Vector sink configuration
>                                        
>                                         - ---
>
> ## Observability & Monitoring
>
> See full documentation: [docs/OBSERVABILITY.md](docs/OBSERVABILITY.md)
>
> ### Metrics Stack
>
> **Prometheus + Grafana**
> - `clickhouse_exporter` deployment and configuration
> - - Pre-built Grafana dashboards (bundled in `monitoring/grafana/dashboards/`)
>   -   - Cluster Overview
>       -   - MergeTree Internals
>           -   - Replication Health
>               -   - Query Performance
>                   -   - Insert Pipeline
>                       -   - Disk & Storage
>                           -   - Memory Pressure
>                               -   - Background Merges & Mutations
>                                
>                                   - **OpenTelemetry**
>                                   - - OTLP trace export from ClickHouse query execution
>                                     - - Span correlation with `query_id` and `trace_id`
>                                       - - Integration with Jaeger, Tempo, and Honeycomb
>                                        
>                                         - **Vector**
>                                         - - Log shipping from ClickHouse server logs to Elasticsearch / Loki / S3
>                                           - - Metrics pipeline from system tables to external TSDB
>                                            
>                                             - ### Key System Tables for Monitoring
>                                            
>                                             - ```sql
>                                               -- Active queries
>                                               SELECT query_id, user, elapsed, memory_usage, read_rows, query
>                                               FROM system.processes ORDER BY elapsed DESC;
>
>                                               -- Replication lag
>                                               SELECT database, table, is_leader, absolute_delay
>                                               FROM system.replicas WHERE absolute_delay > 0;
>
>                                               -- Merge backlog
>                                               SELECT database, table, elapsed, progress, num_parts
>                                               FROM system.merges ORDER BY elapsed DESC;
>
>                                               -- Disk usage
>                                               SELECT name, path, formatReadableSize(free_space), formatReadableSize(total_space)
>                                               FROM system.disks;
>                                               ```
>
> ### Alerting Rules
> - Prometheus alerting rules bundled in `monitoring/prometheus/alerts/`
> -   - ReplicationLagHigh
>     -   - MergeBacklogHigh
>         -   - DiskSpaceLow
>             -   - QueryMemoryPressure
>                 -   - InsertQueueDepthHigh
>                     -   - ClickHouseDown
>                         -   - ZooKeeperSessionExpired
>                          
>                             - ### Log Management
>                             - - Structured logging configuration (`logger` section in `config.xml`)
>                               - - Query log, part log, trace log, crash log, metric log, asynchronous metric log
>                                 - - Log rotation and retention policies
>                                   - - Centralized log analysis patterns for Loki and Elasticsearch
>                                    
>                                     - ---
>
> ## Troubleshooting
>
> See full documentation: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
>
> ### Common Issues & Runbooks
>
> #### High Memory Usage
> 1. Identify top memory-consuming queries via `system.query_log` and `system.processes`
> 2. 2. Check for uncontrolled mutations: `SELECT * FROM system.mutations WHERE is_done = 0`
>    3. 3. Review mark cache and uncompressed cache hit rates
>       4. 4. Apply memory limits per query and per user profile
>         
>          5. #### Slow Queries
>          6. 1. Run `EXPLAIN pipeline SELECT ...` to understand execution plan
>             2. 2. Check primary key and partition key usage (key conditions vs full scan)
>                3. 3. Verify skipping index coverage for filter columns
>                   4. 4. Analyze `system.query_log` for `ProfileEvents` (e.g., `ReadBufferFromFileDescriptorRead`)
>                      5. 5. Check for cross-shard shuffle (GLOBAL IN overhead)
>                        
>                         6. #### Replication Issues
>                         7. 1. `SELECT * FROM system.replicas WHERE is_readonly = 1` — identify read-only replicas
>                            2. 2. `SELECT * FROM system.replication_queue` — inspect pending replication tasks
>                               3. 3. ZooKeeper / ClickHouse Keeper connectivity and session timeout diagnosis
>                                  4. 4. Force replica re-sync: `SYSTEM SYNC REPLICA db.table`
>                                     5. 5. Recovery from replica divergence with `ALTER TABLE ... DROP DETACHED PART`
>                                       
>                                        6. #### Insert Failures
>                                        7. 1. Check `system.part_log` for `Exception` events
>                                           2. 2. Too many parts: tune `max_insert_block_size`, `parts_to_delay_insert`, `parts_to_throw_insert`
>                                              3. 3. Schema mismatch errors in Kafka engine — column type validation
>                                                 4. 4. Quota and throttle limits on insert users
>                                                   
>                                                    5. #### Merge Storms
>                                                    6. 1. Identify tables with excessive part counts: `SELECT database, table, count() FROM system.parts WHERE active GROUP BY database, table ORDER BY count() DESC`
>                                                       2. 2. Tune `max_bytes_to_merge_at_max_space_in_pool` and `number_of_free_entries_in_pool_to_lower_max_size_of_merge`
>                                                          3. 3. Pause non-critical background merges: `SYSTEM STOP MERGES`
>                                                            
>                                                             4. #### Disk Space Issues
>                                                             5. 1. Identify top disk consumers: `SELECT database, table, formatReadableSize(sum(bytes_on_disk)) FROM system.parts WHERE active GROUP BY database, table ORDER BY sum(bytes_on_disk) DESC`
>                                                                2. 2. Trigger manual merge: `OPTIMIZE TABLE db.table FINAL`
>                                                                   3. 3. Drop old partitions: `ALTER TABLE db.table DROP PARTITION 'YYYY-MM'`
>                                                                      4. 4. Move data to cold storage tier
>                                                                        
>                                                                         5. #### Keeper / ZooKeeper Problems
>                                                                         6. 1. Session expiry and reconnection storms
>                                                                            2. 2. ZNode size limits for large replica queues
>                                                                               3. 3. ClickHouse Keeper migration from ZooKeeper (step-by-step runbook)
>                                                                                  4. 4. Keeper snapshot and log compaction management
>                                                                                    
>                                                                                     5. ---
>                                                                                    
>                                                                                     6. ## Disaster Recovery (DR)
>                                                                                    
>                                                                                     7. See full documentation: [docs/DR_HA.md](docs/DR_HA.md)
>
> ### Backup Strategy
>
> **clickhouse-backup** (primary tool)
> ```bash
> # Full backup to S3
> clickhouse-backup create --config /etc/clickhouse-backup/config.yml my_backup
>
> # Upload to remote storage
> clickhouse-backup upload my_backup
>
> # List available backups
> clickhouse-backup list remote
>
> # Restore from backup
> clickhouse-backup download my_backup
> clickhouse-backup restore my_backup
> ```
>
> **Backup Configuration**
> - Incremental backups using `clickhouse-backup` diff feature
> - - Scheduled backups via cron or Kubernetes CronJob
>   - - Multi-region S3 replication for offsite DR
>     - - Backup verification: automated restore tests in isolated environment
>       - - RPO targets: ≤ 1 hour (incremental), ≤ 24 hours (full)
>         - - RTO targets: < 2 hours for full cluster restore
>          
>           - ### Point-in-Time Recovery
>           - - WAL-equivalent: ClickHouse does not use WAL; use atomic incremental backups + replication
>             - - Freeze tables before backup: `ALTER TABLE db.table FREEZE PARTITION`
>               - - Detached parts recovery: restore from frozen parts directory
>                
>                 - ### Cross-Region DR
>                 - - Active-passive setup with async replication to DR region
>                   - - DNS-based failover (Route53, Cloudflare, or internal DNS with TTL ≤ 60s)
>                     - - Promote DR replica to primary: step-by-step runbook
>                       - - Data consistency validation after failover
>                        
>                         - ### Backup Monitoring
>                         - - Alert on backup job failure or missed schedule
>                           - - Track backup size growth trends
>                             - - Verify backup integrity with `clickhouse-backup check`
>                              
>                               - ---
>
> ## High Availability (HA)
>
> See full documentation: [docs/DR_HA.md](docs/DR_HA.md)
>
> ### Replication Architecture
> - `ReplicatedMergeTree` with ClickHouse Keeper (or ZooKeeper) for consensus
> - - Recommended: 3-node ClickHouse Keeper ensemble (odd quorum)
>   - - Shard topology: 2 replicas per shard minimum; 3 replicas for zero-downtime rolling upgrades
>     - - Inter-datacenter replication with `internal_replication = true`
>      
>       - ### ClickHouse Keeper Configuration
>       - ```xml
>         <keeper_server>
>           <tcp_port>9181</tcp_port>
>           <server_id>1</server_id>
>           <log_storage_path>/var/lib/clickhouse/coordination/log</log_storage_path>
>           <snapshot_storage_path>/var/lib/clickhouse/coordination/snapshots</snapshot_storage_path>
>           <coordination_settings>
>             <operation_timeout_ms>10000</operation_timeout_ms>
>             <session_timeout_ms>30000</session_timeout_ms>
>             <raft_logs_level>warning</raft_logs_level>
>           </coordination_settings>
>           <raft_configuration>
>             <server><id>1</id><hostname>keeper1</hostname><port>9234</port></server>
>             <server><id>2</id><hostname>keeper2</hostname><port>9234</port></server>
>             <server><id>3</id><hostname>keeper3</hostname><port>9234</port></server>
>           </raft_configuration>
>         </keeper_server>
>         ```
>
> ### Load Balancing
> - HAProxy configuration for native TCP (port 9000) and HTTP (port 8123) load balancing
> - - Nginx upstream configuration for HTTP interface
>   - - Health check endpoints: `/ping` and `/replicas_status`
>     - - Chproxy (ClickHouse proxy) for connection pooling, query routing, and quota enforcement
>      
>       - ### Rolling Upgrades
>       - 1. Upgrade replicas one at a time
>         2. 2. Wait for replication queue to drain: `SELECT max(absolute_delay) FROM system.replicas`
>            3. 3. Verify new version compatibility before upgrading next replica
>               4. 4. Rollback procedure: downgrade single replica and verify data consistency
>                 
>                  5. ### Failure Scenarios & Recovery
>                  6. - Single replica failure: automatic failover via ReplicatedMergeTree + reads from surviving replica
>                     - - Keeper node failure: quorum maintained with 2/3 nodes; replace failed node
>                       - - Network partition: split-brain prevention via Keeper quorum; partition heals automatically
>                         - - Full datacenter failure: promote cross-region replica; update DNS
>                          
>                           - ---
>
> ## Extensions & Integrations
>
> ### Data Ingestion
> | Integration | Description | Config Location |
> |---|---|---|
> | Kafka Engine | Native Kafka consumer | `configs/kafka/` |
> | Kinesis Engine | AWS Kinesis ingestion | `configs/kinesis/` |
> | RabbitMQ Engine | AMQP message consumer | `configs/rabbitmq/` |
> | S3Queue Engine | S3 event-driven ingestion | `configs/s3queue/` |
> | PostgreSQL Engine | Live query federation | `configs/postgresql/` |
> | MySQL Engine | Live query federation | `configs/mysql/` |
> | JDBC/ODBC Bridge | Generic RDBMS federation | `configs/jdbc/` |
> | Vector (sink) | Log & metrics pipeline | `configs/vector/` |
>
> ### Query Federation
> | Integration | Description |
> |---|---|
> | ClickHouse → Spark | JDBC connector for Spark SQL |
> | ClickHouse → dbt | dbt-clickhouse adapter |
> | ClickHouse → Superset | Apache Superset datasource |
> | ClickHouse → Grafana | Grafana datasource plugin |
> | ClickHouse → Metabase | Metabase driver |
> | ClickHouse → Tableau | Tableau connector |
>
> ### Security
> | Feature | Implementation |
> |---|---|
> | TLS/mTLS | `openssl` section in `config.xml` |
> | RBAC | Role-based access control with `GRANT`/`REVOKE` |
> | Row-level security | Row policies via `CREATE ROW POLICY` |
> | Column-level security | Column-level grants |
> | Audit logging | `system.query_log` + external SIEM integration |
> | LDAP/AD Authentication | `ldap_servers` section in `config.xml` |
> | Kerberos | GSSAPI authentication |
>
> ---
>
> ## Tools Bundled
>
> | Tool | Version | Purpose |
> |---|---|---|
> | `clickhouse-backup` | Latest | Backup & restore automation |
> | `clickhouse-keeper` | Bundled | Distributed coordination (ZK replacement) |
> | `chproxy` | Latest | ClickHouse reverse proxy & query router |
> | `clickhouse_exporter` | Latest | Prometheus metrics exporter |
> | `tabix` | Latest | Web-based SQL UI |
> | `vector` | Latest | Log & metrics pipeline |
> | `clickhouse-diagnostics` | Latest | Cluster health diagnostics |
> | `ch-go` | Latest | High-performance Go client |
> | `clickhouse-driver` (Python) | Latest | Python async client |
> | `dbt-clickhouse` | Latest | dbt adapter |
>
> ---
>
> ## Installation
>
> ### From Packages
>
> ```bash
> # Ubuntu/Debian
> apt-get install -y apt-transport-https ca-certificates curl gnupg
> curl -fsSL 'https://packages.clickhouse.com/rpm/lts/repodata/repomd.xml.key' | apt-key add -
> echo "deb https://packages.clickhouse.com/deb stable main" > /etc/apt/sources.list.d/clickhouse.list
> apt-get update
> apt-get install -y clickhouse-server clickhouse-client clickhouse-keeper
>
> # Apply MinervaDB production configuration overlay
> git clone https://github.com/MinervaDB/MinervaDB-Server.git /opt/minervadb-server
> cp /opt/minervadb-server/configs/production/config.d/*.xml /etc/clickhouse-server/config.d/
> cp /opt/minervadb-server/configs/production/users.d/*.xml /etc/clickhouse-server/users.d/
> systemctl restart clickhouse-server
> ```
>
> ### Docker
>
> ```bash
> docker run -d \
>   --name minervadb-clickhouse \
>   -p 8123:8123 -p 9000:9000 \
>   -v /opt/minervadb-server/configs/production/config.d:/etc/clickhouse-server/config.d \
>   -v /data/clickhouse:/var/lib/clickhouse \
>   clickhouse/clickhouse-server:latest
> ```
>
> ### Kubernetes (Helm)
>
> ```bash
> helm repo add minervadb https://charts.minervadb.xyz
> helm repo update
> helm install minervadb-clickhouse minervadb/minervadb-server \
>   --namespace clickhouse \
>   --create-namespace \
>   -f values-production.yaml
> ```
>
> ---
>
> ## Configuration Reference
>
> Key configuration files in this repository:
>
> ```
> configs/
> ├── production/
> │   ├── config.d/
> │   │   ├── 00-memory.xml          # Memory limits & caches
> │   │   ├── 01-storage.xml         # Disk, tiered storage, S3
> │   │   ├── 02-networking.xml      # Ports, TLS, listen addresses
> │   │   ├── 03-logging.xml         # Log levels & destinations
> │   │   ├── 04-replication.xml     # ZooKeeper/Keeper paths
> │   │   ├── 05-mergetree.xml       # MergeTree engine defaults
> │   │   └── 06-query-limits.xml    # Query complexity limits
> │   └── users.d/
> │       ├── 00-default-profile.xml # Default user restrictions
> │       ├── 01-readonly.xml        # Read-only user profile
> │       ├── 02-analytics.xml       # Analytics user profile
> │       └── 03-admin.xml           # Admin user profile
> ├── keeper/
> │   └── keeper_config.xml          # ClickHouse Keeper 3-node config
> ├── kafka/
> │   └── kafka_tables.sql           # Kafka engine DDL templates
> └── haproxy/
>     └── haproxy.cfg                # HAProxy HA config
> ```
>
> ---
>
> ## Documentation Index
>
> | Document | Description |
> |---|---|
> | [docs/PERFORMANCE.md](docs/PERFORMANCE.md) | Full performance tuning guide |
> | [docs/SCALABILITY.md](docs/SCALABILITY.md) | Horizontal & vertical scaling playbook |
> | [docs/OBSERVABILITY.md](docs/OBSERVABILITY.md) | Monitoring, metrics, alerting, and logging |
> | [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Issue runbooks and diagnostic procedures |
> | [docs/DR_HA.md](docs/DR_HA.md) | Disaster recovery and high availability |
> | [docs/SECURITY.md](docs/SECURITY.md) | Security hardening and RBAC |
> | [docs/UPGRADE.md](docs/UPGRADE.md) | Rolling upgrade and version migration guide |
> | [docs/CAPACITY_PLANNING.md](docs/CAPACITY_PLANNING.md) | Hardware and storage sizing |
> | [docs/QUERY_OPTIMIZATION.md](docs/QUERY_OPTIMIZATION.md) | SQL and schema optimization patterns |
> | [docs/KAFKA_INTEGRATION.md](docs/KAFKA_INTEGRATION.md) | Streaming ingestion with Kafka |
> | [docs/KUBERNETES.md](docs/KUBERNETES.md) | Cloud-native deployment guide |
> | [docs/BACKUP_RESTORE.md](docs/BACKUP_RESTORE.md) | Backup procedures and restore runbooks |
> | [CONTRIBUTING.md](CONTRIBUTING.md) | How to contribute to MinervaDB Server |
>
> ---
>
> ## Contributing
>
> We welcome contributions from the community! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on:
> - Reporting bugs and requesting features
> - - Submitting pull requests
>   - - Documentation standards
>     - - Code review process
>      
>       - ---
>
> ## License
>
> MinervaDB Server for ClickHouse is licensed under the [Apache License 2.0](LICENSE), the same license as the upstream ClickHouse project.
>
> ---
>
> ## About MinervaDB
>
> [MinervaDB](https://minervadb.xyz) is a database infrastructure company specializing in open-source database systems engineering, consulting, and managed services. MinervaDB Server for ClickHouse is our enterprise distribution for production ClickHouse deployments.
>
> - Website: https://minervadb.xyz
> - - GitHub: https://github.com/MinervaDB
>   - - LinkedIn: https://linkedin.com/company/minervadb
