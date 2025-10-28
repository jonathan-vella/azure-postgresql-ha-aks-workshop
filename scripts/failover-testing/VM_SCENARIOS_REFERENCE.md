#!/bin/bash
# VM Scenario Scripts Reference
# 
# These scenarios test failover from an Azure VM in the same VNet but different subnet.
# This simulates external client applications outside the Kubernetes cluster.
#
# IMPORTANT: VM scenarios must be run FROM the Azure VM, not from AKS pods.
# See docs/VM_SETUP_GUIDE.md for VM setup instructions.

cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════╗
║              VM-Based Failover Testing - Quick Reference             ║
╚══════════════════════════════════════════════════════════════════════╝

These scenarios are conceptually similar to AKS scenarios but run from an
Azure VM to test external client behavior during PostgreSQL failover.

┌──────────────────────────────────────────────────────────────────────┐
│ Scenario 3a: VM → Direct PostgreSQL → Manual Failover               │
├──────────────────────────────────────────────────────────────────────┤
│ Purpose: Test manual failover from external client with direct      │
│          PostgreSQL connection (no pooler)                           │
│                                                                      │
│ Setup:                                                               │
│   1. SSH to Azure VM (see VM_SETUP_GUIDE.md)                        │
│   2. Set PGPASSWORD environment variable                            │
│   3. Get ClusterIP of pg-primary-rw service:                        │
│      export PG_HOST=$(kubectl get svc pg-primary-rw -n             │
│        cnpg-database -o jsonpath='{.spec.clusterIP}')               │
│                                                                      │
│ Run:                                                                 │
│   # From VM                                                          │
│   pgbench -h $PG_HOST -U app -d appdb \                            │
│     --protocol=prepared \                                           │
│     --file=payment-gateway-workload.sql \                           │
│     --rate=4000 --time=300 --progress=10 &                          │
│                                                                      │
│   # At 2:30, from another terminal:                                 │
│   kubectl cnpg promote pg-primary <replica-pod> -n cnpg-database    │
│                                                                      │
│ Expected: Connection drops, client must reconnect manually          │
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│ Scenario 3b: VM → Direct PostgreSQL → Simulated Failure             │
├──────────────────────────────────────────────────────────────────────┤
│ Purpose: Test automatic failover from external client with direct   │
│          connection during pod failure                               │
│                                                                      │
│ Setup: Same as 3a                                                    │
│                                                                      │
│ Run:                                                                 │
│   # From VM                                                          │
│   pgbench -h $PG_HOST -U app -d appdb \                            │
│     --protocol=prepared \                                           │
│     --file=payment-gateway-workload.sql \                           │
│     --rate=4000 --time=300 --progress=10 &                          │
│                                                                      │
│   # At 2:30, delete primary:                                         │
│   kubectl delete pod <primary-pod> -n cnpg-database --force         │
│                                                                      │
│ Expected: Connection drops during failover, automatic recovery      │
│           when new primary becomes available                         │
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│ Scenario 4a: VM → PgBouncer Pooler → Manual Failover                │
├──────────────────────────────────────────────────────────────────────┤
│ Purpose: Test manual failover from external client through PgBouncer│
│          connection pooler (recommended application setup)           │
│                                                                      │
│ Setup:                                                               │
│   1. SSH to Azure VM                                                 │
│   2. Set PGPASSWORD                                                  │
│   3. Get ClusterIP of pg-primary-pooler-rw:                         │
│      export PG_POOLER=$(kubectl get svc pg-primary-pooler-rw -n    │
│        cnpg-database -o jsonpath='{.spec.clusterIP}')               │
│                                                                      │
│ Run:                                                                 │
│   # From VM                                                          │
│   pgbench -h $PG_POOLER -U app -d appdb \                          │
│     --protocol=simple \                                             │
│     --file=payment-gateway-workload.sql \                           │
│     --rate=4000 --time=300 --progress=10 &                          │
│                                                                      │
│   # At 2:30, promote replica:                                        │
│   kubectl cnpg promote pg-primary <replica-pod> -n cnpg-database    │
│                                                                      │
│ Expected: PgBouncer handles reconnection transparently, minimal     │
│           client impact, better error handling                       │
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│ Scenario 4b: VM → PgBouncer Pooler → Simulated Failure              │
├──────────────────────────────────────────────────────────────────────┤
│ Purpose: Test automatic failover from external client through       │
│          PgBouncer during pod failure (best lab testing scenario)    │
│                                                                      │
│ Setup: Same as 4a                                                    │
│                                                                      │
│ Run:                                                                 │
│   # From VM                                                          │
│   pgbench -h $PG_POOLER -U app -d appdb \                          │
│     --protocol=simple \                                             │
│     --file=payment-gateway-workload.sql \                           │
│     --rate=4000 --time=300 --progress=10 &                          │
│                                                                      │
│   # At 2:30, delete primary:                                         │
│   kubectl delete pod <primary-pod> -n cnpg-database --force         │
│                                                                      │
│ Expected: Best resilience - PgBouncer queues connections during     │
│           failover, automatic reconnection, lowest error rate        │
└──────────────────────────────────────────────────────────────────────┘

