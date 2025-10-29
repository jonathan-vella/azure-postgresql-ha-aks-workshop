# ✅ Azure Monitor Configuration Complete - Next Steps

## 🎉 What's Been Configured

### Azure-Native Monitoring Stack (All Azure Services)
- ✅ **Azure Monitor Managed Prometheus** collecting CNPG metrics every 15 seconds
- ✅ **Azure Managed Grafana** connected to Prometheus data source
- ✅ **Custom scrape configuration** for load testing & failover metrics
- ✅ **9-panel dashboard JSON** ready for import

### Metrics Being Collected (Focused on Load Test & Failover)

**Load Testing:**
- `cnpg_transactions_total` → Transaction rate (TPS)
- `cnpg_backends_total` → Active database connections
- `cnpg_pg_database_size_bytes` → Database size growth

**Failover Monitoring:**
- `cnpg_collector_up` → Instance health (UP/DOWN)
- `cnpg_pg_replication_lag` → Replication lag per replica
- `cnpg_collector_sync_replicas` → Sync replica count
- `cnpg_collector_fencing_on` → Fencing status

**Backup/Recovery:**
- `cnpg_collector_pg_wal_archive_status` → WAL archiving health

## 📋 Import Dashboard to Grafana (3 Steps)

### Step 1: Open Grafana

**Your Grafana URL:**
```
https://grafana-cnpg-987kr2cs-d2afemdffefvgyb0.cse.grafana.azure.com
```

Click the link above or paste into browser → Azure AD authentication

### Step 2: Import Dashboard JSON

1. In Grafana, click **"+"** (Create menu) → **"Import"**
2. **Option A - Upload File:**
   - Click "Upload JSON file"
   - Select: `/workspaces/azure-postgresql-ha-aks-workshop/grafana-cnpg-ha-dashboard.json`
   
   **Option B - Copy/Paste:**
   - Copy the JSON from above terminal output (the entire JSON object)
   - Paste into "Import via panel json" text area

3. In "Import" form:
   - Dashboard name: `CloudNativePG - Load Testing & Failover Dashboard`
   - Select data source: **"Managed_Prometheus_amw-cnpg-987kr2cs"**
   - Click **"Import"**

### Step 3: Verify Dashboard

Dashboard should display:
- ✅ **Instance Health Status**: 3 instances showing "UP" (green)
- ✅ **Current Primary Instance**: One pod name displayed (blue)
- ✅ **Cluster Availability**: "3" (green) = 3/3 healthy
- ✅ **Replication Lag**: < 1 second for replicas
- ✅ **Transaction Rate**: Near 0 (idle cluster)
- ✅ **WAL Archive Status**: "OK" (green)

**If panels show "No data":**
- Wait 5-10 minutes for metric propagation (Azure Monitor agents just restarted)
- See troubleshooting section below

## 🧪 Test the Dashboard

### Quick Metric Verification (CLI)

```bash
# Get Azure Monitor endpoint
AMW_ENDPOINT=$(az monitor account show \
  --name amw-cnpg-987kr2cs \
  --resource-group rg-cnpg-987kr2cs \
  --query metrics.prometheusQueryEndpoint -o tsv)

# Get auth token
TOKEN=$(az account get-access-token \
  --resource https://prometheus.monitor.azure.com \
  --query accessToken -o tsv)

# Query instance health
curl -s -H "Authorization: Bearer $TOKEN" \
  "${AMW_ENDPOINT}/api/v1/query?query=cnpg_collector_up" \
  | jq '.data.result[] | {pod: .metric.pod, role: .metric.role, status: .value[1]}'

# Expected output: 3 pods, all with status="1" (UP)
```

### Load Test (Watch Transaction Rate Panel)

```bash
# Get primary pod
PRIMARY_POD=$(kubectl get pod -n cnpg-database \
  -l cnpg.io/instanceRole=primary \
  -o jsonpath='{.items[0].metadata.name}')

# Run pgbench load test
kubectl exec -it -n cnpg-database $PRIMARY_POD -- bash -c "
  pgbench -i -s 10 app && \
  pgbench -c 5 -t 100 app
"

# Watch in Grafana dashboard:
# - Transaction Rate: Spikes to 100-500+ TPS
# - Active Connections: Increases to 5
# - Replication Lag: May increase to 1-5 seconds (normal under load)
```

### Failover Test (Watch Current Primary & Replication Lag)

```bash
# Delete primary pod to trigger failover
kubectl delete pod -n cnpg-database $PRIMARY_POD

# Watch in Grafana dashboard:
# - Instance Health: Primary goes RED, then recovers
# - Current Primary: Changes to new pod name
# - Red annotation line appears on graphs
# - Replication Lag: Spikes then returns to < 1s
# - Cluster Availability: May briefly drop to 2/3, then 3/3
```

**Expected failover timeline:**
- T+10s: New primary elected
- T+15s: Red annotation appears on graphs
- T+30s: Deleted pod recreated
- T+60s: Replication lag returns to < 1s

## 🔧 Troubleshooting

### "No data" in dashboard panels

**Wait 5-10 minutes** first - metrics may still be propagating.

