# CloudNativePG Load Testing & Failover Dashboard - Azure Managed Grafana

## 🎯 Dashboard Overview

This custom dashboard is specifically designed for monitoring CloudNativePG PostgreSQL clusters on Azure Kubernetes Service (AKS) during:
- **Load Testing**: Transaction throughput, connection counts, database performance
- **Failover Scenarios**: Replication lag, primary switchover detection, instance health

## 📊 Dashboard Panels

### High Availability Monitoring

1. **Instance Health Status** (Stat Panel)
   - Shows UP/DOWN status for each PostgreSQL pod
   - Color-coded: Green = UP, Red = DOWN
   - Displays role (primary/replica) for each instance

2. **Current Primary Instance** (Stat Panel)
   - Identifies which pod is currently serving as primary
   - Blue background for quick visual identification
   - Updates automatically when primary changes (failover event)

3. **Cluster Availability** (Stat Panel)
   - Count of healthy instances out of total (3 in this deployment)
   - Thresholds: Red < 2, Yellow = 2, Green = 3
   - Shows trend graph of availability over time

### Load Testing Metrics

4. **Transaction Rate (TPS)** (Time Series Graph)
   - Transactions per second (commits + rollbacks)
   - **KEY METRIC**: Primary indicator of database load
   - Shows per-instance transaction rate
   - Useful for: pgbench load testing, identifying bottlenecks

5. **Active Connections** (Stacked Area Chart)
   - Number of active database connections per instance
   - **KEY METRIC**: Connection pool utilization during load
   - Stacked view shows total cluster connections
   - Useful for: Connection pool sizing, detecting connection leaks

6. **Database Size** (Time Series Graph)
   - Database size in bytes over time
   - Monitors growth during load testing
   - Per-database breakdown

### Failover & Replication Monitoring

7. **Replication Lag** (Time Series Graph)
   - Replication lag in seconds for each replica
   - **CRITICAL METRIC**: Indicates how up-to-date replicas are
   - Thresholds: Green < 5s, Yellow 5-10s, Red > 10s
   - **IMPORTANT**: Lag spikes during failover are normal (expect 5-15 seconds)

8. **WAL Archive Status** (Stat Panel)
   - Write-Ahead Log archiving health
   - Green = OK, Red = FAILING
   - Critical for backup/recovery validation

9. **Synchronous Replicas** (Stat Panel)
   - Number of sync replicas required for HA
   - Should be 1 or more for high availability
   - Green when >= 1, Red when 0

### Automatic Annotations

- **Primary Switchover Events**: Automatically annotated on graphs when primary instance changes
- Red vertical lines mark failover events
- Hover over annotation to see which pod became primary

## 🚀 How to Import into Azure Managed Grafana

### Step 1: Copy Dashboard JSON

```bash
# The dashboard JSON is located at:
cat /workspaces/azure-postgresql-ha-aks-workshop/grafana-cnpg-ha-dashboard.json
```

### Step 2: Open Azure Managed Grafana

1. Go to Azure Portal
2. Navigate to your Azure Managed Grafana instance: `grafana-cnpg-987kr2cs`
3. Click "Endpoint" to open Grafana UI
4. Log in (Azure AD authentication)

### Step 3: Import Dashboard

1. In Grafana, click **"+"** (Create) → **"Import"**
2. Click **"Upload JSON file"** OR paste JSON content directly
3. Select data source: **"Managed_Prometheus_amw-cnpg-987kr2cs"** (Azure Monitor Workspace)
4. Click **"Import"**
5. Dashboard will open automatically

### Step 4: Configure Data Source UID (If Needed)

If panels show "Data source not found":

1. Go to **Settings** (gear icon) → **JSON Model**
2. Find all occurrences of `"uid": "managed-prometheus"`
3. Replace with your actual Azure Monitor data source UID
4. Save dashboard

**To find your data source UID:**
- Go to **Configuration** → **Data sources**
- Click on your Azure Monitor Workspace data source
- Copy the UID from the URL: `/datasources/edit/<UID>`

## 📈 Using the Dashboard for Load Testing

### Before Load Test

1. Open dashboard and verify all instances show "UP"
2. Confirm Current Primary Instance is displayed
3. Check baseline metrics:
   - Transaction Rate: Should be near 0 (idle)
   - Active Connections: 1-3 (system connections)
   - Replication Lag: < 1 second

### Running Load Test with pgbench

