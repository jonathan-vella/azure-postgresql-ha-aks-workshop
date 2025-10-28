# Failover Testing Scripts - Quick Start

This directory contains automated failover testing scripts for PostgreSQL HA on AKS.

## 📂 Directory Structure

```
scripts/failover-testing/
├── README.md                              # This file
├── VM_SCENARIOS_REFERENCE.md              # VM testing guide
├── verify-consistency.sh                  # Helper: Database consistency check
├── payment-gateway-workload.sql           # Workload SQL (80% writes / 20% reads)
├── scenario-1a-aks-direct-manual.sh       # AKS → Direct → Manual failover
├── scenario-1b-aks-direct-simulated.sh    # AKS → Direct → Simulated failure
├── scenario-2a-aks-pooler-manual.sh       # AKS → PgBouncer → Manual failover
└── scenario-2b-aks-pooler-simulated.sh    # AKS → PgBouncer → Simulated failure
```

**Note**: VM scenarios (3a, 3b, 4a, 4b) use the same workload but are run manually from Azure VMs. See `VM_SCENARIOS_REFERENCE.md` for details.

## 🚀 Quick Start

### Prerequisites

1. **Deployed Cluster**: PostgreSQL HA cluster running in AKS
   ```bash
   kubectl get cluster pg-primary -n cnpg-database
   kubectl get pods -n cnpg-database
   ```

2. **PgBouncer Pooler**: Deployed with 3 replicas
   ```bash
   kubectl get deployment pg-primary-pooler -n cnpg-database
   ```

3. **Test Data**: Initialize pgbench with scale 100 (~1.6GB)
   ```bash
   kubectl exec -it <pg-primary-pod> -n cnpg-database -- bash
   pgbench -h localhost -U app -d appdb -i -s 100 --quiet
   ```

4. **kubectl Access**: Configured to access AKS cluster
   ```bash
   az aks get-credentials --resource-group $RG_NAME --name $AKS_NAME
   ```

### Run Your First Test

**Scenario 2b** (AKS → PgBouncer → Simulated Failure) - Recommended starting point:

```bash
# Navigate to scripts directory
cd scripts/failover-testing

# Set PostgreSQL password
export PGPASSWORD=$(kubectl get secret pg-primary-app -n cnpg-database \
  -o jsonpath='{.data.password}' | base64 -d)

# Run test (automated, ~5 minutes)
./scenario-2b-aks-pooler-simulated.sh
```

**What happens:**
1. ✅ Pre-flight checks (cluster status, connectivity)
2. ✅ Pre-failover consistency snapshot
3. ✅ Starts 5-minute workload (4000 TPS target)
4. ✅ Deletes primary pod at 2:30 mark
5. ✅ Monitors automatic failover
6. ✅ Post-failover consistency check
7. ✅ Generates results summary

**Results location**: `/tmp/failover-test-<timestamp>/`

## 📊 Test Scenarios

### AKS Pod Scenarios (Automated)

| Script | Description | Connection | Failover | Complexity |
|--------|-------------|------------|----------|------------|
| `scenario-1a` | AKS → Direct → Manual | Direct PostgreSQL | kubectl promote | ⭐⭐ |
| `scenario-1b` | AKS → Direct → Simulated | Direct PostgreSQL | Delete pod | ⭐⭐ |
| `scenario-2a` | AKS → Pooler → Manual | PgBouncer | kubectl promote | ⭐⭐⭐ |
| `scenario-2b` | AKS → Pooler → Simulated | PgBouncer | Delete pod | ⭐⭐⭐ |

**Recommended order**: 2b → 2a → 1b → 1a

**Why start with 2b?** Best lab testing scenario (pooler + automatic failover), most resilient.

### Azure VM Scenarios (Manual)

See `VM_SCENARIOS_REFERENCE.md` for complete guide. Requires Azure VM setup.

| Scenario | Description | Setup Required |
|----------|-------------|----------------|
| 3a/3b | VM → Direct | VM + PostgreSQL client |
| 4a/4b | VM → Pooler | VM + PostgreSQL client |

