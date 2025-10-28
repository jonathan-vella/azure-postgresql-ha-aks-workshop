# � Azure PostgreSQL HA on AKS Workshop

A complete automation framework for deploying a **highly available, production-ready PostgreSQL database** on Azure Kubernetes Service with Premium v2 storage.

[![Status](https://img.shields.io/badge/Status-Production%20Ready-brightgreen)](#) [![License](https://img.shields.io/badge/License-MIT-blue)](#) [![Maintained](https://img.shields.io/badge/Maintained%3F-Yes-green)](#)

---

## 🏗️ Architecture Overview

```mermaid
graph TB
    subgraph "Azure Subscription"
        subgraph "Virtual Network (10.0.0.0/8)"
            subgraph "AKS Cluster (1.32)"
                subgraph "System Node Pool (2x D2s_v5)"
                    CNPG["CNPG Operator<br/>(cnpg-system)"]
                    INF["Prometheus<br/>Monitoring"]
                end
                
                subgraph "PostgreSQL Node Pool (3x E8as_v6)"
                    PG1["PostgreSQL Primary<br/>Instance 1<br/>200GB Data + WAL<br/>40K IOPS"]
                    PG2["PostgreSQL Sync Replica<br/>Instance 2 (Quorum)<br/>200GB Data + WAL<br/>40K IOPS"]
                    PG3["PostgreSQL Async Replica<br/>Instance 3<br/>200GB Data + WAL<br/>40K IOPS"]
                end
                
                subgraph "Kubernetes Services"
                    SVC_RW["Service: pg-primary-rw<br/>(Read-Write)<br/>Port 5432"]
                    SVC_RO["Service: pg-primary-ro<br/>(Read-Only)<br/>Port 5432"]
                end
            end
            
            PG1 ===|Sync Replication<br/>RPO=0| PG2
            PG1 ---|Async Replication| PG3
            PG1 --> SVC_RW
            PG2 --> SVC_RO
            PG3 --> SVC_RO
        end
        
        subgraph "Storage & Backup"
            SA["Azure Storage Account<br/>(ZRS)<br/>Blob Backups"]
            LA["Log Analytics<br/>Workspace"]
        end
        
        subgraph "Monitoring"
            GRAF["Azure Managed Grafana<br/>Instance"]
            AMW["Azure Monitor<br/>Workspace"]
        end
        
        subgraph "Network Security"
            NSG["Network Security Group<br/>- Kubernetes API: 443<br/>- PostgreSQL: 5432"]
            MI["Managed Identity<br/>(Workload Identity)"]
        end
        
        PG1 & PG2 & PG3 -->|WAL Archive + Backups| SA
        CNPG & PG1 & PG2 & PG3 -->|Metrics| AMW
        AMW --> GRAF
        MI -->|Auth to Storage| SA
        NSG -.->|Security Rules| PG1 & PG2 & PG3
    end
    
    style PG1 fill:#336791,stroke:#2d5a7b,color:#fff
    style PG2 fill:#336791,stroke:#2d5a7b,color:#fff
    style PG3 fill:#336791,stroke:#2d5a7b,color:#fff
    style SA fill:#0078d4,stroke:#0062a3,color:#fff
    style GRAF fill:#ff9830,stroke:#d67f1a,color:#fff
    style AMW fill:#0078d4,stroke:#0062a3,color:#fff
    style MI fill:#7fba00,stroke:#6d9b00,color:#fff
    style NSG fill:#ff6b6b,stroke:#e63946,color:#fff
```

## ✨ Key Features

| Feature | Details |
|---------|---------|
| **High Availability** | 3-node PostgreSQL cluster (1 primary + 1 quorum sync replica + 1 async replica) with automatic failover |
| **Data Durability** | Synchronous replication (RPO = 0) - zero data loss on failover |
| **Zone Redundancy** | Deployment across 3 Azure Availability Zones |
| **Storage** | Premium SSD v2 with 40K IOPS & 1,250 MB/s throughput per disk (200 GiB each) |
| **Backup & Recovery** | Automated WAL archiving + full backups to Azure Blob Storage, 7-day retention |
| **Security** | Workload Identity, SCRAM-SHA-256 auth, NSGs, RBAC, encrypted backups |
| **Monitoring** | Prometheus metrics collection, Grafana dashboards, Azure Monitor integration |
| **Infrastructure** | Pure Azure CLI automation following Microsoft reference implementation |
| **Operations** | CloudNativePG 1.27.1 operator for automated management, health checks, and scaling |

---

## 🚀 Quick Start

### Option A: Use DevContainer (Recommended) 🐳

All tools pre-installed in isolated container:

```bash
# Requirements: Docker Desktop + VS Code Remote - Containers extension
# 1. Open project in VS Code
# 2. Ctrl+Shift+P -> "Dev Containers: Reopen in Container"
# 3. Wait for build (2-5 min first time)
# 4. Tools ready: az, kubectl, helm, jq, openssl
```

See `.devcontainer/README.md` for detailed setup.

### Option B: Local Installation

**Prerequisites**:
- Azure CLI (v2.56+), kubectl (v1.21+), Helm (v3.0+), jq, OpenSSL
- Azure subscription with Owner or User Access Administrator role
- Region with Premium v2 disk support

### 1️⃣ Configure
```bash
# Clone repository
git clone <repo-url>
cd azure-postgresql-ha-aks-workshop

# Review and customize environment variables
code config/environment-variables.sh
```

### 2️⃣ Deploy
```bash
# Load environment variables into current shell session
# This makes all configuration values available to deployment scripts
source config/environment-variables.sh

# Deploy all components (6 automated steps)
./scripts/deploy-all.sh
```

> **What does this do?** The `source` command loads all configuration variables (like resource names, regions, VM sizes) from the config file into your current terminal session. This allows the deployment scripts to access these values without hardcoding them.

### 3️⃣ Verify
```bash
# Get cluster credentials
az aks get-credentials --resource-group <rg-name> --name <cluster-name>

# Check status
kubectl cnpg status pg-primary -n cnpg-database

# View pods
kubectl get pods -n cnpg-database -l cnpg.io/cluster=pg-primary
```

### 4️⃣ Connect
```bash
# Port forward
kubectl port-forward svc/pg-primary-rw 5432:5432 -n cnpg-database &

# Connect with psql
psql -h localhost -U app -d appdb
```

---

### 📋 Getting Started Documents
```
SETUP_COMPLETE.md          👈 START HERE - Complete setup guide
QUICK_REFERENCE.md         👈 Quick commands cheat sheet
```

### ⚙️ Configuration
```
config/
└── environment-variables.sh   - Bash environment configuration
    - Resource names with random suffix
    - AKS settings (version, VM sizes)
    - Storage configuration (IOPS, throughput)
    - PostgreSQL parameters
    - Auto-detect public IP for firewall
```

### 🚀 Deployment Scripts
```
scripts/
├── 02-create-infrastructure.sh         - Creates Azure resources (RG, AKS, Storage, Identity)
├── 03-configure-workload-identity.sh   - Sets up federated credentials
├── 04-deploy-cnpg-operator.sh          - Installs CloudNativePG via Helm
├── 05-deploy-postgresql-cluster.sh     - Deploys PostgreSQL cluster + services
├── 06-configure-monitoring.sh          - Configures Grafana + Azure Monitor
├── 07-test-pgbench.sh                  - Verifies pgbench functionality in cluster
└── deploy-all.sh                       - Master orchestration script
```

### ⚙️ Kubernetes Reference
```
kubernetes/
└── postgresql-cluster.yaml - Reference manifest (NOT used in deployment)
    - See scripts/05-deploy-postgresql-cluster.sh for actual deployment
    - Configuration values loaded from environment variables
```

### 📚 Documentation
```
docs/
└── README.md               - Comprehensive full documentation
    - Prerequisites
    - Quick start
    - Configuration guide
    - Monitoring setup
    - Backup procedures
    - Troubleshooting

.github/
└── copilot-instructions.md - AI assistant guidance
    - Project context
    - File purposes
    - Development guidelines
```

---

## 🎓 How to Use This Project

### Phase 1: Understanding (10 mins)
1. Read `SETUP_COMPLETE.md` - Overview and prerequisites
2. Review `QUICK_REFERENCE.md` - Command reference
3. Skim `docs/README.md` - Full capabilities

### Phase 2: Preparation (15 mins)
1. Verify prerequisites installed (az, kubectl, helm, jq)
2. Update `config/environment-variables.sh`
3. Change PostgreSQL password in environment variables
4. Verify region support for Premium v2

### Phase 3: Deployment (20 mins)
1. Load environment: `source config/environment-variables.sh`
2. Run `./scripts/deploy-all.sh`
3. Monitor deployment progress (6 automated steps)
4. Verify cluster health

### Phase 4: Validation (10 mins)
1. Check pods are running
2. Test PostgreSQL connection
3. Verify backups to storage
4. Access Grafana dashboard
5. Run pgbench test: `./scripts/07-test-pgbench.sh`

### Phase 5: Operation (Ongoing)
1. Monitor cluster metrics
2. Test backup/restore
3. Scale as needed
4. Apply updates

---

## 📊 What Gets Deployed

### Azure Resources
- ✅ Resource Group
- ✅ Virtual Network (10.0.0.0/8)
- ✅ Network Security Group
- ✅ AKS Cluster (1.32)
  - System node pool: 2 x Standard_D2s_v5
  - Postgres node pool: 3 x Standard_D4s_v5
- ✅ Managed Identity (Workload Identity)
- ✅ Storage Account (ZRS, Standard_V2)
- ✅ Log Analytics Workspace
- ✅ Managed Grafana Instance

### Kubernetes Resources
- ✅ CNPG Operator (cnpg-system namespace)
- ✅ PostgreSQL Cluster (cnpg-database namespace)
  - 3 PostgreSQL instances (48 GiB RAM, 6 vCPU each)
  - 200GB data storage per instance
  - Premium SSD v2 disks (40,000 IOPS, 1,250 MB/s per disk)
  - Expected performance: 8,000-10,000 TPS sustained
- ✅ StorageClass (managed-csi-premium-v2)
- ✅ Services (read-write, read-only)
- ✅ ConfigMaps & Secrets
- ✅ PersistentVolumeClaims

### Features Enabled
- ✅ High Availability (automatic failover)
- ✅ Zone Redundancy (across 3 AZs)
- ✅ Workload Identity (secure auth)
- ✅ Backup to Azure Storage
- ✅ Point-in-Time Recovery (7 days)
- ✅ WAL compression (lz4)
- ✅ Monitoring (Prometheus + Grafana)
- ✅ Health checks (automatic)

---

## 🔐 Security Features

| Feature | Implementation |
|---------|----------------|
| **Authentication** | Workload Identity + SCRAM-SHA-256 |
| **Network** | NSGs + Network Policies (Cilium) |
| **Secrets** | No hardcoded secrets in pods |
| **RBAC** | Kubernetes + Azure RBAC enabled |
| **Encryption** | Storage encrypted at rest |
| **Backups** | No public access, encrypted |
| **Isolation** | Dedicated namespaces |

---

## 💾 Storage Options

### Premium SSD v2 (Default - Optimized for High Performance)
- **IOPS**: 40,000 per disk (configurable 3,100-80,000)
- **Throughput**: 1,250 MB/s per disk (configurable 125-1,200 MB/s)
- **Capacity**: 200 GiB per instance
- **Benefits**: Excellent price-performance for high-TPS workloads (8-10K TPS)
- **Regions**: swedencentral, westeurope, eastus, canadacentral, etc.

### Premium SSD (Alternative)
- **IOPS**: Fixed per disk size (lower than Premium v2)
- **Throughput**: Fixed per disk size (lower than Premium v2)
- **Benefits**: Widely available, proven performance
- **Tradeoff**: Less cost-efficient and lower IOPS than Premium v2

### Local NVMe (Ultra-High Performance - Future Migration)
- **IOPS**: 400K+ per disk (Standard_L8s_v3)
- **Throughput**: 2,000+ MB/s
- **Benefits**: Sub-millisecond latency, 50K+ TPS capability
- **Tradeoff**: Requires Azure Container Storage, higher cost
- **Use Case**: Extreme transactional workloads (see Step 5 documentation)

---

## 🔧 Configuration Overview

### Key Parameters to Adjust

**In `config/environment-variables.sh`:**
```bash
# Azure settings
PRIMARY_CLUSTER_REGION="swedencentral"
AKS_CLUSTER_VERSION="1.32"

# VM sizes (Standard_E8as_v6: 8 vCPU, 64 GiB RAM, AMD EPYC 9004 @ 3.7 GHz)
SYSTEM_NODE_POOL_VMSKU="Standard_D2s_v5"
USER_NODE_POOL_VMSKU="Standard_E8as_v6"

# Storage (Premium SSD v2 - Optimized for 10K TPS)
DISK_IOPS="40000"              # Max Premium SSD v2 IOPS
DISK_THROUGHPUT="1250"         # Max Premium SSD v2 throughput (MB/s)
PG_STORAGE_SIZE="200Gi"        # Increased for better performance

# PostgreSQL (Optimized for Standard_E8as_v6)
PG_DATABASE_NAME="appdb"
PG_DATABASE_USER="app"
PG_DATABASE_PASSWORD="SecurePassword123!"  # Change this!
PG_MEMORY="48Gi"               # 75% of 64 GiB available on E8as_v6
PG_CPU="6"                     # 75% of 8 vCPUs available on E8as_v6

# CNPG version (Operator 1.27.1)
CNPG_VERSION="0.26.1"
```

**All configuration is centralized in environment variables** - no need to edit multiple files.

---

## 📈 Monitoring & Observability

### Azure Monitor
- Application Insights integration
- Container Insights (AKS logs)
- Performance metrics

### Prometheus + Grafana
- PostgreSQL metrics via PodMonitor
- Cluster health dashboards
- Performance visualization
- Alert capabilities

### Key Metrics
```
pg_up                                   # Database health
pg_stat_replication_lag_bytes            # Replication lag
pg_database_size_bytes                   # Database size
pg_wal_archive_status                    # Backup status
node_memory_MemAvailable_bytes           # Node memory
```

---

## 🚨 Critical Prerequisites

### Tools
- Azure CLI (v2.56+)
- kubectl (v1.21+)
- Helm (v3.0+)
- jq (v1.5+)
- OpenSSL (v3.3+)
- Krew + CNPG plugin

### Azure Requirements
- Subscription with appropriate quota
- Permissions: Owner or User Access Administrator
- Region with Premium v2 support

### Before Deployment
- [ ] Change default passwords
- [ ] Verify region support
- [ ] Check subscription quota
- [ ] Update managed identity references
- [ ] Review cost implications

---

## ✅ Deployment Checklist

Before deployment:
- [ ] Prerequisites installed
- [ ] Configuration reviewed
- [ ] Passwords changed
- [ ] Region selected
- [ ] Quota verified

After deployment:
- [ ] Cluster created
- [ ] Pods running (3 PostgreSQL instances)
- [ ] Storage provisioned
- [ ] Backups to storage
- [ ] Grafana accessible
- [ ] Connection successful

---

## 📞 Support & Troubleshooting

### Quick Diagnostics
```bash
# Check operator
kubectl logs -n cnpg-system deployment/cnpg-cloudnative-pg

# Check cluster status
kubectl cnpg status pg-primary -n cnpg-database

# Check storage
kubectl get pvc -n cnpg-database

# Check backups
az storage blob list --account-name <account> --container-name backups

# Test performance
./scripts/07-test-pgbench.sh
```

### Common Issues
1. **Pods stuck in Init**: Check PVC binding and storage quota
2. **WAL archiving fails**: Verify managed identity permissions
3. **Operator not deploying**: Check Helm repository and CRDs
4. **Premium v2 unavailable**: Check region support

See `docs/README.md` for detailed troubleshooting.

---

## 📚 Learning Path

1. **Understand the basics**
   - Read: SETUP_COMPLETE.md
   - Review: docs/README.md

2. **Explore configuration**
   - Edit: config/deployment-config.json
   - Review: kubernetes/postgresql-cluster.yaml

3. **Deploy to Azure**
   - Run: scripts/deploy-postgresql-ha.sh
   - Monitor: kubectl commands

4. **Test operations**
   - Connect to database
   - Create backups
   - Test failover
   - Monitor metrics

5. **Advanced topics**
   - Scale cluster
   - Update PostgreSQL
   - Performance tuning
   - Backup management

---

## 🎯 Success Criteria

Your deployment is successful when:
- ✅ 3 PostgreSQL pods running
- ✅ Primary pod shows "Primary" status
- ✅ Replica pods show "Standby (sync)"  
- ✅ WAL archiving shows "OK"
- ✅ Backups present in storage
- ✅ Can connect via psql
- ✅ Grafana dashboard accessible
- ✅ All PVCs bound and sized correctly

---

## 🔗 Important Links

- **CloudNativePG**: https://cloudnative-pg.io/
- **Azure AKS**: https://learn.microsoft.com/azure/aks/
- **Premium v2 Disks**: https://learn.microsoft.com/azure/virtual-machines/disks-types
- **Well-Architected Framework**: https://learn.microsoft.com/azure/architecture/framework/

---

## 📝 Version Information

**Project Version**: 1.0  
**Created**: October 2025  
**AKS Version**: 1.32  
**Kubernetes Version**: 1.32  
**CNPG Version**: 1.27.1  
**PostgreSQL Version**: 17.0  
**PostgreSQL Version**: 16  
**Status**: ✅ Production Ready

---

**Ready to deploy?** Start with `SETUP_COMPLETE.md` 🚀
