#!/usr/bin/env bash
# MinervaDB Server: diagnostics.sh
# Deep-dive ClickHouse diagnostics for troubleshooting
set -euo pipefail

CH_HOST="${CH_HOST:-localhost}"
CH_PORT="${CH_PORT:-9000}"
CH_USER="${CH_USER:-minervadb_admin}"
CH_PASSWORD="${CH_PASSWORD:-}"
OUTPUT_DIR="/tmp/minervadb-diag-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTPUT_DIR"

log() { echo "[$(date)] $1"; }

ch_query() {
    clickhouse-client --host="$CH_HOST" --port="$CH_PORT" \
        --user="$CH_USER" --password="$CH_PASSWORD" --query="$1"
}

log "MinervaDB Diagnostics starting. Output: $OUTPUT_DIR"

log "Collecting server information..."
ch_query "SELECT * FROM system.build_options FORMAT PrettyCompact" > "${OUTPUT_DIR}/build_options.txt"
ch_query "SELECT * FROM system.settings WHERE changed = 1 FORMAT PrettyCompact" > "${OUTPUT_DIR}/changed_settings.txt"
ch_query "SELECT * FROM system.merge_tree_settings WHERE changed = 1 FORMAT PrettyCompact" > "${OUTPUT_DIR}/mergetree_settings.txt"

log "Collecting storage information..."
ch_query "SELECT name, path, formatReadableSize(free_space) AS free, formatReadableSize(total_space) AS total FROM system.disks FORMAT PrettyCompact" > "${OUTPUT_DIR}/disks.txt"
ch_query "SELECT database, name, engine, formatReadableSize(total_bytes) AS size, total_rows FROM system.tables WHERE engine LIKE \"Merge%\" ORDER BY total_bytes DESC LIMIT 50 FORMAT PrettyCompact" > "${OUTPUT_DIR}/top_tables.txt"

log "Collecting replication status..."
ch_query "SELECT database, table, is_leader, is_readonly, absolute_delay, queue_size, last_exception FROM system.replicas FORMAT PrettyCompact" > "${OUTPUT_DIR}/replicas.txt"
ch_query "SELECT * FROM system.replication_queue LIMIT 100 FORMAT PrettyCompact" > "${OUTPUT_DIR}/replication_queue.txt"

log "Collecting query analysis..."
ch_query "SELECT query_id, user, elapsed, formatReadableSize(memory_usage) AS mem, query FROM system.processes ORDER BY elapsed DESC FORMAT PrettyCompact" > "${OUTPUT_DIR}/active_queries.txt"
ch_query "SELECT user, query_kind, count(), avg(query_duration_ms)/1000 AS avg_sec, formatReadableSize(avg(memory_usage)) AS avg_mem FROM system.query_log WHERE event_time > now() - INTERVAL 1 HOUR AND type = 2 GROUP BY user, query_kind ORDER BY avg_sec DESC LIMIT 30 FORMAT PrettyCompact" > "${OUTPUT_DIR}/query_stats_1h.txt"

log "Collecting merge and mutation status..."
ch_query "SELECT * FROM system.merges FORMAT PrettyCompact" > "${OUTPUT_DIR}/merges.txt"
ch_query "SELECT * FROM system.mutations WHERE is_done = 0 FORMAT PrettyCompact" > "${OUTPUT_DIR}/pending_mutations.txt"

log "Collecting system metrics..."
ch_query "SELECT metric, value, description FROM system.metrics ORDER BY metric FORMAT PrettyCompact" > "${OUTPUT_DIR}/metrics.txt"
ch_query "SELECT event, value, description FROM system.events ORDER BY event FORMAT PrettyCompact" > "${OUTPUT_DIR}/events.txt"

log "Collecting OS metrics..."
free -h > "${OUTPUT_DIR}/memory.txt" 2>&1 || true
df -h > "${OUTPUT_DIR}/df.txt" 2>&1 || true
uptime > "${OUTPUT_DIR}/uptime.txt" 2>&1 || true

TARBALL="${OUTPUT_DIR}.tar.gz"
tar -czf "$TARBALL" -C "$(dirname $OUTPUT_DIR)" "$(basename $OUTPUT_DIR)"
rm -rf "$OUTPUT_DIR"
log "Diagnostics complete. Archive: ${TARBALL}"
echo "Share ${TARBALL} with MinervaDB support"