**VM Setup**: Follow `docs/VM_SETUP_GUIDE.md` for detailed instructions.

## 📋 Common Commands

### Pre-Test Validation

```bash
# Check cluster status
kubectl cnpg status pg-primary -n cnpg-database

# Check PgBouncer deployment
kubectl get deployment pg-primary-pooler -n cnpg-database
kubectl get pods -n cnpg-database -l app=pg-primary-pooler

# Verify services
kubectl get svc -n cnpg-database | grep pg-primary

# Test connectivity (direct)
kubectl exec -it <pg-primary-pod> -n cnpg-database -- \
  psql -U app -d appdb -c "SELECT version();"

# Test connectivity (pooler)
kubectl exec -it deployment/pg-primary-pooler -n cnpg-database -- \
  psql -h pg-primary-pooler-rw -U app -d appdb -c "SELECT 'pooler works';"
```

### During Test Monitoring

```bash
# Watch pod status
watch kubectl get pods -n cnpg-database

# Monitor cluster events
kubectl get events -n cnpg-database --sort-by='.lastTimestamp' --watch

# Check current primary
kubectl get pods -n cnpg-database -l role=primary

# View test pod logs (if running)
kubectl logs -f pgbench-client-scenario2b -n cnpg-database
```

### Post-Test Analysis

```bash
# View test results
TEST_DIR="/tmp/failover-test-<timestamp>"
cat $TEST_DIR/pgbench-output.log

# Compare consistency
diff $TEST_DIR/consistency-pre-failover.txt \
     $TEST_DIR/consistency-post-failover.txt

# Check transaction counts
grep "transaction count" $TEST_DIR/consistency-*.txt

# View TPS metrics
grep "tps" $TEST_DIR/pgbench-output.log

# View latency metrics
grep "latency" $TEST_DIR/pgbench-output.log
```

### Cleanup

```bash
# Delete test pods
kubectl delete pod pgbench-client-scenario2b -n cnpg-database --force

# Clean up test directories
rm -rf /tmp/failover-test-*

# Delete ConfigMap (if needed)
kubectl delete configmap payment-gateway-workload -n cnpg-database
```

## 🔍 Helper Scripts

### verify-consistency.sh

Checks database consistency before and after failover.

**Usage:**
```bash
./verify-consistency.sh <host> <user> <database> <label> <output_dir>

# Example
./verify-consistency.sh pg-primary-rw app appdb pre-failover /tmp/test-001
```

**Output:**
- Transaction count (pgbench_history)
- Account balance sum (should remain constant)
- Account count
- Database size
- Current primary pod
- JSON and text files saved to output directory

### payment-gateway-workload.sql

Custom workload simulating payment gateway transactions.

**Characteristics:**
- 40% debit transactions (UPDATE + INSERT)
- 40% credit transactions (UPDATE + INSERT)
- 10% balance inquiries (SELECT)
- 10% transaction history lookups (SELECT)
- Realistic transaction amounts ($1-$50)

**Usage with pgbench:**
```bash
# Direct connection (prepared statements)
pgbench -h pg-primary-rw -U app -d appdb \
  --protocol=prepared \
  --file=payment-gateway-workload.sql \
  --rate=4000 --time=300

# Pooler connection (simple protocol)
pgbench -h pg-primary-pooler-rw -U app -d appdb \
  --protocol=simple \
  --file=payment-gateway-workload.sql \
  --rate=4000 --time=300
```

## 📈 Expected Results

### Scenario 2b (Recommended Baseline)

**Performance (Pooler, Simulated Failure):**
- **Pre-failover TPS**: ~4,000-8,000 TPS
- **During failover**: Brief drop (<10s window)
- **Post-failover TPS**: Returns to ~4,000-8,000 TPS
- **Latency (P95)**: <20ms pre/post, spike during failover
- **Error rate**: Minimal (<0.1% with PgBouncer retry)

**Failover Timing:**
- **Detection**: <3s (liveness probe)
- **Promotion**: <5s (automatic)
- **Total RTO**: <10s (target met)

**Data Consistency:**
- **Transaction count**: Continuous increase (no loss)
- **Account sum**: Identical pre/post (RPO=0)
- **Account count**: Unchanged

