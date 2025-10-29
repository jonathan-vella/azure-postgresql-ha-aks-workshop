# Azure PostgreSQL HA on AKS Workshop - Copilot Instructions

This project automates the deployment of a highly available PostgreSQL database on Azure Kubernetes Service (AKS) using CloudNativePG operator with Premium v2 disk storage.

## Project Overview

- **Language**: Azure CLI (Infrastructure), YAML (Kubernetes), Bash (Scripts)
- **Primary Purpose**: Automation framework for PostgreSQL HA on AKS following Microsoft reference implementation
- **Key Technologies**:
  - Azure Kubernetes Service (AKS)
  - CloudNativePG Operator
  - Premium SSD v2 Disks
  - Azure Blob Storage for Backups
  - Azure Monitor + Grafana for Observability
  - Workload Identity with Federated Credentials

## Project Structure

```
├── config/                  # Configuration files
│   └── environment-variables.sh    # Bash environment configuration
├── scripts/                 # Deployment automation (Azure CLI)
│   ├── 02-create-infrastructure.sh         # Creates Azure resources
│   ├── 03-configure-workload-identity.sh   # Federated credentials
│   ├── 04-deploy-cnpg-operator.sh          # Installs CNPG operator
│   ├── 04a-install-barman-cloud-plugin.sh  # Installs Barman plugin for backups
│   ├── 04b-install-prometheus-operator.sh  # Installs Prometheus for metrics
│   ├── 05-deploy-postgresql-cluster.sh     # Deploys PostgreSQL HA
│   ├── 06-configure-monitoring.sh          # Configures observability
│   ├── 07-display-connection-info.sh       # Shows connection endpoints
│   └── deploy-all.sh                       # Master orchestration
├── kubernetes/              # Kubernetes manifests
│   └── postgresql-cluster.yaml  # Reference manifest (not used in deployment)
└── docs/                    # Documentation
    └── README.md
```

## Key Files and Their Purposes

### Environment Configuration (`config/environment-variables.sh`)
- All Azure resource configuration centralized
- Resource names with random 8-character suffix
- AKS settings (version, VM SKUs, zones)
- Storage configuration (Premium v2 IOPS, throughput)
- PostgreSQL credentials and parameters
- Auto-detects public IP for AKS API access

### Deployment Scripts (Azure CLI)
- **02-create-infrastructure**: Creates RG, Storage, Identity, AKS, Monitoring, Bastion, NAT Gateway
- **03-configure-workload-identity**: Sets up federated credentials for backup access
- **04-deploy-cnpg-operator**: Installs CloudNativePG via Helm
- **04a-install-barman-cloud-plugin**: Installs Barman Cloud Plugin v0.8.0
- **04b-install-prometheus-operator**: Installs Prometheus Operator for PodMonitor support
- **05-deploy-postgresql-cluster**: Deploys PostgreSQL HA cluster with Premium v2 storage + PgBouncer + PodMonitor
- **06-configure-monitoring**: Configures Grafana + Azure Monitor integration
- **07-display-connection-info**: Shows connection endpoints and credentials
- **deploy-all**: Master orchestration script (8 steps: 2, 3, 4, 4a, 4b, 5, 6, 7)
- Bash scripts only (DevContainer runs on Linux)

### Kubernetes Manifests (`kubernetes/postgresql-cluster.yaml`)
- Reference manifest showing cluster structure
- **NOT used in actual deployment** (configuration embedded in scripts)
- PostgreSQL cluster, services, and storage class are created by script 05

## Development Guidelines

### When Adding Features

1. **Infrastructure Changes**: Update appropriate script in `scripts/02-create-infrastructure.sh`
2. **Kubernetes Changes**: Update `scripts/05-deploy-postgresql-cluster.sh` (cluster definition embedded)
3. **Configuration Changes**: Update `config/environment-variables.sh`
4. **Script Updates**: All scripts are bash-only (DevContainer environment)

### Best Practices for This Project

1. **Always use Premium v2 disks** for PostgreSQL storage (not Standard SSDs)
2. **Maintain 3-node topology** for high availability (1 primary + 2 replicas)
3. **Use availability zones** for zone redundancy
4. **Enable Workload Identity** for Azure integration (no secrets in pods)
5. **Configure backup retention** for disaster recovery (minimum 7 days)
6. **Monitor WAL archiving** - critical for backup reliability

### Azure Well-Architected Framework Alignment