```bash
# Connect to the primary pod
PRIMARY_POD=$(kubectl get pod -n cnpg-database -l cnpg.io/instanceRole=primary -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it -n cnpg-database $PRIMARY_POD -- bash

# Inside the pod, run pgbench
# Initialize test database
pgbench -i -s 50 app

# Run load test (10 clients, 100 transactions each)
pgbench -c 10 -t 100 app
```

### Watch These Metrics During Load Test

- **Transaction Rate**: Should increase significantly (100-1000+ TPS depending on test)
- **Active Connections**: Should match pgbench client count (-c parameter)
- **Replication Lag**: May increase slightly during heavy write load (< 5 seconds is normal)
- **Instance Health**: All instances should remain UP

### Expected Behavior During Heavy Load

✅ **Normal**:
- Transaction rate spikes
- Connection count increases
- Replication lag stays < 10 seconds
- All instances remain healthy

❌ **Concerning**:
- Instance health changes to DOWN
- Replication lag > 30 seconds
- Transaction rate drops to 0 unexpectedly

## 🔄 Using the Dashboard for Failover Testing

### Triggering a Failover

```bash
# Delete the current primary pod to trigger failover
PRIMARY_POD=$(kubectl get pod -n cnpg-database -l cnpg.io/instanceRole=primary -o jsonpath='{.items[0].metadata.name}')
kubectl delete pod -n cnpg-database $PRIMARY_POD
```

### Watch These Metrics During Failover

1. **Instance Health Status** (0-10 seconds):
   - Old primary goes DOWN (red)
   - Replicas remain UP (green)

2. **Current Primary Instance** (5-15 seconds):
   - Switches to a new pod name
   - Automatic annotation appears on all graphs

3. **Replication Lag** (10-30 seconds):
   - Spike expected as new primary stabilizes
   - Should return to < 1 second within 30 seconds

4. **Transaction Rate**:
   - Brief interruption (0-10 seconds)
   - Should resume normal levels quickly

5. **Cluster Availability**:
   - May briefly drop to 2/3 instances
   - Returns to 3/3 when deleted pod is recreated

### Expected Failover Timeline

| Time | Event | Dashboard Indication |
|------|-------|---------------------|
| T+0s | Delete primary pod | Instance Health: Primary goes RED |
| T+5s | Election starts | Current Primary may clear temporarily |
| T+10s | New primary elected | Current Primary updates to new pod name |
| T+10s | Annotation appears | Red vertical line marks switchover |
| T+15s | Replicas sync to new primary | Replication Lag spikes then decreases |
| T+30s | Old pod recreated | Cluster Availability returns to 3/3 |
| T+60s | New replica catches up | Replication Lag returns to < 1s |

✅ **Successful Failover**:
- New primary elected within 15 seconds
- Replication lag recovers < 60 seconds
- All instances return to healthy state
- Transaction rate resumes (if load test running)

❌ **Failed Failover**:
- No new primary elected after 30 seconds
- Multiple instances DOWN
- Persistent high replication lag (> 60 seconds)

## 🔍 Metric Details

### Critical Metrics Reference

| Metric Name | Description | Healthy Range | Alert Threshold |
|------------|-------------|---------------|-----------------|
| `cnpg_collector_up` | Instance health | 1 (UP) | 0 (DOWN) |
| `cnpg_transactions_total` | Transaction count | Varies | N/A |
| `cnpg_pg_replication_lag` | Replication lag (seconds) | 0-5s | > 10s |
| `cnpg_backends_total` | Active connections | 1-100 | > 90 (if max_connections=100) |
| `cnpg_collector_pg_wal_archive_status` | WAL archiving | 1 (OK) | 0 (FAILING) |
| `cnpg_collector_sync_replicas` | Sync replica count | >= 1 | 0 |
| `cnpg_pg_database_size_bytes` | Database size | Varies | N/A |

### Label Structure

All metrics include these labels (use for filtering):

- `pg_cluster`: PostgreSQL cluster name (e.g., `pg-primary-cnpg-987kr2cs`)
- `pod`: Kubernetes pod name
- `role`: Instance role (`primary` or `replica`)
- `db_namespace`: Kubernetes namespace (`cnpg-database`)
- `cluster`: AKS cluster name (Azure-injected, **not** PostgreSQL cluster)

**Important**: Dashboard uses `pg_cluster` label for PostgreSQL cluster filtering, NOT `cluster` (which contains AKS cluster name).

## 🛠️ Troubleshooting

### Dashboard shows "No data"

