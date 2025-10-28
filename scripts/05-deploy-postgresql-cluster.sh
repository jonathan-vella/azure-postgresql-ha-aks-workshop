#!/bin/bash
# Script 05: Deploy PostgreSQL Cluster
# Creates Premium v2 storage class and deploys PostgreSQL HA cluster with backups

set -euo pipefail

# Source environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/../.env" ]; then
    source "${SCRIPT_DIR}/../.env"
else
    source "${SCRIPT_DIR}/../config/environment-variables.sh"
fi
source "${SCRIPT_DIR}/../.deployment-outputs"

echo "=== Deploying PostgreSQL HA Cluster ==="

# Create Premium SSD v2 storage class
echo "Creating Premium SSD v2 storage class..."
kubectl apply --context "$AKS_PRIMARY_CLUSTER_NAME" -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${STORAGECLASS_NAME}
provisioner: disk.csi.azure.com
parameters:
  skuName: PremiumV2_LRS
  cachingMode: None
  DiskIOPSReadWrite: "${DISK_IOPS}"
  DiskMBpsReadWrite: "${DISK_THROUGHPUT}"
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
EOF

# Deploy ObjectStore CRD for Barman Cloud Plugin
echo "Creating ObjectStore resource for backup configuration..."
kubectl apply --context "$AKS_PRIMARY_CLUSTER_NAME" -n "$PG_NAMESPACE" -f - <<EOF
apiVersion: barmancloud.cnpg.io/v1
kind: ObjectStore
metadata:
  name: azure-backup-store
  namespace: ${PG_NAMESPACE}
spec:
  configuration:
    destinationPath: https://${PG_PRIMARY_STORAGE_ACCOUNT_NAME}.blob.core.windows.net/${PG_STORAGE_BACKUP_CONTAINER_NAME}/
    azureCredentials:
      inheritFromAzureAD: true
    wal:
      compression: gzip
      maxParallel: 4
    data:
      compression: gzip
      immediateCheckpoint: true
      jobs: 4
  retentionPolicy: "7d"
EOF

# Create PostgreSQL cluster manifest
echo "Creating PostgreSQL cluster: $PG_PRIMARY_CLUSTER_NAME"
kubectl apply --context "$AKS_PRIMARY_CLUSTER_NAME" -n "$PG_NAMESPACE" -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: ${PG_PRIMARY_CLUSTER_NAME}
  namespace: ${PG_NAMESPACE}
