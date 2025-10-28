#!/bin/bash
# Azure PostgreSQL HA on AKS - Environment Variables Configuration
# Based on Microsoft Learn reference implementation:
# https://learn.microsoft.com/en-us/azure/aks/create-postgresql-ha

# Generate unique suffix for resource names
export SUFFIX=$(cat /dev/urandom | LC_ALL=C tr -dc 'a-z0-9' | fold -w 8 | head -n 1)

# Base configuration
export LOCAL_NAME="cnpg"
export TAGS="owner=${USER:-user} environment=demo"

# Resource group and region
export RESOURCE_GROUP_NAME="rg-${LOCAL_NAME}-${SUFFIX}"
export PRIMARY_CLUSTER_REGION="${AZURE_REGION:-swedencentral}"

# AKS cluster configuration
export AKS_PRIMARY_CLUSTER_NAME="aks-primary-${LOCAL_NAME}-${SUFFIX}"
export AKS_PRIMARY_MANAGED_RG_NAME="rg-${LOCAL_NAME}-primary-aksmanaged-${SUFFIX}"
export AKS_PRIMARY_CLUSTER_FED_CREDENTIAL_NAME="pg-primary-fedcred1-${LOCAL_NAME}-${SUFFIX}"
export AKS_PRIMARY_CLUSTER_PG_DNSPREFIX=$(echo $(echo "a$(openssl rand -hex 5 | cut -c1-11)"))
export AKS_CLUSTER_VERSION="${AKS_VERSION:-1.32}"

# Managed identity
export AKS_UAMI_CLUSTER_IDENTITY_NAME="mi-aks-${LOCAL_NAME}-${SUFFIX}"

# Node pool configuration
export SYSTEM_NODE_POOL_VMSKU="${SYSTEM_VM_SKU:-Standard_D2s_v5}"
export USER_NODE_POOL_NAME="postgres"
export USER_NODE_POOL_VMSKU="${USER_VM_SKU:-Standard_E8as_v6}"

# PostgreSQL configuration
export PG_NAMESPACE="cnpg-database"
export PG_SYSTEM_NAMESPACE="cnpg-system"
export PG_PRIMARY_CLUSTER_NAME="pg-primary-${LOCAL_NAME}-${SUFFIX}"
export PG_PRIMARY_STORAGE_ACCOUNT_NAME="hacnpgpsa${SUFFIX}"
export PG_STORAGE_BACKUP_CONTAINER_NAME="backups"

# Storage class for Premium SSD v2
export POSTGRES_STORAGE_CLASS="managed-csi-premium-v2"
export STORAGECLASS_NAME="managed-csi-premium-v2"  # Alias for script compatibility

# Storage configuration (Premium SSD v2 - Optimized for 10K TPS)
export DISK_IOPS="${DISK_IOPS:-40000}"      # Max Premium SSD v2 IOPS
export DISK_THROUGHPUT="${DISK_THROUGHPUT:-1250}"  # Max Premium SSD v2 throughput (MB/s)
export PG_STORAGE_SIZE="${PG_STORAGE_SIZE:-200Gi}"  # Increased for better performance

# PostgreSQL database configuration
export PG_DATABASE_NAME="${PG_DATABASE_NAME:-appdb}"
export PG_DATABASE_USER="${PG_DATABASE_USER:-app}"
export PG_DATABASE_PASSWORD="${PG_DATABASE_PASSWORD:-SecurePassword123!}"

# PostgreSQL resource allocation (Optimized for Standard_E8as_v6: 8 vCPU, 64 GiB RAM)
export PG_MEMORY="${PG_MEMORY:-48Gi}"   # 75% of 64 GiB available on E8as_v6
export PG_CPU="${PG_CPU:-6}"            # 75% of 8 vCPUs available on E8as_v6

# CloudNativePG operator version (Helm chart version)
# Operator v1.27.1 = Helm chart v0.26.1
export CNPG_VERSION="${CNPG_VERSION:-0.26.1}"

# Monitoring configuration
export GRAFANA_PRIMARY="grafana-${LOCAL_NAME}-${SUFFIX}"
export AMW_PRIMARY="amw-${LOCAL_NAME}-${SUFFIX}"
export ALA_PRIMARY="ala-${LOCAL_NAME}-${SUFFIX}"

# Network configuration
export MY_PUBLIC_CLIENT_IP=$(dig +short myip.opendns.com @resolver3.opendns.com 2>/dev/null || curl -s ifconfig.me)

# Feature flags
export ENABLE_AZURE_PVC_UPDATES="true"

# Display configuration
echo "=== Azure PostgreSQL HA on AKS Configuration ==="
echo "Resource Group:      $RESOURCE_GROUP_NAME"
echo "Region:              $PRIMARY_CLUSTER_REGION"
echo ""
echo "AKS Configuration:"
echo "  Cluster Name:      $AKS_PRIMARY_CLUSTER_NAME"
echo "  Version:           $AKS_CLUSTER_VERSION"
echo "  System VM SKU:     $SYSTEM_NODE_POOL_VMSKU"
echo "  User VM SKU:       $USER_NODE_POOL_VMSKU"
echo ""
echo "PostgreSQL Configuration:"
echo "  Cluster Name:      $PG_PRIMARY_CLUSTER_NAME"
echo "  Database:          $PG_DATABASE_NAME"
echo "  User:              $PG_DATABASE_USER"
echo "  Memory per Pod:    $PG_MEMORY"
echo "  CPU per Pod:       $PG_CPU"
echo "  CNPG Version:      $CNPG_VERSION"
echo ""
echo "Storage Configuration:"
echo "  Storage Account:   $PG_PRIMARY_STORAGE_ACCOUNT_NAME"
echo "  Storage Class:     $POSTGRES_STORAGE_CLASS"
echo "  Disk Size:         $PG_STORAGE_SIZE"
echo "  IOPS:              $DISK_IOPS"
echo "  Throughput:        $DISK_THROUGHPUT MB/s"
echo ""
echo "Network:"
echo "  Your Public IP:    $MY_PUBLIC_CLIENT_IP"
echo ""
echo "=============================================="
echo ""
echo "⚠️  IMPORTANT: Change PG_DATABASE_PASSWORD before deployment!"
