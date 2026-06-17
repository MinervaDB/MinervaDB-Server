# Troubleshooting Guide — MinervaDB Server for ClickHouse

Runbooks and diagnostic procedures for common ClickHouse operational issues.

---

## Quick Diagnostic Commands

```bash
# Health check script
CH="clickhouse-client -q"

# Active queries > 5s
$CH "SELECT query_id,user,elapsed,formatReadableSize(memory_usage) FROM system.processes WHERE elapsed>5 ORDER BY elapsed DESC"

# Replication lag
$CH "SELECT database,table,is_readonly,absolute_delay,queue_size FROM system.replicas WHERE absolute_delay>0 OR is_readonly=1"

# Disk usage
$CH "SELECT name,formatReadableSize(free_space),formatReadableSize(total_space),round((1-free_space/total_space)*100,1) AS used_pct FROM system.disks"

# Recent errors
$CH "SELECT event_time,user,exception_code,left(exception,150) FROM system.query_log WHERE type IN ('ExceptionBeforeStart','ExceptionWhileProcessing') AND event_time >= now()-INTERVAL 1 HOUR ORDER BY event_time DESC LIMIT 20"
```

---

## 1. High Memory Usage

**Symptoms:** OOM kills, "Memory limit exceeded" errors, server unresponsive

**Diagnose:**
```sql
-- Top memory consumers
SELECT query_id, user, formatReadableSize(memory_usage) AS mem, elapsed, left(query,100)
FROM system.processes ORDER BY memory_usage DESC;

-- Recent high-memory queries
SELECT normalizeQuery(query), count(), formatReadableSize(max(memory_usage)) AS peak
FROM system.query_log
WHERE type='QueryFinish' AND event_time >= now()-INTERVAL 1 HOUR
GROUP BY normalizeQuery(query) ORDER BY max(memory_usage) DESC LIMIT 10;
```

**Fix:**
```sql
KILL QUERY WHERE memory_usage > 20*1024*1024*1024;
SYSTEM DROP MARK CACHE;
SYSTEM DROP UNCOMPRESSED CACHE;
```

