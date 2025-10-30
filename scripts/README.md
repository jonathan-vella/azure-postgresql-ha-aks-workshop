# Deployment Scripts

**Version**: `v1.0.0` | **Last Updated**: October 2025

This folder contains all automation scripts for deploying PostgreSQL HA on AKS.

---

## 🚀 Quick Start

### One-Command Deployment

```bash
# 1. Load environment variables
source ../config/environment-variables.sh

# 2. Deploy everything (8 automated steps)
./deploy-all.sh
```

**Estimated Time**: 20-30 minutes

---

## 📋 Script Overview

| Script | Purpose | Duration | Dependencies |
|--------|---------|----------|--------------|
| **deploy-all.sh** | Master orchestration - runs steps 2-7 with logging | 20-30 min | All scripts below |
| **setup-prerequisites.sh** | ⭐ Installs required tools (az, kubectl, helm, jq, etc.) | 5-10 min | None (run first for manual setup) |
| **regenerate-env.sh** | ⭐ Regenerates .env with new suffix (backs up old .env) | <1 min | DevContainer only |
| **02-create-infrastructure.sh** | Creates Azure resources (RG, AKS, Storage, Identity, Container Insights, Bastion, NAT) | 10-15 min | Azure CLI, environment variables |
| **03-configure-workload-identity.sh** | Sets up federated credentials for backup access | 1-2 min | Script 02 completed |
| **04-deploy-cnpg-operator.sh** | Installs CloudNativePG operator v1.27.1 via Helm | 2-3 min | AKS cluster ready |
| **04a-install-barman-cloud-plugin.sh** | Installs Barman Cloud Plugin v0.8.0 for backups | 1 min | CNPG operator installed |
| **05-deploy-postgresql-cluster.sh** | Deploys PostgreSQL HA (3 nodes) + PgBouncer (3 instances) + PodMonitor | 5-10 min | All previous scripts |
| **06-configure-monitoring.sh** | Configures Azure Managed Grafana | 2-3 min | Cluster deployed |
| **06a-configure-azure-monitor-prometheus.sh** | Configures Azure Monitor Managed Prometheus scraping | 2-3 min | Cluster deployed |
| **06b-import-grafana-dashboard.sh** | ⭐ Automated Grafana dashboard import | <1 min | Grafana configured |
| **07-display-connection-info.sh** | Shows connection endpoints and credentials | <1 min | Cluster deployed |
| **07a-run-cluster-validation.sh** | **In-cluster validation (14 tests, 100% pass, Kubernetes Job)** | **~7 sec** | **Cluster deployed** |
| **08-test-pgbench.sh** | Runs pgbench load test | Variable | Cluster deployed |
| **08a-test-pgbench-high-load.sh** | ⭐ High load pgbench test (8K-10K TPS target) | Variable | Cluster deployed |

---

## 📝 Detailed Script Descriptions

### `deploy-all.sh` - Master Orchestration

**Purpose**: Runs all deployment steps in sequence (steps 2-7) with automatic logging.

**What it does**:
1. Loads environment variables (prompts to regenerate suffix in DevContainer)
2. Validates prerequisites (az, kubectl, helm, jq)
3. Checks Azure CLI login status
4. Creates log file in `logs/deployment-YYYYMMDD-HHMMSS.log`
5. Runs infrastructure creation (step 2) - includes Container Insights
6. Configures workload identity (step 3)
7. Installs CNPG operator v1.27.1 (step 4)
8. Installs Barman Cloud Plugin v0.8.0 (step 4a)
9. Deploys PostgreSQL cluster (step 5)
10. Configures Grafana monitoring (step 6)
11. Configures Azure Monitor Managed Prometheus (step 6a)
12. Displays connection info (step 7)

**Usage (DevContainer)**:
```bash
source .env
./deploy-all.sh
```

**Usage (Manual)**:
```bash
source ../config/environment-variables.sh
./deploy-all.sh
```

**Output**: 
- Complete PostgreSQL HA environment ready for use
- Detailed logs in `logs/` directory

---

### `02-create-infrastructure.sh` - Azure Resources

**Purpose**: Creates all Azure infrastructure components.

