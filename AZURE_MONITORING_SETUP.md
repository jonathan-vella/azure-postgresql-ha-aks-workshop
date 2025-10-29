# Quick Setup Guide - Azure Monitor + Grafana for CNPG

## ✅ What's Already Configured

### Azure Resources Created
- ✅ **Azure Monitor Workspace**: `amw-cnpg-987kr2cs`
- ✅ **Azure Managed Grafana**: `grafana-cnpg-987kr2cs`
- ✅ **AKS Cluster**: `aks-primary-cnpg-987kr2cs` with Azure Monitor addon enabled
- ✅ **CloudNativePG**: PostgreSQL 18.0 cluster with 3 instances (1 primary + 2 replicas)

### Monitoring Configuration Applied
- ✅ **Azure Monitor agents** running in `kube-system` namespace
- ✅ **Custom scrape config** for CNPG metrics (load test + failover focused)
- ✅ **Metric collection** from PostgreSQL pods and CNPG operator
- ✅ **Grafana data source** connected to Azure Monitor Workspace

### Metrics Being Collected

**Load Testing Metrics:**
- `cnpg_transactions_total` - Transaction rate (TPS)
- `cnpg_backends_total` - Active connections
- `cnpg_pg_database_size_bytes` - Database size

**Failover Metrics:**
- `cnpg_collector_up` - Instance health status
- `cnpg_pg_replication_lag` - Replication lag per replica
- `cnpg_collector_sync_replicas` - Synchronous replica count
- `cnpg_collector_fencing_on` - Fencing status
- `cnpg_collector_manual_switchover_required` - Switchover flag

**Backup/Recovery Metrics:**
- `cnpg_collector_pg_wal_archive_status` - WAL archiving status

## 🚀 Next Steps - Import Dashboard to Grafana

### Step 1: Copy the Dashboard JSON

```bash
# Display the dashboard JSON
cat /workspaces/azure-postgresql-ha-aks-workshop/grafana-cnpg-ha-dashboard.json
```

### Step 2: Access Azure Managed Grafana

```bash
# Get Grafana endpoint URL
az grafana show \
  --name grafana-cnpg-987kr2cs \
  --resource-group rg-cnpg-987kr2cs \
  --query properties.endpoint -o tsv

# Expected output: https://grafana-cnpg-987kr2cs-d2afemdffefvgyb0.cse.grafana.azure.com
```

### Step 3: Import Dashboard

1. Open Grafana URL in browser (Azure AD authentication)
2. Click **"+"** (Create) → **"Import"**
3. **Option A**: Upload `grafana-cnpg-ha-dashboard.json`
   - Click "Upload JSON file"
   - Select the file from `/workspaces/azure-postgresql-ha-aks-workshop/`
   
   **Option B**: Paste JSON directly
   - Copy entire JSON content from terminal
   - Paste into "Import via panel json"

4. Select data source: **"Managed_Prometheus_amw-cnpg-987kr2cs"**
5. Click **"Import"**

### Step 4: Verify Dashboard

Dashboard should show:
- ✅ 3 instances in "UP" status (green)
- ✅ Current primary instance identified
- ✅ Cluster availability: 3/3 instances
- ✅ Replication lag < 1 second for replicas
- ✅ Transaction rate near 0 (idle state)
- ✅ WAL Archive Status: OK (green)

**If panels show "No data"**: Wait 5-10 minutes for metric propagation after Azure Monitor configuration was applied.

## 📊 Dashboard Overview

### 9 Panels for Load Testing & Failover

1. **Instance Health Status** - UP/DOWN per pod with role
2. **Current Primary Instance** - Which pod is primary
3. **Cluster Availability** - Count of healthy instances (3/3)
4. **Transaction Rate (TPS)** - Key load test metric
5. **Replication Lag** - Key failover metric (seconds)
6. **Active Connections** - Load test connection count
7. **WAL Archive Status** - Backup health
8. **Database Size** - Storage growth
9. **Synchronous Replicas** - HA configuration

### Automatic Annotations

- Red vertical lines mark **Primary Switchover Events**
- Automatically detected when primary instance changes
- Hover to see new primary pod name

## 🧪 Testing the Dashboard

### Quick Metric Verification

```bash
# Verify metrics are flowing to Azure Monitor
AMW_ENDPOINT=$(az monitor account show \
  --name amw-cnpg-987kr2cs \
  --resource-group rg-cnpg-987kr2cs \
  --query metrics.prometheusQueryEndpoint -o tsv)

TOKEN=$(az account get-access-token \
  --resource https://prometheus.monitor.azure.com \
  --query accessToken -o tsv)

# Query instance health
curl -s -H "Authorization: Bearer $TOKEN" \
  "${AMW_ENDPOINT}/api/v1/query?query=cnpg_collector_up" | jq '.data.result[] | {pod: .metric.pod, role: .metric.role, value: .value[1]}'

# Expected output: 3 pods with value="1"
```

