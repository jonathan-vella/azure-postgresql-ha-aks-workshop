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
# Delete if exists (StorageClass parameters are immutable)
kubectl delete storageclass "${STORAGECLASS_NAME}" --ignore-not-found=true --context "$AKS_PRIMARY_CLUSTER_NAME"
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

# Calculate PostgreSQL memory parameters dynamically based on PG_MEMORY
echo "Calculating PostgreSQL memory parameters from PG_MEMORY=${PG_MEMORY}..."

# Extract numeric value from PG_MEMORY (e.g., "48Gi" -> 48)
PG_MEMORY_VALUE=$(echo "${PG_MEMORY}" | sed 's/[^0-9]*//g')

# Calculate shared_buffers (25% of total RAM)
SHARED_BUFFERS=$((PG_MEMORY_VALUE / 4))

# Calculate effective_cache_size (75% of total RAM)
EFFECTIVE_CACHE_SIZE=$((PG_MEMORY_VALUE * 3 / 4))

# Calculate maintenance_work_mem (3% of total RAM, max 2GB)
MAINTENANCE_WORK_MEM=$((PG_MEMORY_VALUE * 3 / 100))
if [ $MAINTENANCE_WORK_MEM -gt 2 ]; then
    MAINTENANCE_WORK_MEM=2
fi

# Calculate work_mem (shared_buffers / max_connections / 1.5)
# With max_connections=500, work_mem = shared_buffers * 1024MB / 500 / 1.5
WORK_MEM=$((SHARED_BUFFERS * 1024 / 500 * 2 / 3))

echo "  Shared Buffers:        ${SHARED_BUFFERS}GB (25% of ${PG_MEMORY})"
echo "  Effective Cache Size:  ${EFFECTIVE_CACHE_SIZE}GB (75% of ${PG_MEMORY})"
echo "  Maintenance Work Mem:  ${MAINTENANCE_WORK_MEM}GB (3% of ${PG_MEMORY})"
echo "  Work Mem:              ${WORK_MEM}MB"

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
  
  # Failover optimization for <10s failover time
  # Aggressive settings for sub-10 second automatic failover
  failoverDelay: 3                               # Reduced from 5s - faster failover trigger
  startDelay: 3                                  # Reduced from 5s - faster pod startup
  stopDelay: 3                                   # Reduced from 5s - faster pod shutdown
  switchoverDelay: 3                             # Reduced from 5s - faster planned switchover
  livenessProbeTimeout: 3                        # Liveness probe timeout (from 30s default)
  
  smartShutdownTimeout: 5                        # Reduced from 10s - faster graceful shutdown
  
  postgresql:
    parameters:
      # Phase 2 Optimization: Microsoft Azure PostgreSQL HA Guidelines
      # Documentation: https://learn.microsoft.com/en-us/azure/aks/deploy-postgresql-ha
      
      # Connection and memory settings (dynamically calculated from PG_MEMORY)
      max_connections: "500"
      shared_buffers: "${SHARED_BUFFERS}GB"          # 25% of PG_MEMORY (Microsoft: 25% node memory)
      effective_cache_size: "${EFFECTIVE_CACHE_SIZE}GB"  # 75% of PG_MEMORY (Microsoft: 75% node memory)
      work_mem: "${WORK_MEM}MB"                      # shared_buffers / max_connections / 1.5 (Microsoft: 1/256th node memory)
      maintenance_work_mem: "${MAINTENANCE_WORK_MEM}GB"  # 3% of PG_MEMORY, max 2GB (Microsoft: 6.25% node memory, max 2GB)
      
      # WAL (Write-Ahead Log) optimization - Microsoft Azure recommendations
      wal_buffers: "64MB"                        # -1 = auto-tune to 3% of shared_buffers
      min_wal_size: "4GB"                        # Microsoft: 4GB for sustained workloads
      max_wal_size: "6GB"                        # Microsoft: 6GB (optimized for checkpoints)
      wal_compression: "lz4"                     # Microsoft: lz4 (fast, efficient compression)
      wal_writer_delay: "10ms"                   # Faster WAL writes for low latency
      wal_writer_flush_after: "2MB"              # Microsoft: 2MB (balanced flush strategy)
      
      # Checkpoint tuning - Microsoft Azure recommendations
      checkpoint_completion_target: "0.9"        # Spread checkpoints over 90% of interval
      checkpoint_timeout: "15min"                # Microsoft: 15min (balanced for sustained writes)
      checkpoint_flush_after: "2MB"              # Microsoft: 2MB (effective for Premium SSD v2)
      
      # I/O performance tuning - Microsoft Azure for Premium SSD v2
      random_page_cost: "1.1"                    # Microsoft: 1.1 (optimized for Premium SSD)
      effective_io_concurrency: "64"             # Microsoft: 64 (matches Premium SSD v2 capabilities)
      maintenance_io_concurrency: "64"           # Microsoft: 64 (parallel maintenance operations)
      
      # Parallel query execution (optimized for 8 vCPUs)
      max_worker_processes: "12"                 # 1.5× vCPUs (8×1.5=12)
      max_parallel_workers_per_gather: "4"       # Half of vCPUs
      max_parallel_workers: "8"                  # Match vCPUs
      max_parallel_maintenance_workers: "4"      # Half of vCPUs
      
      # Autovacuum tuning - Microsoft Azure recommendations for high-write workloads
      autovacuum_max_workers: "6"                # Increased from default 3
      autovacuum_naptime: "10s"                  # More frequent vacuum checks
      autovacuum_vacuum_cost_limit: "2400"       # Microsoft: 2400 (balanced vacuum aggressiveness)
      autovacuum_vacuum_scale_factor: "0.05"     # Vacuum at 5% dead tuples (from 20%)
      
      # Statistics and query planner
      default_statistics_target: "100"
      
      # Synchronous replication tuning (RPO = 0, zero data loss)
      synchronous_commit: "remote_apply"         # Strictest - ensure replicas apply changes
      wal_receiver_timeout: "3s"                 # Reduced from 5s - faster failure detection
      wal_sender_timeout: "3s"                   # Reduced from 5s - faster failure detection
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
  
  # Managed roles for database access
  managed:
    roles:
    - name: app
      ensure: present
      login: true
      passwordSecret:
        name: pg-app-secret
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
  name: pg-superuser-secret
  namespace: ${PG_NAMESPACE}