**What it creates**:
- Resource Group
- Virtual Network (10.0.0.0/8)
- Network Security Group
- AKS Cluster (1.32)
  - System node pool: 2 × Standard_D4s_v5 (4 vCPU, 16GB RAM)
  - User node pool: 3 × Standard_E8as_v6 (8 vCPU, 64GB RAM)
- Managed Identity (for Workload Identity)
- Storage Account (for backups)
- Log Analytics Workspace
- Managed Grafana Instance
- Azure Bastion (optional)
- NAT Gateway

**Usage**:
```bash
source ../config/environment-variables.sh
./02-create-infrastructure.sh
```

**Prerequisites**: Azure CLI logged in, environment variables loaded.

---

---

### `setup-prerequisites.sh` - Tool Installation

**Purpose**: Installs all required tools for manual setup (non-DevContainer environments).

**What it installs**:
- Azure CLI (with aks-preview extension)
- kubectl
- Helm
- jq
- netcat
- Krew (kubectl plugin manager)
- CNPG kubectl plugin

**Usage**:
```bash
chmod +x setup-prerequisites.sh
./setup-prerequisites.sh
```

**Prerequisites**: None (run this first on fresh systems).

**Platform Support**:
- macOS (via Homebrew)
- Linux (Ubuntu/Debian)
- Windows (manual installation links provided)

---

### `regenerate-env.sh` - Environment Regeneration

**Purpose**: Regenerates `.env` file with new suffix for fresh deployment (DevContainer only).

**What it does**:
- Backs up existing `.env` to `.env.backup-YYYYMMDD-HHMMSS`
- Prompts for confirmation (unless `--yes` flag used)
- Deletes old `.env`
- Runs `.devcontainer/generate-env.sh` to create new `.env`
- New suffix ensures unique resource names

**Usage**:
```bash
# Interactive (prompts for confirmation)
./regenerate-env.sh

# Non-interactive (for automation)
./regenerate-env.sh --yes
```

**Prerequisites**: DevContainer environment.

**When to use**:
- Starting fresh deployment with new resources
- Testing deployment automation
- Avoiding resource name conflicts

---

### `03-configure-workload-identity.sh` - Federated Credentials

**Purpose**: Sets up Workload Identity for secure backup access.

**What it does**:
- Creates federated credential for CNPG service account
- Assigns Storage Blob Data Contributor role
- Enables backup access without secrets in pods

**Usage**:
```bash
source ../config/environment-variables.sh
./03-configure-workload-identity.sh
```

**Prerequisites**: Infrastructure created (step 2).

---

### `04-deploy-cnpg-operator.sh` - CloudNativePG Operator

**Purpose**: Installs CloudNativePG operator for PostgreSQL management.

**What it does**:
- Adds CloudNativePG Helm repository
- Installs operator version 1.27.1
- Creates `cnpg-system` namespace
- Waits for operator to be ready

**Usage**:
```bash
./04-deploy-cnpg-operator.sh
```

**Prerequisites**: AKS cluster credentials configured.

---

### `04a-install-barman-cloud-plugin.sh` - Barman Backup Plugin

**Purpose**: Installs Barman Cloud Plugin for backup/restore to Azure Blob Storage.

**What it does**:
- Installs Barman Cloud Plugin v0.8.0
- Enables WAL archiving to Azure Storage
- Configures backup retention policies

**Usage**:
```bash
./04a-install-barman-cloud-plugin.sh
```

**Prerequisites**: CNPG operator installed (step 4).

---

### `05-deploy-postgresql-cluster.sh` - PostgreSQL HA Cluster

**Purpose**: Deploys 3-node PostgreSQL cluster with PgBouncer connection pooling.

**What it creates**:
- PostgreSQL cluster (3 instances)
  - 1 primary + 1 synchronous replica + 1 async replica
  - 40GB memory, 4 vCPU per pod (safe with 20% AKS overhead)
  - Dynamic parameter calculation from memory allocation
- PgBouncer connection pooler (3 instances)
  - Transaction-mode pooling
  - 10,000 max client connections per instance
  - 25 PostgreSQL connections per pool