- **Reliability**: Multi-zone deployment, auto-failover, backup/recovery
- **Security**: Workload Identity, NSGs, SCRAM-SHA-256 authentication
- **Performance**: Premium v2 disks with configurable IOPS/throughput, tuned PostgreSQL parameters
- **Cost**: Premium v2 (better price-performance than Premium SSD), right-sized VMs, configurable resources
- **Operations**: Azure Monitor, Grafana dashboards, CNPG observability, automated deployment

## Common Tasks

### Deploy Full Stack
```bash
# Load environment variables
source config/environment-variables.sh

# Deploy all components (6 automated steps)
./scripts/deploy-all.sh
```

### Test PostgreSQL Connection
```bash
kubectl port-forward svc/pg-primary-rw 5432:5432 -n cnpg-database
psql -h localhost -U app -d appdb
```

### Check Cluster Health
```bash
kubectl cnpg status pg-primary -n cnpg-database
```

### Create Backup
```bash
kubectl apply -f kubernetes/backup-ondemand.yaml -n cnpg-database
```

## Troubleshooting

### CNPG Operator Not Deploying
- Check Helm repository: `helm repo update cnpg`
- Verify namespace exists: `kubectl get namespace cnpg-system`
- Check operator logs: `kubectl logs -n cnpg-system deployment/cnpg-cloudnative-pg`

### PostgreSQL Pods Stuck in Init
- Check PVC binding: `kubectl get pvc -n cnpg-database`
- Verify storage class: `kubectl get storageclass`
- Check storage quota in the region

### WAL Archiving Failing
- Verify managed identity has Storage Blob Data Contributor role
- Check federated credential: `az identity federated-credential list ...`
- Review pod logs: `kubectl logs -n cnpg-database <pod-name>`

### Premium v2 Disks Not Available
- Check region support: Premium v2 available in limited regions
- Verify VM SKUs support the region
- Consider alternative regions or storage types

## Documentation Policy: MINIMAL & ESSENTIAL ONLY

**DO NOT create new documentation files unless explicitly requested.** This project has comprehensive documentation covering all use cases.

### Existing Documentation (Use These)
- **README.md** - Main entry point, quick start, deployment overview
- **.devcontainer/README.md** - DevContainer setup and usage
- **docs/README.md** - Detailed PostgreSQL HA deployment guide
- **QUICK_REFERENCE.md** - Common commands and troubleshooting
- **SETUP_COMPLETE.md** - Getting started after setup
- **.github/copilot-instructions.md** - This file

### When to Create a New Document
Only create a new document if:
1. ✅ **Explicitly requested** by user
2. ✅ **Required for functionality** (e.g., configuration file needed by scripts)
3. ✅ **No existing document** covers the topic
4. ✅ **High value and reusable** for multiple team members

### When NOT to Create a Document
❌ Comparison tables/guides (use existing docs, add to README)  
❌ Duplicate information (consolidate instead)  
❌ Step-by-step guides (add to existing README or QUICK_REFERENCE.md)  
❌ "Best practices" guides (reference external Microsoft docs)  
❌ Optional enhancement guides (user can request if needed)  

### Document Maintenance
- Keep documentation DRY (Don't Repeat Yourself)
- Update existing files rather than creating new ones
- Remove outdated documentation when replaced
- Consolidate related information

### Current Documentation Status
✅ Complete and sufficient for all use cases  
✅ No additional documents needed at this time  
✅ Focus on code quality, not documentation volume

---

## References

- [CloudNativePG Documentation](https://cloudnative-pg.io/)
- [Azure AKS PostgreSQL HA Deployment](https://learn.microsoft.com/en-us/azure/aks/postgresql-ha-overview)
- [Premium SSD v2 in Azure](https://learn.microsoft.com/en-us/azure/virtual-machines/disks-types#premium-ssd-v2)
- [Azure Well-Architected Framework](https://learn.microsoft.com/en-us/azure/architecture/framework/)

## Important Notes

- **Before Deploying**: Ensure Azure subscription has sufficient quota
- **Sensitive Data**: Change default PostgreSQL password in `kubernetes/postgresql-cluster.yaml`
- **Backup Validation**: Regularly test restore procedures
- **Monitoring Setup**: Ensure Grafana access is properly secured
- **Cost Monitoring**: Premium v2 disks have different pricing; set budget alerts

---

For detailed usage instructions, see `docs/README.md`.
