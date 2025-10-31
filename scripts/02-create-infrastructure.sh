#!/bin/bash
# Script 02: Create Azure Infrastructure
# Creates resource group, VNet, storage account, managed identity, AKS cluster, and monitoring

set -euo pipefail

# Source environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/../.env" ]; then
    source "${SCRIPT_DIR}/../.env"
else
    source "${SCRIPT_DIR}/../config/environment-variables.sh"
fi

echo "=== Creating Azure Infrastructure ==="

# Create resource group
echo "Creating resource group: $RESOURCE_GROUP_NAME in $PRIMARY_CLUSTER_REGION"
az group create \
    --name "$RESOURCE_GROUP_NAME" \
    --location "$PRIMARY_CLUSTER_REGION" \
    --tags $TAGS \
    --query 'properties.provisioningState' \
    --output tsv

# Create user-assigned managed identity
echo "Creating managed identity: $AKS_UAMI_CLUSTER_IDENTITY_NAME"
AKS_UAMI_WI_IDENTITY=$(az identity create \
    --name "$AKS_UAMI_CLUSTER_IDENTITY_NAME" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --location "$PRIMARY_CLUSTER_REGION" \
    --output json)

export AKS_UAMI_WORKLOAD_OBJECTID=$(echo "${AKS_UAMI_WI_IDENTITY}" | jq -r '.principalId')
export AKS_UAMI_WORKLOAD_RESOURCEID=$(echo "${AKS_UAMI_WI_IDENTITY}" | jq -r '.id')
export AKS_UAMI_WORKLOAD_CLIENTID=$(echo "${AKS_UAMI_WI_IDENTITY}" | jq -r '.clientId')

echo "Managed Identity Client ID: $AKS_UAMI_WORKLOAD_CLIENTID"

# Create storage account for backups
echo "Creating storage account: $PG_PRIMARY_STORAGE_ACCOUNT_NAME"
az storage account create \
    --name "$PG_PRIMARY_STORAGE_ACCOUNT_NAME" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --location "$PRIMARY_CLUSTER_REGION" \
    --sku Standard_ZRS \
    --kind StorageV2 \
    --query 'provisioningState' \
    --output tsv

# Create backup container (before network restrictions)
echo "Creating storage container: $PG_STORAGE_BACKUP_CONTAINER_NAME"
az storage container create \
    --name "$PG_STORAGE_BACKUP_CONTAINER_NAME" \
    --account-name "$PG_PRIMARY_STORAGE_ACCOUNT_NAME" \
    --auth-mode login

# Assign Storage Blob Data Contributor role to managed identity
echo "Assigning Storage Blob Data Contributor role..."
STORAGE_ACCOUNT_PRIMARY_RESOURCE_ID=$(az storage account show \
    --name "$PG_PRIMARY_STORAGE_ACCOUNT_NAME" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --query "id" \
    --output tsv)

az role assignment create \
    --role "Storage Blob Data Contributor" \
    --assignee-object-id "$AKS_UAMI_WORKLOAD_OBJECTID" \
    --assignee-principal-type ServicePrincipal \
    --scope "$STORAGE_ACCOUNT_PRIMARY_RESOURCE_ID" \
    --query "id" \
    --output tsv

# Create Azure Managed Grafana
echo "Creating Azure Managed Grafana: $GRAFANA_PRIMARY"
GRAFANA_RESOURCE_ID=$(az grafana create \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --name "$GRAFANA_PRIMARY" \
    --location "$PRIMARY_CLUSTER_REGION" \
    --zone-redundancy Disabled \
    --tags $TAGS \
    --query "id" \
    --output tsv)

# Convert to lowercase for AKS compatibility (AKS requires lowercase provider names)
GRAFANA_RESOURCE_ID=$(echo "$GRAFANA_RESOURCE_ID" | tr '[:upper:]' '[:lower:]')

# Create Azure Monitor workspace
echo "Creating Azure Monitor workspace: $AMW_PRIMARY"
AMW_RESOURCE_ID=$(az monitor account create \
    --name "$AMW_PRIMARY" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --location "$PRIMARY_CLUSTER_REGION" \
    --tags $TAGS \
    --query "id" \
    --output tsv)

