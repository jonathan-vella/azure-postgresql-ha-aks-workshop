# PostgreSQL HA Optimization Plan
**Version**: 1.0  
**Date**: October 30, 2025  
**Status**: Ready for Implementation  

---

## Executive Summary

Based on failover testing results and Microsoft Azure AKS PostgreSQL HA guidelines, this plan addresses three critical areas:

1. **Auth Recovery**: Reduce 20s auth delay to <5s (RTO improvement)
2. **Performance**: Scale from 746 TPS to 2,000-3,000 TPS (capacity improvement)  
3. **Monitoring**: Add comprehensive failover and performance tracking

**Current State**:
- TPS: 746 sustained (peak 1,608)
- RTO: 33 seconds total (13s failover + 20s auth)
- RPO: 0 seconds ✅
- Latency: 120ms average

**Target State**:
- TPS: 2,000-3,000 sustained
- RTO: <15 seconds total (improved auth recovery)
- RPO: 0 seconds (maintain)
- Latency: <100ms p95

---

## Phase 1: Fix PgBouncer Auth Recovery (Critical)

### Problem Statement
**Current**: 20-second auth recovery delay after failover  
**Impact**: Effective RTO of 33 seconds (vs <10s target)  
**Root Cause**: PgBouncer `auth_query` cache not refreshing immediately after primary pod deletion

### Investigation Steps

#### 1.1 Review Current PgBouncer Configuration
```bash
# Check current pooler configuration
kubectl get pooler pg-primary-cnpg-5ohtf3vb-pooler-rw -n cnpg-database -o yaml

# Review pgbouncer parameters
kubectl get pooler pg-primary-cnpg-5ohtf3vb-pooler-rw -n cnpg-database -o jsonpath='{.spec.pgbouncer.parameters}'
```

**Current Values** (from test):
- `server_lifetime: 3600` (1 hour - TOO LONG)
- `server_idle_timeout: 600` (10 minutes)
- `server_connect_timeout: 5` (5 seconds)

#### 1.2 Research CNPG Auth Query Mechanism
**Resources**:
- CNPG Pooler Documentation: https://cloudnative-pg.io/documentation/current/connection_pooling/
- PgBouncer Auth Query: https://www.pgbouncer.org/config.html#auth_query

**Key Findings**:
- CNPG manages auth via `auth_query` secret
- `server_lifetime` controls how long server connections live
- After failover, old server connections must close before reconnecting to new primary
- Long `server_lifetime` (3600s) delays reconnection

### Implementation

#### 1.3 Update PgBouncer Parameters

**File**: `scripts/05-deploy-postgresql-cluster.sh`

**Changes Required**:
```yaml
# Current pooler configuration (search for this in script)
pgbouncer:
  parameters:
    server_lifetime: "3600"    # CHANGE TO: "300" (5 minutes)
    server_idle_timeout: "600" # CHANGE TO: "120" (2 minutes)
    server_connect_timeout: "5" # KEEP (already optimal)
```

**Justification**:
- `server_lifetime: 300` - Forces reconnection every 5 minutes max
- `server_idle_timeout: 120` - Closes idle connections faster
- After failover, connections close within 2-5 minutes instead of up to 1 hour

#### 1.4 Test Auth Recovery

**Test Script**: `scenario-2b-aks-pooler-simulated.sh`

Add timing markers:
```bash
# After primary deleted
AUTH_START=$(date +%s)

# After first successful query post-failover
AUTH_END=$(date +%s)
AUTH_RECOVERY=$((AUTH_END - AUTH_START))

echo "Auth Recovery Time: ${AUTH_RECOVERY}s (Target: <5s)"
```

**Expected Results**:
- Before: 20s auth recovery
- After: <5s auth recovery
- Improvement: 15s reduction in RTO

---

## Phase 2: Optimize PostgreSQL Configuration (Microsoft Guidelines)

### Align with Azure AKS Best Practices

**Reference**: https://learn.microsoft.com/en-us/azure/aks/deploy-postgresql-ha?tabs=azuredisk#postgresql-performance-parameters

### 2.1 PostgreSQL Performance Parameters

**File**: `scripts/05-deploy-postgresql-cluster.sh`

**Current Configuration** (needs update):
```yaml
postgresql:
  parameters:
    # Need to add/update these based on node memory (16GB assumed)
```

**Recommended Configuration** (Microsoft Guidelines):

#### Memory Settings
```yaml
shared_buffers: "4GB"            # 25% of node memory (16GB node)
effective_cache_size: "12GB"     # 75% of node memory
work_mem: "62MB"                 # 1/256th of node memory (16GB / 256)
maintenance_work_mem: "1GB"      # 6.25% of node memory (16GB * 0.0625)
```

