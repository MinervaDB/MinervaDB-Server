#!/usr/bin/env bash
# MinervaDB Server: health-check.sh
# Comprehensive ClickHouse health check script
set -euo pipefail

CH_HOST="${CH_HOST:-localhost}"
CH_PORT="${CH_PORT:-8123}"
CH_USER="${CH_USER:-default}"
CH_PASSWORD="${CH_PASSWORD:-}"
ALERT_THRESHOLD_REPLICATION_DELAY=300
ALERT_THRESHOLD_MERGES=100

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
NC="\033[0m"
PASS=0; WARN=0; FAIL=0

log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS+1)); }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; WARN=$((WARN+1)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL+1)); }

ch_query() {
    clickhouse-client --host="$CH_HOST" --port="${CH_PORT:-9000}" \
        --user="$CH_USER" --password="$CH_PASSWORD" --query="$1" 2>/dev/null
}

echo "============================================"
echo "MinervaDB Server Health Check - $(date)"
echo "Host: ${CH_HOST}:${CH_PORT}"
echo "============================================"

# 1. Basic connectivity
if curl -sf "http://${CH_HOST}:${CH_PORT}/ping" | grep -q "Ok"; then
    log_pass "HTTP ping OK"
else
    log_fail "HTTP ping FAILED"
fi

# 2. Replication errors
REPL_ERRORS=$(ch_query "SELECT countIf(last_exception != \"\") FROM system.replicas")
if [ "${REPL_ERRORS:-0}" -eq 0 ]; then
    log_pass "Replication: no errors"
else
    log_fail "Replication: ${REPL_ERRORS} tables have errors"
fi

# 3. Replication delay
MAX_DELAY=$(ch_query "SELECT max(absolute_delay) FROM system.replicas")
if [ "${MAX_DELAY:-0}" -lt "${ALERT_THRESHOLD_REPLICATION_DELAY}" ]; then
    log_pass "Replication delay: ${MAX_DELAY}s"
else
    log_warn "Replication delay: ${MAX_DELAY}s exceeds threshold"
fi

# 4. Merge queue
MERGES=$(ch_query "SELECT count() FROM system.merges")
if [ "${MERGES:-0}" -lt "${ALERT_THRESHOLD_MERGES}" ]; then
    log_pass "Merge queue: ${MERGES} active merges"
else
    log_warn "Merge queue: ${MERGES} active merges (high)"
fi

# 5. Disk usage
DISK_FREE=$(ch_query "SELECT min(free_space) FROM system.disks WHERE name = \"default\"")
DISK_TOTAL=$(ch_query "SELECT min(total_space) FROM system.disks WHERE name = \"default\"")
if [ -n "$DISK_FREE" ] && [ "$DISK_TOTAL" -gt 0 ]; then
    PCT=$((DISK_FREE * 100 / DISK_TOTAL))
    [ "$PCT" -gt 20 ] && log_pass "Disk free: ${PCT}%" || log_warn "Disk free: ${PCT}% (low)"
fi

# 6. Active queries
ACTIVE=$(ch_query "SELECT count() FROM system.processes WHERE query NOT LIKE \"SELECT count()%\"")
log_pass "Active queries: ${ACTIVE:-0}"

echo "============================================"
echo "Results: PASS=${PASS} WARN=${WARN} FAIL=${FAIL}"
echo "============================================"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
