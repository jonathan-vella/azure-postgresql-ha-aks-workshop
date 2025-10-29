#!/bin/bash
# Script 06a: Configure Azure Monitor Managed Prometheus
# Enables Azure Monitor to scrape metrics from AKS cluster

set -euo pipefail

# Source environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/../.env" ]; then
    source "${SCRIPT_DIR}/../.env"
else
    source "${SCRIPT_DIR}/../config/environment-variables.sh"
fi
source "${SCRIPT_DIR}/../.deployment-outputs"

echo "=== Configuring Azure Monitor Managed Prometheus ==="

# Enable Azure Monitor for the AKS cluster with Prometheus addon
echo "Enabling Azure Monitor addon on AKS cluster..."
az aks update \
    --name "$AKS_PRIMARY_CLUSTER_NAME" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --enable-azure-monitor-metrics \
    --azure-monitor-workspace-resource-id "$AMW_RESOURCE_ID" \
    --no-wait

echo "Waiting for Azure Monitor addon to be ready..."
sleep 30

# Create ConfigMap for Azure Monitor scraping focused on Load Test & Failover metrics
echo "Creating Azure Monitor scrape configuration for Load Testing & Failover scenarios..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ama-metrics-prometheus-config
  namespace: kube-system
data:
  prometheus-config: |
    global:
      scrape_interval: 15s
      evaluation_interval: 15s
    
    scrape_configs:
    # PostgreSQL cluster pods - Load Test & HA metrics
    - job_name: 'cnpg-postgres-ha'
      kubernetes_sd_configs:
      - role: pod
        namespaces:
          names:
          - cnpg-database
      relabel_configs:
      # Only scrape CNPG PostgreSQL pods
      - source_labels: [__meta_kubernetes_pod_label_cnpg_io_cluster]
        action: keep
        regex: pg-primary-cnpg-${SUFFIX}
      # Only scrape metrics port
      - source_labels: [__meta_kubernetes_pod_container_port_name]
        action: keep
        regex: metrics
      # Add pod name
      - source_labels: [__meta_kubernetes_pod_name]
        target_label: pod
      # Add namespace
      - source_labels: [__meta_kubernetes_pod_namespace]
        target_label: db_namespace
      # Add instance role (primary/replica) - CRITICAL for failover monitoring
      - source_labels: [__meta_kubernetes_pod_label_cnpg_io_instanceRole]
        target_label: role
      # Add PostgreSQL cluster name - CRITICAL for dashboard filtering
      - source_labels: [__meta_kubernetes_pod_label_cnpg_io_cluster]
        target_label: pg_cluster
      # Keep pod IP for connection tracking
      - source_labels: [__meta_kubernetes_pod_ip]
        target_label: pod_ip
      
      # Metric relabeling - keep only metrics needed for load test & failover
      metric_relabel_configs:
      # Keep instance health
      - source_labels: [__name__]
        regex: 'cnpg_collector_up'
        action: keep
      # Keep transaction metrics for load testing
      - source_labels: [__name__]
        regex: 'cnpg_transactions_total'
        action: keep
      # Keep replication lag for failover validation
      - source_labels: [__name__]
        regex: 'cnpg_pg_replication_lag'
        action: keep
      # Keep connection metrics for load testing
      - source_labels: [__name__]
        regex: 'cnpg_backends_total'
        action: keep
      # Keep WAL metrics for backup/recovery validation
      - source_labels: [__name__]
        regex: 'cnpg_collector_pg_wal.*'
        action: keep
      # Keep sync replica metrics for HA validation
      - source_labels: [__name__]
        regex: 'cnpg_collector_sync_replicas'
        action: keep
      # Keep fencing status for failover scenarios
      - source_labels: [__name__]
        regex: 'cnpg_collector_fencing_on'
        action: keep
      # Keep switchover required flag
      - source_labels: [__name__]
        regex: 'cnpg_collector_manual_switchover_required'
        action: keep
      # Keep database size for monitoring
      - source_labels: [__name__]
        regex: 'cnpg_pg_database_size_bytes'
        action: keep
EOF

echo ""
echo "Restarting Azure Monitor agents to apply configuration..."
kubectl rollout restart deployment/ama-metrics -n kube-system
kubectl rollout restart deployment/ama-metrics-operator-targets -n kube-system
kubectl rollout status deployment/ama-metrics -n kube-system --timeout=90s

echo "✓ Azure Monitor Managed Prometheus configuration complete!"
echo ""
echo "⏱️  Note: It may take 5-10 minutes for metrics to appear in Azure Monitor"
echo ""
echo "=== Verification Steps ==="
echo "1. Check if metrics are being collected:"
echo "   az monitor metrics list-definitions --resource \$AMW_RESOURCE_ID"
echo ""
echo "2. Query CNPG metrics:"
echo "   az monitor metrics list --resource \$AMW_RESOURCE_ID --metric cnpg_collector_up"
echo ""
echo "3. Open Grafana and verify Prometheus data source shows metrics"