#### WAL and Checkpoint Settings
```yaml
wal_compression: "lz4"           # Compress WAL writes
max_wal_size: "6GB"              # Trigger checkpoint at 6GB
checkpoint_timeout: "15min"      # Max time between checkpoints
checkpoint_flush_after: "2MB"    # Flush after 2MB writes
wal_writer_flush_after: "2MB"    # WAL writer flush interval
min_wal_size: "4GB"              # Minimum WAL size
```

#### I/O and Vacuum Settings
```yaml
random_page_cost: "1.1"          # SSD optimization (default 4.0 for HDD)
effective_io_concurrency: "64"   # Premium SSD v2 concurrent I/O
maintenance_io_concurrency: "64" # Maintenance work I/O
autovacuum_vacuum_cost_limit: "2400"  # Vacuum cost limit
```

### 2.2 Implementation Steps

1. **Update PostgreSQL cluster manifest** in `scripts/05-deploy-postgresql-cluster.sh`
2. **Apply changes** requires cluster restart (plan maintenance window)
3. **Validate parameters** after restart:
   ```bash
   kubectl exec -it pg-primary-cnpg-5ohtf3vb-1 -n cnpg-database -- \
     psql -U postgres -c "SHOW shared_buffers;"
   ```

### 2.3 Expected Impact

- **Write Performance**: WAL optimization reduces I/O wait
- **Query Performance**: Better memory utilization improves cache hit ratio
- **Vacuum Performance**: Autovacuum tuning reduces bloat faster
- **Overall TPS**: 10-20% improvement from better resource utilization

---

## Phase 3: Reduce Workload Contention

### Problem Statement
**Current**: Scale=1 (100,000 rows) with 100 clients → heavy row-level lock contention  
**Impact**: TPS degrades from 1,608 (peak) to 465 (steady-state)  
**Solution**: Increase scale factor + optimize workload balance

### 3.1 Increase Scale Factor to 50

#### Why Scale=50?
- **Rows**: 5,000,000 (vs 100,000)
- **50x more rows** = 50x less chance of lock collision
- **Expected improvement**: Per-client TPS from 7.46 → 15-20 TPS
- **Total capacity**: 100 clients × 20 TPS = 2,000 TPS sustained

#### Implementation

**Create initialization script**: `scripts/failover-testing/init-database-scale50.sh`

```bash
#!/bin/bash
set -euo pipefail

# Initialize pgbench with scale=50
echo "Initializing pgbench database with scale=50 (5M rows)..."
echo "This will take approximately 5-10 minutes..."

kubectl run pgbench-init --rm -i --restart=Never --image=postgres:17 \
  -n cnpg-database --env="PGPASSWORD=${PG_DATABASE_PASSWORD}" -- \
  bash -c "
    pgbench -i --scale=50 \
      -h ${PG_PRIMARY_CLUSTER_NAME}-pooler-rw \
      -U ${PG_DATABASE_USER} \
      -d ${PG_DATABASE_NAME}
  "

echo "Database initialized with 5,000,000 rows"
```

**Add to test workflow**:
```bash
# In scenario-2b-aks-pooler-simulated.sh
# Before running test, check if database is initialized
ROW_COUNT=$(kubectl run pgbench-check --rm -i --restart=Never --image=postgres:17 \
  -n cnpg-database --env="PGPASSWORD=${PGPASSWORD}" -- \
  psql -h ${POOLER_SERVICE} -U ${PG_DATABASE_USER} -d ${PG_DATABASE_NAME} \
  -t -c "SELECT count(*) FROM pgbench_accounts;")

if [ "$ROW_COUNT" -lt 1000000 ]; then
  echo "Database not initialized. Run: ./scripts/failover-testing/init-database-scale50.sh"
  exit 1
fi
```

### 3.2 Create 40/60 Read/Write Workload

**File**: `scripts/failover-testing/payment-gateway-balanced-workload.sql`

**Current Workload** (50/50):
- 2 write transactions (UPDATE + INSERT)
- 2 read transactions (SELECT)

