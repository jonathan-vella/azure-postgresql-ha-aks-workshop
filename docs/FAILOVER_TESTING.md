# PostgreSQL High Availability Failover Testing Guide# PostgreSQL High Availability Failover Testing Guide



Comprehensive failover testing for PostgreSQL HA on AKS, designed for **payment gateway workloads processing 4,000+ credit card transactions per second**.This guide provides comprehensive failover testing scenarios for the PostgreSQL HA deployment on AKS, designed for a **payment gateway workload processing 4,000 credit card transactions per second**.



## 📋 Table of Contents## 📋 Table of Contents



- [Overview](#overview)1. [Overview](#overview)

- [Prerequisites](#prerequisites)2. [Prerequisites](#prerequisites)

- [Test Environment Setup](#test-environment-setup)3. [Test Environment Setup](#test-environment-setup)

- [Testing Scenarios](#testing-scenarios)4. [Testing Scenarios](#testing-scenarios)

- [Running Tests](#running-tests)5. [Automated Test Scripts](#automated-test-scripts)

- [Metrics Collection](#metrics-collection)6. [Metrics Collection](#metrics-collection)

- [Expected Results](#expected-results)7. [Expected Results](#expected-results)

- [Troubleshooting](#troubleshooting)8. [Troubleshooting](#troubleshooting)



------



## Overview## Overview



### Test Objectives### Test Objectives



This guide validates the PostgreSQL HA deployment for lab and proof-of-concept purposes:

- **Validate RPO = 0** (zero data loss during failover)

- **Measure RTO** (Recovery Time Objective - target <10 seconds)

- ✅ **RPO = 0**: Zero data loss during failover (synchronous replication)- **Compare connection methods** (Direct PostgreSQL vs PgBouncer pooler)

- ✅ **RTO < 10s**: Recovery Time Objective under 10 seconds- **Compare client locations** (AKS internal vs Azure VM external)

- ✅ **Connection Resilience**: Compare direct PostgreSQL vs PgBouncer pooler- **Verify transaction consistency** during failover

- ✅ **Network Impact**: Compare AKS internal vs Azure VM external clients- **Measure client reconnection behavior**

- ✅ **Transaction Consistency**: Verify no data corruption during failover

- ✅ **Client Behavior**: Measure reconnection and error handling### Test Matrix



### Test Matrix| Scenario | Client Location | Connection Method | Failover Type | Test Duration |

|----------|----------------|-------------------|---------------|---------------|

8 comprehensive scenarios covering all critical combinations:| 1A | AKS Pod | Direct PostgreSQL | Manual Promote | 5 min (failover @ 2:30) |

| 1B | AKS Pod | Direct PostgreSQL | Simulated Failure | 5 min (failover @ 2:30) |

| Scenario | Client | Connection | Failover Type | Script || 2A | AKS Pod | PgBouncer Pooler | Manual Promote | 5 min (failover @ 2:30) |

|----------|--------|------------|---------------|--------|| 2B | AKS Pod | PgBouncer Pooler | Simulated Failure | 5 min (failover @ 2:30) |

| **1A** | AKS Pod | Direct | Manual Promote | `scenario-1a-aks-direct-manual.sh` || 3A | Azure VM | Direct PostgreSQL | Manual Promote | 5 min (failover @ 2:30) |

| **1B** | AKS Pod | Direct | Simulated Failure | `scenario-1b-aks-direct-failure.sh` || 3B | Azure VM | Direct PostgreSQL | Simulated Failure | 5 min (failover @ 2:30) |

| **2A** | AKS Pod | PgBouncer | Manual Promote | `scenario-2a-aks-pooler-manual.sh` || 4A | Azure VM | PgBouncer Pooler | Manual Promote | 5 min (failover @ 2:30) |

| **2B** | AKS Pod | PgBouncer | Simulated Failure | `scenario-2b-aks-pooler-failure.sh` || 4B | Azure VM | PgBouncer Pooler | Simulated Failure | 5 min (failover @ 2:30) |

| **3A** | Azure VM | Direct | Manual Promote | `scenario-3a-vm-direct-manual.sh` |

| **3B** | Azure VM | Direct | Simulated Failure | `scenario-3b-vm-direct-failure.sh` |### Workload Characteristics

| **4A** | Azure VM | PgBouncer | Manual Promote | `scenario-4a-vm-pooler-manual.sh` |

| **4B** | Azure VM | PgBouncer | Simulated Failure | `scenario-4b-vm-pooler-failure.sh` |**Payment Gateway Profile:**

- **Target TPS**: 4,000 transactions/second sustained

### Workload Profile: Payment Gateway- **Write:Read Ratio**: 80:20 (payment-heavy)

- **Protocol**: Prepared statements for direct, simple protocol for pooler

**Characteristics:**- **Dataset**: Scale 100 (~1.6 GB) for realistic testing

- **Target TPS**: 4,000 transactions/second sustained- **Concurrency**: 100 clients per test

- **Write:Read Ratio**: 80:20 (payment processing heavy)

- **Concurrency**: 100 simultaneous client connections---

- **Dataset**: Scale 100 (~1.6 GB) for realistic testing

- **Protocol**: ## Prerequisites

  - Prepared statements for direct connections (optimal performance)

  - Simple protocol for PgBouncer (required for transaction pooling)### 1. Deployed Infrastructure



**Test Duration:**Ensure the PostgreSQL HA cluster is fully deployed:

- Total: 5 minutes (300 seconds)

- Pre-failover: 150 seconds (2.5 minutes)```bash

- Failover trigger: 150 second mark# Verify cluster is running

- Post-failover: 150 seconds (2.5 minutes)kubectl cnpg status pg-primary -n cnpg-database



---# Expected output:

# Cluster in healthy state

## Prerequisites# Primary instance ready

# 1 sync replica + 1 async replica

### 1. Deployed PostgreSQL HA Cluster# WAL archiving active

```

Verify cluster health before testing:

### 2. Azure VM for External Testing

```bash

# Load environment variablesCreate an Ubuntu VM in the VM subnet for external testing:

source .env  # or source config/environment-variables.sh

source .deployment-outputs```bash

# Load environment variables

# Check cluster statussource .env  # or source config/environment-variables.sh

kubectl cnpg status pg-primary -n cnpg-databasesource .deployment-outputs



# Verify all components# Create Ubuntu 24.04 VM in the dedicated VM subnet

kubectl get pods -n cnpg-databaseVM_NAME="${AKS_PRIMARY_CLUSTER_NAME}-test-vm"

VM_SIZE="Standard_D4s_v5"  # 4 vCPU, 16 GB RAM

# Expected pods:

# - 3x pg-primary-* (PostgreSQL instances)az vm create \

# - 3x pg-primary-pooler-* (PgBouncer poolers)  --resource-group "$RESOURCE_GROUP_NAME" \

```  --name "$VM_NAME" \

  --location "$PRIMARY_CLUSTER_REGION" \

**Required Cluster State:**  --size "$VM_SIZE" \

- ✅ 1 Primary instance (role=primary)  --image Ubuntu2404 \

- ✅ 1 Synchronous replica (replication=sync)  --vnet-name "$VNET_NAME" \

- ✅ 1 Asynchronous replica (replication=async)  --subnet "$VM_SUBNET_NAME" \

- ✅ All PgBouncer poolers running  --admin-username azureuser \

- ✅ WAL archiving active  --generate-ssh-keys \

- ✅ Backups to Azure Blob Storage working  --public-ip-sku Standard \

  --nsg-rule SSH \

### 2. Azure VM for External Testing  --output table



Create test VM in the dedicated VM subnet:# Get VM public IP

VM_PUBLIC_IP=$(az vm show -d \

```bash  --resource-group "$RESOURCE_GROUP_NAME" \

# VM will be created in the same VNet as AKS for realistic testing  --name "$VM_NAME" \

./scripts/failover-testing/setup-test-vm.sh  --query publicIps \

```  --output tsv)



This script:echo "VM Public IP: $VM_PUBLIC_IP"

- Creates Ubuntu 24.04 VM in VM subnet (10.225.0.0/27)

- Installs PostgreSQL 17 client tools# Get VM private IP (for internal connectivity)

- Installs performance monitoring tools (pgbench, jq, bc, sysstat)VM_PRIVATE_IP=$(az vm show -d \

- Configures network access to PostgreSQL services  --resource-group "$RESOURCE_GROUP_NAME" \

- Saves VM details to `.deployment-outputs`  --name "$VM_NAME" \

  --query privateIps \

### 3. Test Database Initialization  --output tsv)



Initialize realistic dataset:echo "VM Private IP: $VM_PRIVATE_IP"



```bash# Save VM details

# Initialize pgbench schema (scale 100 = ~1.6 GB)cat >> .deployment-outputs << EOF

./scripts/failover-testing/init-test-database.shexport VM_NAME="$VM_NAME"

```export VM_PUBLIC_IP="$VM_PUBLIC_IP"

export VM_PRIVATE_IP="$VM_PRIVATE_IP"

This creates:EOF

- pgbench_accounts: ~10M rows (~1.28 GB)```

- pgbench_branches: 100 rows

- pgbench_tellers: 1,000 rows### 3. Install PostgreSQL Client Tools on VM

- pgbench_history: Transaction log (grows during test)

```bash

### 4. Custom Workload Scripts# SSH to the VM

ssh azureuser@$VM_PUBLIC_IP

Payment gateway workload simulation:

# Install PostgreSQL 17 client and tools

```bashsudo apt update

# Creates custom pgbench workload with 80% writes, 20% readssudo apt install -y wget gnupg2

./scripts/failover-testing/create-payment-workload.shsudo sh -c 'echo "deb https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'

```wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -

sudo apt update

Workload characteristics:sudo apt install -y postgresql-client-17 postgresql-contrib-17

- **Write operations** (80%): UPDATE + INSERT simulating credit card transactions

- **Read operations** (20%): SELECT simulating balance verification# Verify installation

- Randomized transaction amountspsql --version

- Realistic transaction history loggingpgbench --version



---# Install monitoring tools

sudo apt install -y jq bc sysstat

## Test Environment Setup

# Exit VM

### Quick Setup (All-in-One)exit

```

Run complete setup with one command:

### 4. Configure Network Access

```bash

# Setup everything needed for failover testingAllow VM subnet to access PostgreSQL services:

./scripts/failover-testing/setup-all.sh

``````bash

# Get PostgreSQL service IPs (LoadBalancer IPs if using LoadBalancer service type)

This orchestrates:kubectl get svc -n cnpg-database

1. VM creation and configuration

2. Database initialization# For ClusterIP services (default), expose via LoadBalancer for VM access

3. Workload script creation# Option 1: Port-forward from VM (recommended for testing)

4. Network verification# Option 2: Expose via LoadBalancer service (if needed)

5. Baseline performance test

# We'll use internal DNS resolution since VM is in same VNet

### Manual Setup (Step-by-Step)# Get the internal service FQDNs

PG_DIRECT_RW_SVC="${PG_PRIMARY_CLUSTER_NAME}-rw.${PG_NAMESPACE}.svc.cluster.local"

If you prefer manual control:PG_POOLER_RW_SVC="${PG_PRIMARY_CLUSTER_NAME}-pooler-rw.${PG_NAMESPACE}.svc.cluster.local"



```bashecho "Direct RW Service: $PG_DIRECT_RW_SVC"

# 1. Create and configure test VMecho "Pooler RW Service: $PG_POOLER_RW_SVC"

./scripts/failover-testing/setup-test-vm.sh```



# 2. Initialize test database

**Note**: For VM access to ClusterIP services, we'll use `kubectl port-forward` from a bastion or expose services via LoadBalancer. For lab testing, this is sufficient. For production scenarios, use Private Link or expose via internal LoadBalancer.

./scripts/failover-testing/init-test-database.sh

---

# 3. Create custom payment workload

./scripts/failover-testing/create-payment-workload.sh## Test Environment Setup



# 4. Verify connectivity (both direct and pooler)### 1. Initialize Test Database

./scripts/failover-testing/verify-connectivity.sh

Create a realistic dataset for payment gateway testing:

# 5. Run baseline performance test (no failover)

./scripts/failover-testing/baseline-performance.sh```bash

```# Get PostgreSQL password

PG_PASSWORD=$(kubectl get secret pg-superuser-secret \

### Network Configuration  -n cnpg-database \

  -o jsonpath='{.data.password}' | base64 -d)

**Architecture:**

```# Create initialization pod

┌─────────────────────────────────────────────────────────────┐kubectl run pgbench-init \

│ Azure VNet: 10.224.0.0/12                                  │  --image=postgres:17 \

│                                                              │  --restart=Never \

│  ┌──────────────────────────────────────┐                  │  --rm -it \

│  │ AKS Subnet: 10.224.0.0/16            │                  │  -n cnpg-database \

│  │                                       │                  │  --env="PGPASSWORD=$PG_PASSWORD" \

│  │  ┌──────────────────────────────┐    │                  │  -- bash -c "

│  │  │ PostgreSQL Pods              │    │                  │    echo 'Initializing pgbench schema (scale 100 = ~1.6 GB)...'

│  │  │ - pg-primary-1 (Primary)     │    │                  │    pgbench -h pg-primary-rw -U app -d appdb -i -s 100 --quiet

│  │  │ - pg-primary-2 (Sync)        │    │                  │    echo 'Schema initialized successfully'

│  │  │ - pg-primary-3 (Async)       │    │                  │    psql -h pg-primary-rw -U app -d appdb -c 'SELECT pg_size_pretty(pg_database_size(current_database()));'

│  │  └──────────────────────────────┘    │                  │  "

│  │                                       │                  │```

│  │  ┌──────────────────────────────┐    │                  │

│  │  │ PgBouncer Poolers            │    │                  │### 2. Create Custom Payment Gateway Workload Script

│  │  │ - pooler-1, pooler-2, pooler-3 │  │                  │

│  │  └──────────────────────────────┘    │                  │Create a custom pgbench script that simulates payment transactions (80% writes, 20% reads):

│  │                                       │                  │

│  │  ┌──────────────────────────────┐    │                  │```bash

│  │  │ Test Pods (Scenarios 1A-2B)  │    │                  │cat > /tmp/payment-gateway-workload.sql << 'EOF'

│  │  └──────────────────────────────┘    │                  │\set aid random(1, 100000 * :scale)

│  └──────────────────────────────────────┘                  │\set bid random(1, 1 * :scale)

│                                                              │\set tid random(1, 10 * :scale)

│  ┌──────────────────────────────────────┐                  │\set delta random(-5000, 5000)

│  │ VM Subnet: 10.225.0.0/27             │                  │

│  │                                       │                  │-- 80% writes: Update account balance (credit card transaction)

│  │  ┌──────────────────────────────┐    │                  │BEGIN;

│  │  │ Test VM (Scenarios 3A-4B)    │    │                  │UPDATE pgbench_accounts SET abalance = abalance + :delta WHERE aid = :aid;

│  │  │ Ubuntu 24.04 + pgbench       │    │                  │SELECT abalance FROM pgbench_accounts WHERE aid = :aid;

│  │  └──────────────────────────────┘    │                  │INSERT INTO pgbench_history (tid, bid, aid, delta, mtime) VALUES (:tid, :bid, :aid, :delta, CURRENT_TIMESTAMP);

│  └──────────────────────────────────────┘                  │COMMIT;

│                                                              │

└─────────────────────────────────────────────────────────────┘-- 20% reads: Query account balance (verification)

```SELECT abalance FROM pgbench_accounts WHERE aid = :aid;

EOF

**Service Endpoints:**```

- **Direct Read-Write**: `pg-primary-rw.cnpg-database.svc.cluster.local:5432`

- **Direct Read-Only**: `pg-primary-ro.cnpg-database.svc.cluster.local:5432`### 3. Verification Script

- **Pooler Read-Write**: `pg-primary-pooler-rw.cnpg-database.svc.cluster.local:5432`

- **Pooler Read-Only**: `pg-primary-pooler-ro.cnpg-database.svc.cluster.local:5432`Create a script to verify database state before and after failover:



---```bash

cat > /tmp/verify-consistency.sh << 'EOFSCRIPT'

## Testing Scenarios#!/bin/bash

# Verify database consistency before and after failover

### Scenario 1: AKS Pod + Direct Connection

set -euo pipefail

**Purpose**: Test failover behavior with direct PostgreSQL connection from within cluster.

PG_HOST="${1:-pg-primary-rw}"

**Use Case**: Applications deployed in same AKS cluster (lowest network latency).PG_USER="${2:-app}"

PG_DATABASE="${3:-appdb}"

#### 1A: Manual Promotion (Planned Switchover)LABEL="${4:-pre-failover}"



Simulates planned maintenance or upgrade scenario.echo "=== Database Consistency Check: $LABEL ==="



```bash# Get transaction count

./scripts/failover-testing/scenario-1a-aks-direct-manual.shTX_COUNT=$(PGPASSWORD="$PGPASSWORD" psql -h "$PG_HOST" -U "$PG_USER" -d "$PG_DATABASE" -t -c \

```  "SELECT count(*) FROM pgbench_history;")



**What it does:**# Get account sum

1. Verify pre-failover database stateACCOUNT_SUM=$(PGPASSWORD="$PGPASSWORD" psql -h "$PG_HOST" -U "$PG_USER" -d "$PG_DATABASE" -t -c \

2. Start 5-minute performance test (100 clients, 4K TPS target)  "SELECT sum(abalance) FROM pgbench_accounts;")

3. At 2:30 mark, manually promote sync replica to primary

4. Monitor failover completion# Get current primary

5. Verify post-failover consistencyPRIMARY=$(kubectl get pods -n cnpg-database -l role=primary -o jsonpath='{.items[0].metadata.name}')

6. Generate metrics report

echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"

**Expected Behavior:**echo "Primary Pod: $PRIMARY"

- Brief connection errors during promotion (~2-5 seconds)echo "Transaction Count: $TX_COUNT"

- Automatic reconnection to new primaryecho "Account Balance Sum: $ACCOUNT_SUM"

- Zero data loss (RPO = 0)echo ""

- TPS recovery within seconds

# Save for comparison

#### 1B: Simulated Failure (Unplanned Outage)mkdir -p /tmp/failover-test

cat > "/tmp/failover-test/consistency-$LABEL.txt" << EOF

Simulates catastrophic primary failure.timestamp=$(date '+%Y-%m-%d %H:%M:%S')

primary=$PRIMARY

```bashtx_count=$TX_COUNT

./scripts/failover-testing/scenario-1b-aks-direct-failure.shaccount_sum=$ACCOUNT_SUM

```EOF

EOFSCRIPT

**What it does:**

1. Verify pre-failover database statechmod +x /tmp/verify-consistency.sh

2. Start 5-minute performance test```

3. At 2:30 mark, forcefully delete primary pod (simulates crash)

4. CNPG automatically promotes sync replica---

5. Monitor automatic failover

6. Verify consistency## Testing Scenarios

7. Generate metrics report

### Scenario 1: AKS Pod + Direct Connection

**Expected Behavior:**

- Longer connection errors during detection + promotion (~5-10 seconds)Test failover behavior with direct PostgreSQL connection from within AKS cluster.

- Automatic failover by CNPG operator

- Zero data loss (synchronous replication)#### 1A: Manual Promotion (Planned Failover)

- TPS recovery after new primary ready

<function_calls>

---<invoke name="run_in_terminal">

<parameter name="command">wc -l /workspaces/azure-postgresql-ha-aks-workshop/docs/FAILOVER_TESTING.md
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
- **Azure AKS Best Practices**: https://learn.microsoft.com/azure/aks/best-practices

---

**Ready to test?** Start with the setup scripts:

```bash
# Complete setup
./scripts/failover-testing/setup-all.sh

# Run first scenario
./scripts/failover-testing/scenario-1a-aks-direct-manual.sh
```

**Questions or Issues?** Check the [Troubleshooting](#troubleshooting) section or review script comments for detailed explanations.