**Check 1: Verify metrics are being collected**
```bash
# Get Azure Monitor Workspace endpoint
AMW_ENDPOINT=$(az monitor account show --name amw-cnpg-987kr2cs --resource-group rg-cnpg-987kr2cs --query metrics.prometheusQueryEndpoint -o tsv)

# Get auth token
TOKEN=$(az account get-access-token --resource https://prometheus.monitor.azure.com --query accessToken -o tsv)

# Query for cnpg_collector_up metric
curl -s -H "Authorization: Bearer $TOKEN" "${AMW_ENDPOINT}/api/v1/query?query=cnpg_collector_up" | jq
```

Expected output: Should show 3 instances with value "1"

**Check 2: Verify scrape configuration is applied**
```bash
kubectl get configmap -n kube-system ama-metrics-prometheus-config -o yaml
```

Look for `job_name: 'cnpg-postgres-ha'` in the configuration.

**Check 3: Verify Azure Monitor agents are running**
```bash
kubectl get pods -n kube-system -l rsName=ama-metrics
```

Expected: 2 pods in Running state

**Check 4: Wait for metric propagation**
- Metrics may take 5-10 minutes to appear after configuration changes
- Try refreshing dashboard after waiting

### Variable dropdown is empty

**Check the variable query:**
1. Go to Dashboard Settings → Variables
2. Variable `pg_cluster` should query: `label_values(cnpg_collector_up, pg_cluster)`
3. Click "Run queries" to test
4. If empty, metrics haven't propagated yet (wait 5-10 minutes)

**Manual override:**
1. Edit variable `pg_cluster`
2. Change Type to "Custom"
3. Set custom values: `pg-primary-cnpg-987kr2cs`
4. Save dashboard

### Panels show "Data source not found"

**Fix data source UID:**
1. Go to Configuration → Data sources
2. Find your Azure Monitor Workspace data source
3. Copy the UID from the URL
4. Go to Dashboard Settings → JSON Model
5. Replace all `"uid": "managed-prometheus"` with your actual UID
6. Save dashboard

### Replication lag shows "No data" for replicas

**Possible cause**: Metric only exists when role="replica"

**Check with PromQL:**
```promql
cnpg_pg_replication_lag{pg_cluster="pg-primary-cnpg-987kr2cs", role="replica"}
```

If no results, verify:
```bash
kubectl get pods -n cnpg-database -l cnpg.io/cluster=pg-primary-cnpg-987kr2cs --show-labels
```

Look for labels: `cnpg.io/instanceRole=replica` and `cnpg.io/instanceRole=primary`

## 📚 Additional Resources

- [CloudNativePG Monitoring Documentation](https://cloudnative-pg.io/documentation/current/monitoring/)
- [Azure Monitor Managed Prometheus](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/prometheus-metrics-overview)
- [Azure Managed Grafana Documentation](https://learn.microsoft.com/en-us/azure/managed-grafana/)
- [PostgreSQL High Availability Best Practices](https://learn.microsoft.com/en-us/azure/aks/postgresql-ha-overview)

## 🎓 Best Practices

### Dashboard Usage

1. **Set appropriate time range**: 
   - Load testing: Last 15 minutes (default)
   - Failover testing: Last 30 minutes
   - Long-term monitoring: Last 24 hours

2. **Use refresh interval**:
   - Active testing: 5-10 seconds
   - Passive monitoring: 30 seconds - 1 minute

3. **Save dashboard after customization**:
   - Star the dashboard for quick access
   - Add to a folder (e.g., "PostgreSQL HA")
   - Share with team members via Grafana sharing

4. **Create alerts** (optional):
   - Go to a panel → More → New alert rule
   - Example: Alert when replication lag > 30 seconds
   - Route to Azure Monitor Alert Rules for actions

### Metric Collection

1. **Scrape interval**: 15 seconds (configured in Azure Monitor)
2. **Metric retention**: 18 months (Azure Monitor default)
3. **Cost optimization**: Metrics are filtered to only essential metrics for load test/failover

### Load Testing Tips

1. Start with light load and increase gradually
2. Monitor replication lag during write-heavy tests
3. Test failover under load to validate HA configuration
4. Record baseline metrics before major changes

### Failover Testing Tips

1. Test during off-peak hours initially
2. Announce failover tests to stakeholders
3. Have rollback plan ready
4. Document failover duration and impact
5. Test both manual failover (delete pod) and automatic failover (simulate node failure)