**Prevent:**
```xml
<profiles><default>
  <max_memory_usage>10737418240</max_memory_usage>
    <max_bytes_before_external_group_by>5368709120</max_bytes_before_external_group_by>
    </default></profiles>
    ```

    ---

    ## 2. Slow Queries

    **Diagnose:**
    ```sql
    -- Slow query analysis
    SELECT query_id, round(query_duration_ms/1000,2) AS sec,
           formatReadableSize(read_bytes) AS read_size,
                  normalizeQuery(query)
                  FROM system.query_log
                  WHERE type='QueryFinish' AND query_duration_ms>10000 AND event_time>=now()-INTERVAL 1 HOUR
                  ORDER BY query_duration_ms DESC LIMIT 20;

                  -- Check query plan
                  EXPLAIN indexes=1 SELECT ...your_query...;

                  -- Profile I/O
                  SELECT ProfileEvents['SelectedMarks'] AS marks_read,
                         ProfileEvents['SelectedRows'] AS rows_read,
                                ProfileEvents['RealTimeMicroseconds']/1000 AS wall_ms
                                FROM system.query_log WHERE query_id='your-query-id' AND type='QueryFinish';
                                ```

                                **Common Fixes:**
                                - Full scan → add/fix primary key or add projection
                                - Cross-shard IN → use `GLOBAL IN`  
                                - Missing partition pruning → include partition key in WHERE clause
                                - No skipping index → add bloom_filter or minmax index

                                ---

                                ## 3. Replication Issues

                                **Diagnose:**
                                ```sql
                                -- Replica status overview
                                SELECT database, table, is_leader, is_readonly, is_session_expired,
                                       absolute_delay, queue_size, inserts_in_queue, merges_in_queue
                                       FROM system.replicas ORDER BY absolute_delay DESC;

                                       -- Replication queue errors
                                       SELECT database, table, type, num_tries, last_exception, create_time
                                       FROM system.replication_queue WHERE last_exception != '' ORDER BY num_tries DESC LIMIT 20;
                                       ```

                                       **Fix:**
                                       ```sql
                                       -- Force sync
                                       SYSTEM SYNC REPLICA database.table;

                                       -- Restart stuck replica
                                       SYSTEM RESTART REPLICA database.table;

                                       -- Drop bad detached part (last resort)
                                       ALTER TABLE database.table DROP DETACHED PART 'part_name';
                                       ```

                                       **Keeper/ZooKeeper check:**
                                       ```bash
                                       echo "stat" | nc keeper-1 9181
                                       echo "ruok" | nc keeper-1 9181  # should return: imok
                                       ```

                                       ---

                                       ## 4. Too Many Parts

                                       **Error:** `DB::Exception: Too many parts (N)`

                                       **Diagnose:**
                                       ```sql
                                       SELECT database, table, count() AS parts
                                       FROM system.parts WHERE active=1
                                       GROUP BY database, table HAVING parts > 200 ORDER BY parts DESC;
                                       ```

                                       **Fix:**
                                       ```sql
                                       SYSTEM STOP INSERTS database.table;
                                       OPTIMIZE TABLE database.table PARTITION 'partition_id' FINAL;
                                       SYSTEM START INSERTS database.table;
                                       ```

                                       **Config fix:**
                                       ```xml
                                       <merge_tree>
                                         <parts_to_delay_insert>500</parts_to_delay_insert>
                                           <parts_to_throw_insert>1000</parts_to_throw_insert>
                                             <background_pool_size>32</background_pool_size>
                                             </merge_tree>
                                             ```

                                             ---

                                             ## 5. Insert Failures

                                             **Diagnose:**
                                             ```sql
                                             SELECT event_time, database, table, part_name, exception
                                             FROM system.part_log WHERE event_type='NewPart' AND exception!=''
                                               AND event_time >= now()-INTERVAL 1 HOUR ORDER BY event_time DESC;
                                               ```

                                               **Common causes and fixes:**
                                               - Too many parts → see section 4
                                               - No disk space → drop old partitions: `ALTER TABLE t DROP PARTITION 'old'`
                                               - Schema mismatch (Kafka) → drop and recreate Kafka engine table
                                               - Quota exceeded → check user quotas: `SELECT * FROM system.quotas_usage`

                                               ---

                                               ## 6. Disk Space Emergency

                                               ```sql
                                               -- Largest tables
                                               SELECT database, table, formatReadableSize(sum(bytes_on_disk)) AS size
                                               FROM system.parts WHERE active=1 GROUP BY database, table ORDER BY sum(bytes_on_disk) DESC LIMIT 10;

                                               -- Largest partitions
                                               SELECT database, table, partition, formatReadableSize(sum(bytes_on_disk)) AS size
                                               FROM system.parts WHERE active=1 GROUP BY database,table,partition ORDER BY sum(bytes_on_disk) DESC LIMIT 20;

                                               -- Detached parts wasting space
                                               SELECT database, table, formatReadableSize(sum(bytes_on_disk))
                                               FROM system.detached_parts GROUP BY database, table ORDER BY sum(bytes_on_disk) DESC;
                                               ```

                                               **Recovery:**
                                               ```sql
                                               -- Drop old partitions
                                               ALTER TABLE db.table DROP PARTITION '2023-01';

                                               -- Move to cold tier
                                               ALTER TABLE db.table MOVE PARTITION '2023-06' TO VOLUME 'cold';

                                               -- Force merge (reduces part count)
                                               OPTIMIZE TABLE db.table PARTITION '2024-01' FINAL;
                                               ```

                                               ---

                                               ## 7. Mutation Problems

                                               **Diagnose:**
                                               ```sql
                                               SELECT database, table, mutation_id, command, parts_to_do, is_done,
                                                      latest_failed_part, latest_fail_reason
                                                      FROM system.mutations WHERE is_done=0 ORDER BY create_time;
                                                      ```

                                                      **Fix:**
                                                      ```sql
                                                      -- Kill stuck mutation
                                                      KILL MUTATION WHERE database='mydb' AND table='events' AND mutation_id='mutation_123';

                                                      -- Detach problematic part
                                                      ALTER TABLE db.table DETACH PART 'bad_part';
                                                      ```

                                                      ---

                                                      ## 8. Server Crash / OOM Recovery

                                                      ```bash
                                                      # Check error logs
                                                      tail -100 /var/log/clickhouse-server/clickhouse-server.err.log

                                                      # Check OOM killer
                                                      dmesg | grep -i "out of memory\|killed process" | tail -20

                                                      # Restart and verify
                                                      systemctl restart clickhouse-server
                                                      clickhouse-client -q "SELECT version(), uptime()"
                                                      clickhouse-client -q "CHECK TABLE db.important_table"

                                                      # Check crash log
                                                      clickhouse-client -q "SELECT * FROM system.crash_log ORDER BY event_time DESC LIMIT 5"
                                                      ```

                                                      ---

                                                      ## 9. Keeper / ZooKeeper Migration

                                                      ```bash
                                                      # 1. Deploy 3-node Keeper ensemble
                                                      # 2. Start all Keeper nodes and verify quorum
                                                      echo "ruok" | nc keeper-1 9181   # imok
                                                      echo "isro" | nc keeper-1 9181   # rw or ro

                                                      # 3. Migrate data (if replacing ZooKeeper)
                                                      clickhouse-keeper-converter \
                                                        --zookeeper-logs-dir /var/lib/zookeeper/version-2/ \
                                                          --zookeeper-snapshots-dir /var/lib/zookeeper/version-2/ \
                                                            --output-dir /var/lib/clickhouse-keeper/

                                                            # 4. Update ClickHouse config and reload
                                                            clickhouse-client -q "SYSTEM RELOAD CONFIG"
                                                            ```

                                                            ---

                                                            ## 10. DDL Issues

                                                            ```sql
                                                            -- Check distributed DDL queue
                                                            SELECT host, port, status, exception_text, query
                                                            FROM system.distributed_ddl_queue WHERE status != 'Finished' ORDER BY entry_time DESC;

                                                            -- Check for long-running DDL
                                                            SELECT query_id, elapsed, left(query,200)
                                                            FROM system.processes WHERE query LIKE '%ALTER%' OR query LIKE '%CREATE%';
                                                            ```

                                                            ---

                                                            *See also:*
                                                            - [PERFORMANCE.md](PERFORMANCE.md) — Query optimization
                                                            - [OBSERVABILITY.md](OBSERVABILITY.md) — Monitoring setup
                                                            - [DR_HA.md](DR_HA.md) — Backup and recovery
                                                            - [Back to README](../README.md)
