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
| **deploy-all.sh** | Master orchestration - runs steps 2-7 | 20-30 min | All scripts below |
| **02-create-infrastructure.sh** | Creates Azure resources (RG, AKS, Storage, Identity, Container Insights, Bastion, NAT) | 10-15 min | Azure CLI, environment variables |
| **03-configure-workload-identity.sh** | Sets up federated credentials for backup access | 1-2 min | Script 02 completed |
| **04-deploy-cnpg-operator.sh** | Installs CloudNativePG operator via Helm | 2-3 min | AKS cluster ready |
| **04a-install-barman-cloud-plugin.sh** | Installs Barman Cloud Plugin v0.8.0 for backups | 1 min | CNPG operator installed |
| **05-deploy-postgresql-cluster.sh** | Deploys PostgreSQL HA (3 nodes) + PgBouncer (3 instances) + PodMonitor | 5-10 min | All previous scripts |
| **06-configure-monitoring.sh** | Configures Azure Managed Grafana | 2-3 min | Cluster deployed |
| **06a-configure-azure-monitor-prometheus.sh** | Configures Azure Monitor Managed Prometheus scraping | 2-3 min | Cluster deployed |
| **07-display-connection-info.sh** | Shows connection endpoints and credentials | <1 min | Cluster deployed |
| **07a-validate-cluster.sh** | **Comprehensive cluster validation (connectivity, replication, HA)** | **2-3 min** | **Cluster deployed** |
| **08-test-pgbench.sh** | Runs pgbench load test | Variable | Cluster deployed |
| **regenerate-env.sh** | **Regenerates .env with new suffix (backs up old .env)** | **<1 min** | **None** |
| **setup-prerequisites.sh** | Installs required tools (az, kubectl, helm, etc.) | 5-10 min | None (run first) |

---

## 📝 Detailed Script Descriptions

### `deploy-all.sh` - Master Orchestration

**Purpose**: Runs all deployment steps in sequence (steps 2-7).

**What it does**:
1. Validates environment variables are loaded
2. Runs infrastructure creation (step 2) - includes Container Insights
3. Configures workload identity (step 3)
4. Installs CNPG operator (step 4)
5. Installs Barman Cloud Plugin (step 4a)
6. Deploys PostgreSQL cluster (step 5)
7. Configures Grafana monitoring (step 6)
8. Configures Azure Monitor Managed Prometheus (step 6a)
9. Displays connection info (step 7)

**Usage**:
```bash
source ../config/environment-variables.sh
./deploy-all.sh
```

**Output**: Complete PostgreSQL HA environment ready for use.

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

**Next Steps**: Import dashboard from `../grafana/grafana-cnpg-ha-dashboard.json`.

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

### `07a-validate-cluster.sh` - Cluster Validation ⭐

**Purpose**: Comprehensive validation of PostgreSQL HA cluster deployment.

**What it tests**:
1. **Cluster Status**: Ready state, instance counts, HA configuration
2. **Multi-Zone Distribution**: Pods spread across 3 availability zones
3. **Service Endpoints**: All required services (rw, ro, pooler)
4. **Primary Connection**: PgBouncer pooler connectivity
5. **Data Write Operations**: Create table, insert data, verify persistence
6. **Synchronous Replication**: Data consistency, RPO=0 validation
7. **PgBouncer Pooler**: 3 instances, readiness checks
8. **WAL Archiving**: Backup plugin status, archival health
9. **Monitoring**: PodMonitor and metrics endpoint verification
10. **Cleanup**: Test data removal

**Usage**:
```bash
source ../config/environment-variables.sh
./07a-validate-cluster.sh
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
3. 07a-validate-cluster.sh (recommended - validates deployment)
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
