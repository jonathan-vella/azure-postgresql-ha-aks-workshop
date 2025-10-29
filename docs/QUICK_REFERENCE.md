# ⚡ Quick Reference Guide

**Version**: `v1.0.0` | **Last Updated**: October 2025

Your command cheat sheet for PostgreSQL HA on AKS operations.

---

## 📋 Files at a Glance

| File | Purpose |
|------|---------|
| `SETUP_COMPLETE.md` | Getting started guide |
| `docs/README.md` | Full documentation |
| `.github/copilot-instructions.md` | AI assistant guidance |
| `config/environment-variables.sh` | Bash environment configuration |
| `scripts/deploy-all.sh` | Master deployment orchestration |
| `scripts/02-create-infrastructure.sh` | Creates Azure resources |
| `scripts/05-deploy-postgresql-cluster.sh` | Deploys PostgreSQL HA cluster |
| `scripts/07-test-pgbench.sh` | Tests pgbench performance tool |
| `kubernetes/postgresql-cluster.yaml` | Reference manifest (not used in deployment) |

## 🚀 Quick Start Commands

### 1. Setup Prerequisites
```bash
chmod +x scripts/setup-prerequisites.sh
./scripts/setup-prerequisites.sh
```

### 2. Configure
```bash
# Edit environment variables
code config/environment-variables.sh
```

### 3. Deploy
```bash
# Load environment variables into current terminal session
# 'source' executes the script in the current shell context
source config/environment-variables.sh

# Deploy all components (7 automated steps)
./scripts/deploy-all.sh
```

> **Key Concept**: The command loads configuration into your active terminal session, making variables like `$RESOURCE_GROUP_NAME`, `$AKS_CLUSTER_VERSION`, and `$DISK_IOPS` available to deployment scripts. Without this step, scripts won't know what values to use.

## 🔍 Verify Deployment

```bash
# Get credentials
az aks get-credentials \
  --resource-group <rg-name> \
  --name <cluster-name>

# Check status
kubectl cnpg status pg-primary -n cnpg-database

# Watch pods
kubectl get pods -n cnpg-database -w

# View logs
kubectl logs -n cnpg-system deployment/cnpg-cloudnative-pg -f
```

## ⚙️ Key Configuration Values

Edit in `config/environment-variables.sh`:

### Node Pool
- **VM SKU**: `USER_NODE_POOL_VMSKU="Standard_E8as_v6"` (8 vCPU, 64 GB RAM)

### Storage (Premium v2 - High Performance)
- **IOPS**: `DISK_IOPS="40000"` (range: 3,100-80,000)
- **Throughput**: `DISK_THROUGHPUT="1250"` MB/s (range: 125-1,200 MB/s)
- **Size**: `PG_STORAGE_SIZE="200Gi"` per instance

### PostgreSQL
- **Instances**: 3 (1 primary + 2 replicas)
- **Version**: 17 (via CNPG operator)
- **Memory**: `PG_MEMORY="48Gi"` per instance (75% of 64 GB node RAM)
- **CPU**: `PG_CPU="6"` per instance (75% of 8 vCPU)
- **Max Connections**: 500 (direct PostgreSQL)
- **Pooled Connections**: 10,000 (via PgBouncer pooler)
- **Database**: `PG_DATABASE_NAME="appdb"`
- **User**: `PG_DATABASE_USER="app"`
- **Password**: `PG_DATABASE_PASSWORD` (change from default!)

### Performance
- **Expected TPS**: 8,000-10,000 sustained throughput
- **Failover Time**: <10 seconds (optimized from 30-60s default)
- **Replication**: Synchronous with RPO=0 (zero data loss)

### Backup
- **Retention**: 7 days (configurable in script 05)
- **Storage**: Azure Blob Storage (auto-created)
- **WAL Compression**: gzip
- **Container**: `PG_STORAGE_BACKUP_CONTAINER_NAME="backups"`

## 🔐 Security Checklist

- [ ] Change PostgreSQL password in `config/environment-variables.sh`
- [ ] Review auto-detected public IP for AKS API access
- [ ] Verify managed identity permissions (auto-configured)
- [ ] Review storage account access (auto-configured with Workload Identity)
- [ ] Set up additional RBAC for AKS cluster access if needed
- [ ] Review network security group rules (auto-created)

## 📊 Monitoring Commands

```bash
# Get cluster metrics
kubectl top nodes
kubectl top pods -n cnpg-database

# Check WAL archiving
kubectl cnpg status pg-primary 1 -n cnpg-database | grep "WAL"

# View backups
az storage blob list \
  --account-name <storage-account> \
  --container-name backups

# Check resource usage
kubectl describe nodes
```

## 🔄 Common Operations

### Test Connection

**Direct PostgreSQL connection** (admin tasks, bypasses pooler):
```bash
# Primary (read-write)
kubectl port-forward svc/pg-primary-rw 5432:5432 -n cnpg-database &
psql -h localhost -U app -d appdb

# Replicas (read-only)
kubectl port-forward svc/pg-primary-ro 5433:5432 -n cnpg-database &
psql -h localhost -p 5433 -U app -d appdb
```

