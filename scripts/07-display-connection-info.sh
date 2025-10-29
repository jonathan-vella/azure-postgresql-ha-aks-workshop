#!/bin/bash
# Script 07: Display Connection Information
# Shows PostgreSQL connection endpoints and credentials

set -euo pipefail

# Source environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/../.env" ]; then
    source "${SCRIPT_DIR}/../.env"
else
    source "${SCRIPT_DIR}/../config/environment-variables.sh"
fi
source "${SCRIPT_DIR}/../.deployment-outputs"

echo "=========================================="
echo "PostgreSQL HA Deployment - Connection Info"
echo "=========================================="
echo ""

# Cluster Status
echo "=== Cluster Status ==="
kubectl cnpg status "$PG_PRIMARY_CLUSTER_NAME" -n "$PG_NAMESPACE" --context "$AKS_PRIMARY_CLUSTER_NAME"
echo ""

# Services
echo "=== PostgreSQL Services ==="
kubectl get svc -n "$PG_NAMESPACE" --context "$AKS_PRIMARY_CLUSTER_NAME" | grep -E "NAME|$PG_PRIMARY_CLUSTER_NAME" || true
echo ""

# Connection Information
echo "=== Connection Information ==="
echo ""
echo "📊 Direct PostgreSQL Connections:"
echo "  Read-Write:  $PG_PRIMARY_CLUSTER_NAME-rw.$PG_NAMESPACE.svc.cluster.local:5432"
echo "  Read-Only:   $PG_PRIMARY_CLUSTER_NAME-ro.$PG_NAMESPACE.svc.cluster.local:5432"
echo ""
echo "🔄 PgBouncer Pooler Connections (Recommended):"
echo "  Read-Write:  $PG_PRIMARY_CLUSTER_NAME-pooler-rw.$PG_NAMESPACE.svc.cluster.local:5432"
echo "  Read-Only:   $PG_PRIMARY_CLUSTER_NAME-pooler-ro.$PG_NAMESPACE.svc.cluster.local:5432"
echo ""
echo "📦 Database Credentials:"
echo "  Database:    $PG_DATABASE_NAME"
echo "  Username:    app"
echo "  Password:    (stored in secret pg-app-secret)"
echo ""
echo "  Superuser:   $PG_DATABASE_USER"
echo "  Password:    (stored in secret pg-superuser-secret)"
echo ""

# Get password from secret
APP_PASSWORD=$(kubectl get secret pg-app-secret -n "$PG_NAMESPACE" -o jsonpath='{.data.password}' | base64 -d)
SUPER_PASSWORD=$(kubectl get secret pg-superuser-secret -n "$PG_NAMESPACE" -o jsonpath='{.data.password}' | base64 -d)

echo "🔐 Retrieved Passwords:"
echo "  App Password:        $APP_PASSWORD"
echo "  Superuser Password:  $SUPER_PASSWORD"
echo ""

# Test Connection Command
echo "=== Test Connection Commands ==="
echo ""
echo "1. Port-forward to access from local machine:"
echo "   kubectl port-forward svc/$PG_PRIMARY_CLUSTER_NAME-rw 5432:5432 -n $PG_NAMESPACE"
echo ""
echo "2. Connect using psql:"
echo "   psql -h localhost -U app -d $PG_DATABASE_NAME"
echo ""
echo "3. Or connect via PgBouncer pooler:"
echo "   kubectl port-forward svc/$PG_PRIMARY_CLUSTER_NAME-pooler-rw 5432:5432 -n $PG_NAMESPACE"
echo "   psql -h localhost -U app -d $PG_DATABASE_NAME"
echo ""

# Monitoring URLs
echo "=== Monitoring ==="
GRAFANA_URL=$(az grafana show \
    --name "$GRAFANA_PRIMARY" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --query properties.endpoint \
    -o tsv 2>/dev/null || echo "")

if [ -n "$GRAFANA_URL" ]; then
    echo "  Grafana:     $GRAFANA_URL"
    echo "  Dashboards:  Import CNPG dashboard from https://cloudnative-pg.io/documentation/current/monitoring/"
else
    echo "  Grafana:     (Configure in Azure Portal)"
fi
echo ""

# Backup Configuration
echo "=== Backup Configuration ==="
echo "  Storage Account:  $PG_PRIMARY_STORAGE_ACCOUNT_NAME"
echo "  Container:        $PG_STORAGE_BACKUP_CONTAINER_NAME"
echo "  WAL Archiving:    Enabled (via Barman Cloud Plugin)"
echo "  Retention:        7 days"
echo ""

# Resource Information
echo "=== Azure Resources ==="
echo "  Resource Group:   $RESOURCE_GROUP_NAME"
echo "  Region:           $PRIMARY_CLUSTER_REGION"
echo "  AKS Cluster:      $AKS_PRIMARY_CLUSTER_NAME"
echo "  Storage:          $PG_PRIMARY_STORAGE_ACCOUNT_NAME"
echo "  Grafana:          $GRAFANA_PRIMARY"
if [ -n "${BASTION_NAME:-}" ]; then
    echo "  Bastion:          $BASTION_NAME"
fi
if [ -n "${NAT_GATEWAY_NAME:-}" ]; then
    echo "  NAT Gateway:      $NAT_GATEWAY_NAME"
fi
echo ""

echo "=========================================="
echo "✅ Deployment Complete!"
echo "=========================================="
echo ""
echo "📚 Next Steps:"
echo "  1. Test database connection (see commands above)"
echo "  2. Import Grafana dashboards for monitoring"
echo "  3. Review failover testing guide: docs/FAILOVER_TESTING.md"
echo "  4. Configure automated backups schedule"
echo ""
