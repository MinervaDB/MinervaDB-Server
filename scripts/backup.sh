#!/usr/bin/env bash
# MinervaDB Server: backup.sh
# Production ClickHouse backup using native BACKUP command
set -euo pipefail

CH_HOST="${CH_HOST:-localhost}"
CH_PORT="${CH_PORT:-9000}"
CH_USER="${CH_USER:-minervadb_admin}"
CH_PASSWORD="${CH_PASSWORD:-}"
BACKUP_DEST="${BACKUP_DEST:-/mnt/backup/clickhouse}"
S3_BUCKET="${S3_BUCKET:-}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
LOG_FILE="/var/log/clickhouse/backup.log"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="minervadb_backup_${TIMESTAMP}"

log() { echo "[$(date)] $1" | tee -a "$LOG_FILE"; }
die() { log "ERROR: $1"; exit 1; }

ch_query() {
    clickhouse-client --host="$CH_HOST" --port="$CH_PORT" \
        --user="$CH_USER" --password="$CH_PASSWORD" --query="$1"
}

log "Starting MinervaDB backup: ${BACKUP_NAME}"
ch_query "SELECT 1" > /dev/null || die "Cannot connect to ClickHouse"

if [ -n "$S3_BUCKET" ]; then
    BACKUP_LOC="S3(\"${S3_BUCKET}/${BACKUP_NAME}\", \"${AWS_ACCESS_KEY_ID:-}\", \"${AWS_SECRET_ACCESS_KEY:-}\")"
    log "Backing up to S3: ${S3_BUCKET}/${BACKUP_NAME}"
else
    mkdir -p "${BACKUP_DEST}"
    BACKUP_LOC="File(\"${BACKUP_DEST}/${BACKUP_NAME}\")"
    log "Backing up to local: ${BACKUP_DEST}/${BACKUP_NAME}"
fi

log "Running BACKUP ALL DATABASES..."
ch_query "BACKUP ALL DATABASES EXCEPT system TO ${BACKUP_LOC}" || die "Backup failed"
log "Backup completed: ${BACKUP_NAME}"

# Cleanup old local backups
if [ -z "$S3_BUCKET" ] && [ -d "$BACKUP_DEST" ]; then
    log "Cleaning up backups older than ${RETENTION_DAYS} days"
    find "$BACKUP_DEST" -maxdepth 1 -name "minervadb_backup_*" \
        -mtime "+${RETENTION_DAYS}" -exec rm -rf {} \;
    log "Cleanup complete"
fi

log "Backup process finished successfully: ${BACKUP_NAME}"
