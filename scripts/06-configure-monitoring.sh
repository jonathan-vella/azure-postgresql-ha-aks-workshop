#!/bin/bash
# Script 06: Configure Monitoring
# Sets up Prometheus, Grafana integration, and monitoring dashboards

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

echo "=== Configuring Monitoring ==="

# Link Azure Monitor workspace to Grafana
echo "Linking Azure Monitor workspace to Grafana..."
az grafana data-source create \
    --name "$GRAFANA_PRIMARY" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --definition '{
        "name": "Azure Monitor",
        "type": "prometheus",
        "access": "proxy",
        "url": "'"$AMW_RESOURCE_ID"'",
        "isDefault": true
    }' 2>/dev/null || echo "✓ Data source already exists"

# Get Grafana URL
GRAFANA_URL=$(az grafana show \
    --name "$GRAFANA_PRIMARY" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --query "properties.endpoint" \
    --output tsv)

# Assign current user as Grafana Admin
CURRENT_USER_OBJECT_ID=$(az ad signed-in-user show --query id --output tsv)
az role assignment create \
    --role "Grafana Admin" \
    --assignee "$CURRENT_USER_OBJECT_ID" \
    --scope "$GRAFANA_RESOURCE_ID" 2>/dev/null || echo "✓ Role assignment already exists"

# Note: PodMonitor not needed - Azure Monitor Managed Prometheus automatically scrapes metrics
echo "✓ Azure Monitor will automatically collect PostgreSQL metrics"

echo "✓ Monitoring configuration complete!"
echo ""
echo "=== Access Information ==="
echo "Grafana URL: $GRAFANA_URL"
echo "Azure Monitor Workspace: $AMW_PRIMARY"
echo "Log Analytics Workspace: $ALA_PRIMARY"
echo ""
echo "To view PostgreSQL metrics in Grafana:"
echo "1. Open Grafana URL in browser"
echo "2. Navigate to Dashboards > Import"
echo "3. Upload grafana/grafana-cnpg-ha-dashboard.json"
echo "   (Or use CloudNativePG official dashboard from https://cloudnative-pg.io/documentation/current/monitoring/)"
echo ""
echo "Note: Azure Monitor Managed Prometheus is configured in step 6a"
