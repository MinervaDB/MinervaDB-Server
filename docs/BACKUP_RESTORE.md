# MinervaDB Server Backup & Restore

## Backup Strategies

**Native BACKUP Command (Recommended)**: Uses ClickHouse built-in BACKUP/RESTORE with support for incremental backups, S3/GCS/Azure destinations, and consistent snapshots. Minimal query impact.

**Filesystem Snapshots**: LVM/ZFS/EBS snapshots of `/var/lib/clickhouse`. Fast for large datasets but requires storage layer support.

**clickhouse-backup tool**: Open source by Altinity. Supports S3, GCS, Azure. Good for older ClickHouse versions.

## Using scripts/backup.sh

```bash
# Local backup
BACKUP_DEST=/mnt/backup/clickhouse ./scripts/backup.sh

# S3 backup
S3_BUCKET=s3://my-bucket/clickhouse \
  AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE \
  AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI \
  ./scripts/backup.sh
```

## Native BACKUP Examples

```sql
-- Full backup to S3
BACKUP ALL DATABASES EXCEPT system
    TO S3("s3://my-bucket/backups/full_20240101", "ACCESS_KEY", "SECRET_KEY");

-- Incremental backup
BACKUP ALL DATABASES EXCEPT system
    TO S3("s3://my-bucket/backups/incr_20240102", "ACCESS_KEY", "SECRET_KEY")
    SETTINGS base_backup = S3("s3://my-bucket/backups/full_20240101", "ACCESS_KEY", "SECRET_KEY");

-- Single table backup
BACKUP TABLE mydb.events TO File("/mnt/backup/events_backup");
```

## Restore Procedures

```sql
-- Restore all databases from S3
RESTORE ALL DATABASES EXCEPT system
    FROM S3("s3://my-bucket/backups/full_20240101", "ACCESS_KEY", "SECRET_KEY");

-- Restore single table
RESTORE TABLE mydb.events
    FROM File("/mnt/backup/events_backup")
    SETTINGS allow_non_empty_tables = true;
```

## Backup Verification

```sql
-- Check backup status
SELECT * FROM system.backups ORDER BY start_time DESC LIMIT 10;
```

## RPO/RTO Targets

| Method | RPO | RTO |
|--------|-----|-----|
| Native BACKUP to S3 (daily full) | 24h | 2-4h |
| Native BACKUP incremental (hourly) | 1h | 30min-1h |
| Replication (HA) | Near-zero | < 1min |
| Filesystem snapshot | Near-zero | 15-30min |
