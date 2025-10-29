#!/bin/bash
# Auto-generate environment variables for devcontainer
# This creates a persistent .env file with generated values

ENV_FILE="/workspaces/azure-postgresql-ha-aks-workshop/.env"

# Check if .env already exists
if [ -f "$ENV_FILE" ]; then
    echo "✅ Environment variables already generated at: $ENV_FILE"
    echo "   To regenerate, delete the file and rebuild the container."
    exit 0
fi

echo "🔧 Generating environment variables..."

# Generate unique suffix
SUFFIX=$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | fold -w 8 | head -n 1)

# Generate DNS prefix
DNSPREFIX="a$(openssl rand -hex 5 | cut -c1-11)"

# Get public IP
PUBLIC_IP=$(dig +short myip.opendns.com @resolver3.opendns.com 2>/dev/null || curl -s ifconfig.me || echo "unknown")

# Create .env file
cat > "$ENV_FILE" <<EOF
# Auto-generated environment variables
# Generated on: $(date)
# DO NOT COMMIT THIS FILE TO GIT

# Unique suffix for this deployment
export SUFFIX="$SUFFIX"

# Base configuration
export LOCAL_NAME="cnpg"
export TAGS="owner=\${USER:-user} environment=demo"

# Resource group and region
export RESOURCE_GROUP_NAME="rg-\${LOCAL_NAME}-\${SUFFIX}"
export PRIMARY_CLUSTER_REGION="\${AZURE_REGION:-swedencentral}"

# AKS cluster configuration
export AKS_PRIMARY_CLUSTER_NAME="aks-primary-\${LOCAL_NAME}-\${SUFFIX}"
export AKS_PRIMARY_MANAGED_RG_NAME="rg-\${LOCAL_NAME}-primary-aksmanaged-\${SUFFIX}"
export AKS_PRIMARY_CLUSTER_FED_CREDENTIAL_NAME="pg-primary-fedcred1-\${LOCAL_NAME}-\${SUFFIX}"
export AKS_PRIMARY_CLUSTER_PG_DNSPREFIX="$DNSPREFIX"
export AKS_CLUSTER_VERSION="\${AKS_VERSION:-1.32}"

# Managed identity
export AKS_UAMI_CLUSTER_IDENTITY_NAME="mi-aks-\${LOCAL_NAME}-\${SUFFIX}"

# Node pool configuration
export SYSTEM_NODE_POOL_VMSKU="\${SYSTEM_VM_SKU:-Standard_D2s_v5}"
export USER_NODE_POOL_NAME="postgres"
export USER_NODE_POOL_VMSKU="\${USER_VM_SKU:-Standard_E8as_v6}"

# PostgreSQL configuration
export PG_NAMESPACE="cnpg-database"
export PG_SYSTEM_NAMESPACE="cnpg-system"
export PG_PRIMARY_CLUSTER_NAME="pg-primary-\${LOCAL_NAME}-\${SUFFIX}"
export PG_PRIMARY_STORAGE_ACCOUNT_NAME="hacnpgpsa\${SUFFIX}"
export PG_STORAGE_BACKUP_CONTAINER_NAME="backups"

# Storage class for Premium SSD v2
export POSTGRES_STORAGE_CLASS="managed-csi-premium-v2"
export STORAGECLASS_NAME="managed-csi-premium-v2"

# Storage configuration (Premium SSD v2)
export DISK_IOPS="\${DISK_IOPS:-40000}"
export DISK_THROUGHPUT="\${DISK_THROUGHPUT:-1250}"
export PG_STORAGE_SIZE="\${PG_STORAGE_SIZE:-200Gi}"

# PostgreSQL database configuration
export PG_DATABASE_NAME="\${PG_DATABASE_NAME:-appdb}"
export PG_DATABASE_USER="\${PG_DATABASE_USER:-app}"
export PG_DATABASE_PASSWORD="\${PG_DATABASE_PASSWORD:-SecurePassword123!}"

# PostgreSQL resource allocation (Safe for Standard_E8as_v6 with 20% AKS overhead)
# Node capacity: 8 vCPU, 64GB - 20% AKS = 6.4 vCPU, 51.2GB available
# Per node: 1 PostgreSQL pod + 1 PgBouncer pod + system pods
export PG_MEMORY="\${PG_MEMORY:-40Gi}"  # Leaves 11GB for PgBouncer (2GB) + system (9GB)
export PG_CPU="\${PG_CPU:-4}"           # Leaves 2.4 vCPU for PgBouncer (1) + system (1.4)

# CloudNativePG operator version
export CNPG_VERSION="\${CNPG_VERSION:-0.22.1}"

# Monitoring configuration
export GRAFANA_PRIMARY="grafana-\${LOCAL_NAME}-\${SUFFIX}"
export AMW_PRIMARY="amw-\${LOCAL_NAME}-\${SUFFIX}"
export ALA_PRIMARY="ala-\${LOCAL_NAME}-\${SUFFIX}"

# Network configuration
export MY_PUBLIC_CLIENT_IP="$PUBLIC_IP"

# Feature flags
export ENABLE_AZURE_PVC_UPDATES="true"
EOF

echo "✅ Environment file created: $ENV_FILE"
echo ""
echo "=== Generated Configuration ==="
echo "Suffix:              $SUFFIX"
echo "Resource Group:      rg-cnpg-$SUFFIX"
echo "AKS Cluster:         aks-primary-cnpg-$SUFFIX"
echo "Storage Account:     hacnpgpsa$SUFFIX"
echo "DNS Prefix:          $DNSPREFIX"
echo "Public IP:           $PUBLIC_IP"
echo "==============================="
echo ""
echo "💡 To use these variables, run:"
echo "   source /workspaces/azure-postgresql-ha-aks-workshop/.env"