spec:
  instances: 3
  
  # Inherited metadata applies labels to all pods and services
  inheritedMetadata:
    labels:
      azure.workload.identity/use: "true"
  
  primaryUpdateStrategy: unsupervised
  
  # Failover optimization for <10s failover time (currently 30-60s)
  # These settings reduce detection time and speed up automatic failover
  failoverDelay: 5                               # Seconds before triggering failover (from 30s default)
  startDelay: 5                                  # Seconds before starting instance (from 30s default)
  stopDelay: 5                                   # Seconds before stopping instance (from 30s default)
  switchoverDelay: 5                             # Seconds before switchover (from 40000000s default)
  
  # Faster health checks for quick failure detection
  livenessProbeTimeout: 3                        # Liveness probe timeout in seconds (from 30s)
  readinessProbeTimeout: 3                       # Readiness probe timeout in seconds (from 30s)
  
  smartShutdownTimeout: 10                       # Fast shutdown timeout (from 180s)
  
  postgresql:
    parameters:
      # Connection and memory settings (tuned for Standard_E8as_v6: 8 vCPU, 64 GiB RAM)
      max_connections: "500"
      shared_buffers: "16GB"                     # 25% of 64 GiB RAM (optimal for PostgreSQL)
      effective_cache_size: "48GB"               # 75% of 64 GiB RAM
      work_mem: "64MB"                           # 48GB / 500 connections / 1.5
      maintenance_work_mem: "2GB"                # 3% of RAM for maintenance operations
      
      # WAL (Write-Ahead Log) optimization for high throughput (40K IOPS disk)
      wal_buffers: "64MB"                        # -1 = auto-tune to 3% of shared_buffers
      min_wal_size: "4GB"                        # Doubled to reduce checkpoint frequency
      max_wal_size: "16GB"                       # 4x increase for sustained writes
      wal_compression: "lz4"                     # Fast compression for high TPS
      wal_writer_delay: "10ms"                   # Faster WAL writes for low latency
      wal_writer_flush_after: "8MB"              # Larger flush batches for throughput
      
      # Checkpoint tuning for performance
      checkpoint_completion_target: "0.9"        # Spread checkpoints over 90% of interval
      checkpoint_timeout: "15min"                # Longer intervals for sustained workloads
      checkpoint_flush_after: "256kB"            # Max allowed value
      
      # I/O performance tuning (Premium SSD v2: 40K IOPS, 1250 MB/s)
      random_page_cost: "1.1"                    # Optimized for Premium SSD v2
      effective_io_concurrency: "200"            # High for Premium SSD v2
      maintenance_io_concurrency: "200"          # Parallel maintenance I/O
      
      # Parallel query execution (optimized for 8 vCPUs)
      max_worker_processes: "12"                 # 1.5× vCPUs (8×1.5=12)
      max_parallel_workers_per_gather: "4"       # Half of vCPUs
      max_parallel_workers: "8"                  # Match vCPUs
      max_parallel_maintenance_workers: "4"      # Half of vCPUs
      
      # Autovacuum tuning for high-write workloads
      autovacuum_max_workers: "6"                # Increased from default 3
      autovacuum_naptime: "10s"                  # More frequent vacuum checks
      autovacuum_vacuum_cost_limit: "10000"      # Aggressive vacuum (from 200)
      autovacuum_vacuum_scale_factor: "0.05"     # Vacuum at 5% dead tuples (from 20%)
      
      # Statistics and query planner
      default_statistics_target: "100"
      
      # Synchronous replication tuning (RPO = 0, zero data loss)
      synchronous_commit: "remote_apply"         # Strictest - ensure replicas apply changes
      wal_receiver_timeout: "5s"                 # Fast failure detection (from 60s)
      wal_sender_timeout: "5s"                   # Fast failure detection (from 60s)
      wal_receiver_status_interval: "1s"         # Frequent status updates for fast failover
      
      # Memory and resource management
      huge_pages: "off"
    
    # Synchronous replication for RPO = 0 (zero data loss)
    # With method=any and number=1, at least 1 replica must acknowledge commits
    # dataDurability defaults to "required" - blocks writes if sync replicas unavailable
    synchronous:
      method: any
      number: 1
      maxStandbyNamesFromCluster: 1
  
  bootstrap:
    initdb:
      database: ${PG_DATABASE_NAME}
      owner: ${PG_DATABASE_USER}
      secret:
        name: pg-superuser-secret
  
  storage:
    storageClass: ${STORAGECLASS_NAME}
    size: ${PG_STORAGE_SIZE}
  
  resources:
    requests:
      memory: "${PG_MEMORY}"
      cpu: "${PG_CPU}"
    limits:
      memory: "${PG_MEMORY}"
  
  affinity:
    topologyKey: topology.kubernetes.io/zone
    nodeSelector:
      workload: postgres
    # Pod anti-affinity: guarantee no two PostgreSQL pods on same node (eliminate SPOF)
    podAntiAffinityType: required
    additionalPodAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
          - key: cnpg.io/cluster
            operator: In
            values:
            - ${PG_PRIMARY_CLUSTER_NAME}
        topologyKey: kubernetes.io/hostname
  
  serviceAccountTemplate:
    metadata:
      annotations:
        azure.workload.identity/client-id: ${AKS_UAMI_WORKLOAD_CLIENTID}
      labels:
        azure.workload.identity/use: "true"
  
  # Backup configuration using Barman Cloud Plugin
  plugins:
  - name: barman-cloud.cloudnative-pg.io
    isWALArchiver: true
    parameters:
      barmanObjectName: azure-backup-store
  
  # PgBouncer connection pooler for high-concurrency workloads
  # Native CNPG pooler (not sidecar) - deployed as separate service
  managed:
    roles:
    - name: app
      ensure: present
      login: true
      passwordSecret:
        name: pg-app-secret
    - name: pooler
      ensure: present
      login: true
      passwordSecret:
        name: pg-pooler-secret
  
  pooler:
    instances: 3                                 # HA deployment across zones
    type: rw                                     # Read-write connections only
    pgbouncer:
      poolMode: transaction                      # Transaction pooling for max efficiency
      parameters:
        max_client_conn: "10000"                 # Support 10K concurrent client connections
        default_pool_size: "25"                  # Pool size per user/database (25 × 500 max_connections)
        reserve_pool_size: "5"                   # Reserve connections for critical queries
        reserve_pool_timeout: "3"                # Seconds to wait for reserve connection
        max_db_connections: "500"                # Match PostgreSQL max_connections
        max_user_connections: "500"              # Match PostgreSQL max_connections
        server_idle_timeout: "600"               # Close idle server connections after 10 min
        server_lifetime: "3600"                  # Recycle connections after 1 hour
        server_connect_timeout: "5"              # Fast connection timeout
        query_timeout: "0"                       # No query timeout (app manages this)
        query_wait_timeout: "120"                # Wait for connection from pool
        client_idle_timeout: "0"                 # No client timeout (app manages this)
        idle_transaction_timeout: "0"            # No idle transaction timeout
        log_connections: "0"                     # Disable connection logging (performance)
        log_disconnections: "0"                  # Disable disconnection logging
        log_pooler_errors: "1"                   # Log pooler errors only
        stats_period: "60"                       # Stats reporting interval
        ignore_startup_parameters: "extra_float_digits"
    resources:
      requests:
        cpu: "1"
        memory: "2Gi"
      limits:
        memory: "4Gi"
    monitoring:
      enablePodMonitor: true
    # Pod anti-affinity: guarantee no two pooler pods on same node (eliminate SPOF)
    podTemplate:
      spec:
        affinity:
          podAntiAffinity:
            requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchLabels:
                  cnpg.io/poolerName: ${PG_PRIMARY_CLUSTER_NAME}
              topologyKey: "kubernetes.io/hostname"