# Create Log Analytics workspace
echo "Creating Log Analytics workspace: $ALA_PRIMARY"
ALA_RESOURCE_ID=$(az monitor log-analytics workspace create \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --workspace-name "$ALA_PRIMARY" \
    --location "$PRIMARY_CLUSTER_REGION" \
    --query "id" \
    --output tsv)

# Create Virtual Network for AKS and test VMs
echo "Creating Virtual Network: ${AKS_PRIMARY_CLUSTER_NAME}-vnet"
VNET_NAME="${AKS_PRIMARY_CLUSTER_NAME}-vnet"
az network vnet create \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --name "$VNET_NAME" \
    --location "$PRIMARY_CLUSTER_REGION" \
    --address-prefixes 10.224.0.0/12 \
    --query "newVNet.provisioningState" \
    --output tsv

# Create AKS subnet with service endpoint for Azure Storage
echo "Creating AKS subnet..."
AKS_SUBNET_NAME="${AKS_PRIMARY_CLUSTER_NAME}-aks-subnet"
AKS_SUBNET_ID=$(az network vnet subnet create \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --vnet-name "$VNET_NAME" \
    --name "$AKS_SUBNET_NAME" \
    --address-prefixes 10.224.0.0/16 \
    --service-endpoints Microsoft.Storage \
    --query "id" \
    --output tsv)

# Configure storage account network rules (after AKS subnet creation)
echo "Configuring storage account network access..."
az storage account network-rule add \
    --account-name "$PG_PRIMARY_STORAGE_ACCOUNT_NAME" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --subnet "$AKS_SUBNET_ID" \
    --output none

az storage account update \
    --name "$PG_PRIMARY_STORAGE_ACCOUNT_NAME" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --default-action Deny \
    --bypass AzureServices \
    --output none

echo "✓ Storage account network rules configured:"
echo "  - Default action: Deny"
echo "  - Allow trusted Microsoft services: Yes"
echo "  - Allow AKS subnet: $AKS_SUBNET_NAME"

# Create dedicated subnet for failover testing VMs (/27 = 32 IPs, 27 usable)
echo "Creating VM subnet for failover testing..."
VM_SUBNET_NAME="${AKS_PRIMARY_CLUSTER_NAME}-vm-subnet"
VM_SUBNET_ID=$(az network vnet subnet create \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --vnet-name "$VNET_NAME" \
    --name "$VM_SUBNET_NAME" \
    --address-prefixes 10.225.0.0/27 \
    --query "id" \
    --output tsv)

# Create Azure Bastion subnet (/26 required, 64 IPs)
echo "Creating Azure Bastion subnet..."
BASTION_SUBNET_NAME="AzureBastionSubnet"
BASTION_SUBNET_ID=$(az network vnet subnet create \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --vnet-name "$VNET_NAME" \
    --name "$BASTION_SUBNET_NAME" \
    --address-prefixes 10.225.1.0/26 \
    --query "id" \
    --output tsv)

echo "✓ Virtual Network created:"
echo "  VNet: $VNET_NAME (10.224.0.0/12)"
echo "  AKS Subnet: $AKS_SUBNET_NAME (10.224.0.0/16)"
echo "  VM Subnet: $VM_SUBNET_NAME (10.225.0.0/27)"
echo "  Bastion Subnet: $BASTION_SUBNET_NAME (10.225.1.0/26)"

# Create NAT Gateway for VM subnet outbound connectivity
echo "Creating NAT Gateway for VM subnet..."
NAT_GATEWAY_NAME="${AKS_PRIMARY_CLUSTER_NAME}-nat-gateway"
NAT_PUBLIC_IP_NAME="${AKS_PRIMARY_CLUSTER_NAME}-nat-pip"