### Comparison Matrix

| Metric | Direct | PgBouncer | VM vs AKS |
|--------|--------|-----------|-----------|
| **Failover Impact** | High (connection drop) | Low (queued) | Similar pattern |
| **Error Rate** | 5-10% | <1% | VM slightly higher |
| **Recovery Time** | Manual reconnect | Automatic | Same for both |
| **Latency Impact** | Large spike | Small spike | VM +2-5ms baseline |
| **Recommended For** | ⚠️ Requires retry logic | ✅ Applications | ✅ Applications (with pooler) |

## 🐛 Troubleshooting

### Test Script Fails to Start

**Error**: `Namespace cnpg-database not found`
```bash
# Solution: Deploy cluster first
cd /workspaces/azure-postgresql-ha-aks-workshop
./scripts/deploy-all.sh
```

**Error**: `PgBouncer service not found`
```bash
# Check if pooler is deployed
kubectl get deployment pg-primary-pooler -n cnpg-database

# If missing, check cluster configuration
kubectl get cluster pg-primary -n cnpg-database -o yaml | grep -A 10 pooler
```

### Workload Fails During Test

**Error**: `pgbench: connection to server failed`
```bash
# Check primary pod status
kubectl get pods -n cnpg-database -l role=primary

# Check service endpoints
kubectl get endpoints pg-primary-rw -n cnpg-database

# Verify password
kubectl get secret pg-primary-app -n cnpg-database -o jsonpath='{.data.password}' | base64 -d
```

**Error**: `could not connect to server: Connection timed out`
```bash
# Check network connectivity
kubectl exec -it <test-pod> -n cnpg-database -- ping pg-primary-rw

# Check service configuration
kubectl describe svc pg-primary-rw -n cnpg-database
```

### Consistency Check Fails

**Error**: `Transaction count decreased`

This should NEVER happen with synchronous replication (RPO=0). If it does:
1. Check replication mode: `kubectl get cluster pg-primary -n cnpg-database -o yaml | grep -A 5 synchronousReplicaElectionConstraint`
2. Review PostgreSQL logs: `kubectl logs <primary-pod> -n cnpg-database -c postgres`
3. Check cluster status: `kubectl cnpg status pg-primary -n cnpg-database`

### Failover Doesn't Complete

**Symptom**: No new primary after 30 seconds

```bash
# Check cluster events
kubectl describe cluster pg-primary -n cnpg-database

# Check operator logs
kubectl logs -n cnpg-system deployment/cnpg-cloudnative-pg

# Verify replica health
kubectl get pods -n cnpg-database -l role=replica
kubectl exec -it <replica-pod> -n cnpg-database -- pg_isready
```

## 📚 Additional Resources

- **Main Guide**: `docs/FAILOVER_TESTING.md` - Comprehensive testing documentation
- **VM Setup**: `docs/VM_SETUP_GUIDE.md` - Azure VM configuration for external testing
- **Quick Reference**: `QUICK_REFERENCE.md` - Common commands and troubleshooting
- **Main README**: `README.md` - Project overview and architecture

## 🎯 Best Practices

1. **Always test PgBouncer scenarios first** - Most representative of application workloads
2. **Run tests during dedicated testing windows** - Minimize impact on other lab activities
3. **Collect baseline metrics** - Know your normal performance
4. **Test both failover types** - Manual and simulated cover different failure modes
5. **Document actual results** - Fill in expected results with real data
6. **Automate regularly** - Include in testing workflows for consistency
7. **Compare VM vs AKS** - Understand external client behavior

## 💡 Tips

- **Parallel testing**: Run AKS scenarios while VM is initializing
- **Increase scale factor**: Use scale 500+ for larger dataset validation
- **Vary TPS targets**: Test at 50%, 100%, 150% of expected load
- **Extended duration**: Run 30-minute tests for endurance validation
- **Multiple failovers**: Test 3+ consecutive failovers in one run

---

**Questions?** See `docs/FAILOVER_TESTING.md` for detailed explanations and expected outcomes.
