#!/bin/bash

#######################################
# Import Grafana Dashboard with Correct Datasource
# This script:
# 1. Retrieves the Azure Monitor datasource UID from Grafana
# 2. Updates the dashboard JSON with the correct datasource
# 3. Imports the dashboard via Grafana API
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
GRAFANA_ENDPOINT=$(az grafana show \
    --name "${GRAFANA_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "properties.endpoint" \
    -o tsv)

if [ -z "$GRAFANA_ENDPOINT" ]; then
    echo -e "${RED}Error: Could not retrieve Grafana endpoint${NC}"
    exit 1
fi

echo "Grafana URL: ${GRAFANA_ENDPOINT}"

echo -e "\n${BLUE}=== Step 2: Get Access Token ===${NC}"
# Azure Managed Grafana resource ID for token
GRAFANA_RESOURCE_ID="ce34e7e5-485f-4d76-964f-b3d2b16d1e5f"
TOKEN=$(az account get-access-token \
    --resource "${GRAFANA_RESOURCE_ID}" \
    --query accessToken \
    -o tsv)

if [ -z "$TOKEN" ]; then
    echo -e "${RED}Error: Could not retrieve access token${NC}"
    exit 1
fi

echo "✓ Access token retrieved"

echo -e "\n${BLUE}=== Step 3: Get Azure Monitor Datasource UID ===${NC}"
DATASOURCES=$(curl -s -H "Authorization: Bearer ${TOKEN}" \
    "${GRAFANA_ENDPOINT}/api/datasources" 2>/dev/null)

if [ -z "$DATASOURCES" ]; then
    echo -e "${RED}Error: Could not retrieve datasources from Grafana${NC}"
    exit 1
fi

# Find Azure Monitor Prometheus datasource
DATASOURCE_UID=$(echo "$DATASOURCES" | jq -r '.[] | select(.type=="prometheus" and (.name | contains("Azure Monitor") or contains("azure-monitor") or contains("amw-"))) | .uid' | head -1)

if [ -z "$DATASOURCE_UID" ]; then
    echo -e "${YELLOW}Warning: Azure Monitor datasource not found. Searching for any Prometheus datasource...${NC}"
    DATASOURCE_UID=$(echo "$DATASOURCES" | jq -r '.[] | select(.type=="prometheus") | .uid' | head -1)
fi

if [ -z "$DATASOURCE_UID" ]; then
    echo -e "${RED}Error: No Prometheus datasource found in Grafana${NC}"
    echo "Available datasources:"
    echo "$DATASOURCES" | jq -r '.[] | "\(.name) (\(.type)) - UID: \(.uid)"'
    exit 1
fi

DATASOURCE_NAME=$(echo "$DATASOURCES" | jq -r ".[] | select(.uid==\"${DATASOURCE_UID}\") | .name")
echo "✓ Found datasource: ${DATASOURCE_NAME} (UID: ${DATASOURCE_UID})"

echo -e "\n${BLUE}=== Step 4: Configure Dashboard JSON ===${NC}"
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

echo -e "\n${BLUE}=== Step 5: Import Dashboard to Grafana ===${NC}"

# Wrap dashboard JSON in required format for import API
IMPORT_PAYLOAD=$(jq -n \
  --arg uid "$DATASOURCE_UID" \
  --slurpfile dashboard "$TEMP_DASHBOARD" \
  '{
    "dashboard": $dashboard[0],
    "overwrite": true,
    "inputs": [
      {
        "name": "DS_PROMETHEUS",
        "type": "datasource",
        "pluginId": "prometheus",
        "value": $uid
      }
    ]
  }')

# Import dashboard
IMPORT_RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$IMPORT_PAYLOAD" \
  "${GRAFANA_ENDPOINT}/api/dashboards/import" 2>/dev/null)

# Check if import was successful
IMPORT_STATUS=$(echo "$IMPORT_RESPONSE" | jq -r '.status // empty')
DASHBOARD_UID=$(echo "$IMPORT_RESPONSE" | jq -r '.uid // empty')
DASHBOARD_URL=$(echo "$IMPORT_RESPONSE" | jq -r '.url // empty')

if [ -n "$DASHBOARD_UID" ] || echo "$IMPORT_RESPONSE" | jq -e '.id' > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Dashboard imported successfully!${NC}"
    
    if [ -n "$DASHBOARD_URL" ]; then
        FULL_URL="${GRAFANA_ENDPOINT}${DASHBOARD_URL}"
    else
        FULL_URL="${GRAFANA_ENDPOINT}/d/${DASHBOARD_UID}/cloudnativepg-load-testing-failover-dashboard"
    fi
    
    echo -e "\n${GREEN}=== Dashboard Ready ===${NC}"
    echo "Dashboard URL: ${FULL_URL}"
    echo ""
    echo "Note: It may take 5-10 minutes for metrics to appear after initial deployment."
    echo "      Metrics collection started at: $(kubectl get configmap ama-metrics-prometheus-config -n kube-system -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null || echo 'unknown')"
else
    echo -e "${RED}Error: Dashboard import failed${NC}"
    echo "Response: $IMPORT_RESPONSE"
    
    # Check if it's a permissions error
    if echo "$IMPORT_RESPONSE" | grep -q "403\|Forbidden\|Unauthorized"; then
        echo -e "\n${YELLOW}Troubleshooting: Permissions Issue${NC}"
        echo "1. Ensure you have Grafana Admin role:"
        echo "   az role assignment create --role 'Grafana Admin' \\"
        echo "     --assignee-object-id \$(az ad signed-in-user show --query id -o tsv) \\"
        echo "     --scope '${GRAFANA_RESOURCE_ID}'"
        echo ""
        echo "2. Wait 1-2 minutes for role assignment to propagate, then re-run this script"
    fi
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
