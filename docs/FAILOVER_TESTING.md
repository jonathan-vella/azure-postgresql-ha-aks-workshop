# PostgreSQL High Availability Failover Testing Guide

This guide provides comprehensive failover testing scenarios for the PostgreSQL HA deployment on AKS, designed for a **payment gateway workload processing 4,000 credit card transactions per second**.

---

## 📋 Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Test Environment Setup](#test-environment-setup)
4. [Testing Scenarios](#testing-scenarios)
5. [Running Tests](#running-tests)
6. [Metrics Collection](#metrics-collection)
7. [Expected Results](#expected-results)
8. [Troubleshooting](#troubleshooting)
9. [Best Practices](#best-practices)
10. [Next Steps](#next-steps)

---

## Overview

### Test Objectives

This guide validates the PostgreSQL HA deployment for lab and proof-of-concept purposes:

- ✅ **RPO = 0**: Zero data loss during failover (synchronous replication)
- ✅ **RTO < 10s**: Recovery Time Objective under 10 seconds
- ✅ **Connection Resilience**: Compare direct PostgreSQL vs PgBouncer pooler
- ✅ **Network Impact**: Compare AKS internal vs Azure VM external clients
- ✅ **Transaction Consistency**: Verify no data corruption during failover
- ✅ **Client Behavior**: Measure reconnection and error handling

### Test Matrix

8 comprehensive scenarios covering all critical combinations:

| Scenario | Client Location | Connection Method | Failover Type | Test Duration | Script |
|----------|----------------|-------------------|---------------|---------------|--------|
| **1A** | AKS Pod | Direct PostgreSQL | Manual Promote | 5 min (failover @ 2:30) | `scenario-1a-aks-direct-manual.sh` |
| **1B** | AKS Pod | Direct PostgreSQL | Simulated Failure | 5 min (failover @ 2:30) | `scenario-1b-aks-direct-failure.sh` |
| **2A** | AKS Pod | PgBouncer Pooler | Manual Promote | 5 min (failover @ 2:30) | `scenario-2a-aks-pooler-manual.sh` |
| **2B** | AKS Pod | PgBouncer Pooler | Simulated Failure | 5 min (failover @ 2:30) | `scenario-2b-aks-pooler-failure.sh` |
| **3A** | Azure VM | Direct PostgreSQL | Manual Promote | 5 min (failover @ 2:30) | `scenario-3a-vm-direct-manual.sh` |
| **3B** | Azure VM | Direct PostgreSQL | Simulated Failure | 5 min (failover @ 2:30) | `scenario-3b-vm-direct-failure.sh` |
| **4A** | Azure VM | PgBouncer Pooler | Manual Promote | 5 min (failover @ 2:30) | `scenario-4a-vm-pooler-manual.sh` |
| **4B** | Azure VM | PgBouncer Pooler | Simulated Failure | 5 min (failover @ 2:30) | `scenario-4b-vm-pooler-failure.sh` |

### Workload Profile: Payment Gateway

**Characteristics:**

- **Target TPS**: 4,000 transactions/second sustained
- **Write:Read Ratio**: 80:20 (payment processing heavy)
- **Concurrency**: 100 simultaneous client connections
- **Dataset**: Scale 100 (~1.6 GB) for realistic testing
- **Protocol**:
  - Prepared statements for direct connections (optimal performance)
  - Simple protocol for PgBouncer (required for transaction pooling)

**Test Duration:**

- Total: 5 minutes (300 seconds)
- Pre-failover: 150 seconds (2.5 minutes)
- Failover trigger: 150 second mark
- Post-failover: 150 seconds (2.5 minutes)

---

## Prerequisites

### 1. Deployed PostgreSQL HA Cluster

Ensure the PostgreSQL HA cluster is fully deployed and healthy:

```bash
# Verify cluster is running
kubectl cnpg status pg-primary -n cnpg-database

# Expected output:
# Cluster in healthy state
# Primary instance ready
# 1 sync replica + 1 async replica
# WAL archiving active
```

**Required Cluster State:**

- ✅ 1 Primary instance (role=primary)
- ✅ 1 Synchronous replica (replication=sync)
- ✅ 1 Asynchronous replica (replication=async)
- ✅ All PgBouncer poolers running
- ✅ WAL archiving active
- ✅ Backups to Azure Blob Storage working

### 2. Azure VM for External Testing

Create an Ubuntu VM in the VM subnet for external testing:

```bash
# Load environment variables
# DevContainer: source .env
# Manual: source config/environment-variables.sh
source .env  # or source config/environment-variables.sh
source .deployment-outputs

# Create Ubuntu 24.04 VM in the dedicated VM subnet (NO public IP - using Bastion)
VM_NAME="${AKS_PRIMARY_CLUSTER_NAME}-test-vm"
VM_SIZE="Standard_E8as_v6"  # 4 vCPU, 16 GB RAM

az vm create \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --name "$VM_NAME" \
  --location "$PRIMARY_CLUSTER_REGION" \
  --size "$VM_SIZE" \
  --image Ubuntu2404 \
  --vnet-name "$VNET_NAME" \
  --subnet "$VM_SUBNET_NAME" \
  --admin-username azureuser \
  --generate-ssh-keys \
  --public-ip-address "" \
  --nsg-rule NONE \
  --output table

# Get VM private IP (internal connectivity)
VM_PRIVATE_IP=$(az vm show -d \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --name "$VM_NAME" \
  --query privateIps \
  --output tsv)

echo "VM Private IP: $VM_PRIVATE_IP"

# Save VM details
cat >> .deployment-outputs << EOF
export VM_NAME="$VM_NAME"
export VM_PRIVATE_IP="$VM_PRIVATE_IP"
export BASTION_NAME="$BASTION_NAME"
EOF
```

### 3. Install PostgreSQL Client Tools on VM

**Connect to VM via Azure Bastion:**

```bash
# SSH to the VM via Bastion (uses Azure CLI authentication)
az network bastion ssh \
  --name "$BASTION_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --target-resource-id $(az vm show -g "$RESOURCE_GROUP_NAME" -n "$VM_NAME" --query id -o tsv) \
  --auth-type AAD
```

**Or using SSH key:**

```bash
# SSH with key
az network bastion ssh \
  --name "$BASTION_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --target-resource-id $(az vm show -g "$RESOURCE_GROUP_NAME" -n "$VM_NAME" --query id -o tsv) \
  --auth-type ssh-key \
  --username azureuser \
  --ssh-key ~/.ssh/id_rsa

# Install PostgreSQL 17 client and tools
sudo apt update
sudo apt install -y wget gnupg2
sudo sh -c 'echo "deb https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
sudo apt update
sudo apt install -y postgresql-client-17 postgresql-contrib-17

# Verify installation
psql --version
pgbench --version

# Install monitoring tools
sudo apt install -y jq bc sysstat

# Exit VM
exit
```

### 4. Network Configuration

**Service Endpoints:**

- **Direct Read-Write**: `pg-primary-rw.cnpg-database.svc.cluster.local:5432`
- **Direct Read-Only**: `pg-primary-ro.cnpg-database.svc.cluster.local:5432`
- **Pooler Read-Write**: `pg-primary-pooler-rw.cnpg-database.svc.cluster.local:5432`
- **Pooler Read-Only**: `pg-primary-pooler-ro.cnpg-database.svc.cluster.local:5432`

**Note**: For VM access to ClusterIP services, use `kubectl port-forward` from a bastion or expose services via LoadBalancer. For lab testing, this is sufficient.

---

## Test Environment Setup

> **🔒 VM Connectivity Note**: All test VMs use Azure Bastion for secure access (no public IPs).
> 
> **Quick SSH command:**
> ```bash
> # Connect to test VM via Bastion
> az network bastion ssh \
>   --name "$BASTION_NAME" \
>   --resource-group "$RESOURCE_GROUP_NAME" \
>   --target-resource-id $(az vm show -g "$RESOURCE_GROUP_NAME" -n "$VM_NAME" --query id -o tsv) \
>   --auth-type AAD
> ```

### 1. Initialize Test Database

Create a realistic dataset for payment gateway testing:

```bash
# Get PostgreSQL password
PG_PASSWORD=$(kubectl get secret pg-superuser-secret \
  -n cnpg-database \
  -o jsonpath='{.data.password}' | base64 -d)

# Create initialization pod
kubectl run pgbench-init \
  --image=postgres:17 \
  --restart=Never \
  --rm -it \
  -n cnpg-database \
  --env="PGPASSWORD=$PG_PASSWORD" \
  -- bash -c "
    echo 'Initializing pgbench schema (scale 100 = ~1.6 GB)...'
    pgbench -h pg-primary-rw -U app -d appdb -i -s 100 --quiet
    echo 'Schema initialized successfully'
    psql -h pg-primary-rw -U app -d appdb -c 'SELECT pg_size_pretty(pg_database_size(current_database()));'
  "
```

**This creates:**

- `pgbench_accounts`: ~10M rows (~1.28 GB)
- `pgbench_branches`: 100 rows
- `pgbench_tellers`: 1,000 rows
- `pgbench_history`: Transaction log (grows during test)

### 2. Create Custom Payment Gateway Workload Script

Create a custom pgbench script that simulates payment transactions (80% writes, 20% reads):

```bash
cat > /tmp/payment-gateway-workload.sql << 'EOF'
\set aid random(1, 100000 * :scale)
\set bid random(1, 1 * :scale)
\set tid random(1, 10 * :scale)
\set delta random(-5000, 5000)

-- 80% writes: Update account balance (credit card transaction)
BEGIN;
UPDATE pgbench_accounts SET abalance = abalance + :delta WHERE aid = :aid;
SELECT abalance FROM pgbench_accounts WHERE aid = :aid;
INSERT INTO pgbench_history (tid, bid, aid, delta, mtime) VALUES (:tid, :bid, :aid, :delta, CURRENT_TIMESTAMP);
COMMIT;

-- 20% reads: Query account balance (verification)
SELECT abalance FROM pgbench_accounts WHERE aid = :aid;
EOF
```

**Workload characteristics:**

- **Write operations** (80%): UPDATE + INSERT simulating credit card transactions
- **Read operations** (20%): SELECT simulating balance verification
- Randomized transaction amounts
- Realistic transaction history logging

### 3. Quick Setup Script

Run complete setup with one command:

```bash
# Setup everything needed for failover testing
./scripts/failover-testing/setup-all.sh
```

This orchestrates:

1. VM creation and configuration
2. Database initialization
3. Workload script creation
4. Network verification
5. Baseline performance test

---

## Testing Scenarios

### Scenario 1: AKS Pod + Direct Connection

**Purpose**: Test failover behavior with direct PostgreSQL connection from within cluster.

**Use Case**: Applications deployed in same AKS cluster (lowest network latency).

#### 1A: Manual Promotion (Planned Switchover)

Simulates planned maintenance or upgrade scenario.

```bash
./scripts/failover-testing/scenario-1a-aks-direct-manual.sh
```

**What it does:**

1. Verify pre-failover database state
2. Start 5-minute performance test (100 clients, 4K TPS target)
3. At 2:30 mark, manually promote sync replica to primary
4. Monitor failover completion
5. Verify post-failover consistency
6. Generate metrics report

**Expected Behavior:**

- Brief connection errors during promotion (~2-5 seconds)
- Automatic reconnection to new primary
- Zero data loss (RPO = 0)
- TPS recovery within seconds

#### 1B: Simulated Failure (Unplanned Outage)

Simulates catastrophic primary failure.

```bash
./scripts/failover-testing/scenario-1b-aks-direct-failure.sh
```

**What it does:**

1. Verify pre-failover database state
2. Start 5-minute performance test
3. At 2:30 mark, forcefully delete primary pod (simulates crash)
4. CNPG automatically promotes sync replica
5. Monitor automatic failover
6. Verify consistency
7. Generate metrics report

**Expected Behavior:**

- Longer connection errors during detection + promotion (~5-10 seconds)
- Automatic failover by CNPG operator
- Zero data loss (synchronous replication)
- TPS recovery after new primary ready

---

### Scenario 2: AKS Pod + PgBouncer Pooler

**Purpose**: Test failover with connection pooling layer.

**Use Case**: High-concurrency applications, microservices, serverless functions.

#### 2A: Manual Promotion with Pooler

```bash
./scripts/failover-testing/scenario-2a-aks-pooler-manual.sh
```

**Expected Advantage over Direct:**

- PgBouncer maintains client connections during failover
- Automatic retry and connection re-routing
- Lower client-side error rate
- Faster perceived recovery

#### 2B: Simulated Failure with Pooler

```bash
./scripts/failover-testing/scenario-2b-aks-pooler-failure.sh
```

**Key Difference:**

- PgBouncer detects backend failure
- Transparently reconnects to new primary
- Clients experience fewer disruptions
- Connection pool preserved

---

### Scenario 3: Azure VM + Direct Connection

**Purpose**: Test failover from external client (different network segment).

**Use Case**: Applications running on VMs, hybrid connectivity scenarios.

#### 3A: Manual Promotion from VM

```bash
# SSH to test VM
ssh azureuser@$VM_PUBLIC_IP

# Run test
./scenario-3a-vm-direct-manual.sh
```

**Network Impact:**

- Additional network hop (VM → AKS subnet)
- Slightly higher baseline latency
- Tests service discovery across subnets

#### 3B: Simulated Failure from VM

```bash
ssh azureuser@$VM_PUBLIC_IP
./scenario-3b-vm-direct-failure.sh
```

**Expected Differences:**

- Network latency affects perceived failover time
- DNS/service resolution delays
- More realistic for external clients

---

### Scenario 4: Azure VM + PgBouncer Pooler

**Purpose**: Test pooler effectiveness for external clients.

**Use Case**: Applications with external connectivity in lab environments.

#### 4A: Manual Promotion via Pooler from VM

```bash
ssh azureuser@$VM_PUBLIC_IP
./scenario-4a-vm-pooler-manual.sh
```

**Best Lab Testing Scenario:**

- Combines pooler resilience with realistic network
- Common deployment pattern for testing
- Recommended for payment gateway workload simulation

#### 4B: Simulated Failure via Pooler from VM

```bash
ssh azureuser@$VM_PUBLIC_IP
./scenario-4b-vm-pooler-failure.sh
```

**Ultimate Test:**

- Worst-case scenario (crash + external client)
- PgBouncer's full resilience on display
- Validates HA behavior and failover capabilities

---

## Running Tests

### Individual Test Execution

Run any scenario independently:

```bash
# From repository root
cd /workspaces/azure-postgresql-ha-aks-workshop

# Run specific scenario
./scripts/failover-testing/scenario-1a-aks-direct-manual.sh

# View results
cat /tmp/failover-test/scenario-1a/results-summary.txt
```

### Batch Test Execution

Run all scenarios sequentially:

```bash
# Run all 8 scenarios (takes ~40 minutes)
./scripts/failover-testing/run-all-scenarios.sh

# Results saved to: /tmp/failover-test/batch-results/
```

**Batch execution includes:**

- Automatic cleanup between tests
- Consolidated metrics report
- Comparison matrix across all scenarios
- CSV export for analysis

### Parallel Test Execution (Advanced)

Run scenarios in parallel for faster completion:

```bash
# Requires multiple test VMs
./scripts/failover-testing/run-parallel.sh

# Completes all tests in ~10 minutes
```

⚠️ **Warning**: Parallel execution may impact individual test accuracy due to shared cluster resources.

---

## Metrics Collection

### Automated Metrics

Each test script automatically collects:

| Metric | Description | Source |
|--------|-------------|--------|
| **TPS** | Transactions per second | pgbench output |
| **Latency (avg)** | Average transaction latency (ms) | pgbench output |
| **Latency (p95)** | 95th percentile latency (ms) | pgbench log files |
| **Latency (p99)** | 99th percentile latency (ms) | pgbench log files |
| **Failed Transactions** | Count of failed transactions | pgbench output |
| **Connection Errors** | Client connection failures | pgbench error log |
| **Failover Duration** | Time from trigger to completion (s) | kubectl events |
| **Transaction Delta** | Pre vs post transaction count | PostgreSQL history table |
| **Data Consistency** | Account balance checksum | PostgreSQL query |
| **Primary Switch Time** | Role change completion (s) | CNPG status |

### Metrics Output Files

Results stored in `/tmp/failover-test/scenario-XX/`:

```
scenario-1a/
├── pgbench-output.log          # Full pgbench output
├── pgbench-latency.log         # Per-transaction latency
├── kubectl-events.log          # Kubernetes events during test
├── cnpg-status-pre.txt         # Cluster state before test
├── cnpg-status-post.txt        # Cluster state after test
├── consistency-check-pre.json  # Database state before
├── consistency-check-post.json # Database state after
├── metrics-timeline.csv        # Time-series metrics (10s intervals)
└── results-summary.txt         # Human-readable summary
```

### Visualizing Results

Generate comparison charts:

```bash
# Create visual comparison across all scenarios
./scripts/failover-testing/generate-charts.sh

# Output: /tmp/failover-test/charts/
# - tps-comparison.png
# - latency-comparison.png
# - failover-duration.png
# - error-rate-comparison.png
```

---

## Expected Results

### Target Performance Benchmarks

Based on Standard_E8as_v6 with Premium v2 storage (40K IOPS):

| Phase | TPS | Avg Latency | P95 Latency | P99 Latency |
|-------|-----|-------------|-------------|-------------|
| **Steady State** | 4,000-5,000 | <25 ms | <50 ms | <100 ms |
| **During Failover** | 0-500 | N/A | N/A | N/A |
| **Recovery** | 3,500-4,500 | <30 ms | <60 ms | <120 ms |

### Failover Time Targets

| Failover Type | Detection | Promotion | Total RTO | Data Loss (RPO) |
|---------------|-----------|-----------|-----------|-----------------|
| **Manual Promote** | 0s (planned) | 3-5s | 3-5s | 0 transactions |
| **Simulated Failure** | 5-7s | 3-5s | 8-12s | 0 transactions |

### Connection Method Comparison

| Metric | Direct PostgreSQL | PgBouncer Pooler | Winner |
|--------|-------------------|------------------|---------|
| **Connection Errors** | _TBD after testing_ | _TBD after testing_ | _TBD_ |
| **Client Reconnect Time** | _TBD_ | _TBD_ | _TBD_ |
| **Failed Transactions** | _TBD_ | _TBD_ | _TBD_ |
| **TPS Recovery Time** | _TBD_ | _TBD_ | _TBD_ |

### Client Location Comparison

| Metric | AKS Internal (Pod) | Azure VM (External) | Delta |
|--------|---------------------|---------------------|--------|
| **Baseline Latency** | _TBD_ | _TBD_ | _TBD_ |
| **Failover Impact** | _TBD_ | _TBD_ | _TBD_ |
| **Network Overhead** | _TBD_ | _TBD_ | _TBD_ |

**Note**: Results will be populated after running actual tests in your environment.

---

## Troubleshooting

### Test Failures

#### Pod Won't Start

```bash
# Check pod events
kubectl describe pod <test-pod-name> -n cnpg-database

# Check resource constraints
kubectl top nodes
kubectl top pods -n cnpg-database

# Common issues:
# - Insufficient resources (need 100 concurrent connections)
# - Image pull errors (check Docker Hub rate limits)
# - DNS resolution failures
```

#### Connection Refused

```bash
# Verify service endpoints
kubectl get svc -n cnpg-database

# Test direct connectivity
kubectl run -it --rm debug \
  --image=postgres:17 \
  --restart=Never \
  -n cnpg-database \
  -- psql -h pg-primary-rw -U app -d appdb -c 'SELECT 1;'

# Check PgBouncer status
kubectl logs -n cnpg-database -l cnpg.io/poolerName=pg-primary-pooler
```

#### Failover Not Triggering

```bash
# Check CNPG operator logs
kubectl logs -n cnpg-system deployment/cnpg-cloudnative-pg

# Verify cluster configuration
kubectl get cluster pg-primary -n cnpg-database -o yaml | grep -A 10 failover

# Check replica readiness
kubectl get pods -n cnpg-database -l role=replica
```

### Performance Issues

#### Low TPS (Below 4,000)

**Possible Causes:**

1. **Insufficient IOPS**: Verify 40K IOPS disk configuration
2. **CPU throttling**: Check E8as_v6 node utilization
3. **Network bottleneck**: Check Azure CNI bandwidth
4. **PostgreSQL tuning**: Verify shared_buffers, work_mem settings

**Diagnostics:**

```bash
# Check disk performance
kubectl exec -it pg-primary-1 -n cnpg-database -- iostat -x 1 10

# Check PostgreSQL stats
kubectl exec -it pg-primary-1 -n cnpg-database -- \
  psql -U postgres -c 'SELECT * FROM pg_stat_database WHERE datname = '\''appdb'\'';'

# Check network throughput
kubectl exec -it pg-primary-1 -n cnpg-database -- iftop -t -s 10
```

#### High Latency

**Possible Causes:**

1. **Disk latency**: Premium v2 configuration issue
2. **Synchronous replication delay**: Network between zones
3. **Lock contention**: High concurrent writes
4. **Connection pool saturation**: PgBouncer queue wait

**Diagnostics:**

```bash
# Check replication lag
kubectl exec -it pg-primary-1 -n cnpg-database -- \
  psql -U postgres -c 'SELECT * FROM pg_stat_replication;'

# Check lock contention
kubectl exec -it pg-primary-1 -n cnpg-database -- \
  psql -U postgres -c 'SELECT * FROM pg_locks WHERE NOT granted;'
```

### Data Consistency Issues

#### Transaction Count Mismatch

If pre-failover and post-failover transaction counts don't match:

```bash
# Check for in-flight transactions at failover time
kubectl logs pg-primary-1 -n cnpg-database --tail=100 | grep -i "transaction"

# Verify synchronous replication was active
kubectl exec -it pg-primary-2 -n cnpg-database -- \
  psql -U postgres -c 'SELECT * FROM pg_stat_wal_receiver;'

# This indicates a bug - synchronous replication should prevent this
```

#### Account Balance Checksum Mismatch

```bash
# Re-run consistency check
./scripts/failover-testing/verify-consistency.sh pg-primary-rw app appdb post-failover-verify

# If mismatch persists, check WAL replay
kubectl exec -it pg-primary-2 -n cnpg-database -- \
  psql -U postgres -c 'SELECT pg_last_wal_replay_lsn();'
```

### VM Connectivity Issues

#### Can't Connect from VM to PostgreSQL

```bash
# Test network connectivity
ping <primary-pod-ip>

# Test PostgreSQL port
telnet <service-name> 5432

# Check NSG rules
az network nsg show --resource-group $RESOURCE_GROUP_NAME \
  --name <nsg-name> --query securityRules

# Verify service type
kubectl get svc -n cnpg-database -o wide
```

**Solutions:**

1. Expose services via LoadBalancer for external access
2. Use kubectl port-forward from VM
3. Configure Private Link for production scenarios (beyond lab scope)

---

## Best Practices

### Before Testing

1. ✅ **Backup Current Data**: Take snapshot of lab data
2. ✅ **Schedule Testing Window**: Coordinate with team
3. ✅ **Monitor Resources**: Ensure sufficient capacity
4. ✅ **Document Baseline**: Record normal performance metrics
5. ✅ **Prepare Rollback**: Have recovery plan ready

### During Testing

1. ✅ **Monitor Cluster Health**: Watch CNPG status continuously
2. ✅ **Save All Logs**: Capture complete test output
3. ✅ **Take Notes**: Document unexpected behaviors
4. ✅ **Video Recording**: Record console output for analysis
5. ✅ **Team Communication**: Keep stakeholders informed

### After Testing

1. ✅ **Verify Consistency**: Run thorough data validation
2. ✅ **Analyze Metrics**: Compare against targets
3. ✅ **Document Findings**: Record observations and anomalies
4. ✅ **Update Runbooks**: Improve operational procedures
5. ✅ **Share Results**: Distribute report to team

---

## Next Steps

1. **Run Baseline Test**: Establish performance without failover

   ```bash
   ./scripts/failover-testing/baseline-performance.sh
   ```

2. **Start with Scenario 1A**: Simplest scenario (AKS + Direct + Manual)

   ```bash
   ./scripts/failover-testing/scenario-1a-aks-direct-manual.sh
   ```

3. **Progress Through Scenarios**: Run all 8 scenarios systematically

4. **Analyze Results**: Compare metrics across all tests

5. **Tune Configuration**: Adjust based on findings

6. **Re-test Critical Scenarios**: Validate improvements

7. **Document Results**: Create test reports and operational notes

---

## Additional Resources

- **CloudNativePG Failover**: https://cloudnative-pg.io/documentation/current/failover/
- **PostgreSQL Replication**: https://www.postgresql.org/docs/17/warm-standby.html
- **PgBouncer Documentation**: https://www.pgbouncer.org/
- **Azure AKS Best Practices**: https://learn.microsoft.com/en-us/azure/aks/best-practices

---

**Ready to test?** Start with the setup scripts:

```bash
# Complete setup
./scripts/failover-testing/setup-all.sh

# Run first scenario
./scripts/failover-testing/scenario-1a-aks-direct-manual.sh
```

**Questions or Issues?** Check the [Troubleshooting](#troubleshooting) section or review script comments for detailed explanations.
