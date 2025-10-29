#!/bin/bash
# Master Deployment Script: deploy-all.sh
# Orchestrates complete PostgreSQL HA deployment on AKS

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "================================================"
echo "PostgreSQL HA Deployment on Azure AKS"
echo "================================================"
echo ""

# Load environment variables
echo "Step 1/7: Loading environment variables..."
if [ -f "${SCRIPT_DIR}/../.env" ]; then
    source "${SCRIPT_DIR}/../.env"
else
    echo -e "${RED}✗ .env file not found! Run: bash .devcontainer/generate-env.sh${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Environment variables loaded${NC}"
echo ""

# Validate prerequisites
echo "Validating prerequisites..."
command -v az >/dev/null 2>&1 || { echo -e "${RED}✗ Azure CLI not found${NC}"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo -e "${RED}✗ kubectl not found${NC}"; exit 1; }
command -v helm >/dev/null 2>&1 || { echo -e "${RED}✗ Helm not found${NC}"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo -e "${RED}✗ jq not found${NC}"; exit 1; }

# Check Azure CLI login and prompt if needed
if ! az account show >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠ Not logged in to Azure CLI${NC}"
    echo "Please login to Azure..."
    az login
    if ! az account show >/dev/null 2>&1; then
        echo -e "${RED}✗ Azure login failed${NC}"
        exit 1
    fi
fi
echo -e "${GREEN}✓ All prerequisites validated${NC}"
echo ""

# Step 2: Create infrastructure
echo "Step 2/7: Creating Azure infrastructure..."
"${SCRIPT_DIR}/02-create-infrastructure.sh"
echo -e "${GREEN}✓ Infrastructure created${NC}"
echo ""

# Step 3: Configure Workload Identity
echo "Step 3/7: Configuring Workload Identity..."
"${SCRIPT_DIR}/03-configure-workload-identity.sh"
echo -e "${GREEN}✓ Workload Identity configured${NC}"
echo ""

# Step 4: Deploy CNPG operator
echo "Step 4/7: Deploying CloudNativePG operator..."
"${SCRIPT_DIR}/04-deploy-cnpg-operator.sh"
echo -e "${GREEN}✓ CNPG operator deployed${NC}"
echo ""

# Step 4a: Install Barman Cloud Plugin
echo "Step 4a/7: Installing Barman Cloud Plugin..."
"${SCRIPT_DIR}/04a-install-barman-cloud-plugin.sh"
echo -e "${GREEN}✓ Barman Cloud Plugin installed${NC}"
echo ""

# Step 4b: Install Prometheus Operator
echo "Step 4b/7: Installing Prometheus Operator..."
"${SCRIPT_DIR}/04b-install-prometheus-operator.sh"
echo -e "${GREEN}✓ Prometheus Operator installed${NC}"
echo ""

# Step 5: Deploy PostgreSQL cluster
echo "Step 5/7: Deploying PostgreSQL HA cluster..."
"${SCRIPT_DIR}/05-deploy-postgresql-cluster.sh"
echo -e "${GREEN}✓ PostgreSQL cluster deployed${NC}"
echo ""

# Step 6: Configure monitoring
echo "Step 6/7: Configuring monitoring..."
"${SCRIPT_DIR}/06-configure-monitoring.sh"
echo -e "${GREEN}✓ Monitoring configured${NC}"
echo ""

# Deployment summary
echo "================================================"
echo "Deployment Complete!"
echo "================================================"
echo ""

# Source outputs
source "${SCRIPT_DIR}/../.deployment-outputs"

echo "Resource Group: $RESOURCE_GROUP_NAME"
echo "AKS Cluster: $AKS_PRIMARY_CLUSTER_NAME"
echo "PostgreSQL Cluster: $PG_PRIMARY_CLUSTER_NAME"
echo "Storage Account: $PG_PRIMARY_STORAGE_ACCOUNT_NAME"
echo ""

# Get service IPs
echo "PostgreSQL Connection Information:"
kubectl get svc -n "$PG_NAMESPACE" --context "$AKS_PRIMARY_CLUSTER_NAME" | grep "$PG_PRIMARY_CLUSTER_NAME" || true
echo ""

# Get Grafana URL
GRAFANA_URL=$(az grafana show \
    --name "$GRAFANA_PRIMARY" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --query "properties.endpoint" \
    --output tsv)

echo "Monitoring URLs:"
echo "  Grafana: $GRAFANA_URL"
echo ""

echo "Next Steps:"
echo "1. Test PostgreSQL connection:"
echo "   kubectl port-forward svc/${PG_PRIMARY_CLUSTER_NAME}-rw 5432:5432 -n ${PG_NAMESPACE}"
echo "   psql -h localhost -U ${PG_DATABASE_USER} -d ${PG_DATABASE_NAME}"
echo ""
echo "2. Check cluster status:"
echo "   kubectl cnpg status ${PG_PRIMARY_CLUSTER_NAME} -n ${PG_NAMESPACE}"
echo ""
echo "3. View logs:"
echo "   kubectl logs -n ${PG_NAMESPACE} -l postgresql=${PG_PRIMARY_CLUSTER_NAME}"
echo ""
echo "4. Access Grafana:"
echo "   Open: $GRAFANA_URL"
echo ""
