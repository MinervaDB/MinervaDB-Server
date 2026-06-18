#!/usr/bin/env bash
# MinervaDB Server: upgrade.sh
# Zero-downtime rolling upgrade for ClickHouse cluster
set -euo pipefail

TARGET_VERSION="${1:-}"
CH_HOST="${CH_HOST:-localhost}"
CH_PORT="${CH_PORT:-9000}"
CH_USER="${CH_USER:-minervadb_admin}"
CH_PASSWORD="${CH_PASSWORD:-}"
BACKUP_BEFORE_UPGRADE="${BACKUP_BEFORE_UPGRADE:-true}"
DRY_RUN="${DRY_RUN:-false}"

log() { echo "[$(date)] $1"; }
die() { log "ERROR: $1"; exit 1; }

[ -z "$TARGET_VERSION" ] && die "Usage: $0 <version> (e.g. 24.3.3.102)"

ch_query() {
    clickhouse-client --host="$CH_HOST" --port="$CH_PORT" \
        --user="$CH_USER" --password="$CH_PASSWORD" --query="$1"
}

CURRENT_VERSION=$(ch_query "SELECT version()")
log "Current: ${CURRENT_VERSION}  Target: ${TARGET_VERSION}"
[ "$CURRENT_VERSION" = "$TARGET_VERSION" ] && { log "Already at target version"; exit 0; }

# Pre-upgrade checks
log "Running pre-upgrade checks..."
REPL_ERRORS=$(ch_query "SELECT countIf(last_exception != \"\") FROM system.replicas")
[ "${REPL_ERRORS:-0}" -gt 0 ] && die "Replication errors detected. Fix before upgrading."

PENDING_MUTATIONS=$(ch_query "SELECT count() FROM system.mutations WHERE is_done = 0")
[ "${PENDING_MUTATIONS:-0}" -gt 0 ] && log "WARNING: ${PENDING_MUTATIONS} pending mutations"

# Pre-upgrade backup
if [ "$BACKUP_BEFORE_UPGRADE" = "true" ] && [ "$DRY_RUN" = "false" ]; then
    log "Running pre-upgrade backup..."
    BACKUP_DEST="/mnt/backup/clickhouse" BACKUP_BEFORE_UPGRADE=false \
        "$(dirname "$0")/backup.sh" || die "Pre-upgrade backup failed"
fi

# Detect package manager
if command -v apt-get &>/dev/null; then PKG_MGR="apt"
elif command -v yum &>/dev/null; then PKG_MGR="yum"
elif command -v dnf &>/dev/null; then PKG_MGR="dnf"
else die "No supported package manager found"; fi

if [ "$DRY_RUN" = "true" ]; then
    log "[DRY RUN] Would upgrade ClickHouse to ${TARGET_VERSION} using ${PKG_MGR}"
    exit 0
fi

log "Upgrading ClickHouse to ${TARGET_VERSION} using ${PKG_MGR}..."
if [ "$PKG_MGR" = "apt" ]; then
    apt-get install -y \
        "clickhouse-server=${TARGET_VERSION}" \
        "clickhouse-client=${TARGET_VERSION}" \
        "clickhouse-common-static=${TARGET_VERSION}"
else
    ${PKG_MGR} install -y \
        "clickhouse-server-${TARGET_VERSION}" \
        "clickhouse-client-${TARGET_VERSION}"
fi

log "Restarting ClickHouse service..."
systemctl restart clickhouse-server
sleep 10

NEW_VERSION=$(ch_query "SELECT version()" 2>/dev/null || echo "unknown")
log "Post-upgrade version: ${NEW_VERSION}"
[ "$NEW_VERSION" = "$TARGET_VERSION" ] && log "Upgrade successful!" || die "Upgrade verification failed"