### Load Test (Optional)

```bash
# Get primary pod
PRIMARY_POD=$(kubectl get pod -n cnpg-database \
  -l cnpg.io/instanceRole=primary \
  -o jsonpath='{.items[0].metadata.name}')

# Run pgbench load test (watch Transaction Rate panel)
kubectl exec -it -n cnpg-database $PRIMARY_POD -- bash -c "
  pgbench -i -s 10 app && \
  pgbench -c 5 -t 100 app
"
```

**Watch in dashboard:**
- Transaction Rate spikes (100-500+ TPS)
- Active Connections increases to 5
- Replication Lag may increase slightly (< 5s is normal)

### Failover Test (Optional)

```bash
# Delete primary to trigger failover (watch Current Primary panel)
kubectl delete pod -n cnpg-database $PRIMARY_POD

# Watch dashboard for:
# - Instance Health: Primary goes RED
# - Current Primary: Changes to new pod name
# - Annotation appears (red line)
# - Replication Lag: Spike then recovery
```

**Expected failover timeline:**
- T+10s: New primary elected
- T+15s: Annotation appears
- T+30s: Old pod recreated
- T+60s: Replication lag < 1s

## 🔧 Troubleshooting

### "No data" in dashboard panels

**Wait 5-10 minutes** - Metrics may still be propagating from Azure Monitor agents.

**Verify scrape config:**
```bash
kubectl get configmap -n kube-system ama-metrics-prometheus-config -o yaml | grep -A 5 "job_name: 'cnpg-postgres-ha'"
```

**Restart agents if needed:**
```bash
kubectl rollout restart deployment/ama-metrics -n kube-system
kubectl rollout restart deployment/ama-metrics-operator-targets -n kube-system
sleep 300  # Wait 5 minutes
```

### Variable dropdown empty

**Temporary fix** - Use custom variable:
1. Dashboard Settings → Variables → `pg_cluster`
2. Change Type to "Custom"
3. Custom options: `pg-primary-cnpg-987kr2cs`
4. Save

**Root cause**: Metrics haven't propagated yet. Check again in 5-10 minutes.

### Data source UID error

**Find correct UID:**
```bash
# This needs to be done in Grafana UI:
# Configuration → Data sources → Click your data source → Copy UID from URL
```

**Update dashboard:**
1. Dashboard Settings → JSON Model
2. Find `"uid": "managed-prometheus"`
3. Replace with actual UID
4. Save

## 📚 Documentation Files

- **GRAFANA_DASHBOARD_GUIDE.md** - Detailed dashboard usage, metric reference, testing procedures
- **scripts/06a-configure-azure-monitor-prometheus.sh** - Azure Monitor configuration script
- **grafana-cnpg-ha-dashboard.json** - Dashboard JSON for import

## 🎯 Success Criteria

✅ **Monitoring Fully Operational When:**
- Dashboard imported successfully
- All 9 panels showing data
- Variable dropdown populated with `pg-primary-cnpg-987kr2cs`
- Instance health shows 3/3 instances UP
- Replication lag < 1 second
- Can run load test and see metrics update in real-time
- Can trigger failover and see automatic annotation

## 💡 Key Differences from In-Cluster Monitoring

| Aspect | Azure-Native (Current) | In-Cluster (NOT Used) |
|--------|------------------------|----------------------|
| Prometheus | Azure Monitor Workspace | kube-prometheus-stack |
| Grafana | Azure Managed Grafana | In-cluster Grafana pod |
| Data Retention | 18 months | Limited by disk space |
| High Availability | Azure-managed | Requires manual setup |
| Cost | Pay-per-metric | Cluster resources |
| Access | Azure AD auth | Port-forward / Ingress |
| Backup | Automatic | Manual |
| Metric Label | `pg_cluster` | Could use `cluster` |

**Why Azure-native?**
- ✅ Production-grade HA and disaster recovery
- ✅ No operational overhead (managed service)
- ✅ Integration with Azure Monitor alerts and actions
- ✅ Long-term metric retention (18 months)
- ✅ Azure AD authentication and RBAC
- ✅ No cluster resources consumed

## 🚀 What You Can Do Now

1. **Import the dashboard** (follow Step 3 above)
2. **Run a load test** to see metrics in action
3. **Test a failover** to validate HA monitoring
4. **Create alerts** based on dashboard panels (optional)
5. **Share dashboard** with team members
6. **Customize panels** for your specific needs

---

**Next**: See **GRAFANA_DASHBOARD_GUIDE.md** for detailed usage instructions.
