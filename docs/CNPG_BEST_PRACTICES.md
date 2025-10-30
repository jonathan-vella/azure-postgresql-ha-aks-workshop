# CloudNativePG 1.27 Best Practices for Azure PostgreSQL HA on AKS

**Version**: v1.0.0 | **CloudNativePG Version**: 1.27.1 | **Last Updated**: October 2025

This document provides comprehensive best practices for deploying and operating CloudNativePG (CNPG) 1.27 in production environments, specifically tailored for the Azure PostgreSQL HA on AKS workshop architecture.

---

## Table of Contents

1. [Operator Installation & Configuration](#1-operator-installation--configuration)
2. [High Availability & Cluster Design](#2-high-availability--cluster-design)
3. [Storage Configuration](#3-storage-configuration)
4. [Backup & Recovery Strategies](#4-backup--recovery-strategies)
5. [Disaster Recovery](#5-disaster-recovery)
6. [Replication Configuration](#6-replication-configuration)
7. [Resource Management & Performance Tuning](#7-resource-management--performance-tuning)
8. [Connection Pooling with PgBouncer](#8-connection-pooling-with-pgbouncer)
9. [Monitoring & Observability](#9-monitoring--observability)
10. [Security Hardening](#10-security-hardening)
11. [Upgrades & Maintenance](#11-upgrades--maintenance)
12. [Operational Best Practices](#12-operational-best-practices)

---

## 1. Operator Installation & Configuration

### ✅ Installation Best Practices

- **Use Official Methods**: Deploy the operator using official Helm charts, kubectl manifests, or OperatorHub for predictable and supported deployments.
- **Dedicated Namespace**: Install the operator in a dedicated namespace (typically `cnpg-system`) for isolation and easier management.
- **Resource Limits**: Set appropriate resource requests and limits for the operator pods to ensure stable operation.
- **Version Pinning**: Pin operator versions in production environments to prevent unexpected upgrades.

```yaml
# Example Helm installation
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo update
helm install cnpg --namespace cnpg-system --create-namespace \
  cloudnative-pg/cloudnative-pg --version 0.26.1
```

### 🔧 Network Configuration

- **Webhook Access**: Ensure firewall rules allow webhook traffic on port 9443 (especially on GKE and restricted environments).
- **DNS Resolution**: Verify Kubernetes DNS resolution works correctly for operator-to-pod communication.
- **Network Policies**: Implement network policies for operator namespace if using policy-based network isolation (e.g., Cilium, Calico).

### 📋 Applicable to This Project

✅ **Current Implementation**: Operator installed via Helm chart in `cnpg-system` namespace  
✅ **Script**: `scripts/04-deploy-cnpg-operator.sh`  
✅ **Version**: 0.26.1 (CNPG 1.27.1)

---

## 2. High Availability & Cluster Design

### 🏗️ Multi-Instance Architecture

- **Minimum 3 Instances**: Deploy at least three PostgreSQL instances (1 primary + 2 replicas) for quorum-based failover and high availability.
- **Quorum-Based Failover**: Use the stable quorum-based failover introduced in CNPG 1.27 for improved split-brain prevention.
- **Zone Distribution**: Schedule pods across different availability zones using Kubernetes topology constraints (`topologySpreadConstraints`).
- **Node Distribution**: Use pod anti-affinity to ensure replicas run on different physical nodes.

```yaml
# Example topology spread configuration
spec:
  instances: 3
  affinity:
    topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: topology.kubernetes.io/zone
      whenUnsatisfiable: DoNotSchedule
      labelSelector:
        matchLabels:
          cnpg.io/cluster: pg-primary
```

### ⚡ Failover Configuration

- **Primary Isolation Check**: Enable the stable primary isolation check (`spec.probes.liveness.isolationCheck`) introduced in CNPG 1.27 for enhanced failure detection.
- **Failover Timeout**: Configure appropriate failover timeouts (target: <10 seconds).
- **Switchover Strategy**: Use `switchoverDelay` to control manual vs. automatic failover timing.

### 🎯 Target RPO/RTO

- **RPO (Recovery Point Objective)**: 0 seconds with synchronous replication
- **RTO (Recovery Time Objective)**: <10 seconds with proper quorum configuration

### 📋 Applicable to This Project

✅ **Current Implementation**: 3-node cluster (1 primary + 1 sync replica + 1 async replica)  
✅ **Zone Redundancy**: Deployed across 3 Azure Availability Zones  
✅ **Target**: RPO=0, RTO<10s  
✅ **Configuration**: `scripts/05-deploy-postgresql-cluster.sh`

---

## 3. Storage Configuration

### 💾 Storage Class Selection

- **Production Storage**: Use SSD-backed storage classes for production workloads (Premium SSD v2, Premium SSD, or NVMe).
- **Access Mode**: Always use `ReadWriteOnce` (RWO) access mode for PostgreSQL PVCs.
- **Volume Expansion**: Enable `allowVolumeExpansion: true` in StorageClass for growth without downtime.
- **Reclaim Policy**: Use `Retain` reclaim policy in production to prevent accidental data loss.

### 🚀 Azure Premium SSD v2 (Recommended)

- **IOPS Configuration**: Configure IOPS based on workload (3,100-80,000 per disk).
- **Throughput**: Set throughput to match IOPS requirements (125-1,200 MB/s).
- **Sizing**: Provision sufficient storage with overhead for WAL files, backups, and growth (minimum 200 GiB recommended).
- **Regional Availability**: Verify Premium SSD v2 availability in target Azure region.

```yaml
# Example Premium SSD v2 StorageClass
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: managed-csi-premium-v2
provisioner: disk.csi.azure.com
parameters:
  skuName: PremiumV2_LRS
  diskIOPSReadWrite: "40000"
  diskMBpsReadWrite: "1250"
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Retain
```

### 📦 WAL Volume Separation

- **Dedicated WAL Storage**: Consider separate PVCs for WAL files on high-transaction workloads.
- **Tablespace Separation**: Use dedicated fast storage for temp tablespaces if needed.
- **Benchmarking**: Use `fio` for storage benchmarking before deployment.

### 📋 Applicable to This Project

✅ **Current Implementation**: Premium SSD v2 with 40K IOPS, 1,250 MB/s throughput  
✅ **Size**: 200 GiB per instance  
✅ **Benefits**: Optimized for 8-10K TPS target  
✅ **Region**: swedencentral (Premium v2 supported)

---

## 4. Backup & Recovery Strategies

### 🔄 Backup Architecture

- **Plugin-Based Backups**: Use the Barman Cloud Plugin for cloud-native backup management (transitioning to CNP-I plugin architecture).
- **Object Storage**: Store backups in durable cloud object storage (Azure Blob Storage, S3, GCS).
- **Backup Scheduling**: Configure automated scheduled backups using CronJobs or CNPG's integrated scheduling.
- **Immutable Backups**: Backup specifications are immutable after creation in CNPG 1.27 (improves consistency).

### 📅 Retention Policies

- **Minimum Retention**: Maintain at least 7 days of backups for production systems.
- **WAL Retention**: Configure WAL retention independently from base backups.
- **Legal/Compliance**: Adjust retention based on regulatory requirements (e.g., 30, 90, 365 days).
- **Testing**: Regularly test restore procedures (monthly minimum).

```yaml
# Example backup configuration
spec:
  backup:
    barmanObjectStore:
      destinationPath: "https://ACCOUNT.blob.core.windows.net/backups"
      azureCredentials:
        storageAccount:
          name: pg-backup-secret
          key: AZURE_STORAGE_ACCOUNT
        storageKey:
          name: pg-backup-secret
          key: AZURE_STORAGE_KEY
      wal:
        compression: lz4
        maxParallel: 4
      data:
        compression: lz4
        jobs: 4
```

### 🎯 Point-in-Time Recovery (PITR)

- **Continuous WAL Archiving**: Enable continuous WAL archiving for granular recovery.
- **Recovery Testing**: Schedule regular PITR drills to validate procedures.
- **Recovery Targets**: Practice recovery to specific timestamps and transaction IDs.

### ⚠️ Backup Validation

- **Automated Validation**: Implement automated backup validation using restore tests.
- **Monitoring**: Monitor backup status via metrics and logs.
- **Hibernation Prevention**: CNPG 1.27 prevents backups on hibernated clusters (avoiding inconsistent states).
- **Enhanced Status**: Use enhanced backup status commands for detailed reporting.

### 📋 Applicable to This Project

✅ **Current Implementation**: Barman Cloud Plugin v0.8.0 with Azure Blob Storage  
✅ **Retention**: 7 days configured  
✅ **WAL Compression**: lz4 enabled  
✅ **Script**: `scripts/04a-install-barman-cloud-plugin.sh`  
✅ **Authentication**: Workload Identity with federated credentials

---

## 5. Disaster Recovery

### 🌍 WAL Archiving for DR

- **Primary DR Mechanism**: WAL archiving is essential for disaster recovery and PITR.
- **Single Plugin**: Only one WAL archiving plugin can be active per cluster.
- **Compression**: Always enable compression (lz4, gzip) to reduce storage costs and transfer time.
- **Parallel Upload**: Configure parallel WAL upload for high-transaction workloads.

### 📸 Volume Snapshots

- **Fast Recovery**: Kubernetes Volume Snapshots provide rapid base backup for large databases.
- **CSI Driver Support**: Requires CSI-compliant storage driver with snapshot support.
- **Hybrid Strategy**: Combine volume snapshots (base backup) with WAL archives (PITR).
- **VLDB Optimization**: Volume snapshots are optimal for Very Large Database (VLDB) scenarios.

```yaml
# Example volume snapshot configuration
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: pg-primary-snapshot
spec:
  volumeSnapshotClassName: csi-azuredisk-vsc
  source:
    persistentVolumeClaimName: pg-primary-1
```

### 🔧 Bootstrap Recovery

- **New Cluster Pattern**: Always recover by bootstrapping a new cluster (never in-place).
- **Recovery Targets**: Specify recovery timestamp, transaction ID, or "latest".
- **Source Configuration**: Define recovery source (object store or volume snapshot) in bootstrap stanza.

```yaml
# Example recovery bootstrap
spec:
  bootstrap:
    recovery:
      source: pg-primary-backup
      recoveryTarget:
        targetTime: "2025-10-30 12:00:00"
  externalClusters:
  - name: pg-primary-backup
    barmanObjectStore:
      destinationPath: "https://ACCOUNT.blob.core.windows.net/backups"
      azureCredentials:
        # credentials
```

### 📋 Applicable to This Project

✅ **Current Implementation**: WAL archiving to Azure Blob Storage with lz4 compression  
✅ **Parallel Upload**: Configured for optimal performance  
✅ **Volume Snapshots**: Available via Azure Disk CSI Driver  
✅ **Hybrid Approach**: Volume snapshots + WAL archives supported

---

## 6. Replication Configuration

### 🔄 Synchronous Replication

- **Data Durability**: Use synchronous replication for zero data loss (RPO=0).
- **Quorum Configuration**: Configure `minSyncReplicas` and `maxSyncReplicas` for flexible quorum.
- **Performance Trade-off**: Synchronous replication may reduce write performance; balance based on requirements.
- **Network Requirements**: Ensure low-latency, reliable network between primary and sync replicas.

```yaml
# Example synchronous replication configuration
spec:
  postgresql:
    synchronous:
      method: quorum
      number: 1
      minSyncReplicas: 1
      maxSyncReplicas: 2
```

### ⚡ Asynchronous Replication

- **Better Write Performance**: Asynchronous replication provides lower write latency.
- **Acceptable Data Loss**: Accept potential transaction loss during failover (RPO > 0).
- **Mixed Configuration**: Use 1 sync replica + additional async replicas for balance.

### 🔌 Replication Slots

- **Physical Failover Slots**: Enable physical replication slots for self-healing and failover resilience.
- **Automatic Management**: CNPG manages replication slots automatically.
- **WAL Retention**: Replication slots prevent premature WAL removal for disconnected replicas.

### 📋 Applicable to This Project

✅ **Current Implementation**: 1 quorum sync replica + 1 async replica  
✅ **RPO**: 0 seconds (synchronous replication with remote_apply)  
✅ **Configuration**: Quorum-based synchronous replication enabled  
✅ **Replication Slots**: Automatically managed by CNPG

---

## 7. Resource Management & Performance Tuning

### 💪 Resource Allocation

- **Guaranteed QoS**: Set resource requests and limits to the same values for "Guaranteed" QoS.
- **Memory Sizing**: Allocate 75% of node memory to PostgreSQL (leave 25% for OS and Kubernetes).
- **CPU Allocation**: Similarly, allocate 75% of vCPUs to PostgreSQL.
- **Pod Eviction Prevention**: Guaranteed QoS prevents pod eviction under node pressure.

```yaml
# Example resource configuration
spec:
  resources:
    requests:
      memory: "48Gi"  # 75% of 64 GiB on E8as_v6
      cpu: "6"        # 75% of 8 vCPUs on E8as_v6
    limits:
      memory: "48Gi"
      cpu: "6"
```

### 🎛️ PostgreSQL Parameter Tuning

**Priority Levels:**
- **P0 (Critical)**: Must be configured for production; significant impact on stability and performance
- **P1 (High)**: Strongly recommended; improves performance and reliability
- **P2 (Medium)**: Fine-tuning parameters; beneficial but not essential
- **P3 (Low)**: Advanced optimization; workload-specific tuning

---

### 📊 P0 - Critical Parameters (Must Configure)

#### 1. **shared_buffers** (P0 - Memory)
- **Purpose**: PostgreSQL's main data cache; reduces disk I/O
- **Recommended**: 25% of allocated memory (up to 40% max)
- **Formula**: `shared_buffers = allocated_memory * 0.25`
- **Example**: 12 GiB for 48 GiB pod (25%)
- **Context**: Too low = excessive disk reads; too high = OS memory contention
- **This Project**: `12GB` for 48 GiB pods on E8as_v6 instances

```yaml
shared_buffers: "12GB"  # 25% of 48 GiB
```

#### 2. **max_connections** (P0 - Connections)
- **Purpose**: Maximum concurrent database connections
- **Recommended**: 100-300 for most applications; use connection pooling beyond this
- **Formula**: Set based on application concurrency needs
- **Example**: 200 for web applications with PgBouncer pooling
- **Context**: Each connection consumes memory; avoid over-provisioning
- **This Project**: `200` with PgBouncer handling 10K+ client connections

```yaml
max_connections: "200"
```

#### 3. **effective_cache_size** (P0 - Planner)
- **Purpose**: Hints query planner about available cache (shared_buffers + OS cache)
- **Recommended**: 50-75% of total RAM
- **Formula**: `effective_cache_size = total_memory * 0.70`
- **Example**: 36 GiB for 48 GiB allocated memory (75%)
- **Context**: Influences planner decisions on index vs sequential scans; not actual memory allocation
- **This Project**: `36GB` for 48 GiB pods

```yaml
effective_cache_size: "36GB"  # 75% of 48 GiB
```

---

### 🔥 P1 - High Priority Parameters (Strongly Recommended)

#### 4. **work_mem** (P1 - Query Memory)
- **Purpose**: Memory per query operation (sorts, hash joins, etc.)
- **Recommended**: 4-64 MB per connection; calculate based on concurrency
- **Formula**: `work_mem = (allocated_memory * 0.25) / max_connections`
- **Example**: 60 MB for 48 GiB RAM with 200 max_connections
- **Context**: Too low = disk spills (slow); too high = OOM risk (multiplies per query operation)
- **This Project**: `64MB` balanced for 8-10K TPS OLTP workload

```yaml
work_mem: "64MB"
```

#### 5. **maintenance_work_mem** (P1 - Maintenance)
- **Purpose**: Memory for VACUUM, CREATE INDEX, ALTER TABLE operations
- **Recommended**: 256 MB - 2 GiB; larger for big databases
- **Formula**: Up to 10% of allocated memory, but don't exceed pod limits
- **Example**: 2 GiB for 48 GiB pod
- **Context**: Speeds up maintenance operations; doesn't multiply per connection
- **This Project**: `2GB` for efficient maintenance on 200 GiB volumes

```yaml
maintenance_work_mem: "2GB"
```

#### 6. **max_wal_size** (P1 - WAL)
- **Purpose**: Maximum size of WAL between checkpoints
- **Recommended**: 2-8 GiB for production; higher for write-heavy workloads
- **Example**: 4 GiB for balanced OLTP workload
- **Context**: Larger values reduce checkpoint frequency but increase recovery time
- **This Project**: `4GB` for 8-10K TPS with Premium SSD v2 storage

```yaml
max_wal_size: "4GB"
```

#### 7. **checkpoint_timeout** (P1 - Checkpoints)
- **Purpose**: Maximum time between automatic checkpoints
- **Recommended**: 10-30 minutes for production
- **Example**: 15 minutes for balanced workload
- **Context**: Too frequent = performance impact; too infrequent = longer recovery
- **This Project**: `15min` balanced for HA with <10s RTO

```yaml
checkpoint_timeout: "15min"
```

#### 8. **checkpoint_completion_target** (P1 - I/O Smoothing)
- **Purpose**: Fraction of checkpoint interval to spread writes
- **Recommended**: 0.7-0.9 to smooth I/O spikes
- **Example**: 0.9 for production (spread over 90% of interval)
- **Context**: Higher values = smoother I/O, less impact on queries
- **This Project**: `0.9` for consistent performance on Premium SSD v2

```yaml
checkpoint_completion_target: "0.9"
```

---

### ⚙️ P2 - Medium Priority Parameters (Performance Tuning)

#### 9. **random_page_cost** (P2 - Planner Cost)
- **Purpose**: Relative cost of random disk access vs sequential
- **Recommended**: 1.1-2.0 for SSDs; 4.0 (default) for HDDs
- **Example**: 1.1 for Premium SSD v2 (NVMe-class performance)
- **Context**: Lower values favor index scans on fast storage
- **This Project**: `1.1` optimized for Premium SSD v2 (40K IOPS)

```yaml
random_page_cost: "1.1"
```

#### 10. **effective_io_concurrency** (P2 - I/O)
- **Purpose**: Number of concurrent I/O operations
- **Recommended**: 200 for SSDs; 1-2 for HDDs
- **Example**: 200 for Premium SSD v2
- **Context**: Higher values for fast storage enable parallel I/O
- **This Project**: `200` for Premium SSD v2 with 40K IOPS

```yaml
effective_io_concurrency: "200"
```

#### 11. **wal_buffers** (P2 - WAL Performance)
- **Purpose**: Memory for WAL data before writing to disk
- **Recommended**: Auto-calculated by PostgreSQL (typically -1); 16 MB minimum
- **Example**: -1 (auto) or 16 MB for write-heavy workloads
- **Context**: Usually default is sufficient; tune only for extreme write workloads
- **This Project**: `-1` (auto-tuned)

```yaml
wal_buffers: "-1"
```

#### 12. **log_min_duration_statement** (P2 - Monitoring)
- **Purpose**: Log queries exceeding specified milliseconds
- **Recommended**: 1000 ms (1 second) for production monitoring
- **Example**: 1000 ms to identify slow queries
- **Context**: Essential for performance troubleshooting; balance logging overhead
- **This Project**: `1000` for query performance analysis

```yaml
log_min_duration_statement: "1000"
```

#### 13. **idle_in_transaction_session_timeout** (P2 - Connection Management)
- **Purpose**: Terminate idle transactions after timeout
- **Recommended**: 60000 ms (60 seconds) to prevent connection leaks
- **Example**: 60000 ms for web applications
- **Context**: Prevents blocking locks from forgotten transactions
- **This Project**: `60000` for microservices architectures

```yaml
idle_in_transaction_session_timeout: "60000"
```

---

### 🔧 P3 - Low Priority Parameters (Advanced Tuning)

#### 14. **autovacuum_max_workers** (P3 - Autovacuum)
- **Purpose**: Maximum autovacuum worker processes
- **Recommended**: 3-5 for production; higher for write-heavy workloads
- **Example**: 5 for 8-10K TPS workload
- **Context**: More workers = faster table cleanup but higher overhead
- **This Project**: `5` for high-transaction workload

```yaml
autovacuum_max_workers: "5"
```

#### 15. **autovacuum_vacuum_cost_delay** (P3 - Autovacuum Throttling)
- **Purpose**: Sleep time between autovacuum cost limit reaches
- **Recommended**: 2-20 ms; lower for less aggressive vacuuming
- **Example**: 10 ms for balanced performance
- **Context**: Lower = more aggressive vacuuming; adjust based on I/O impact
- **This Project**: `10ms` balanced for Premium SSD v2

```yaml
autovacuum_vacuum_cost_delay: "10ms"
```

#### 16. **max_worker_processes** (P3 - Parallelism)
- **Purpose**: Maximum background worker processes
- **Recommended**: Equal to or greater than CPU count
- **Example**: 8 for 6-8 vCPU instances
- **Context**: Enables parallel queries and maintenance
- **This Project**: `8` for E8as_v6 instances (8 vCPU)

```yaml
max_worker_processes: "8"
```

#### 17. **max_parallel_workers_per_gather** (P3 - Query Parallelism)
- **Purpose**: Maximum parallel workers per query node
- **Recommended**: 2-4 for OLTP; higher for analytical workloads
- **Example**: 2 for balanced OLTP/OLAP
- **Context**: Enables parallel query execution on multi-core systems
- **This Project**: `2` for OLTP-focused workload

```yaml
max_parallel_workers_per_gather: "2"
```

---

### 📋 Complete Configuration Example (This Project)

```yaml
# CloudNativePG Cluster PostgreSQL Parameters
spec:
  postgresql:
    parameters:
      # P0 - Critical Parameters
      shared_buffers: "12GB"                    # 25% of 48 GiB
      max_connections: "200"                    # With PgBouncer pooling
      effective_cache_size: "36GB"              # 75% of 48 GiB
      
      # P1 - High Priority Parameters
      work_mem: "64MB"                          # Calculated for 200 connections
      maintenance_work_mem: "2GB"               # 4% of 48 GiB
      max_wal_size: "4GB"                       # For 8-10K TPS
      checkpoint_timeout: "15min"               # Balanced for HA
      checkpoint_completion_target: "0.9"       # Smooth I/O distribution
      
      # P2 - Medium Priority Parameters
      random_page_cost: "1.1"                   # Premium SSD v2 optimized
      effective_io_concurrency: "200"           # For 40K IOPS storage
      wal_buffers: "-1"                         # Auto-tuned
      log_min_duration_statement: "1000"        # Log queries > 1s
      idle_in_transaction_session_timeout: "60000"  # 60 seconds
      
      # P3 - Advanced Tuning
      autovacuum_max_workers: "5"               # High transaction rate
      autovacuum_vacuum_cost_delay: "10ms"      # Balanced vacuuming
      max_worker_processes: "8"                 # E8as_v6 (8 vCPU)
      max_parallel_workers_per_gather: "2"      # OLTP focused
      
      # Additional production settings
      wal_compression: "lz4"                    # Reduce storage and I/O
      wal_log_hints: "on"                       # For pg_rewind
      full_page_writes: "on"                    # Data integrity (required)
      log_checkpoints: "on"                     # Checkpoint monitoring
      log_connections: "on"                     # Connection auditing
      log_disconnections: "on"                  # Connection tracking
      log_lock_waits: "on"                      # Lock contention detection
```

---

### 🎯 Parameter Calculation Formula Summary

| Parameter | Formula | This Project (48 GiB RAM) |
|-----------|---------|---------------------------|
| shared_buffers | `memory * 0.25` | 12 GB |
| effective_cache_size | `memory * 0.75` | 36 GB |
| work_mem | `(memory * 0.25) / max_connections` | 64 MB |
| maintenance_work_mem | `memory * 0.04` (up to 10%) | 2 GB |
| max_wal_size | Based on TPS and checkpoint frequency | 4 GB |
| checkpoint_timeout | Balance recovery time and I/O | 15 min |
| max_connections | Application needs (use pooling) | 200 |

---

### ⚠️ Important Configuration Notes

1. **Configuration Priority**: CNPG applies parameters in order:
   - Global defaults (operator-managed)
   - PostgreSQL version defaults
   - User-provided parameters (your YAML)
   - Fixed parameters (operator-required)

2. **No ALTER SYSTEM**: Never use `ALTER SYSTEM` or edit `postgresql.conf` directly in CNPG clusters; changes won't persist and aren't replicated.

3. **String Values**: All parameters must be specified as strings in YAML (e.g., `"200"`, not `200`).

4. **Validation**: Test parameter changes in staging before production; invalid values can prevent pod startup.

5. **Monitoring**: Always monitor the impact of parameter changes using metrics and query performance logs.

### 📊 Vertical vs. Horizontal Scaling

- **Vertical Scaling**: Increase pod resources (CPU, memory) for single-instance performance gains.
- **Horizontal Scaling**: Add replicas for read scaling and high availability.
- **Benchmarking**: Always benchmark before and after scaling changes using pgbench.

### 🔧 Maintenance Operations

- **Schedule Wisely**: Run VACUUM, REINDEX, and backups during low-load periods.
- **Monitor Resource Usage**: Watch for OOM during maintenance operations.
- **Maintenance Work Memory**: Size `maintenance_work_mem` appropriately for maintenance tasks.

### 📋 Applicable to This Project

✅ **Current Implementation**: Guaranteed QoS with 48 GiB RAM, 6 vCPU per instance  
✅ **VM SKU**: Standard_E8as_v6 (8 vCPU, 64 GiB RAM, AMD EPYC 9004)  
✅ **PostgreSQL Tuning**: Parameters auto-calculated from memory allocation  
✅ **Target Performance**: 8,000-10,000 TPS sustained

---

## 8. Connection Pooling with PgBouncer

### 🔌 Pooler Deployment

- **Native CNPG Support**: Use CNPG's Pooler CRD for native PgBouncer integration.
- **High Availability**: Deploy multiple PgBouncer instances (minimum 2-3) with anti-affinity.
- **Separate Namespace**: Poolers can be in the same namespace as the cluster.
- **Unique Naming**: Ensure Pooler names don't conflict with cluster names.

```yaml
# Example Pooler configuration
apiVersion: postgresql.cnpg.io/v1
kind: Pooler
metadata:
  name: pg-primary-pooler
  namespace: cnpg-database
spec:
  cluster:
    name: pg-primary
  instances: 3
  type: rw  # or 'ro' for read-only
  pgbouncer:
    poolMode: transaction
    parameters:
      max_client_conn: "10000"
      default_pool_size: "25"
```

### ⚙️ Pooling Modes

- **Session Pooling**: Default mode; one connection per client session (compatible with most applications).
- **Transaction Pooling**: Best for stateless applications; connection per transaction (recommended for high concurrency).
- **Statement Pooling**: Very high concurrency with stateless queries (rarely used).

### 🎯 Configuration Parameters

- **max_client_conn**: Set based on expected concurrent client connections per pod (e.g., 10,000).
- **default_pool_size**: Configure based on typical active connections per user/database (e.g., 25).
- **Pool Monitoring**: Monitor actual usage and tune to avoid over-provisioning.
- **Connection Limits**: Balance between client connections and PostgreSQL max_connections.

### 🔐 Application Integration

- **Connect via Pooler**: Applications must connect to Pooler service, not directly to PostgreSQL.
- **DNS-Based Discovery**: Use Kubernetes service DNS for connection strings.
- **Service Endpoints**:
  - Read-Write: `<pooler-name>-rw.<namespace>.svc.cluster.local`
  - Read-Only: `<pooler-name>-ro.<namespace>.svc.cluster.local`

### ✅ Use Cases for PgBouncer

- **Short-lived connections**: Applications with many short-lived connections
- **Microservices**: Microservices architectures with connection bursts
- **Serverless**: Azure Functions, AWS Lambda with connection spikes
- **High Concurrency**: Applications requiring 1K+ concurrent connections

### ⚠️ When to Avoid PgBouncer

- **Long-running queries**: Analytical workloads with long transactions
- **Admin tasks**: Database administration and schema migrations
- **Prepared statements**: Applications heavily using prepared statements (session mode required)

### 📋 Applicable to This Project

✅ **Current Implementation**: 3 PgBouncer instances with pod anti-affinity  
✅ **Pooling Mode**: Transaction mode for OLTP workloads  
✅ **Capacity**: 30,000 total client connections (10K per instance)  
✅ **Services**: Both read-write and read-only pooled services available  
✅ **Configuration**: `scripts/05-deploy-postgresql-cluster.sh`

---

## 9. Monitoring & Observability

### 📊 Prometheus Integration

- **Manual PodMonitor**: In CNPG 1.27, `monitoring.enablePodMonitor` is deprecated; manually create PodMonitor resources.
- **Metrics Port**: PostgreSQL instances expose metrics on port 9187.
- **Label Matching**: Use correct label selectors (`cnpg.io/cluster=<cluster-name>`).
- **Namespace Scoping**: Ensure PodMonitor is in the correct namespace.

```yaml
# Example PodMonitor configuration
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: pg-primary
  namespace: cnpg-database
spec:
  selector:
    matchLabels:
      cnpg.io/cluster: pg-primary
  podMetricsEndpoints:
  - port: metrics
    path: /metrics
    relabelings:
    - sourceLabels: [__meta_kubernetes_pod_name]
      targetLabel: pod
    - sourceLabels: [__meta_kubernetes_namespace]
      targetLabel: namespace
```

### 🔧 Relabeling Configuration

- **Critical**: Add manual relabeling for `namespace` and `pod` labels (CNPG 1.27 breaking change).
- **Dashboard Compatibility**: Official Grafana dashboards require these labels; configure relabeling in PodMonitor.
- **Prometheus Config**: Alternatively, configure relabeling in Prometheus scrape configs.

### 📈 Grafana Dashboards

- **Official Dashboards**: Use official CNPG dashboards from [grafana-dashboards repo](https://github.com/cloudnative-pg/grafana-dashboards).
- **Helm Deployment**: Deploy dashboards via Helm chart or OCI registry.
- **Custom Dashboards**: Create custom dashboards for application-specific metrics.

### 🎯 Key Metrics to Monitor

**PostgreSQL Metrics:**
- `pg_up`: Database health and uptime
- `pg_stat_replication_lag_bytes`: Replication lag in bytes
- `pg_database_size_bytes`: Database size growth
- `pg_stat_database_tup_inserted`: Transaction throughput
- `pg_wal_archive_status`: WAL archiving health

**PgBouncer Metrics:**
- `pgbouncer_pools_cl_active`: Active client connections
- `pgbouncer_pools_sv_active`: Active server connections
- `pgbouncer_pools_maxwait`: Connection pool wait time
- `pgbouncer_pools_cl_waiting`: Queued client connections

**Infrastructure Metrics:**
- `node_memory_MemAvailable_bytes`: Node memory availability
- `kube_pod_container_resource_limits`: Resource limit utilization

### 📝 Custom Metrics

- **SQL Queries**: Define custom PostgreSQL queries via ConfigMap or Secret.
- **Exporter Integration**: Reference custom queries in cluster spec.
- **Application Metrics**: Export application-specific metrics for comprehensive observability.

### 📋 Applicable to This Project

✅ **Current Implementation**: Prometheus Operator with manual PodMonitor  
✅ **Grafana**: Azure Managed Grafana with pre-built dashboard (9 panels)  
✅ **Metrics Collection**: PostgreSQL + PgBouncer metrics exposed  
✅ **Configuration**: `scripts/06-configure-monitoring.sh`, `scripts/06a-configure-azure-monitor-prometheus.sh`

---

## 10. Security Hardening

### 🔐 Authentication & Authorization

- **TLS/SSL Enforcement**: Enforce SSL/TLS for all client and replication connections.
- **Client Certificates**: Use client certificate authentication where possible.
- **pg_hba.conf Hardening**: Restrict connections with strict authentication rules (prefer `hostssl`).
- **Role Separation**: Use separate roles for superuser, replication, application, and read-only access.
- **Minimal Privileges**: Follow principle of least privilege for all roles.

```yaml
# Example pg_hba.conf configuration
spec:
  postgresql:
    pg_hba:
    - "hostssl all all 0.0.0.0/0 scram-sha-256"
    - "hostssl replication all 0.0.0.0/0 cert"
```

### 🔑 Secrets Management

- **Kubernetes Secrets**: Use Kubernetes secrets for credentials (never hardcode).
- **External Secrets**: Consider external secret managers (Azure Key Vault, AWS Secrets Manager).
- **Rotation**: Implement regular password rotation policies.
- **SCRAM-SHA-256**: Use SCRAM-SHA-256 for password hashing (default in modern PostgreSQL).

### 🛡️ Network Security

- **Network Policies**: Implement Kubernetes network policies to restrict traffic.
- **NSGs**: Use Azure Network Security Groups for additional network-level protection.
- **Private Endpoints**: Use private networking; avoid public exposure.
- **Ingress Control**: Restrict ingress to known sources (application namespaces, bastion hosts).

### 🏰 Workload Identity

- **Federated Credentials**: Use Azure Workload Identity for cloud resource access (no secrets in pods).
- **Managed Identities**: Leverage managed identities for storage, monitoring, and other Azure services.
- **RBAC Integration**: Combine with Azure RBAC for fine-grained access control.

### 🔍 Audit & Compliance

- **pg_audit Extension**: Enable pg_audit for comprehensive audit logging.
- **Log Retention**: Configure appropriate log retention for compliance.
- **Regular Reviews**: Regularly audit roles, privileges, and connection sources.
- **Security Scanning**: Implement container security scanning in CI/CD pipelines.

### 📋 Applicable to This Project

✅ **Current Implementation**: Workload Identity with federated credentials (no secrets in pods)  
✅ **Authentication**: SCRAM-SHA-256 password encryption  
✅ **Network**: NSGs, private networking, NAT Gateway  
✅ **RBAC**: Kubernetes + Azure RBAC enabled  
✅ **Encryption**: Storage encrypted at rest, TLS in transit

---

## 11. Upgrades & Maintenance

### 🔄 Minor Version Upgrades (Rolling Updates)

- **Zero Downtime**: With replicas, rolling updates provide zero-downtime minor upgrades.
- **Replica-First Strategy**: CNPG upgrades replicas first, then the primary last.
- **Unsupervised Mode**: Default automated mode; operator orchestrates entire process.
- **Supervised Mode**: Manual intervention after replicas; allows validation before primary upgrade.
- **Image Management**: Update image reference in cluster spec or use image catalog.

```yaml
# Example rolling update configuration
spec:
  imageName: ghcr.io/cloudnative-pg/postgresql:18.0
  instances: 3
  primaryUpdateStrategy: unsupervised  # or 'supervised'
```

### 🚀 Major Version Upgrades

**Option 1: Declarative In-Place Upgrade (Offline)**
- Available since CNPG 1.26
- Update image tag to trigger pg_upgrade
- Brief downtime during upgrade process
- Reproducible and streamlined

**Option 2: Logical Replication (Blue/Green, Zero Downtime)**
- Create new cluster with new PostgreSQL version
- Set up logical replication from old to new
- Cut over after synchronization
- True zero downtime for critical workloads

**Option 3: Backup & Restore**
- Backup from old version
- Bootstrap new cluster from backup
- Longer downtime; suitable for smaller databases

### 🔧 Operator Upgrades

- **Two-Phase Process**: Controller upgrade, then instance manager upgrade in pods.
- **Rolling Restart**: Default; pods restart one at a time.
- **In-Place Upgrade**: Optional via environment variable (reduces downtime but breaks immutability).
- **Version Compatibility**: Always review upgrade notes for API changes.

### 🎯 Zero Downtime Strategies

- **Minor Upgrades**: Almost always zero downtime with HA configuration (primary + replicas).
- **Major Upgrades**: Use logical replication for true zero downtime.
- **Planning**: Test upgrades in staging; measure downtime for realistic expectations.
- **Maintenance Windows**: Schedule upgrades during low-traffic periods even with zero-downtime capability.

### 📋 Applicable to This Project

✅ **Current Implementation**: Rolling update support with 3-instance HA  
✅ **Strategy**: Unsupervised rolling updates for minor versions  
✅ **Future**: Blue/green logical replication for major version upgrades  
✅ **Testing**: Always test upgrades in staging environment first

---

## 12. Operational Best Practices

### 📖 Documentation & Runbooks

- **Maintain Runbooks**: Document standard operational procedures (failover, backup restore, upgrades).
- **Disaster Recovery Plan**: Document and test DR procedures quarterly.
- **Architecture Documentation**: Keep architecture diagrams current.
- **Configuration Management**: Version control all configurations (GitOps approach).

### 🔍 Regular Health Checks

- **Cluster Status**: Regular `kubectl cnpg status` checks.
- **Replication Health**: Monitor replication lag and WAL archiving.
- **Backup Validation**: Weekly backup and restore tests.
- **Disk Space**: Monitor disk usage; set alerts at 70% and 85%.

### 📊 Capacity Planning

- **Growth Monitoring**: Track database size growth trends.
- **Performance Baselines**: Establish performance baselines with pgbench.
- **Resource Utilization**: Monitor CPU, memory, disk I/O trends.
- **Proactive Scaling**: Scale before reaching resource limits.

### 🎓 Team Training

- **CNPG Knowledge**: Ensure team understands CNPG concepts and operations.
- **PostgreSQL Expertise**: Maintain PostgreSQL DBA skills.
- **Kubernetes Skills**: Train on Kubernetes fundamentals.
- **Incident Response**: Conduct regular incident response drills.

### 🔄 Change Management

- **Change Windows**: Establish maintenance windows for planned changes.
- **Rollback Plans**: Always have rollback plans for changes.
- **Staged Rollouts**: Test changes in dev → staging → production.
- **Communication**: Communicate changes to stakeholders in advance.

### 📈 Continuous Improvement

- **Post-Incident Reviews**: Conduct blameless postmortems after incidents.
- **Performance Reviews**: Quarterly performance review and optimization.
- **Cost Optimization**: Regular review of resource usage and costs.
- **Technology Updates**: Stay current with CNPG releases and PostgreSQL versions.

### 📋 Applicable to This Project

✅ **Documentation**: Comprehensive docs in `docs/` directory  
✅ **Monitoring**: Grafana dashboards with key metrics  
✅ **Testing**: Failover testing scripts in `scripts/failover-testing/`  
✅ **Validation**: Cluster validation script for health checks (`scripts/07a-run-cluster-validation.sh`)

---

## Summary: Quick Reference Checklist

### ✅ Pre-Deployment

- [ ] Operator installed in dedicated namespace
- [ ] Storage class configured with appropriate IOPS/throughput
- [ ] Backup storage configured (Azure Blob Storage)
- [ ] Workload Identity federated credentials configured
- [ ] Monitoring infrastructure deployed (Prometheus, Grafana)

### ✅ Cluster Configuration

- [ ] Minimum 3 instances for HA
- [ ] Synchronous replication configured
- [ ] Pod anti-affinity and topology spread configured
- [ ] Resource requests/limits set to same values (Guaranteed QoS)
- [ ] PostgreSQL parameters tuned for workload
- [ ] PgBouncer pooler deployed (if needed)

### ✅ Backup & Recovery

- [ ] Automated backups scheduled
- [ ] WAL archiving enabled with compression
- [ ] Backup retention policy configured (minimum 7 days)
- [ ] Restore procedures tested and documented

### ✅ Security

- [ ] TLS/SSL enforcement enabled
- [ ] SCRAM-SHA-256 authentication configured
- [ ] Network policies implemented
- [ ] Workload Identity configured (no secrets in pods)
- [ ] Role-based access control configured

### ✅ Monitoring

- [ ] PodMonitor created manually (CNPG 1.27)
- [ ] Grafana dashboards imported
- [ ] Key metrics monitored (replication lag, WAL archiving, connections)
- [ ] Alerts configured for critical conditions
- [ ] PgBouncer metrics monitored (if using connection pooling)

### ✅ Operational Readiness

- [ ] Runbooks documented
- [ ] Disaster recovery plan tested
- [ ] Team trained on CNPG operations
- [ ] Incident response procedures established
- [ ] Change management process defined

---

## Additional Resources

### 📚 Official Documentation

- [CloudNativePG Documentation v1.27](https://cloudnative-pg.io/documentation/1.27/)
- [CloudNativePG GitHub Repository](https://github.com/cloudnative-pg/cloudnative-pg)
- [CloudNativePG Grafana Dashboards](https://github.com/cloudnative-pg/grafana-dashboards)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)

### 🎓 Learning Resources

- [EDB CloudNativePG Blog](https://www.enterprisedb.com/blog)
- [Gabriele Bartolini's CNPG Recipes](https://www.gabrielebartolini.it/tags/postgresql/)
- [Azure AKS PostgreSQL HA Deployment](https://learn.microsoft.com/en-us/azure/aks/postgresql-ha-overview)
- [Azure Well-Architected Framework](https://learn.microsoft.com/en-us/azure/architecture/framework/)

### 🛠️ Tools & Utilities

- **kubectl cnpg plugin**: Install via Krew for CNPG-specific commands
- **pgbench**: PostgreSQL benchmarking tool
- **pg_stat_statements**: Query performance monitoring
- **pg_audit**: Audit logging extension

---

## Conclusion

This best practices guide provides comprehensive recommendations for deploying and operating CloudNativePG 1.27 in production environments, specifically tailored for the Azure PostgreSQL HA on AKS workshop architecture. By following these guidelines, you can achieve:

- **High Availability**: RPO=0, RTO<10s with proper quorum configuration
- **Data Durability**: Comprehensive backup and disaster recovery capabilities
- **Performance**: 8,000-10,000 TPS sustained with proper tuning
- **Security**: Enterprise-grade security with Workload Identity and encryption
- **Operational Excellence**: Reliable, maintainable PostgreSQL deployments on Kubernetes

Regular review and updates of these practices, combined with continuous monitoring and improvement, will ensure successful PostgreSQL operations on Azure Kubernetes Service.

---

**Document Version**: v1.0.0  
**CloudNativePG Version**: 1.27.1  
**PostgreSQL Version**: 18.0  
**Last Updated**: October 2025
