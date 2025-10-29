# Pre-Deployment Checklist ✅

**Date:** October 28, 2025  
**Status:** Ready for Deployment

---

## ✅ Validation Complete

### What Was Validated:
- ✅ All deployment scripts (02-06, deploy-all.sh) syntax validated
- ✅ Environment variable auto-generation working
- ✅ DevContainer configuration updated with shellcheck
- ✅ Documentation updated to reflect correct deployment workflow
- ✅ Incompatible scripts removed (deploy-postgresql-ha.sh with Bicep dependency)

### Cleaned Up:
- ❌ Removed `scripts/deploy-postgresql-ha.sh` (expected Bicep, project uses Azure CLI)
- ❌ Removed `scripts/deploy-postgresql-ha.ps1` (not compatible with this project)
- ❌ Removed `config/deployment-config.json` (not used by this project)

---

## 🚀 Ready to Deploy!

### Current Project Architecture:
- **Deployment Method:** Azure CLI (via bash scripts)
- **Configuration:** `config/environment-variables.sh` loaded by scripts
- **Auto-generated:** `.env` file with unique resource names
- **Orchestration:** `scripts/deploy-all.sh` runs 7 deployment phases

---

## Pre-Deployment Steps

### 1. Load Environment Variables
```bash
cd /workspaces/azure-postgresql-ha-aks-workshop

# Load auto-generated variables
source .env

# Verify
echo "Resource Group: $RESOURCE_GROUP_NAME"
echo "AKS Cluster: $AKS_PRIMARY_CLUSTER_NAME"
echo "Region: $PRIMARY_CLUSTER_REGION"
```

**Expected Output:**
```
Resource Group: rg-cnpg-ik7wnien
AKS Cluster: aks-primary-cnpg-ik7wnien
Region: swedencentral
```

### 2. Change PostgreSQL Password (CRITICAL)
```bash
export PG_DATABASE_PASSWORD="YourVerySecurePassword123!"

# Verify
echo "Password set: ${PG_DATABASE_PASSWORD:0:3}***"
```

### 3. Authenticate to Azure
```bash
az login

# Verify
az account show --query "{Subscription:name, ID:id}" -o table
```

### 4. Review Configuration
```bash
# Check key settings
echo "=== Deployment Configuration ==="
echo "Resource Group: $RESOURCE_GROUP_NAME"
echo "Region: $PRIMARY_CLUSTER_REGION"
echo "AKS Version: $AKS_CLUSTER_VERSION"
echo "System Node VM: $SYSTEM_NODE_POOL_VMSKU"
echo "User Node VM: $USER_NODE_POOL_VMSKU"
echo "PostgreSQL Version: 16"
echo "Instances: 3 (1 primary + 2 replicas)"
echo "Storage Class: Premium SSD v2"
echo "IOPS: $DISK_IOPS"
echo "Throughput: ${DISK_THROUGHPUT} MB/s"
echo "================================="
```

---

## Deployment Command

```bash
# Run the master deployment script
bash scripts/deploy-all.sh
```

---

## What Will Be Deployed

### Phase 1: Infrastructure (script 02)
- Resource Group: `$RESOURCE_GROUP_NAME`
- Managed Identity: `$AKS_UAMI_CLUSTER_IDENTITY_NAME`
- Storage Account: `$PG_PRIMARY_STORAGE_ACCOUNT_NAME`
- AKS Cluster: `$AKS_PRIMARY_CLUSTER_NAME`
  - System node pool: Standard_D2s_v5
  - User node pool: Standard_E8as_v6 (labeled for PostgreSQL)
- Log Analytics: `$ALA_PRIMARY`
- Azure Monitor Workspace: `$AMW_PRIMARY`
- Managed Grafana: `$GRAFANA_PRIMARY`

### Phase 2: Workload Identity (script 03)
- Federated credential for PostgreSQL backups
- RBAC assignment: Storage Blob Data Contributor
- Service account configuration

### Phase 3: CNPG Operator (script 04)
- Helm repository: cloudnative-pg
- Namespace: `cnpg-system`
- Operator version: Latest stable

### Phase 4: PostgreSQL Cluster (script 05)
- Cluster name: `$PG_PRIMARY_CLUSTER_NAME`
- Namespace: `cnpg-database`
- Instances: 3 (1 primary + 2 sync replicas)
- PostgreSQL version: 16
- Storage: Premium SSD v2 (4000 IOPS, 250 MB/s)
- Memory per pod: 8GB
- CPU per pod: 2 cores
- Backup: Azure Blob Storage with 7-day retention
- WAL compression: lz4

### Phase 5: Monitoring (script 06)
- Prometheus integration
- Grafana dashboards
- Azure Monitor integration
- Container insights

---

## Estimated Deployment Time

- **Phase 1 (Infrastructure):** 10-15 minutes
- **Phase 2 (Workload Identity):** 2-3 minutes
- **Phase 3 (CNPG Operator):** 2-3 minutes
- **Phase 4 (PostgreSQL Cluster):** 5-7 minutes
- **Phase 5 (Monitoring):** 3-5 minutes