- Premium SSD v2 storage (40K IOPS, 1,250 MB/s per disk)
- Kubernetes Services (pooler-rw, pooler-ro, direct-rw, direct-ro)
- PodMonitor for Prometheus metrics
- Backup configuration (7-day retention)

**Usage**:
```bash
source ../config/environment-variables.sh
./05-deploy-postgresql-cluster.sh
```

**Prerequisites**: All previous scripts completed.

**Key Configuration**:
- **Failover timings**: 3s delays for <10s RTO target
- **Synchronous replication**: remote_apply (RPO=0)
- **Dynamic parameters**: Auto-calculated from `PG_MEMORY` environment variable
- **Resource allocation**: Accounts for 20% AKS system overhead

---

### `06-configure-monitoring.sh` - Grafana & Azure Monitor

**Purpose**: Configures observability stack.

**What it does**:
- Configures Azure Monitor integration
- Sets up Managed Grafana access
- Prepares dashboard import
- Configures Prometheus data source

**Usage**:
```bash
source ../config/environment-variables.sh
./06-configure-monitoring.sh
```

**Prerequisites**: Cluster deployed (step 5).

**Next Steps**: Import dashboard using `06b-import-grafana-dashboard.sh` or manually.

---

### `06a-configure-azure-monitor-prometheus.sh` - Prometheus Scraping

**Purpose**: Configures Azure Monitor Managed Prometheus to scrape CNPG metrics.

**What it does**:
- Enables Azure Monitor Managed Prometheus addon on AKS
- Configures PodMonitor scraping for CNPG metrics
- Sets up Prometheus data source in Grafana
- Validates metrics collection

**Usage**:
```bash
source ../config/environment-variables.sh
./06a-configure-azure-monitor-prometheus.sh
```

**Prerequisites**: 
- Cluster deployed (step 5)
- Grafana configured (step 6)

**Metrics Collected**:
- PostgreSQL instance metrics
- Connection pool statistics
- Replication lag and status
- WAL archiving status
- Database performance metrics

---

### `06b-import-grafana-dashboard.sh` - Dashboard Import ⭐

**Purpose**: Automatically import pre-built Grafana dashboard for CNPG monitoring.

**What it does**:
- Gets Grafana endpoint from Azure
- Retrieves Prometheus datasource UID
- Configures dashboard JSON with correct datasource
- Imports dashboard via Azure CLI
- Provides dashboard URL for access

**Usage**:
```bash
source ../config/environment-variables.sh
./06b-import-grafana-dashboard.sh
```

**Prerequisites**: 
- Grafana configured (step 6)
- Azure Monitor Prometheus configured (step 6a)

**Dashboard Features**:
- 9 monitoring panels
- Real-time metrics visualization
- Cluster health status
- Connection pooling metrics
- Replication lag monitoring
- WAL archiving status

**Output**: Direct URL to imported dashboard.

---

### `07-display-connection-info.sh` - Connection Details

**Purpose**: Shows how to connect to PostgreSQL.

**What it displays**:
- Service endpoints (PgBouncer and direct)
- Database credentials
- Port-forward commands
- psql connection examples

**Usage**:
```bash
./07-display-connection-info.sh
```

**Prerequisites**: Cluster deployed.

---

### `07a-run-cluster-validation.sh` - In-Cluster Validation ⭐

**Purpose**: Deploy and execute comprehensive validation tests inside AKS cluster using Kubernetes Job.

**What it tests (14 tests, 100% pass rate, ~7 seconds)**:
1. **Primary Connection (Direct)**: Direct PostgreSQL connectivity, version check, primary verification
2. **PgBouncer Pooler Connection**: Connection through pooler service
3. **Data Write Operations**: CREATE TABLE, INSERT data (3 rows), verify persistence
4. **Read Replica Connection**: Read-only service connectivity, replica verification
5. **Data Replication**: Replication to read replicas (3 rows), data consistency check
6. **Replication Status**: Replica accessibility (3 attempts), replication health
7. **Connection Pooling**: 5 concurrent connections via pooler
8. **Cleanup**: Test table deletion

