#!/bin/bash
# Script 06a: Configure Azure Monitor Managed Prometheus
# Enables Azure Monitor to scrape metrics from AKS cluster

set -euo pipefail

# Source environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/../.env" ]; then
    source "${SCRIPT_DIR}/../.env"
else
    echo "❌ Error: .env file not found. Run: bash .devcontainer/generate-env.sh"
    exit 1
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
EOF

echo ""
echo "Restarting Azure Monitor agents to apply configuration..."
kubectl rollout restart deployment/ama-metrics -n kube-system
kubectl rollout restart deployment/ama-metrics-operator-targets -n kube-system
kubectl rollout status deployment/ama-metrics -n kube-system --timeout=90s

echo "✓ Azure Monitor Managed Prometheus configuration complete!"
echo ""
echo "⏱️  Note: It may take 5-10 minutes for metrics to appear in Grafana"
echo ""
echo "=== Verification Steps ==="
echo "1. Check if Azure Monitor is scraping metrics:"
echo "   kubectl get pods -n kube-system | grep ama-metrics"
echo ""
echo "2. View CNPG metrics in Grafana:"
echo "   - Open Grafana URL (from Step 6 output)"
echo "   - Go to Explore"
echo "   - Select 'Azure Monitor' data source"
echo "   - Query: cnpg_collector_up{pg_cluster=\"$PG_PRIMARY_CLUSTER_NAME\"}"
echo ""
echo "3. Import CNPG Dashboard:"
echo "   - Dashboards > Import > Upload grafana/grafana-cnpg-ha-dashboard.json"
