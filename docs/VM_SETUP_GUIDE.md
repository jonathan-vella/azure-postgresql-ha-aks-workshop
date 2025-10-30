# VM Setup Guide for Failover Testing

This guide covers setting up Azure VMs in the dedicated VM subnet for external failover testing.

## Prerequisites

- Infrastructure deployed with VM subnet (10.1.0.0/27)
- AKS cluster running with PostgreSQL deployed
- Azure CLI installed and authenticated

## VM Specifications

- **VM Size**: Standard_E8as_v6 (4 vCPU, 16 GB RAM)
- **OS**: Latest Ubuntu LTS
- **Location**: Same region as AKS cluster
- **Network**: Connected to VM subnet (10.1.0.0/27)
- **Count**: 1 VM sufficient for testing

## Automated VM Creation

```bash
# Source environment variables (DevContainer: source .env)
source .env  # or source config/environment-variables.sh

# Load deployment outputs
source .deployment-outputs

# Create VM in the VM subnet
az vm create \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --name "pgtest-vm-01" \
  --size "Standard_E8as_v6" \
  --image "Ubuntu2204" \
  --vnet-name "${RESOURCE_GROUP_NAME}-vnet" \
  --subnet "$VM_SUBNET_ID" \
  --admin-username "azureuser" \
  --generate-ssh-keys \
  --public-ip-address "" \
  --nsg "" \
  --output table

# Get VM private IP
VM_PRIVATE_IP=$(az vm show \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --name "pgtest-vm-01" \
  --show-details \
  --query privateIps \
  --output tsv)

echo "VM Created: pgtest-vm-01"
echo "Private IP: $VM_PRIVATE_IP"
```

## Connect to VM via Azure Bastion (Recommended)

```bash
# Create Bastion subnet if not exists
az network vnet subnet create \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --vnet-name "${RESOURCE_GROUP_NAME}-vnet" \
  --name "AzureBastionSubnet" \
  --address-prefixes "10.2.0.0/26"

# Create Bastion public IP
az network public-ip create \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --name "bastion-pip" \
  --sku Standard \
  --location "$LOCATION"

# Create Bastion host
az network bastion create \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --name "aks-bastion" \
  --public-ip-address "bastion-pip" \
  --vnet-name "${RESOURCE_GROUP_NAME}-vnet" \
  --location "$LOCATION"

# Connect via Azure CLI
az network bastion ssh \
  --name "aks-bastion" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --target-resource-id $(az vm show --resource-group "$RESOURCE_GROUP_NAME" --name "pgtest-vm-01" --query id -o tsv) \
  --auth-type "ssh-key" \
  --username "azureuser"
```

## Alternative: Connect via Jump Box in AKS

If Bastion is not available, use an AKS pod as jump box:

```bash
# Create jump box pod
kubectl run jump-box -n cnpg-database --image=ubuntu:22.04 -- sleep infinity

# Wait for pod
kubectl wait --for=condition=Ready pod/jump-box -n cnpg-database --timeout=60s

# Exec into pod
kubectl exec -it jump-box -n cnpg-database -- bash

# Inside pod, install SSH client
apt-get update && apt-get install -y openssh-client

# SSH to VM (requires private key)
ssh azureuser@<VM_PRIVATE_IP>
```

## Install PostgreSQL Client Tools on VM

Once connected to the VM, install required tools:

```bash
# Update system
sudo apt-get update && sudo apt-get upgrade -y

# Install PostgreSQL 17 client and pgbench
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget -qO- https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo tee /etc/apt/trusted.gpg.d/pgdg.asc &>/dev/null
sudo apt-get update
sudo apt-get install -y postgresql-client-17 postgresql-contrib-17

# Verify installation
psql --version  # Should show PostgreSQL 17.x
pgbench --version

# Install monitoring tools
sudo apt-get install -y htop iotop sysstat curl jq

# Install kubectl for cluster interaction
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl
```

## Configure kubectl Access from VM

To run scenario scripts from the VM, configure kubectl:

```bash
# On your local machine, get AKS credentials
az aks get-credentials \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --name "$AKS_CLUSTER_NAME" \
  --overwrite-existing

# Copy kubeconfig to VM (via jump box or Bastion)
# Option 1: Via kubectl cp
kubectl cp ~/.kube/config jump-box:/tmp/kubeconfig -n cnpg-database

# Then from jump box, scp to VM
kubectl exec -it jump-box -n cnpg-database -- scp /tmp/kubeconfig azureuser@<VM_PRIVATE_IP>:/home/azureuser/.kube/config

# Option 2: Manually copy content
cat ~/.kube/config
# SSH to VM and paste content to ~/.kube/config
```

## Get PostgreSQL Service Endpoints

The VM needs to connect to PostgreSQL services. Get the ClusterIP addresses:

```bash
# Direct PostgreSQL services
kubectl get svc pg-primary-rw -n cnpg-database -o jsonpath='{.spec.clusterIP}'
kubectl get svc pg-primary-ro -n cnpg-database -o jsonpath='{.spec.clusterIP}'

# PgBouncer pooler services
kubectl get svc pg-primary-pooler-rw -n cnpg-database -o jsonpath='{.spec.clusterIP}'
kubectl get svc pg-primary-pooler-ro -n cnpg-database -o jsonpath='{.spec.clusterIP}'
```

**Note**: ClusterIP services are accessible from the VM because it's in the same VNet as AKS.

## Set PostgreSQL Password on VM

```bash
# Get password from Kubernetes secret
export PGPASSWORD=$(kubectl get secret pg-primary-app -n cnpg-database -o jsonpath='{.data.password}' | base64 -d)

# Verify connection
psql -h <CLUSTERIP_OF_pg-primary-rw> -U app -d appdb -c "SELECT version();"
```

## Copy Failover Test Scripts to VM

```bash
# From local machine, copy scripts directory
cd /workspaces/azure-postgresql-ha-aks-workshop

# Via jump box
kubectl cp scripts/failover-testing jump-box:/tmp/failover-testing -n cnpg-database

# Then from jump box to VM
kubectl exec -it jump-box -n cnpg-database -- bash
scp -r /tmp/failover-testing azureuser@<VM_PRIVATE_IP>:/home/azureuser/

# Or use git clone on VM
ssh azureuser@<VM_PRIVATE_IP>
git clone https://github.com/jonathan-vella/azure-postgresql-ha-aks-workshop.git
cd azure-postgresql-ha-aks-workshop/scripts/failover-testing
```

## Test Connectivity from VM

```bash
# SSH to VM
ssh azureuser@<VM_PRIVATE_IP>

# Set environment
export PGPASSWORD="<password>"
export PG_PRIMARY_RW="<clusterip-of-pg-primary-rw>"
export PG_POOLER_RW="<clusterip-of-pg-primary-pooler-rw>"

# Test direct connection
psql -h "$PG_PRIMARY_RW" -U app -d appdb -c "SELECT 'Direct connection works!';"

# Test pooler connection
psql -h "$PG_POOLER_RW" -U app -d appdb -c "SELECT 'Pooler connection works!';"

# Test pgbench initialization
pgbench -h "$PG_PRIMARY_RW" -U app -d appdb -i -s 1 --quiet

# Test pgbench run (10 seconds)
pgbench -h "$PG_PRIMARY_RW" -U app -d appdb -T 10 -c 10 -j 2
```

## Run VM-Based Failover Tests

Once the VM is configured, run scenario scripts:

```bash
cd ~/azure-postgresql-ha-aks-workshop/scripts/failover-testing

# Make scripts executable
chmod +x scenario-*.sh verify-consistency.sh

# Set environment variables
export PGPASSWORD=$(kubectl get secret pg-primary-app -n cnpg-database -o jsonpath='{.data.password}' | base64 -d)

# Run scenarios (examples)
./scenario-3a-vm-direct-manual.sh
./scenario-3b-vm-direct-simulated.sh
./scenario-4a-vm-pooler-manual.sh
./scenario-4b-vm-pooler-simulated.sh
```

## Cleanup

```bash
# Delete VM
az vm delete \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --name "pgtest-vm-01" \
  --yes --no-wait

# Optionally delete Bastion (if created)
az network bastion delete \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --name "aks-bastion" \
  --yes
```

## Troubleshooting

### Cannot Connect to PostgreSQL from VM

1. **Check VNet connectivity**:
   ```bash
   # From VM, test network connectivity
   ping <AKS_NODE_IP>
   nc -zv <CLUSTERIP_OF_pg-primary-rw> 5432
   ```

2. **Verify NSG rules**:
   - Ensure no NSG blocks traffic between VM subnet and AKS subnet
   - Check AKS cluster security rules

3. **Check service endpoints**:
   ```bash
   kubectl get svc -n cnpg-database
   kubectl get endpoints -n cnpg-database
   ```

### kubectl Commands Fail on VM

1. **Verify kubeconfig**:
   ```bash
   kubectl config view
   kubectl get nodes
   ```

2. **Check AKS API server access**:
   - Ensure VM has network path to AKS API server
   - If AKS has authorized IP ranges, add VM's outbound IP

### SSH Connection Issues

- Use Azure Bastion for secure access without public IPs
- Check VM is running: `az vm list --resource-group "$RESOURCE_GROUP_NAME" --output table`
- Verify SSH keys: `az vm show --resource-group "$RESOURCE_GROUP_NAME" --name "pgtest-vm-01" --query "osProfile.linuxConfiguration.ssh.publicKeys"`

## Summary

| Component | Value |
|-----------|-------|
| VM Size | Standard_E8as_v6 |
| OS | Ubuntu 22.04 LTS |
| Subnet | 10.1.0.0/27 (VM subnet) |
| PostgreSQL Client | Version 17 |
| Access Method | Azure Bastion or Jump Box |
| Network | Same VNet as AKS (10.0.0.0/8) |

The VM is now ready to run external failover tests simulating client applications outside the Kubernetes cluster.