**Key Features**:
- ⚡ **Fast**: Completes in ~7 seconds (vs 60+ seconds with port-forward)
- ✅ **Reliable**: 100% pass rate (vs 85% with port-forward)
- 🎯 **Accurate**: Tests run inside AKS with direct ClusterIP access
- 🔄 **Auto-cleanup**: Job deleted automatically after 1 hour

**Usage**:
```bash
source ../.env
./07a-run-cluster-validation.sh
```

**Output**:
- ✅ **Pass**: Test succeeded
- ❌ **Fail**: Test failed (requires action)
- ⚠️ **Warn**: Non-critical issue detected

**Success Criteria**:
- All 3 PostgreSQL instances ready
- Pods distributed across zones
- Primary and replica connections verified
- Data replication confirmed (RPO=0)
- PgBouncer pooler operational
- WAL archiving active

**Prerequisites**: Cluster deployed (step 5).

**Recommended**: Run after deployment to validate all components.

---

### `08-test-pgbench.sh` - Load Testing

**Purpose**: Runs pgbench performance test against PostgreSQL.

**What it does**:
- Initializes pgbench schema
- Runs configurable load test
- Reports TPS and latency
- Tests both direct and pooled connections

**Usage**:
```bash
# Quick test (5 clients, 1000 transactions each)
./08-test-pgbench.sh

# Custom test
./08-test-pgbench.sh --clients 10 --duration 120
```

**Prerequisites**: Cluster deployed.

**Expected Results** (with current low-IOPS disks):
- TPS: 1,500-2,000
- Latency: 3-6ms
- With 40K IOPS disks: 8,000-10,000 TPS

---

### `setup-prerequisites.sh` - Tool Installation

**Purpose**: Installs required tools for deployment.

**What it installs**:
- Azure CLI (v2.56+)
- kubectl (v1.21+)
- Helm (v3.0+)
- jq (v1.5+)
- OpenSSL (v3.3+)
- Krew + CNPG plugin

**Usage**:
```bash
./setup-prerequisites.sh
```

**Note**: Use DevContainer for pre-configured environment (recommended).

---

## 🔄 Execution Order

**Correct order**:
```
1. setup-prerequisites.sh (if needed)
2. deploy-all.sh (orchestrates steps 2-7)
   OR
   Run individually:
   → 02-create-infrastructure.sh (includes Container Insights)
   → 03-configure-workload-identity.sh
   → 04-deploy-cnpg-operator.sh
   → 04a-install-barman-cloud-plugin.sh
   → 05-deploy-postgresql-cluster.sh (creates PodMonitor)
   → 06-configure-monitoring.sh (Grafana)
   → 06a-configure-azure-monitor-prometheus.sh (Azure Monitor)
   → 07-display-connection-info.sh
3. 07a-run-cluster-validation.sh (recommended - in-cluster validation, 100% pass rate)
4. 08-test-pgbench.sh (optional - performance testing)
```

---

## 🛠️ Common Workflows

### First-Time Deployment
```bash
# 1. Configure environment
cd /workspaces/azure-postgresql-ha-aks-workshop
source config/environment-variables.sh

# 2. Deploy everything
cd scripts
./deploy-all.sh

# 3. Test connection
./07-display-connection-info.sh
```

### Re-deploy Cluster Only
```bash
# Delete existing cluster
kubectl delete cluster pg-primary -n cnpg-database

# Re-deploy
source ../config/environment-variables.sh
./05-deploy-postgresql-cluster.sh
```

### Update Configuration
```bash
# 1. Edit environment variables
code ../config/environment-variables.sh

# 2. Reload
source ../config/environment-variables.sh

# 3. Re-deploy affected components
./05-deploy-postgresql-cluster.sh
```

### Clean Up
```bash
# Delete entire resource group
az group delete --name $RESOURCE_GROUP_NAME --yes --no-wait
```

---

## ⚠️ Important Notes

### Environment Variables
**Always load before running scripts**:
```bash
source ../config/environment-variables.sh
```

### Script 05 Configuration
- **Dynamic parameters**: PostgreSQL settings auto-calculate from `PG_MEMORY`
- **Cluster definition**: Embedded in script, NOT from `../kubernetes/postgresql-cluster.yaml`
- **Resource allocation**: Accounts for 20% AKS overhead (safe limits)