# Create public IP for NAT Gateway
az network public-ip create \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --name "$NAT_PUBLIC_IP_NAME" \
    --location "$PRIMARY_CLUSTER_REGION" \
    --sku Standard \
    --allocation-method Static \
    --query "publicIp.provisioningState" \
    --output tsv

# Create NAT Gateway
az network nat gateway create \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --name "$NAT_GATEWAY_NAME" \
    --location "$PRIMARY_CLUSTER_REGION" \
    --public-ip-addresses "$NAT_PUBLIC_IP_NAME" \
    --idle-timeout 10 \
    --query "provisioningState" \
    --output tsv

# Associate NAT Gateway with VM subnet
echo "Associating NAT Gateway with VM subnet..."
az network vnet subnet update \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --vnet-name "$VNET_NAME" \
    --name "$VM_SUBNET_NAME" \
    --nat-gateway "$NAT_GATEWAY_NAME" \
    --output none

echo "✓ NAT Gateway created and associated with VM subnet"

# Create public IP for Azure Bastion
echo "Creating Azure Bastion public IP..."
BASTION_PUBLIC_IP_NAME="${AKS_PRIMARY_CLUSTER_NAME}-bastion-pip"
az network public-ip create \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --name "$BASTION_PUBLIC_IP_NAME" \
    --location "$PRIMARY_CLUSTER_REGION" \
    --sku Standard \
    --allocation-method Static \
    --query "publicIp.provisioningState" \
    --output tsv

# Create Azure Bastion (Standard SKU with --no-wait for parallel deployment)
echo "Creating Azure Bastion (Standard SKU, ~10 minutes, running in background)..."
BASTION_NAME="${AKS_PRIMARY_CLUSTER_NAME}-bastion"
az network bastion create \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --name "$BASTION_NAME" \
    --location "$PRIMARY_CLUSTER_REGION" \
    --vnet-name "$VNET_NAME" \
    --public-ip-address "$BASTION_PUBLIC_IP_NAME" \
    --sku Standard \
    --enable-tunneling true \
    --no-wait

echo "✓ Azure Bastion deployment initiated (will complete in background)"

# Create AKS cluster
echo "Creating AKS cluster: $AKS_PRIMARY_CLUSTER_NAME (this may take 10-15 minutes)"
az aks create \
    --name "$AKS_PRIMARY_CLUSTER_NAME" \
    --tags $TAGS \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --location "$PRIMARY_CLUSTER_REGION" \
    --generate-ssh-keys \
    --node-resource-group "$AKS_PRIMARY_MANAGED_RG_NAME" \
    --enable-managed-identity \
    --assign-identity "$AKS_UAMI_WORKLOAD_RESOURCEID" \
    --network-plugin azure \
    --network-plugin-mode overlay \
    --network-dataplane cilium \
    --vnet-subnet-id "$AKS_SUBNET_ID" \
    --nodepool-name systempool \
    --os-sku AzureLinux \
    --enable-oidc-issuer \
    --enable-workload-identity \
    --enable-cluster-autoscaler \
    --min-count 2 \
    --max-count 3 \
    --node-vm-size "$SYSTEM_NODE_POOL_VMSKU" \
    --enable-addons monitoring \
    --workspace-resource-id "$ALA_RESOURCE_ID" \
    --enable-azure-monitor-metrics \
    --azure-monitor-workspace-resource-id "$AMW_RESOURCE_ID" \
    --grafana-resource-id "$GRAFANA_RESOURCE_ID" \
    --tier standard \
    --kubernetes-version "$AKS_CLUSTER_VERSION" \
    --zones 1 2 3 \
    --output table

# Wait for cluster creation to complete
echo "Waiting for AKS cluster creation to complete..."
az aks wait \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --name "$AKS_PRIMARY_CLUSTER_NAME" \
    --created

# Add PostgreSQL user node pool
echo "Adding PostgreSQL user node pool: $USER_NODE_POOL_NAME"
az aks nodepool add \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --cluster-name "$AKS_PRIMARY_CLUSTER_NAME" \
    --name "$USER_NODE_POOL_NAME" \
    --os-sku AzureLinux \
    --enable-cluster-autoscaler \
    --min-count 3 \
    --max-count 6 \
    --node-vm-size "$USER_NODE_POOL_VMSKU" \
    --zones 1 2 3 \
    --labels workload=postgres \
    --output table

