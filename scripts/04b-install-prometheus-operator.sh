#!/bin/bash
# Script 04b: Install Prometheus Operator
# Installs Prometheus Operator for PodMonitor support

set -euo pipefail

# Source environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/../.env" ]; then
    source "${SCRIPT_DIR}/../.env"
else
    source "${SCRIPT_DIR}/../config/environment-variables.sh"
fi

echo "=== Installing Prometheus Operator ==="

# Check if Prometheus Operator is already installed
if kubectl get crd prometheuses.monitoring.coreos.com &>/dev/null; then
    echo "✓ Prometheus Operator CRDs already installed"
else
    echo "Installing Prometheus Operator CRDs..."
    
    # Add Prometheus community Helm repo
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    
    # Install kube-prometheus-stack (includes Prometheus Operator, Prometheus, Grafana)
    # We'll use minimal config since we already have Azure Managed Grafana
    echo "Installing kube-prometheus-stack..."
    helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
        --namespace cnpg-system \
        --create-namespace \
        --set prometheus.enabled=true \
        --set grafana.enabled=false \
        --set alertmanager.enabled=false \
        --set prometheusOperator.enabled=true \
        --set kubeStateMetrics.enabled=true \
        --set nodeExporter.enabled=true \
        --wait \
        --timeout 10m
    
    echo "✓ Prometheus Operator installed successfully"
fi

# Verify CRDs are available
echo ""
echo "Verifying Prometheus Operator CRDs..."
kubectl get crd | grep monitoring.coreos.com || echo "WARNING: No Prometheus CRDs found"

# Check if Prometheus Operator is running
echo ""
echo "Checking Prometheus Operator status..."
kubectl get pods -n cnpg-system -l app.kubernetes.io/name=prometheus-operator

echo ""
echo "✓ Prometheus Operator installation complete!"
echo ""
echo "Available CRDs:"
kubectl get crd | grep monitoring.coreos.com | awk '{print "  - " $1}'