**Then verify agents are running:**
```bash
kubectl get pods -n kube-system -l rsName=ama-metrics

# Expected: 2 pods in Running state
# ama-metrics-xxxxxxx-xxxxx      2/2     Running
# ama-metrics-xxxxxxx-xxxxx      2/2     Running
```

**Check scrape configuration:**
```bash
kubectl get configmap -n kube-system ama-metrics-prometheus-config -o yaml | grep "job_name:"

# Expected output should include:
# - job_name: 'cnpg-postgres-ha'
```

**Restart agents if needed:**
```bash
kubectl rollout restart deployment/ama-metrics -n kube-system
sleep 300  # Wait 5 minutes for metrics to propagate
```

### Variable dropdown empty

**Temporary workaround:**
1. Dashboard Settings → Variables → `pg_cluster`
2. Change Type to "Custom"
3. Custom options: `pg-primary-cnpg-987kr2cs`
4. Save dashboard

**This happens when:** Metrics haven't propagated yet. Try again in 5-10 minutes.

### Data source UID mismatch

**Symptoms:** Panels show "Data source not found"

**Fix:**
1. Configuration → Data sources → Click your Prometheus data source
2. Copy UID from URL (e.g., `abcd1234`)
3. Dashboard Settings → JSON Model
4. Find/replace `"uid": "managed-prometheus"` with `"uid": "abcd1234"`
5. Save dashboard

## 📚 Documentation Files

All documentation is located in `/workspaces/azure-postgresql-ha-aks-workshop/`:

- **AZURE_MONITORING_SETUP.md** (this file) - Quick setup guide
- **GRAFANA_DASHBOARD_GUIDE.md** - Detailed usage guide, metric reference, testing procedures
- **grafana-cnpg-ha-dashboard.json** - Dashboard JSON for import
- **scripts/06a-configure-azure-monitor-prometheus.sh** - Azure Monitor configuration script

## 🎯 Success Criteria Checklist

When everything is working correctly:

- [ ] Grafana dashboard imported successfully
- [ ] All 9 panels showing data (not "No data")
- [ ] Variable dropdown shows `pg-primary-cnpg-987kr2cs`
- [ ] Instance Health shows 3/3 instances UP (green)
- [ ] Current Primary shows one pod name (blue background)
- [ ] Replication Lag < 1 second for replicas
- [ ] Transaction Rate near 0 (idle) or spikes during load test
- [ ] WAL Archive Status shows "OK" (green)
- [ ] Can trigger failover and see red annotation appear

## 🚀 What You Have Now

### Azure-Native Production Monitoring Stack

| Component | Service | Status |
|-----------|---------|--------|
| Metrics Collection | Azure Monitor Workspace | ✅ Running |
| Metrics Storage | Azure Monitor (18 months retention) | ✅ Active |
| Visualization | Azure Managed Grafana | ✅ Ready for dashboard |
| Scraping | ama-metrics agents (2 pods) | ✅ Collecting every 15s |
| Dashboard | Custom JSON (9 panels) | ✅ Ready to import |

### Key Advantages of Azure-Native Approach

- ✅ **No Cluster Resources** - Monitoring runs in Azure, not in your AKS cluster
- ✅ **18 Month Retention** - Metrics stored for 18 months automatically
- ✅ **High Availability** - Azure-managed, no single point of failure
- ✅ **Azure AD Auth** - Integrated authentication and RBAC
- ✅ **Zero Maintenance** - Fully managed by Azure
- ✅ **Cost Optimized** - Only pay for metrics collected (filtered to essentials)

### No In-Cluster Monitoring Required

❌ **Not using** (as per your requirement):
- kube-prometheus-stack (in-cluster Prometheus)
- In-cluster Grafana pod
- ServiceMonitors (created but not needed)
- PrometheusRules (created but not needed)

✅ **Using only Azure services**:
- Azure Monitor Managed Prometheus
- Azure Managed Grafana  
- Azure Monitor Container Insights
- ama-metrics agents (Azure-managed, runs in kube-system)

## 💡 Next Actions

1. **Import dashboard** using steps above → Should take 2 minutes
2. **Verify metrics** showing → Wait 5-10 minutes if needed
3. **Run load test** → See TPS spike in dashboard
4. **Test failover** → See automatic annotation on graphs
5. **Customize dashboard** → Add your own panels if needed
6. **Create alerts** → Optional, use Azure Monitor Alert Rules
7. **Share with team** → Grafana has built-in sharing

## 📖 Learn More

- **GRAFANA_DASHBOARD_GUIDE.md** - Deep dive on all 9 panels, metric meanings, testing scenarios
- [CloudNativePG Monitoring Docs](https://cloudnative-pg.io/documentation/current/monitoring/)
- [Azure Monitor Managed Prometheus](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/prometheus-metrics-overview)
- [Azure Managed Grafana](https://learn.microsoft.com/en-us/azure/managed-grafana/)

---

**Ready to import?** Open Grafana now: https://grafana-cnpg-987kr2cs-d2afemdffefvgyb0.cse.grafana.azure.com