# Get AKS credentials
echo "Getting AKS cluster credentials..."
az aks get-credentials \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --name "$AKS_PRIMARY_CLUSTER_NAME" \
    --output none

# Function to retry kubectl commands with exponential backoff
retry_kubectl() {
    local max_attempts=5
    local timeout=2
    local attempt=1
    local exitCode=0

    while [ $attempt -le $max_attempts ]; do
        if "$@"; then
            return 0
        else
            exitCode=$?
        fi

        if [ $attempt -lt $max_attempts ]; then
            echo "Attempt $attempt failed. Waiting ${timeout}s before retry..."
            sleep $timeout
            timeout=$((timeout * 2))
            attempt=$((attempt + 1))
        else
            echo "Command failed after $max_attempts attempts."
            return $exitCode
        fi
    done
}

# Create namespaces with retry logic
echo "Creating Kubernetes namespaces..."
echo "Waiting for AKS API server to be fully ready..."
sleep 30  # Initial wait for API server stabilization

retry_kubectl kubectl create namespace "$PG_NAMESPACE" --context "$AKS_PRIMARY_CLUSTER_NAME" --dry-run=client -o yaml | kubectl apply -f -
retry_kubectl kubectl create namespace "$PG_SYSTEM_NAMESPACE" --context "$AKS_PRIMARY_CLUSTER_NAME" --dry-run=client -o yaml | kubectl apply -f -

echo "Verifying namespaces..."
kubectl get namespace "$PG_NAMESPACE" "$PG_SYSTEM_NAMESPACE"

# Note: Container Insights is already enabled during AKS cluster creation
# via --enable-addons monitoring flag, so no need to enable it again here

# Save outputs to file for next scripts
OUTPUT_FILE="${SCRIPT_DIR}/../.deployment-outputs"
cat > "$OUTPUT_FILE" << EOF
export AKS_UAMI_WORKLOAD_CLIENTID="$AKS_UAMI_WORKLOAD_CLIENTID"
export AKS_UAMI_WORKLOAD_OBJECTID="$AKS_UAMI_WORKLOAD_OBJECTID"
export STORAGE_ACCOUNT_PRIMARY_RESOURCE_ID="$STORAGE_ACCOUNT_PRIMARY_RESOURCE_ID"
export GRAFANA_RESOURCE_ID="$GRAFANA_RESOURCE_ID"
export AMW_RESOURCE_ID="$AMW_RESOURCE_ID"
export ALA_RESOURCE_ID="$ALA_RESOURCE_ID"
export VNET_NAME="$VNET_NAME"
export AKS_SUBNET_NAME="$AKS_SUBNET_NAME"
export AKS_SUBNET_ID="$AKS_SUBNET_ID"
export VM_SUBNET_NAME="$VM_SUBNET_NAME"
export VM_SUBNET_ID="$VM_SUBNET_ID"
export BASTION_NAME="$BASTION_NAME"
export NAT_GATEWAY_NAME="$NAT_GATEWAY_NAME"
EOF

echo "✓ Infrastructure creation complete!"
echo "Outputs saved to: $OUTPUT_FILE"
echo ""
echo "Network Configuration:"
echo "  VNet: $VNET_NAME (10.224.0.0/12)"
echo "  AKS Subnet: $AKS_SUBNET_NAME (10.224.0.0/16)"
echo "  VM Subnet: $VM_SUBNET_NAME (10.225.0.0/27, NAT Gateway: $NAT_GATEWAY_NAME)"
echo "  Bastion Subnet: AzureBastionSubnet (10.225.1.0/26, Bastion: $BASTION_NAME)"
echo ""
echo "⏳ Note: Azure Bastion is deploying in background (~10 minutes)"
echo "   Check status: az network bastion show -g $RESOURCE_GROUP_NAME -n $BASTION_NAME --query provisioningState"