**New Workload** (40 reads / 60 writes):
```sql
-- Payment Gateway Balanced Workload (40% reads, 60% writes)
-- For pgbench: pgbench -f payment-gateway-balanced-workload.sql

-- Transaction 1: Process Debit (20% - Write)
\set aid1 random(1, 5000000)  -- Scale=50 → 5M rows
\set delta random(-5000, -100)
BEGIN;
UPDATE pgbench_accounts SET abalance = abalance + :delta WHERE aid = :aid1;
INSERT INTO pgbench_history (tid, bid, aid, delta, mtime) 
  VALUES (1, 1, :aid1, :delta, CURRENT_TIMESTAMP);
COMMIT;

-- Transaction 2: Process Credit (20% - Write)
\set aid2 random(1, 5000000)
\set delta random(100, 5000)
BEGIN;
UPDATE pgbench_accounts SET abalance = abalance + :delta WHERE aid = :aid2;
INSERT INTO pgbench_history (tid, bid, aid, delta, mtime) 
  VALUES (2, 1, :aid2, :delta, CURRENT_TIMESTAMP);
COMMIT;

-- Transaction 3: Process Transfer (20% - Write)
\set aid_from random(1, 5000000)
\set aid_to random(1, 5000000)
\set amount random(100, 2000)
BEGIN;
UPDATE pgbench_accounts SET abalance = abalance - :amount WHERE aid = :aid_from;
UPDATE pgbench_accounts SET abalance = abalance + :amount WHERE aid = :aid_to;
INSERT INTO pgbench_history (tid, bid, aid, delta, mtime) 
  VALUES (3, 1, :aid_from, -:amount, CURRENT_TIMESTAMP);
INSERT INTO pgbench_history (tid, bid, aid, delta, mtime) 
  VALUES (3, 1, :aid_to, :amount, CURRENT_TIMESTAMP);
COMMIT;

-- Transaction 4: Check Balance (20% - Read)
\set aid3 random(1, 5000000)
SELECT aid, abalance FROM pgbench_accounts WHERE aid = :aid3;

-- Transaction 5: Get Transaction History (20% - Read)
\set aid4 random(1, 5000000)
SELECT * FROM pgbench_history 
WHERE aid = :aid4 
ORDER BY mtime DESC 
LIMIT 10;
```

**Breakdown**:
- **Writes (60%)**: Debit (20%) + Credit (20%) + Transfer (20%)
- **Reads (40%)**: Balance check (20%) + History (20%)
- **Realistic pattern**: Payment gateway processes transactions + queries

**Update scenario-2b** to use new workload:
```bash
# Change in pod spec
--file=/workload/payment-gateway-balanced-workload.sql
```

### 3.3 Expected Results

**Before** (scale=1, 50/50 workload):
- Sustained TPS: 746
- Peak TPS: 1,608
- Per-client TPS: 7.46

**After** (scale=50, 40/60 workload):
- Sustained TPS: 2,000-3,000 (target)
- Peak TPS: 3,500-4,000
- Per-client TPS: 20-30

**Math**: 100 clients × 25 TPS per client = 2,500 TPS sustained

---

## Phase 4: Enhanced Monitoring

### 4.1 Key Metrics to Track

#### Metric 1: Latency (Target: <100ms p95)
**Data Source**: pgbench output, PostgreSQL pg_stat_statements  
**Dashboard**: Grafana panel with p50/p95/p99 percentiles

**Query**:
```promql
# Grafana dashboard query
histogram_quantile(0.95, 
  rate(cnpg_backends_waiting_total[5m])
)
```

#### Metric 2: Failover Time (Target: <10s)
**Components**:
1. Detection time (primary unhealthy → promotion decision)
2. Promotion time (replica → new primary)
3. DNS/Service update time
4. Total RTO

**Data Source**: CNPG operator logs, custom script timing

**Grafana Query**:
```promql
# Time to elect new primary
cnpg_pg_replication_lag{cluster="pg-primary-cnpg-5ohtf3vb"}
```

#### Metric 3: Auth Recovery (Target: <5s)
**Measurement**: Time from failover complete → first successful auth  
**Implementation**: Add timing to scenario-2b script

```bash
# In scenario-2b-aks-pooler-simulated.sh
FAILOVER_COMPLETE=$(date '+%Y-%m-%d %H:%M:%S')
AUTH_RECOVERY_START=$(date +%s)

# Wait for first successful query
until kubectl run auth-test --rm -i --restart=Never --image=postgres:17 \
  -n cnpg-database --env="PGPASSWORD=${PGPASSWORD}" -- \
  psql -h ${POOLER_SERVICE} -U ${PG_DATABASE_USER} -d ${PG_DATABASE_NAME} \
  -c "SELECT 1;" &>/dev/null; do
  sleep 1
done

AUTH_RECOVERY_END=$(date +%s)
AUTH_RECOVERY_TIME=$((AUTH_RECOVERY_END - AUTH_RECOVERY_START))

echo "Auth Recovery: ${AUTH_RECOVERY_TIME}s (Target: <5s)"
```

### 4.2 Grafana Dashboard Updates

**File**: `grafana/grafana-cnpg-ha-dashboard.json`

