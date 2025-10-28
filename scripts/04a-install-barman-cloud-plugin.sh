#!/bin/bash
# ============================================================================
# Script: 04a-install-barman-cloud-plugin.sh
# Purpose: Install Barman Cloud Plugin for CloudNativePG
#
# Description:
#   Installs the Barman Cloud Plugin v0.8.0 for backup/restore operations.
#   The plugin provides:
#   - Modern backup architecture using ObjectStore CRD
#   - Better separation of concerns (backup config separate from Cluster)
#   - Future-proof solution (native barmanObjectStore removed in CNPG 1.29.0)
#
# Prerequisites:
#   - CloudNativePG operator 1.26+ installed
#   - cert-manager installed in cluster
#   - kubectl configured for target AKS cluster
#
# Usage:
#   ./04a-install-barman-cloud-plugin.sh
#
# Author: Azure PostgreSQL HA Workshop
# Date: 2025
# ============================================================================

set -euo pipefail

echo "==================================================================="
echo "Barman Cloud Plugin Installation for CloudNativePG"
echo "==================================================================="
echo ""

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config/environment-variables.sh"

echo "Step 1: Check prerequisites..."
echo "-------------------------------------------------------------------"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ Error: kubectl not found. Please install kubectl."
    exit 1
fi

# Check if connected to AKS cluster
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Error: Not connected to Kubernetes cluster."
    echo "   Run: az aks get-credentials --resource-group $RESOURCE_GROUP_NAME --name $AKS_CLUSTER_NAME"
    exit 1
fi

# Verify CloudNativePG operator version
echo "Checking CloudNativePG operator version..."
CNPG_VERSION=$(kubectl get deployment -n cnpg-system cnpg-cloudnative-pg -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | cut -d':' -f2 || echo "not-found")

if [[ "$CNPG_VERSION" == "not-found" ]]; then
    echo "❌ Error: CloudNativePG operator not found in cnpg-system namespace."
    echo "   Run script 04-deploy-cnpg-operator.sh first."
    exit 1
fi

echo "✅ CloudNativePG operator version: $CNPG_VERSION"

# Plugin requires CNPG 1.26+
CNPG_MAJOR=$(echo "$CNPG_VERSION" | cut -d'.' -f1)
CNPG_MINOR=$(echo "$CNPG_VERSION" | cut -d'.' -f2)

if [[ "$CNPG_MAJOR" -lt 1 ]] || [[ "$CNPG_MAJOR" -eq 1 && "$CNPG_MINOR" -lt 26 ]]; then
    echo "❌ Error: Barman Cloud Plugin requires CloudNativePG 1.26 or higher."
    echo "   Current version: $CNPG_VERSION"
    exit 1
fi

echo "✅ Version check passed (1.26+ required)"

# Check if cert-manager is installed
echo ""
echo "Checking for cert-manager..."
if kubectl get namespace cert-manager &> /dev/null; then
    echo "✅ cert-manager namespace found"
    
    # Check if cert-manager API is ready
    if kubectl get pods -n cert-manager | grep -q "Running"; then
        echo "✅ cert-manager pods are running"
    else
        echo "⚠️  Warning: cert-manager pods may not be ready"
    fi
else
    echo "⚠️  cert-manager not found. Installing cert-manager..."
    echo ""
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.3/cert-manager.yaml
    
    echo "Waiting for cert-manager to be ready..."
    kubectl wait --for=condition=Available --timeout=300s deployment/cert-manager -n cert-manager
    kubectl wait --for=condition=Available --timeout=300s deployment/cert-manager-cainjector -n cert-manager
    kubectl wait --for=condition=Available --timeout=300s deployment/cert-manager-webhook -n cert-manager
    echo "✅ cert-manager installed successfully"
fi

echo ""
echo "Step 2: Install Barman Cloud Plugin v0.8.0..."
echo "-------------------------------------------------------------------"

# Check if plugin is already installed
if kubectl get deployment -n cnpg-system barman-cloud &> /dev/null; then
    echo "⚠️  Barman Cloud Plugin already installed. Checking version..."
    CURRENT_VERSION=$(kubectl get deployment -n cnpg-system barman-cloud -o jsonpath='{.spec.template.spec.containers[0].image}' | cut -d':' -f2 || echo "unknown")
    echo "   Current version: $CURRENT_VERSION"
    
    read -p "Do you want to reinstall/upgrade the plugin? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Skipping plugin installation."
        exit 0
    fi
fi

echo "Installing plugin from manifest..."
kubectl apply -f https://github.com/cloudnative-pg/plugin-barman-cloud/releases/download/v0.8.0/manifest.yaml

echo ""
echo "Step 3: Wait for plugin deployment to be ready..."
echo "-------------------------------------------------------------------"

kubectl rollout status deployment/barman-cloud -n cnpg-system --timeout=300s

echo ""
echo "Step 4: Verify plugin installation..."
echo "-------------------------------------------------------------------"

# Check plugin deployment
echo "Plugin deployment status:"
kubectl get deployment -n cnpg-system barman-cloud

echo ""
echo "Plugin pods:"
kubectl get pods -n cnpg-system -l app.kubernetes.io/name=barman-cloud

echo ""
echo "Plugin version:"
PLUGIN_VERSION=$(kubectl get deployment -n cnpg-system barman-cloud -o jsonpath='{.spec.template.spec.containers[0].image}')
echo "  Image: $PLUGIN_VERSION"

echo ""
echo "==================================================================="
echo "✅ Barman Cloud Plugin Installation Complete"
echo "==================================================================="
echo ""
echo "NEXT STEPS:"
echo "1. Deploy PostgreSQL cluster (script 05 will automatically):"
echo "   - Deploy ObjectStore CRD with Azure Blob Storage config"
echo "   - Configure cluster to use plugin for backups"
echo ""
echo "NOTE: The plugin-based backup is the recommended approach."
echo "The older barmanObjectStore configuration will be removed in CNPG 1.29.0."
echo ""