### Prerequisites
- Azure CLI logged in: `az login`
- Correct subscription: `az account show`
- Environment variables loaded
- Sufficient Azure quota

### Timing
- **Fastest**: 20 minutes (with pre-warmed environment)
- **Typical**: 25-30 minutes (fresh deployment)
- **First time**: 35-40 minutes (including tool installation)

---

## 🐛 Troubleshooting

### Script Fails to Find Environment Variables
```bash
# Solution: Load environment variables
source ../config/environment-variables.sh
echo $RESOURCE_GROUP_NAME  # Should show value
```

### AKS Cluster Creation Fails
```bash
# Check region support for Premium v2
az vm list-skus --location $PRIMARY_CLUSTER_REGION --size Standard_E8as_v6 --output table

# Check quota
az vm list-usage --location $PRIMARY_CLUSTER_REGION --output table | grep Standard_E8as_v6
```

### CNPG Operator Not Installing
```bash
# Check Helm repository
helm repo list | grep cnpg
helm repo update cnpg

# Check operator logs
kubectl logs -n cnpg-system deployment/cnpg-cloudnative-pg
```

### PostgreSQL Pods Stuck in Init
```bash
# Check PVC binding
kubectl get pvc -n cnpg-database

# Check storage class
kubectl get storageclass

# Check pod events
kubectl describe pod -n cnpg-database <pod-name>
```

### WAL Archiving Fails
```bash
# Check workload identity
az identity federated-credential list \
  --resource-group $RESOURCE_GROUP_NAME \
  --identity-name $IDENTITY_NAME

# Check storage role
az role assignment list --assignee <identity-object-id> --scope <storage-account-id>

# Check pod logs
kubectl logs -n cnpg-database <pod-name> | grep -i backup
```

---

## � Environment Management

### `regenerate-env.sh` - Regenerate Environment with New Suffix

**Purpose**: Creates a fresh `.env` file with a new random suffix for deploying a new environment.

**When to use**:
- Starting a completely new deployment
- Testing deployment automation
- Creating isolated environments (dev, test, prod)

**What it does**:
1. Shows current suffix and resource group name
2. Prompts for confirmation
3. Backs up current `.env` to `.env.backup-TIMESTAMP`
4. Deletes old `.env`
5. Generates new `.env` with fresh suffix
6. Shows new configuration

**Usage**:
```bash
./scripts/regenerate-env.sh

# Example output:
# 📋 Current configuration:
#   Old Suffix:         0lt2bi0v
#   Old Resource Group: rg-cnpg-0lt2bi0v
# 
# ⚠️  Delete current .env and generate new suffix? (y/N): y
# 💾 Backed up old .env to: .env.backup-20251030-111500
# 🗑️  Deleted old .env file
# 🔧 Generating new .env file...
# ✅ New .env file created!
# 
# New Suffix:         x4k9m2p7
# Resource Group:     rg-cnpg-x4k9m2p7
```

**Then load and deploy**:
```bash
source .env
./scripts/deploy-all.sh
```

---

## �📚 Additional Resources

- **Main Documentation**: [../docs/SETUP_COMPLETE.md](../docs/SETUP_COMPLETE.md)
- **Quick Reference**: [../docs/QUICK_REFERENCE.md](../docs/QUICK_REFERENCE.md)
- **Cost Estimation**: [../docs/COST_ESTIMATION.md](../docs/COST_ESTIMATION.md)
- **Failover Testing**: [../docs/FAILOVER_TESTING.md](../docs/FAILOVER_TESTING.md)
- **Grafana Dashboard**: [../docs/GRAFANA_DASHBOARD_GUIDE.md](../docs/GRAFANA_DASHBOARD_GUIDE.md)

---

## 🔗 External Documentation

- CloudNativePG: https://cloudnative-pg.io/
- Azure AKS: https://learn.microsoft.com/en-us/azure/aks/
- Premium SSD v2: https://learn.microsoft.com/en-us/azure/virtual-machines/disks-types

---

**Need help?** See [../docs/README.md](../docs/README.md) for comprehensive documentation.