╔══════════════════════════════════════════════════════════════════════╗
║                         Key Differences                               ║
╚══════════════════════════════════════════════════════════════════════╝

┌──────────────────┬─────────────────────────────────────────────────┐
│ Aspect           │ VM vs AKS Pod Testing                           │
├──────────────────┼─────────────────────────────────────────────────┤
│ Network Path     │ VM: External → VNet → AKS subnet → Pod         │
│                  │ AKS: Internal pod-to-pod networking             │
├──────────────────┼─────────────────────────────────────────────────┤
│ Connection Type  │ VM: Uses ClusterIP (requires VNet integration)  │
│                  │ AKS: Uses ClusterIP (native k8s networking)     │
├──────────────────┼─────────────────────────────────────────────────┤
│ Latency          │ VM: Higher latency (VNet routing)               │
│                  │ AKS: Lower latency (pod network)                │
├──────────────────┼─────────────────────────────────────────────────┤
│ Failure Impact   │ VM: Simulates external app behavior             │
│                  │ AKS: Simulates microservice behavior            │
├──────────────────┼─────────────────────────────────────────────────┤
│ Use Case         │ VM: Traditional apps, external integrations     │
│                  │ AKS: Cloud-native apps, k8s workloads           │
└──────────────────┴─────────────────────────────────────────────────┘

╔══════════════════════════════════════════════════════════════════════╗
║                    Expected Outcomes                                  ║
╚══════════════════════════════════════════════════════════════════════╝

Direct Connection (Scenarios 3a/3b):
  ✓ Connection error during failover (expected)
  ✓ Must manually reconnect after new primary ready
  ✓ Higher error rate during failover window
  ✓ Transaction count may have gap
  ✗ No automatic retry

PgBouncer Connection (Scenarios 4a/4b):
  ✓ Connection queued during failover (not dropped)
  ✓ Automatic reconnection by PgBouncer
  ✓ Lower error rate (pooler handles retries)
  ✓ Smoother transaction continuity
  ✓ Application-recommended approach

╔══════════════════════════════════════════════════════════════════════╗
║                      Prerequisites                                    ║
╚══════════════════════════════════════════════════════════════════════╝

1. VM Setup (see docs/VM_SETUP_GUIDE.md):
   - Azure VM in VM subnet (10.1.0.0/27)
   - PostgreSQL 17 client installed
   - kubectl configured with AKS access
   - Network connectivity to AKS cluster

2. PostgreSQL Cluster:
   - 3-node cluster deployed (pg-primary)
   - PgBouncer pooler configured (3 instances)
   - Services accessible via ClusterIP

3. Test Data:
   - pgbench initialized with scale 100+ (~1.6GB)
   - payment-gateway-workload.sql available

4. Monitoring:
   - Access to kubectl logs
   - Access to verify-consistency.sh script

╔══════════════════════════════════════════════════════════════════════╗
║                    Quick Start Commands                               ║
╚══════════════════════════════════════════════════════════════════════╝

# 1. Connect to VM
az network bastion ssh \
  --name "aks-bastion" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --target-resource-id $(az vm show --resource-group "$RESOURCE_GROUP_NAME" \
    --name "pgtest-vm-01" --query id -o tsv) \
  --auth-type "ssh-key" --username "azureuser"

# 2. Set environment
export PGPASSWORD=$(kubectl get secret pg-primary-app -n cnpg-database \
  -o jsonpath='{.data.password}' | base64 -d)
export PG_HOST=$(kubectl get svc pg-primary-rw -n cnpg-database \
  -o jsonpath='{.spec.clusterIP}')
export PG_POOLER=$(kubectl get svc pg-primary-pooler-rw -n cnpg-database \
  -o jsonpath='{.spec.clusterIP}')

# 3. Initialize test data (if not done)
pgbench -h $PG_HOST -U app -d appdb -i -s 100 --quiet

# 4. Run scenario (example: 4b - VM, Pooler, Simulated)
cd ~/azure-postgresql-ha-aks-workshop/scripts/failover-testing

# Background: Start workload
pgbench -h $PG_POOLER -U app -d appdb \
  --protocol=simple \
  --file=payment-gateway-workload.sql \
  --rate=4000 --time=300 --progress=10 \
  --log --log-prefix=/tmp/pgbench &

# Foreground: Monitor and trigger failover at 2:30
sleep 150
kubectl delete pod $(kubectl get pods -n cnpg-database -l role=primary \
  -o jsonpath='{.items[0].metadata.name}') -n cnpg-database --force

# Wait for test completion
wait

# 5. Analyze results
cat /tmp/pgbench.*.log

╔══════════════════════════════════════════════════════════════════════╗
║                         Documentation                                 ║
╚══════════════════════════════════════════════════════════════════════╝

Full Guide: docs/FAILOVER_TESTING.md
VM Setup: docs/VM_SETUP_GUIDE.md
Quick Reference: QUICK_REFERENCE.md
Main README: README.md

For detailed scenario walkthroughs, see docs/FAILOVER_TESTING.md
EOF