**Pooled connection** (recommended for applications):
```bash
# Through PgBouncer pooler (supports 10K concurrent connections)
kubectl port-forward svc/pg-primary-pooler-rw 5432:5432 -n cnpg-database &
psql -h localhost -U app -d appdb
```

### Service Endpoints

Inside the cluster, applications can use:
- `pg-primary-rw.cnpg-database.svc.cluster.local:5432` - Direct primary (read-write)
- `pg-primary-ro.cnpg-database.svc.cluster.local:5432` - Direct replicas (read-only)
- `pg-primary-pooler-rw.cnpg-database.svc.cluster.local:5432` - **Pooled primary (recommended)**

### Check Pooler Status

```bash
# List pooler pods
kubectl get pods -n cnpg-database -l cnpg.io/poolerName=pg-primary-pooler-rw

# View pooler logs
kubectl logs -n cnpg-database -l cnpg.io/poolerName=pg-primary-pooler-rw

# Check pooler service
kubectl get svc pg-primary-pooler-rw -n cnpg-database

# PgBouncer stats (from inside pod)
kubectl exec -it -n cnpg-database <pooler-pod> -- \
  psql -U pooler -p 5432 pgbouncer -c "SHOW STATS"
```

### Test Performance
```bash
./scripts/07-test-pgbench.sh
```

### Create Manual Backup
```bash
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: backup-$(date +%s)
  namespace: cnpg-database
spec:
  method: barmanObjectStore
  cluster:
    name: pg-primary
EOF
```

### Scale Cluster
```bash
# Edit replicas
kubectl edit cluster pg-primary -n cnpg-database
# Change: instances: 3 → instances: 5

# Or via kubectl patch
kubectl patch cluster pg-primary -n cnpg-database \
  --type=merge \
  -p '{"spec":{"instances":5}}'
```

### View PostgreSQL Logs
```bash
kubectl logs -n cnpg-database <pod-name> -f
```

### Test Failover
```bash
# Get primary pod
PRIMARY=$(kubectl get pod -n cnpg-database \
  -l cnpg.io/instanceRole=primary \
  -o jsonpath='{.items[0].metadata.name}')

echo "Current primary: $PRIMARY"

# Delete it (simulate crash)
echo "Triggering failover..."
time kubectl delete pod $PRIMARY -n cnpg-database --grace-period=1

# Monitor status (watch for new primary election)
kubectl cnpg status pg-primary -n cnpg-database --watch

# Expected: 8-12 second failover time
```

### Manual Switchover (Planned Failover)
```bash
# Promote specific replica to primary (graceful switchover)
kubectl cnpg promote pg-primary <replica-pod-name> -n cnpg-database

# Example
kubectl cnpg promote pg-primary pg-primary-2 -n cnpg-database
```

## 🆘 Troubleshooting

### Pod Stuck in Init
```bash
kubectl describe pod -n cnpg-database <pod-name>
kubectl get pvc -n cnpg-database
```

### WAL Archiving Issues
```bash
# Check status
kubectl cnpg status pg-primary 1 -n cnpg-database | grep "WAL"

# Check pod logs for archive errors
kubectl logs -n cnpg-database pg-primary-1 | grep archive

# Verify storage account permissions
az role assignment list \
  --scope /subscriptions/{id}/resourceGroups/{rg}/providers/Microsoft.Storage/storageAccounts/{sa}
```

### Operator Issues
```bash
# Check operator logs
kubectl logs -n cnpg-system deployment/cnpg-cloudnative-pg

# Verify CRDs installed
kubectl get crd | grep postgresql

# Check operator pod
kubectl describe pod -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg
```

## 📝 Important Notes

1. **Change Passwords**: Default password is `SecurePassword123!` in environment variables
2. **Random Suffix**: Resource names get 8-character random suffix to avoid conflicts
3. **Backup Validation**: Regularly test restore procedures
4. **Cost Monitoring**: Set budget alerts for Premium v2 disks (configurable IOPS/throughput)
5. **Region Limitations**: Premium v2 available in select regions (canadacentral, eastus, etc.)
6. **Quota Checks**: Verify subscription quota before deploying
7. **Deployment Outputs**: Critical IDs saved to `.deployment-outputs` for subsequent scripts

## 🧹 Cleanup

```bash
# Delete resource group (removes everything)
az group delete --resource-group <rg-name> --no-wait --yes

# Or gradually:
kubectl delete namespace cnpg-database cnpg-system
az group delete --resource-group <rg-name>
```

## 📚 Resources

- **CloudNativePG**: https://cloudnative-pg.io/documentation/
- **AKS Docs**: https://learn.microsoft.com/azure/aks/
- **Premium v2**: https://learn.microsoft.com/azure/virtual-machines/disks-types
- **This Project**: See `docs/README.md`

---

**Need help?** Check `docs/README.md` for detailed instructions or review inline comments in source files.
