# MinervaDB Server Upgrade Guide

## Overview

This guide covers zero-downtime rolling upgrades for MinervaDB Server (ClickHouse) in production.

## Pre-Upgrade Checklist

- [ ] Review the ClickHouse changelog for breaking changes
- [ ] Test the upgrade in a staging environment
- [ ] Verify replication is healthy: no errors, delay < 60s
- [ ] Verify no pending mutations: `SELECT count() FROM system.mutations WHERE is_done = 0`
- [ ] Ensure at least 20% free disk space on all nodes
- [ ] Take a full backup using `scripts/backup.sh`
- [ ] Notify stakeholders of maintenance window

## Upgrade Strategy

MinervaDB Server upgrades use a rolling strategy: upgrade one replica at a time within each shard, never taking down more than half the replicas simultaneously. This maintains read availability throughout the upgrade.

For a 2-shard x 2-replica cluster, upgrade in this order: shard1-replica2 (non-leader), shard2-replica2 (non-leader), shard1-replica1 (leader), shard2-replica1 (leader). Always upgrade non-leaders first.

Check leadership: `SELECT table, is_leader FROM system.replicas`

## Using the Upgrade Script

```bash
# Dry run to see what would happen
DRY_RUN=true ./scripts/upgrade.sh 24.3.3.102

# Perform the upgrade (run on each node individually)
CH_HOST=localhost CH_USER=minervadb_admin CH_PASSWORD=secret \
    ./scripts/upgrade.sh 24.3.3.102
```

## Manual Upgrade Steps

**Step 1**: Stop writes to the node being upgraded (remove from HAProxy).
**Step 2**: Wait for replication queue to drain: `SELECT sum(queue_size) FROM system.replicas` = 0.
**Step 3**: Upgrade packages on the node.
**Step 4**: Restart: `systemctl restart clickhouse-server`.
**Step 5**: Verify: `clickhouse-client --query "SELECT version()"`.
**Step 6**: Re-enable the node in HAProxy.
**Step 7**: Monitor replication lag before proceeding to the next node.

## Post-Upgrade Validation

```bash
./scripts/health-check.sh

# Verify version consistency across all nodes
clickhouse-client --query "SELECT hostName(), version() FROM clusterAllReplicas(minervadb_cluster, system, one)"
```

## Rollback

ClickHouse supports downgrade between patch versions within the same minor release. For major version rollbacks, restore from the pre-upgrade backup using the RESTORE command in `docs/BACKUP_RESTORE.md`.