type: kubernetes.io/basic-auth
stringData:
  username: ${PG_DATABASE_USER}
  password: ${PG_DATABASE_PASSWORD}
EOF

# Deploy PgBouncer Pooler separately (supported in CNPG 1.27.1)
echo ""
echo "Deploying PgBouncer Pooler for connection pooling..."
kubectl apply --context "$AKS_PRIMARY_CLUSTER_NAME" -n "$PG_NAMESPACE" -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Pooler
metadata:
  name: ${PG_PRIMARY_CLUSTER_NAME}-pooler-rw
  namespace: ${PG_NAMESPACE}
spec:
  cluster:
    name: ${PG_PRIMARY_CLUSTER_NAME}
  
  instances: 3
  type: rw
  
  pgbouncer:
    poolMode: transaction
    parameters:
      max_client_conn: "10000"
      default_pool_size: "100"           # Increased from 25 for higher throughput (Phase 5)
      reserve_pool_size: "20"            # Increased proportionally
      reserve_pool_timeout: "3"
      max_db_connections: "500"
      max_user_connections: "500"
      # Phase 4 Optimization: Reduced client load (30 vs 100) to reduce auth_query failures
      # Authentication recovery optimization - prevent cache poisoning during failover
      server_lifetime: "3600"             # 1 hour (from 120s) - reduce connection churn
      server_idle_timeout: "600"          # 10 minutes (from 60s) - keep connections alive longer
      server_login_retry: "15"            # 15 retries (from 5) - match PgBouncer default, handle all clients
      # Connection establishment and health checks
      server_connect_timeout: "10"        # 10s (from 5s) - more tolerant during failover
      server_check_delay: "10"            # Health check interval for failure detection
      server_check_query: "SELECT 1"      # Simple health check query
      # Query timeouts - balanced for application workloads
      query_timeout: "0"                  # Disable query timeout (application controls)
      query_wait_timeout: "120"           # 2 minutes (from 300s) - faster queue timeout
      client_idle_timeout: "0"            # No client timeout (application manages)
      idle_transaction_timeout: "0"       # No transaction timeout (application controls)
      # Logging for observability
      log_connections: "1"
      log_disconnections: "1"
      log_pooler_errors: "1"
      stats_period: "60"
      ignore_startup_parameters: "extra_float_digits"
  
  template:
    metadata:
      labels:
        app: pgbouncer
    spec:
      containers:
      - name: pgbouncer
        resources:
          requests:
            cpu: "1"
            memory: "2Gi"
          limits:
            memory: "4Gi"
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                cnpg.io/poolerName: ${PG_PRIMARY_CLUSTER_NAME}-pooler-rw
            topologyKey: "kubernetes.io/hostname"
EOF

# Wait for cluster to be ready
echo "Waiting for PostgreSQL cluster to be ready (this may take 5-10 minutes)..."
kubectl wait --for=condition=Ready \
    --timeout=600s \
    --context "$AKS_PRIMARY_CLUSTER_NAME" \
    -n "$PG_NAMESPACE" \
    cluster/"$PG_PRIMARY_CLUSTER_NAME"

# Note: PodMonitor not needed - Azure Monitor Managed Prometheus automatically scrapes metrics
echo "✓ Cluster ready - Azure Monitor will automatically collect metrics"

# Get cluster status
echo "PostgreSQL cluster status:"
kubectl cnpg status "$PG_PRIMARY_CLUSTER_NAME" -n "$PG_NAMESPACE" --context "$AKS_PRIMARY_CLUSTER_NAME"

# Get services (CNPG creates these automatically)
echo ""
echo "PostgreSQL Services:"
kubectl get svc -n "$PG_NAMESPACE" --context "$AKS_PRIMARY_CLUSTER_NAME" | grep "$PG_PRIMARY_CLUSTER_NAME"

echo "✓ PostgreSQL HA cluster deployed successfully!"
