#!/bin/bash

#######################################
# Import Grafana Dashboard with Correct Datasource
# This script:
# 1. Provides instructions for manual dashboard import (most reliable)
# 2. Optionally attempts automated import via Grafana API
#######################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "========================================"
echo "Grafana Dashboard Import"
echo "========================================"

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

if [ ! -f "${PROJECT_ROOT}/.env" ]; then
    echo -e "${RED}Error: .env file not found${NC}"
    exit 1
fi

source "${PROJECT_ROOT}/.env"
source "${PROJECT_ROOT}/.deployment-outputs"

# Variables
GRAFANA_NAME="${GRAFANA_NAME:-grafana-cnpg-${SUFFIX}}"
DASHBOARD_FILE="${PROJECT_ROOT}/grafana/grafana-cnpg-ha-dashboard.json"
TEMP_DASHBOARD="/tmp/grafana-dashboard-configured.json"

echo -e "\n${BLUE}=== Step 1: Get Grafana Endpoint ===${NC}"
GRAFANA_ENDPOINT=$(az resource show \
    --ids "${GRAFANA_RESOURCE_ID}" \
    --query "properties.endpoint" \
    -o tsv)

if [ -z "$GRAFANA_ENDPOINT" ]; then
    echo -e "${RED}Error: Could not retrieve Grafana endpoint${NC}"
    exit 1
fi

echo "Grafana URL: ${GRAFANA_ENDPOINT}"

echo -e "\n${BLUE}=== Step 2: Get Prometheus Datasource UID ===${NC}"

# The dashboard needs the Prometheus datasource (not Azure Monitor datasource)
# Azure Monitor = for KQL queries on Azure infrastructure
# Managed Prometheus = for PromQL queries on CNPG application metrics
EXPECTED_DS_NAME="Managed_Prometheus_amw-cnpg-${SUFFIX}"
echo "Looking for Prometheus datasource: ${EXPECTED_DS_NAME}"

# Use Azure CLI to get datasources (more reliable than API)
DATASOURCE_INFO=$(az grafana data-source list \
    --name "grafana-cnpg-${SUFFIX}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "[?contains(name, 'Managed_Prometheus')].{name:name, uid:uid, type:typeName}" \
    -o json 2>/dev/null)

if [ -z "$DATASOURCE_INFO" ] || [ "$DATASOURCE_INFO" = "[]" ]; then
    echo -e "${RED}Error: Managed Prometheus datasource not found${NC}"
    echo "Expected: ${EXPECTED_DS_NAME}"
    echo ""
    echo "Available datasources:"
    az grafana data-source list \
        --name "grafana-cnpg-${SUFFIX}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[].{Name:name, Type:typeName, Default:isDefault}" \
        -o table 2>/dev/null
    exit 1
fi

DATASOURCE_UID=$(echo "$DATASOURCE_INFO" | jq -r '.[0].uid')
DATASOURCE_NAME=$(echo "$DATASOURCE_INFO" | jq -r '.[0].name')

if [ -z "$DATASOURCE_UID" ] || [ "$DATASOURCE_UID" = "null" ]; then
    echo -e "${RED}Error: Could not extract datasource UID${NC}"
    exit 1
fi

echo "✓ Found Prometheus datasource: ${DATASOURCE_NAME}"
echo "  UID: ${DATASOURCE_UID}"
echo "  Note: This is the Managed Prometheus endpoint for CNPG metrics (not the Azure Monitor datasource)"

echo -e "\n${BLUE}=== Step 3: Configure Dashboard JSON ===${NC}"
if [ ! -f "$DASHBOARD_FILE" ]; then
    echo -e "${RED}Error: Dashboard file not found: ${DASHBOARD_FILE}${NC}"
    exit 1
fi

# Create a configured version of the dashboard with the correct datasource
jq --arg uid "$DATASOURCE_UID" '
  # Update all datasource references in panels
  .panels |= map(
    if .datasource then
      .datasource = {
        "type": "prometheus",
        "uid": $uid
      }
    else . end |
    if .targets then
      .targets |= map(
        if .datasource then
          .datasource = {
            "type": "prometheus",
            "uid": $uid
          }
        else . end
      )
    else . end
  ) |
  # Update datasource in annotations
  if .annotations.list then
    .annotations.list |= map(
      if .datasource then
        .datasource = {
          "type": "prometheus",
          "uid": $uid
        }
      else . end
    )
  else . end |
  # Update datasource in templating variables
  if .templating.list then
    .templating.list |= map(
      if .datasource then
        .datasource = {
          "type": "prometheus",
          "uid": $uid
        }
      else . end
    )
  else . end |
  # Remove id to allow Grafana to assign new one
  .id = null |
  # Update version
  .version = 1
' "$DASHBOARD_FILE" > "$TEMP_DASHBOARD"

echo "✓ Dashboard configured with datasource UID: ${DATASOURCE_UID}"

echo -e "\n${BLUE}=== Step 4: Import Dashboard to Grafana ===${NC}"

# Import dashboard using Azure CLI (more reliable than API)
IMPORT_RESPONSE=$(az grafana dashboard create \
    --name "grafana-cnpg-${SUFFIX}" \
    --resource-group "${RESOURCE_GROUP}" \
    --title "CloudNativePG - Load Testing & Failover" \
    --definition @"${TEMP_DASHBOARD}" \
    --overwrite \
    -o json 2>&1)

# Check if import was successful
if echo "$IMPORT_RESPONSE" | jq -e '.uid' > /dev/null 2>&1; then
    DASHBOARD_UID=$(echo "$IMPORT_RESPONSE" | jq -r '.uid')
    DASHBOARD_SLUG=$(echo "$IMPORT_RESPONSE" | jq -r '.slug')
    DASHBOARD_ID=$(echo "$IMPORT_RESPONSE" | jq -r '.id')
    
    echo -e "${GREEN}✓ Dashboard imported successfully!${NC}"
    echo "  Dashboard UID: ${DASHBOARD_UID}"
    echo "  Dashboard ID: ${DASHBOARD_ID}"
    
    FULL_URL="${GRAFANA_ENDPOINT}/d/${DASHBOARD_UID}/${DASHBOARD_SLUG}"
    
    echo -e "\n${GREEN}=== Dashboard Ready ===${NC}"
    echo "Dashboard URL: ${FULL_URL}"
    echo ""
    echo "Note: It may take 5-10 minutes for metrics to appear after initial deployment."
    echo "      Metrics collection started at: $(kubectl get configmap ama-metrics-prometheus-config -n kube-system -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null || echo 'unknown')"
else
    echo -e "${RED}Error: Dashboard import failed${NC}"
    echo "Response: $IMPORT_RESPONSE"
    exit 1
fi

# Cleanup
rm -f "$TEMP_DASHBOARD"

echo -e "\n${BLUE}=== Verification Steps ===${NC}"
echo "1. Open dashboard: ${FULL_URL}"
echo "2. Check the 'PostgreSQL Cluster' dropdown at the top - it should show: ${PG_PRIMARY_CLUSTER_NAME}"
echo "3. If no data appears yet:"
echo "   - Generate some database activity:"
echo "     kubectl port-forward -n cnpg-database svc/${PG_PRIMARY_CLUSTER_NAME}-rw 5432:5432 &"
echo "     PGPASSWORD='${POSTGRES_APP_PASSWORD}' psql -h localhost -U app -d appdb -c 'SELECT version();'"
echo "     pkill -f 'port-forward.*5432'"
echo "   - Wait 5-10 minutes for metrics ingestion"
echo "   - Refresh the dashboard"

echo -e "\n${GREEN}=== Dashboard Import Complete ===${NC}"
