#!/bin/bash
# Script 03: Configure Workload Identity
# Sets up federated credentials and service account for PostgreSQL backup

set -euo pipefail

# Source environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/../.env" ]; then
    source "${SCRIPT_DIR}/../.env"
else
    source "${SCRIPT_DIR}/../config/environment-variables.sh"
fi
source "${SCRIPT_DIR}/../.deployment-outputs"

echo "=== Configuring Workload Identity ==="

# Get AKS OIDC issuer URL
echo "Retrieving AKS OIDC issuer URL..."
export AKS_PRIMARY_CLUSTER_OIDC_ISSUER=$(az aks show \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --name "$AKS_PRIMARY_CLUSTER_NAME" \
    --query "oidcIssuerProfile.issuerUrl" \
    --output tsv)

echo "OIDC Issuer: $AKS_PRIMARY_CLUSTER_OIDC_ISSUER"

# Note: CloudNativePG operator auto-creates service account via serviceAccountTemplate
# We only need to create the federated credential for the CNPG-generated service account
# Service account name will be: ${PG_PRIMARY_CLUSTER_NAME} (not ${PG_PRIMARY_CLUSTER_NAME}-sa)

# Create federated credential for CNPG-generated service account
echo "Creating federated credential for CloudNativePG service account: $PG_PRIMARY_CLUSTER_NAME"
az identity federated-credential create \
    --name "${PG_PRIMARY_CLUSTER_NAME}-federated-credential" \
    --identity-name "$AKS_UAMI_CLUSTER_IDENTITY_NAME" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --issuer "$AKS_PRIMARY_CLUSTER_OIDC_ISSUER" \
    --subject "system:serviceaccount:${PG_NAMESPACE}:${PG_PRIMARY_CLUSTER_NAME}" \
    --audience "api://AzureADTokenExchange" \
    --output table

echo "✓ Workload Identity configuration complete!"
echo "Federated credential created for service account: ${PG_PRIMARY_CLUSTER_NAME}"
echo "Namespace: ${PG_NAMESPACE}"
echo "Client ID: ${AKS_UAMI_WORKLOAD_CLIENTID}"
echo ""
echo "Note: CloudNativePG operator will create the service account automatically"
echo "      when the PostgreSQL cluster is deployed in Step 5."
