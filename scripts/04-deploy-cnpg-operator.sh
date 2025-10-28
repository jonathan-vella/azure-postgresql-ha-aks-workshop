#!/bin/bash
# Script 04: Deploy CloudNativePG Operator
# Installs CNPG operator via Helm

set -euo pipefail

# Source environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/../.env" ]; then
    source "${SCRIPT_DIR}/../.env"
else
    source "${SCRIPT_DIR}/../config/environment-variables.sh"
fi

echo "=== Deploying CloudNativePG Operator ==="

# Add CloudNativePG Helm repository
echo "Adding CloudNativePG Helm repository..."
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo update

# Install CNPG operator
echo "Installing CloudNativePG operator version ${CNPG_VERSION}..."
helm upgrade --install cnpg \
    --namespace "$PG_SYSTEM_NAMESPACE" \
    --create-namespace \
    --kube-context "$AKS_PRIMARY_CLUSTER_NAME" \
    --version "$CNPG_VERSION" \
    cnpg/cloudnative-pg \
    --wait

# Wait for operator to be ready
echo "Waiting for CNPG operator to be ready..."
kubectl wait --for=condition=Available \
    --timeout=300s \
    --context "$AKS_PRIMARY_CLUSTER_NAME" \
    -n "$PG_SYSTEM_NAMESPACE" \
    deployment/cnpg-cloudnative-pg

# Verify operator installation
echo "Verifying CNPG operator installation..."
kubectl get deployment -n "$PG_SYSTEM_NAMESPACE" --context "$AKS_PRIMARY_CLUSTER_NAME"

echo "✓ CloudNativePG operator deployed successfully!"