**Add Panels**:
1. **Query Latency Percentiles** (p50, p95, p99)
2. **Failover Event Timeline** (detection → promotion → ready)
3. **Connection Pool Health** (active, idle, waiting)
4. **Auth Failure Rate** (post-failover recovery tracking)
5. **TPS Over Time** (with failover marker)
6. **WAL Generation Rate** (I/O health indicator)

---

## Phase 5: Execution Plan

### Step-by-Step Implementation

#### Week 1: Auth Recovery Fix
- [ ] Day 1: Update PgBouncer parameters in `05-deploy-postgresql-cluster.sh`
- [ ] Day 2: Apply pooler changes (kubectl apply)
- [ ] Day 3: Run scenario-2b test, measure auth recovery
- [ ] Day 4: Validate <5s auth recovery achieved
- [ ] Day 5: Document results, commit changes

#### Week 2: PostgreSQL Optimization
- [ ] Day 1: Update PostgreSQL parameters per Microsoft guidelines
- [ ] Day 2: Plan maintenance window for parameter changes
- [ ] Day 3: Apply configuration (requires restart)
- [ ] Day 4: Validate parameters loaded correctly
- [ ] Day 5: Run performance baseline test

#### Week 3: Workload Optimization
- [ ] Day 1: Create init-database-scale50.sh script
- [ ] Day 2: Initialize database with 5M rows (takes ~10 minutes)
- [ ] Day 3: Create payment-gateway-balanced-workload.sql (40/60)
- [ ] Day 4: Update scenario-2b to use new workload
- [ ] Day 5: Run optimized failover test

#### Week 4: Monitoring & Validation
- [ ] Day 1-2: Update Grafana dashboard with new panels
- [ ] Day 3: Add monitoring to scenario-2b script
- [ ] Day 4: Run final comprehensive test
- [ ] Day 5: Document results, update SLAs

### Validation Criteria

**✅ Success Metrics**:
1. Auth recovery: <5s (from 20s)
2. Sustained TPS: 2,000-3,000 (from 746)
3. Total RTO: <15s (from 33s)
4. Latency p95: <100ms (from 120ms)
5. RPO: 0 seconds (maintain)

**📊 Test Results Template**:
```markdown
## Optimization Test Results

| Metric | Before | After | Target | Status |
|--------|--------|-------|--------|--------|
| Auth Recovery | 20s | Xs | <5s | ✅/❌ |
| Sustained TPS | 746 | X | 2,000+ | ✅/❌ |
| Total RTO | 33s | Xs | <15s | ✅/❌ |
| Latency p95 | 120ms | Xms | <100ms | ✅/❌ |
| RPO | 0s | 0s | 0s | ✅ |
```

---

## Risks & Mitigation

### Risk 1: PostgreSQL Parameter Changes Require Restart
**Mitigation**: Plan maintenance window, test in non-production first

### Risk 2: Scale=50 Initialization Takes 10+ Minutes
**Mitigation**: Run once, persist data, document in setup guide

### Risk 3: Auth Recovery May Not Improve to <5s
**Mitigation**: Iterate on `server_lifetime` values (try 60s, 120s, 300s)

### Risk 4: 8K-10K TPS May Still Be Unachievable
**Mitigation**: Document realistic SLAs (2K-3K), note 8K+ requires horizontal scaling

---

## Documentation Updates

### Files to Update:
1. **README.md**: Update performance targets
2. **QUICK_REFERENCE.md**: Add new commands
3. **docs/SETUP_COMPLETE.md**: Add scale=50 initialization
4. **docs/FAILOVER_TESTING.md**: Update expected results
5. **CHANGELOG.md**: Add optimization version entry

### New Documentation Needed:
1. **docs/PERFORMANCE_TUNING.md**: PostgreSQL optimization guide
2. **docs/PGBOUNCER_TUNING.md**: Auth recovery optimization
3. **scripts/failover-testing/README.md**: Update for new workload

---

## References

1. **Microsoft Azure AKS PostgreSQL HA Guide**  
   https://learn.microsoft.com/en-us/azure/aks/deploy-postgresql-ha?tabs=azuredisk#postgresql-performance-parameters

2. **CloudNativePG Connection Pooling**  
   https://cloudnative-pg.io/documentation/current/connection_pooling/

3. **PgBouncer Configuration Reference**  
   https://www.pgbouncer.org/config.html

4. **PostgreSQL Performance Tuning**  
   https://wiki.postgresql.org/wiki/Performance_Optimization

5. **pgbench Documentation**  
   https://www.postgresql.org/docs/current/pgbench.html

---

## Next Steps

1. Review this plan with team
2. Prioritize phases (suggest: Phase 1 first - critical RTO issue)
3. Schedule implementation windows
4. Begin with Phase 1 (auth recovery fix)

**Ready to start?** Begin with todo item #1: Research CNPG pooler auth_query configuration