---
apiVersion: v1
kind: Secret
metadata:
  name: pg-app-secret
  namespace: ${PG_NAMESPACE}
type: kubernetes.io/basic-auth
stringData:
  username: app
  password: ${PG_DATABASE_PASSWORD}
---
apiVersion: v1
kind: Secret
metadata:
  name: pg-pooler-secret
  namespace: ${PG_NAMESPACE}
type: kubernetes.io/basic-auth
stringData:
  username: pooler
  password: ${PG_DATABASE_PASSWORD}
---
apiVersion: v1
kind: Secret
metadata:
  name: pg-superuser-secret
  namespace: ${PG_NAMESPACE}
type: kubernetes.io/basic-auth
stringData:
  username: ${PG_DATABASE_USER}
  password: ${PG_DATABASE_PASSWORD}
EOF

# Wait for cluster to be ready
echo "Waiting for PostgreSQL cluster to be ready (this may take 5-10 minutes)..."
kubectl wait --for=condition=Ready \
    --timeout=600s \
    --context "$AKS_PRIMARY_CLUSTER_NAME" \
    -n "$PG_NAMESPACE" \
    cluster/"$PG_PRIMARY_CLUSTER_NAME"

# Deploy PodMonitor for Prometheus metrics collection
echo "Deploying PodMonitor for cluster monitoring..."
kubectl apply --context "$AKS_PRIMARY_CLUSTER_NAME" -n "$PG_NAMESPACE" -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: ${PG_PRIMARY_CLUSTER_NAME}
  namespace: ${PG_NAMESPACE}
spec:
  selector:
    matchLabels:
      cnpg.io/cluster: ${PG_PRIMARY_CLUSTER_NAME}
  podMetricsEndpoints:
  - port: metrics
EOF

# Get cluster status
echo "PostgreSQL cluster status:"
kubectl cnpg status "$PG_PRIMARY_CLUSTER_NAME" -n "$PG_NAMESPACE" --context "$AKS_PRIMARY_CLUSTER_NAME"

# Get services (CNPG creates these automatically)
echo ""
echo "PostgreSQL Services:"
kubectl get svc -n "$PG_NAMESPACE" --context "$AKS_PRIMARY_CLUSTER_NAME" | grep "$PG_PRIMARY_CLUSTER_NAME"

echo "✓ PostgreSQL HA cluster deployed successfully!"
