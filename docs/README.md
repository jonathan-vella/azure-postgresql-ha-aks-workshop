# Azure PostgreSQL HA on AKS Workshop

A comprehensive automation framework for deploying a highly available PostgreSQL database on Azure Kubernetes Service (AKS) with Premium v2 disk storage.

> **⚠️ IMPORTANT: Lab and Proof-of-Concept Use Only**  
> This code is provided strictly for **lab environments and proof-of-concept purposes only**. It is not intended for production use. Additional hardening, security reviews, compliance validation, and operational procedures are required before considering any production deployment.

## 🎯 Overview

This project automates the deployment of a **3-node highly available PostgreSQL cluster** on AKS using CloudNativePG (CNPG) operator with the following features:

### Key Features

- **High Availability**: 1 Primary + 2 Synchronous Replicas across availability zones
- **Fast Failover**: <10 second automatic failover with optimized health checks
- **Connection Pooling**: Native PgBouncer pooler supporting 10,000 concurrent connections
- **Premium v2 Storage**: Optimized for cost and performance with configurable IOPS/throughput
- **Zero Data Loss**: Synchronous replication with RPO=0 (remote_apply)
- **Azure Integration**: 
  - Workload Identity for authentication
  - Azure Blob Storage for backups
  - Azure Monitor + Grafana for observability
- **Disaster Recovery**: Automated backups with Point-in-Time Recovery (PITR)
- **Zone Redundancy**: Automatic failover across zones
- **Automation**: Pure Azure CLI commands following Microsoft reference implementation

## 📋 Prerequisites

### Tools Required

- Azure CLI (v2.56+)
- kubectl (v1.21+)
- Helm (v3.0+)
- jq (v1.5+)
- OpenSSL (v3.3+)
- Krew (kubectl plugin manager)
- CloudNativePG (CNPG) kubectl plugin

### Azure Requirements

- Azure subscription with Owner or User Access Administrator role
- Quota for resources in your chosen region:
  - Standard_D2s_v5 VMs (system pool)
  - Standard_E8as_v6 VMs (postgres pool) - 8 vCPU, 64 GB RAM
  - Premium v2 disks
- **AKS Node OS**: Azure Linux (CBL-Mariner) - optimized for container workloads

### Supported Regions