**Total: ~25-35 minutes**

---

## Post-Deployment Verification

### 1. Check Cluster Status
```bash
kubectl cnpg status $PG_PRIMARY_CLUSTER_NAME -n $PG_NAMESPACE
```

**Expected:** 3 instances running, 1 primary, 2 replicas streaming

### 2. Check Pods
```bash
kubectl get pods -n $PG_NAMESPACE
```

**Expected:** 3 pods in Running state

### 3. Check Services
```bash
kubectl get svc -n $PG_NAMESPACE
```

**Expected:** 
- `<cluster>-rw` (read-write to primary)
- `<cluster>-ro` (read-only to replicas)
- `<cluster>-r` (read to any)

### 4. Test Connection
```bash
kubectl port-forward svc/${PG_PRIMARY_CLUSTER_NAME}-rw 5432:5432 -n $PG_NAMESPACE &
psql -h localhost -U $PG_DATABASE_USER -d $PG_DATABASE_NAME -c '\l'
```

### 5. Verify Backups
```bash
# Check WAL archiving
kubectl logs -n $PG_NAMESPACE ${PG_PRIMARY_CLUSTER_NAME}-1 | grep -i "wal"

# Check storage account
az storage blob list \
  --account-name $PG_PRIMARY_STORAGE_ACCOUNT_NAME \
  --container-name $PG_STORAGE_BACKUP_CONTAINER_NAME \
  --output table
```

### 6. Access Grafana
```bash
# Get Grafana URL (displayed at end of deployment)
az grafana show \
  --name $GRAFANA_PRIMARY \
  --resource-group $RESOURCE_GROUP_NAME \
  --query "properties.endpoint" \
  --output tsv
```

---

## Troubleshooting

### If deployment fails at Phase 1:
- Check Azure quota in region
- Verify Premium SSD v2 availability in region
- Check AKS version availability: `az aks get-versions --location $PRIMARY_CLUSTER_REGION -o table`

### If deployment fails at Phase 4:
- Check storage class: `kubectl get storageclass`
- Check CNPG operator logs: `kubectl logs -n cnpg-system deployment/cnpg-cloudnative-pg`
- Verify managed identity: `az identity show --name $AKS_UAMI_CLUSTER_IDENTITY_NAME --resource-group $RESOURCE_GROUP_NAME`

### If PostgreSQL pods won't start:
- Check PVC binding: `kubectl get pvc -n $PG_NAMESPACE`
- Check node labels: `kubectl get nodes --show-labels | grep postgres`
- Check events: `kubectl get events -n $PG_NAMESPACE --sort-by='.lastTimestamp'`

---

## Cleanup (if needed)

```bash
# Delete the entire resource group
az group delete --name $RESOURCE_GROUP_NAME --yes --no-wait

# Or keep infrastructure, just delete PostgreSQL
kubectl delete cluster $PG_PRIMARY_CLUSTER_NAME -n $PG_NAMESPACE
```

---

## Cost Estimate (Approximate)

Based on Sweden Central region:

- **AKS:** ~$150/month (2 D2s_v5 + 3 D4s_v5 nodes)
- **Premium SSD v2:** ~$30/month (3x 32GB @ 4000 IOPS)
- **Storage Account:** ~$2/month (ZRS)
- **Log Analytics:** ~$10/month (500MB ingestion estimate)
- **Grafana:** ~$20/month (managed instance)

**Total: ~$212/month** (varies by region and actual usage)

💡 **Cost Optimization:**
- Use Standard SSD instead of Premium v2: Save ~50%
- Reduce node count after testing
- Use Spot instances for dev/test
- Adjust Log Analytics retention

---

## Security Recommendations

✅ **Already Implemented:**
- Workload Identity (no secrets in pods)
- SCRAM-SHA-256 password authentication
- Network isolation via Kubernetes namespaces
- Encrypted backups at rest (Azure Storage encryption)
- RBAC on AKS and storage

⚠️ **Additional Steps (Optional):**
- Enable Azure Key Vault for password management
- Configure NSG rules for AKS
- Enable Azure Policy for governance
- Set up Private Link for AKS API server
- Configure Azure Firewall for egress filtering

---

## Documentation Reference

- **Setup Guide:** `SETUP_COMPLETE.md`
- **Quick Commands:** `QUICK_REFERENCE.md`
- **Detailed Docs:** `docs/README.md`
- **GitHub Copilot:** `.github/copilot-instructions.md`

---

## Final Checklist Before Running deploy-all.sh

- [ ] Environment variables loaded (`source .env`)
- [ ] PostgreSQL password changed (`export PG_DATABASE_PASSWORD="..."`)
- [ ] Logged into Azure (`az login`)
- [ ] Correct subscription selected
- [ ] Region supports Premium SSD v2
- [ ] AKS version 1.32 available (or changed in config)
- [ ] Sufficient Azure quota in region
- [ ] Network connectivity stable
- [ ] Terminal session won't timeout (use screen/tmux for long deployments)

---

**Ready to deploy?**

```bash
bash scripts/deploy-all.sh
```

🎉 **Good luck with your deployment!**
