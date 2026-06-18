# MinervaDB Server Kubernetes Deployment Guide

## Overview

MinervaDB Server can be deployed on Kubernetes using the Altinity ClickHouse Operator or the official ClickHouse Operator, which manages the full lifecycle including configuration, upgrades, and scaling.

## Installing ClickHouse Operator

```bash
kubectl apply -f https://github.com/Altinity/clickhouse-operator/raw/master/deploy/operator/clickhouse-operator-install-bundle.yaml
kubectl get pods -n kube-system | grep clickhouse
```

## ClickHouseInstallation Resource

```yaml
apiVersion: clickhouse.altinity.com/v1
kind: ClickHouseInstallation
metadata:
  name: minervadb
  namespace: minervadb
spec:
  configuration:
    clusters:
      - name: minervadb_cluster
        layout:
          shardsCount: 2
          replicasCount: 2
    zookeeper:
      nodes:
        - host: keeper1
          port: 9181
        - host: keeper2
          port: 9181
        - host: keeper3
          port: 9181
  defaults:
    templates:
      podTemplate: minervadb-pod-template
      dataVolumeClaimTemplate: minervadb-data-volume
  templates:
    podTemplates:
      - name: minervadb-pod-template
        spec:
          containers:
            - name: clickhouse
              image: clickhouse/clickhouse-server:24.3
              resources:
                requests:
                  memory: "64Gi"
                  cpu: "16"
                limits:
                  memory: "128Gi"
                  cpu: "32"
    volumeClaimTemplates:
      - name: minervadb-data-volume
        spec:
          storageClassName: fast-ssd
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 2Ti
```

## Applying MinervaDB Configurations

```bash
kubectl create configmap minervadb-config \
    --from-file=configs/production/config.d/ -n minervadb
kubectl create configmap minervadb-users \
    --from-file=configs/production/users.d/ -n minervadb
```

## Storage Considerations

Always use StorageClasses backed by NVMe SSDs with high IOPS. Avoid NFS/EFS for the primary data directory — high latency severely degrades ClickHouse performance. Use local PersistentVolumes with `volumeBindingMode: WaitForFirstConsumer` for best performance.

## Health Checks

```yaml
livenessProbe:
  httpGet:
    path: /ping
    port: 8123
  initialDelaySeconds: 60
  periodSeconds: 30
readinessProbe:
  httpGet:
    path: /replicas_status
    port: 8123
  initialDelaySeconds: 10
  periodSeconds: 10
```

## Monitoring

Apply the Prometheus configuration from `monitoring/prometheus/prometheus.yml`. ClickHouse exposes metrics on port 9363 when configured with the prometheus endpoint in `configs/production/config.d/02-networking.xml`.