Premium SSD v2 disks are available in:
- Canada Central
- East US
- UK South
- West Europe
- Westus3
- And others (see [Azure documentation](https://learn.microsoft.com/en-us/azure/virtual-machines/disks-types#regional-availability))

## 🚀 Quick Start

### 1. Configure Environment Variables

Edit `config/environment-variables.sh`:

```bash
# Azure settings
PRIMARY_CLUSTER_REGION="canadacentral"
AKS_CLUSTER_VERSION="1.32"

# Node pool (optimized for high-performance PostgreSQL)
USER_NODE_POOL_VMSKU="Standard_E8as_v6"  # 8 vCPU, 64 GB RAM, AMD EPYC 9004

# Storage (Premium v2 - high performance configuration)
DISK_IOPS="40000"           # Max: 80,000 IOPS
DISK_THROUGHPUT="1200"      # Max: 1,200 MB/s (increased for high throughput)
PG_STORAGE_SIZE="200Gi"     # 200 GB per instance

# PostgreSQL resources (aligned with E8as_v6 hardware)
PG_MEMORY="48Gi"            # 75% of 64 GB node RAM
PG_CPU="6"                  # 75% of 8 vCPU

# PostgreSQL credentials
PG_DATABASE_PASSWORD="SecurePassword123!"  # Change this!
```

### 2. Deploy All Components

```bash
# Load environment variables into current shell session
# This reads config/environment-variables.sh and exports all variables
source config/environment-variables.sh

# Run deployment (uses loaded variables)
./scripts/deploy-all.sh
```

**What happens:** The `source` command executes the script in your current shell, making all `export VARIABLE=value` statements available to subsequent commands and scripts.

### 3. Validate Deployment (Recommended ⭐)

```bash
# Run in-cluster validation (14 tests, ~7 seconds)
./scripts/07a-run-cluster-validation.sh
```

**What gets validated:**
- ✅ Primary & replica connectivity (direct & PgBouncer)
- ✅ Data write operations & persistence
- ✅ Data replication consistency (RPO=0)
- ✅ Read-only service routing to replicas
- ✅ Replica accessibility & health
- ✅ Connection pooling (5 concurrent connections)
- ⚡ Executed inside AKS cluster (no port-forward instability)

**Expected result:** 14/14 tests pass (100% success rate)

### 4. Manual Verification (Optional)

```bash
# Get credentials
az aks get-credentials \
  --resource-group $RESOURCE_GROUP \
  --name $CLUSTER_NAME

# Check CNPG operator
kubectl get deployment -n cnpg-system

# Check PostgreSQL cluster
kubectl get pods -n cnpg-database -l cnpg.io/cluster=pg-primary

# Check cluster status
kubectl cnpg status pg-primary -n cnpg-database
```

## 📁 Project Structure

```
├── config/
│   └── environment-variables.sh   # Bash environment configuration
├── scripts/
│   ├── 02-create-infrastructure.sh         # Creates Azure resources
│   ├── 03-configure-workload-identity.sh   # Federated credentials setup
│   ├── 04-deploy-cnpg-operator.sh          # Installs CNPG operator
│   ├── 05-deploy-postgresql-cluster.sh     # Deploys PostgreSQL HA
│   ├── 06-configure-monitoring.sh          # Configures observability
│   ├── 07a-run-cluster-validation.sh       # ⭐ In-cluster validation (14 tests, 100% pass, ~7s)
│   ├── 08-test-pgbench.sh                  # Tests pgbench performance tool
│   └── deploy-all.sh                       # Master orchestration
├── kubernetes/
│   ├── postgresql-cluster.yaml             # Reference manifest (not used in deployment)
│   └── cluster-validation-job.yaml         # In-cluster validation Job
└── docs/
    └── README.md                # This file
```

## 🔧 Configuration Guide

### Premium v2 Disk Settings

The deployment uses Premium SSD v2 disks for optimal price-performance:

- **IOPS**: 40,000 (configurable 3,100-80,000)
- **Throughput**: 1,250 MB/s (configurable 125-1,200 MB/s)
- **Storage Size**: 200 GB per PostgreSQL instance

Adjust these in `config/environment-variables.sh`:

```bash
DISK_IOPS="40000"
DISK_THROUGHPUT="1200"
PG_STORAGE_SIZE="200Gi"
```

**Performance Expectations**: With this configuration, expect 8,000-10,000 TPS sustained throughput.

### PostgreSQL Tuning

Key performance parameters are configured in the deployment script (`scripts/05-deploy-postgresql-cluster.sh`):

```yaml
# Memory settings (optimized for Standard_E8as_v6: 8 vCPU, 64 GB RAM)
shared_buffers: "16GB"                     # 25% of 64 GB RAM
effective_cache_size: "48GB"               # 75% of 64 GB RAM
work_mem: "64MB"                           # Optimized for 500 connections
maintenance_work_mem: "2GB"                # 3% of RAM

# WAL optimization (40K IOPS disk)
min_wal_size: "4GB"
max_wal_size: "16GB"
wal_compression: "lz4"

# Parallel workers (aligned with 8 vCPU)
max_worker_processes: "12"                 # 1.5× vCPUs
max_parallel_workers_per_gather: "4"       # Half of vCPUs
max_parallel_workers: "8"                  # Match vCPUs

# Synchronous replication (zero data loss, RPO=0)
synchronous_commit: "remote_apply"         # Strictest guarantee
wal_receiver_timeout: "5s"                 # Fast failure detection
wal_sender_timeout: "5s"                   # Fast failure detection
```

These values are optimized for the 48GB memory allocation per PostgreSQL instance.

### Connection Pooling (PgBouncer)

The deployment includes a **native CNPG pooler** (not sidecar) that provides:

- **10,000 concurrent client connections** support
- **Transaction-mode pooling** for maximum efficiency
- **3 pooler instances** for high availability
- **Separate service endpoint** (`pg-primary-pooler-rw`)

#### Pooler Configuration

```yaml
pooler:
  instances: 3
  type: rw
  pgbouncer:
    poolMode: transaction
    parameters:
      max_client_conn: "10000"              # Support 10K clients
      default_pool_size: "25"               # 25 connections per user/database
      max_db_connections: "500"             # Match PostgreSQL max_connections
      server_idle_timeout: "600"            # 10 min idle timeout
      server_lifetime: "3600"               # 1 hour connection lifetime
```

#### Connection Strings

**Direct PostgreSQL connection** (for admin tasks):
```bash
# Primary (read-write)
psql "host=pg-primary-rw.cnpg-database.svc.cluster.local port=5432 dbname=appdb user=app"

# Replicas (read-only)
psql "host=pg-primary-ro.cnpg-database.svc.cluster.local port=5432 dbname=appdb user=app"
```

**Pooled connection** (recommended for applications):
```bash
# Through PgBouncer pooler (handles 10K concurrent connections)
psql "host=pg-primary-pooler-rw.cnpg-database.svc.cluster.local port=5432 dbname=appdb user=app"
```

**Why use the pooler?**
- Handles 10,000 concurrent clients with only 25-500 PostgreSQL connections
- Reduces connection overhead and memory usage
- Transaction pooling allows connection reuse between transactions
- Automatic connection management and health checks

### Failover Optimization

The deployment is configured for **<10 second failover time** (reduced from default 30-60s):

#### Failover Settings

```yaml
failoverDelay: 5                           # Trigger failover after 5s (from 30s)
startDelay: 5                              # Start new instance in 5s (from 30s)
stopDelay: 5                               # Stop instance in 5s (from 30s)
switchoverDelay: 5                         # Switchover in 5s (from 40000000s)

# Fast health checks
livenessProbeTimeout: 3                    # 3s liveness timeout (from 30s)
readinessProbeTimeout: 3                   # 3s readiness timeout (from 30s)
smartShutdownTimeout: 10                   # 10s shutdown (from 180s)
```

#### How Failover Works

1. **Failure Detection** (3-5s): Liveness probe fails after 3s timeout × probe attempts
2. **Decision** (5s): Operator waits `failoverDelay` before triggering failover
3. **Promotion** (2-3s): Replica promoted to primary via `pg_promote()`
4. **Service Update** (1-2s): Kubernetes updates service endpoints
5. **Total Time**: **8-12 seconds** typical failover (vs 30-60s default)

**Trade-off**: Faster failover increases risk of false positives during network hiccups. For lab testing with <10s targets, these settings are appropriate. For production, consider increasing to 10-15s based on your network stability and RTO requirements.

## 📊 Monitoring

### Azure Monitor + Grafana

1. **Access Grafana Dashboard**:
   ```bash
   az grafana show \
     --resource-group $RESOURCE_GROUP \
     --name "aks-postgresql-ha-grafana"
   ```

2. **Prometheus Metrics**: Automatically scraped via PodMonitor
3. **Log Analytics**: Container insights enabled

### Important Metrics to Monitor

- `pg_stat_replication_status` - Replication lag
- `pg_database_size_bytes` - Database size
- `pg_wal_archive_status` - WAL archiving status
- `node_filesystem_avail_bytes` - Disk available space

## 🔐 Security Considerations

### Workload Identity

The deployment uses Azure AD Workload Identity for secure authentication to Azure Storage:

1. User-Assigned Managed Identity is created
2. Federated credential maps Kubernetes SA to Azure identity
3. No secrets stored in Kubernetes

### Network Security

- NSG rules restrict access to:
  - Kubernetes API (port 443)
  - PostgreSQL (port 5432)
- Network policies enforced via Cilium

### Authentication

- PostgreSQL uses SCRAM-SHA-256 password authentication
- Database user credentials stored as Kubernetes secrets

### Backup Security

- Backups stored in Azure Blob Storage with no public access
- Automatic encryption at rest
- Retention policy: 7 days (configurable)

## 💾 Backup and Recovery

### Automated Backups

- **WAL Archiving**: Continuous archiving to Azure Blob Storage
- **Full Backups**: Daily on-demand backups
- **Scheduled Backups**: Hourly scheduled backups (configurable)

### Point-in-Time Recovery (PITR)

Restore from any point within the retention window:

```bash
# Create recovery cluster from backup
kubectl cnpg backup pg-primary -n cnpg-database

# List backups
az storage blob list \
  --account-name $STORAGE_ACCOUNT \
  --container-name backups
```

### Manual Backup

```bash
# Create on-demand backup
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: manual-backup-$(date +%s)
  namespace: cnpg-database
spec:
  method: barmanObjectStore
  cluster:
    name: pg-primary
EOF
```

## 🔄 Failover Testing

### Test Automatic Failover

```bash
# Get primary pod
PRIMARY_POD=$(kubectl get pod -n cnpg-database \
  -l cnpg.io/cluster=pg-primary,cnpg.io/instanceRole=primary \
  -o jsonpath='{.items[0].metadata.name}')

echo "Current primary: $PRIMARY_POD"

# Delete primary (simulates crash)
echo "Deleting primary pod to trigger failover..."
time kubectl delete pod $PRIMARY_POD -n cnpg-database --grace-period=1

# Monitor cluster status
echo "Monitoring failover..."
kubectl cnpg status pg-primary -n cnpg-database --watch
```

### Manual Switchover (Planned Failover)

```bash
# Promote a specific replica to primary
kubectl cnpg promote pg-primary <replica-pod-name> -n cnpg-database

# Example: Promote pg-primary-2
kubectl cnpg promote pg-primary pg-primary-2 -n cnpg-database
```

### Expected Behavior

1. **Failure Detection** (3-5s): Kubernetes detects pod failure
2. **Failover Decision** (5s): CNPG operator waits `failoverDelay` 
3. **Replica Promotion** (2-3s): Best replica promoted via `pg_promote()`
4. **Service Update** (1-2s): Endpoints updated to new primary
5. **Total Time**: **8-12 seconds** (vs 30-60s default)

The original primary will rejoin as a replica once recovered.

### Test Pooler Failover

```bash
# Connect through pooler during failover
kubectl port-forward svc/pg-primary-pooler-rw 5432:5432 -n cnpg-database &

# Run continuous queries
while true; do
  psql -h localhost -U app -d appdb -c "SELECT now();"
  sleep 1
done

# In another terminal, trigger failover
kubectl delete pod <primary-pod> -n cnpg-database --grace-period=1

# Observe connection behavior (may see brief interruption, then auto-reconnect)
```

## 📈 Scaling

### Add More Replicas

Update instances in `kubernetes/postgresql-cluster.yaml`:

```yaml
spec:
  instances: 5  # Change from 3 to 5
```

Apply:
```bash
kubectl apply -f kubernetes/postgresql-cluster.yaml
```

### Scale Node Pool

```bash
az aks nodepool scale \
  --resource-group $RESOURCE_GROUP \
  --cluster-name $CLUSTER_NAME \
  --name postgrespool \
  --node-count 5
```

## 🆘 Troubleshooting

### Check Operator Health

```bash
kubectl logs -n cnpg-system deployment/cnpg-cloudnative-pg
```

### Check Cluster Status

```bash
kubectl describe cluster pg-primary -n cnpg-database

# Detailed status
kubectl cnpg status pg-primary 1 -n cnpg-database
```

### View Pod Events

```bash
kubectl describe pod -n cnpg-database -l cnpg.io/cluster=pg-primary
```

### Check WAL Archiving

```bash
kubectl cnpg status pg-primary 1 -n cnpg-database | grep "WAL archiving"
```

For detailed troubleshooting, see `docs/TROUBLESHOOTING.md`.

## 🧹 Cleanup

Delete all resources:

```bash
# Delete resource group (removes everything)
az group delete --resource-group $RESOURCE_GROUP --no-wait --yes

# Or manually:
kubectl delete namespace cnpg-database cnpg-system
```

## 📚 Additional Resources

- [CloudNativePG Documentation](https://cloudnative-pg.io/documentation/current/)
- [Azure AKS PostgreSQL HA Guide](https://learn.microsoft.com/en-us/azure/aks/postgresql-ha-overview)
- [Premium SSD v2 Documentation](https://learn.microsoft.com/en-us/azure/virtual-machines/disks-types#premium-ssd-v2)
- [Azure Well-Architected Framework](https://learn.microsoft.com/en-us/azure/architecture/framework/)

## 🤝 Contributing

Improvements welcome! Please check `docs/CONTRIBUTING.md`.

## 📄 License

MIT License - See LICENSE file

## 🙋 Support

For issues and questions:
1. Check `docs/TROUBLESHOOTING.md`
2. Review CloudNativePG logs
3. Check AKS cluster events
4. Open an issue with logs and configuration

---

**Last Updated**: October 2025  
**Tested With**: AKS 1.32, CNPG 1.27, Kubernetes 1.32
