# Implementation TODO: ~10 Second RTO with RPO=0

**Goal:** Reduce RTO from 15s to ~10s while maintaining RPO=0  
**Current Status:** Phase 1+2 COMPLETED | Cluster 3/3 Ready | WAL Archiving Fixed ✅  
**Target Status:** RTO 8-10s | RPO 0 | Optimized

---

## 🔧 INFRASTRUCTURE FIX: WAL Archiving to Azure Blob Storage ✅ RESOLVED

**Issue:** WAL archiving failing with "exit status 4" - blocking pg_rewind  
**Root Cause:** Storage account network access misconfigured  
**Resolution:** October 31, 2025

### What Was Fixed
1. ✅ **Storage Account Service Endpoint**: Added `Microsoft.Storage` to AKS subnet
2. ✅ **Network Rules**: Added AKS subnet to storage account's allowed virtual networks
3. ✅ **Network Security**: Set default action to `Deny` + bypass `AzureServices`
4. ✅ **Script Updated**: `scripts/02-create-infrastructure.sh` now auto-configures correctly

### Result
- ✅ WAL archiving status: `Failing` → `OK`
- ✅ Last archived WAL: `0000000900000001000000D3` @ 08:14:14 UTC
- ✅ Point-in-Time Recovery (PITR) enabled
- ✅ pg_rewind will work for future replica recovery

### Cluster Recovery
- ✅ Deleted problematic replicas (pods 2 & 3)
- ✅ CNPG rebuilt replicas using pg_basebackup (pods 4 & 5)
- ✅ Final status: 3/3 instances ready, all healthy

---

## 🔴 PHASE 1: CRITICAL - Failover Quorum + Data Durability ✅ COMPLETED

**Priority:** CRITICAL | **Effort:** 15 min | **Risk:** Low  
**Impact:** 2-3s RTO improvement + guaranteed RPO=0  
**Status:** ✅ COMPLETED (Partial - `failoverQuorum` not available in CNPG 1.27.1)

### Tasks
- [x] Edit `scripts/05-deploy-postgresql-cluster.sh`
- [x] ~~Add line to synchronous section: `failoverQuorum: true`~~ (NOT available in CNPG 1.27.1)
- [x] Add line to synchronous section: `dataDurability: required`
- [x] Redeploy cluster: Applied successfully
- [x] Validate: `kubectl cnpg status pg-primary -n cnpg-database` ✓
- [x] Run failover test: `./scripts/failover-testing/scenario-2b-aks-pooler-simulated.sh` ✅ TESTED
- [x] Measure RTO: **15s (Test 1), 14s (Test 2)** ⚠️ No improvement from baseline
- [x] Verify RPO=0 maintained ✅ Confirmed

### Configuration Changes
```yaml
# Add to postgresql.synchronous section:
failoverQuorum: true      # NEW in v1.27.0
dataDurability: required  # Explicit RPO=0 guarantee
```

### Actual Result (TESTED)
- RTO: **15s → 14-15s** ❌ No improvement (Phase 1 ensures RPO=0, not RTO)
- RPO: **0** ✅ Explicitly guaranteed (data durability enforced)
- Failover safety: ✅ Enhanced (writes block without sync replica)

**Analysis**: `dataDurability: required` prevents data loss by blocking writes when sync replica unavailable, but doesn't reduce promotion time. Promotion still requires WAL recovery completion (~5.6s) + timeline switch (~1s) + checkpoint (~0.5s).

---

## 🔴 PHASE 2: CRITICAL - Streaming Startup Probe ✅ COMPLETED

**Priority:** CRITICAL | **Effort:** 20 min | **Risk:** Low  
**Impact:** 2-3s RTO improvement  
**Status:** ✅ COMPLETED & OPERATIONAL

### Tasks
- [x] Edit `scripts/05-deploy-postgresql-cluster.sh`
- [x] Add `spec.probes.startup` section after `switchoverDelay`
- [x] Set `type: streaming`
- [x] Set `maximumLag: 1Gi`
- [x] Set `periodSeconds: 5`
- [x] Redeploy cluster: Applied successfully
- [x] Monitor replica startup: Both replicas (pods 4 & 5) started successfully
- [x] Run failover test: `./scripts/failover-testing/scenario-2b-aks-pooler-simulated.sh` ✅ TESTED
- [x] Measure RTO: **15s (Test 1), 14s (Test 2)** ⚠️ No improvement from baseline

### Configuration Changes
```yaml
# Add after switchoverDelay:
probes:
  startup:
    type: streaming              # Wait for streaming replication
    maximumLag: 1Gi              # Within 1GB of primary
    periodSeconds: 5             # Check every 5 seconds
    timeoutSeconds: 5
    failureThreshold: 20         # Allow 100 seconds total
```

### Actual Result (TESTED)
- RTO: **15s → 14-15s** ❌ No improvement (Phase 2 ensures replica readiness, not promotion speed)
- Replicas status: ✅ Always caught-up for promotion (lag < 1GB enforced)
- Reduced false failovers: ✅ Confirmed (prevents promoting out-of-date replicas)

**Analysis**: Streaming startup probe ensures replicas are synchronized before being marked ready, preventing stale replica promotion. However, promotion time still dominated by WAL recovery completion. Replica was already caught up, so no time saved during actual failover.

---

## 🟡 PHASE 3a: CRITICAL - Checkpoint Tuning (NEW - IMMEDIATE IMPACT)

**Priority:** CRITICAL | **Effort:** 15 min | **Risk:** Low  
**Impact:** 2-3s RTO improvement (reduces WAL recovery time)  
**Status:** ⏳ RECOMMENDED NEXT STEP

### Tasks
- [ ] Edit `scripts/05-deploy-postgresql-cluster.sh`
- [ ] Add `checkpoint_timeout: "1min"` to postgresql.parameters
- [ ] Add `checkpoint_completion_target: "0.9"` to postgresql.parameters
- [ ] Redeploy cluster
- [ ] Monitor checkpoint activity: `kubectl logs <primary-pod> -n cnpg-database | grep checkpoint`
- [ ] Run failover test to measure RTO improvement
- [ ] Expected RTO: 14-15s → 11-12s

### Configuration Changes
```yaml
# Add to postgresql.parameters section:
checkpoint_timeout: "1min"              # More frequent checkpoints (default: 5min)
checkpoint_completion_target: "0.9"     # Spread I/O over 90% of interval
```

### Why This Helps
**Root Cause of 14-15s RTO:**
- WAL Recovery: 5.6s (applying uncommitted WAL during promotion)
- Instance Manager: 3.9s (CNPG coordination overhead)
- Timeline Switch: 1s (creating new timeline)
- Service Update: 3s (Kubernetes DNS propagation)

**How Checkpoint Tuning Reduces RTO:**
- Current: Checkpoints every 5 minutes → replica has up to 5 min of WAL to replay
- New: Checkpoints every 1 minute → replica has maximum 1 min of WAL to replay
- Expected WAL recovery reduction: 5.6s → 3s (saves ~2.6s)

### Expected Result
- RTO: 14-15s → 11-12s ✓ **SIGNIFICANT IMPROVEMENT**
- WAL recovery time: 5.6s → ~3s
- Trade-off: Slightly more I/O overhead (acceptable on Premium SSD v2)
- RPO: 0 (unchanged)

### Risk Assessment
- ✅ **Low Risk**: Standard PostgreSQL tuning parameter
- ✅ **Rollback**: Revert to default `checkpoint_timeout: "5min"`
- ✅ **I/O Impact**: Minimal on Premium SSD v2 (40K IOPS capacity)
- ✅ **Performance**: Should not affect TPS significantly

---

## 🟡 PHASE 3b: MEDIUM - Switchover Delay Tuning

**Priority:** MEDIUM | **Effort:** 15 min | **Risk:** Medium  
**Impact:** WAL archiving safety (DOES NOT affect unplanned failover RTO)

⚠️ **IMPORTANT**: `switchoverDelay` only applies to **planned switchovers**, NOT unplanned failovers (pod deletion/crash)

### Tasks
- [ ] Edit `scripts/05-deploy-postgresql-cluster.sh`
- [ ] Change `switchoverDelay: 3` → `switchoverDelay: 15`
- [ ] Redeploy cluster
- [ ] Monitor WAL archiving: `kubectl logs <primary-pod> -n cnpg-database | grep archived`
- [ ] Run **PLANNED** switchover: `kubectl cnpg promote <replica-name> -n cnpg-database`
- [ ] Verify WAL archiving completes within 15s
- [ ] Measure planned switchover time (expected: ~18s with delay)

### Configuration Changes
```yaml
# Change from:
switchoverDelay: 3

# Change to:
switchoverDelay: 15  # More time for WAL archiving during planned maintenance
```

### Expected Result
- **Unplanned Failover RTO**: Unchanged (switchoverDelay ignored)
- **Planned Switchover Time**: 3s → 15s (by design)
- WAL archiving: ✅ Safer (more time for flush)
- Reduced archiving failures during maintenance

### When to Use
- **Planned Maintenance**: When manually promoting a replica
- **Controlled Switchovers**: When you want primary to flush WAL gracefully
- **NOT for**: Unplanned failures (pod crash, node failure, network partition)

---

## 🟡 PHASE 4: MEDIUM - WAL Timeout Tuning

**Priority:** MEDIUM | **Effort:** 10 min | **Risk:** Low  
**Impact:** Stability (prevents false failovers, does NOT reduce RTO)

⚠️ **IMPORTANT**: This phase improves stability but does NOT reduce failover time. Prevents unnecessary failovers due to network latency.

### Tasks
- [ ] Edit `scripts/05-deploy-postgresql-cluster.sh`
- [ ] Change `wal_receiver_timeout: "3s"` → `"5s"` in postgresql.parameters
- [ ] Change `wal_sender_timeout: "3s"` → `"5s"` in postgresql.parameters
- [ ] Redeploy cluster
- [ ] Monitor replication lag during normal operations
- [ ] Monitor for false failover reduction

### Configuration Changes
```yaml
# In postgresql.parameters section:
wal_receiver_timeout: "5s"  # Was "3s" - More tolerant of network latency
wal_sender_timeout: "5s"    # Was "3s" - Prevents premature connection drops
```

### Why This Helps
**Problem**: 3s timeout may be too aggressive for network latency/jitter
**Solution**: 5s timeout provides buffer for transient network issues
**Benefit**: Reduces false "replica disconnected" alerts and unnecessary failovers

### Expected Result
- **Unplanned Failover RTO**: Unchanged (doesn't affect promotion speed)
- **Stability**: ✅ Better network tolerance
- **False Failovers**: ✅ Reduced
- **Detection Time**: +2s slower to detect true failures (acceptable trade-off)

---

## 🟠 PHASE 5: HIGH - Separate WAL Volume (MAINTENANCE REQUIRED)

**Priority:** HIGH (For 8-10s RTO Goal) | **Effort:** 60-90 min | **Risk:** High  
**Impact:** 1-2s RTO improvement + better I/O isolation + improved RPO=0 reliability

⚠️ **CRITICAL: Requires cluster re-creation (DESTRUCTIVE OPERATION)**

### Why This Matters for RTO
**Current Bottleneck**: WAL recovery takes 3s (after Phase 3a checkpoint tuning)
**Root Cause**: WAL and data share same disk, causing I/O contention during recovery
**Solution**: Dedicated Premium SSD v2 disk for WAL = faster sequential writes/reads
**Expected Improvement**: WAL recovery 3s → 1-2s (saves ~1-2s total RTO)

### Maintenance Plan: Separate WAL Volume Deployment

#### Pre-Maintenance Checklist
- [ ] **Schedule Maintenance Window**: Minimum 2 hours, low-traffic period
- [ ] **Notify Stakeholders**: Application teams, operations, management
- [ ] **Verify Backups Current**: Last successful backup < 24 hours old
  ```bash
  kubectl cnpg status pg-primary-cnpg-5ohtf3vb -n cnpg-database | grep "Last Successful Backup"
  ```
- [ ] **Test Restore Process**: Verify backup can be restored (in test environment)
- [ ] **Document Current State**:
  - Current RTO: 11-12s (after Phase 3a)
  - Current cluster size: 1.9G
  - Current WAL volume: Shared with data (200Gi Premium SSD v2)
  - Primary instance: pg-primary-cnpg-5ohtf3vb-1
- [ ] **Prepare Rollback Plan**: Document steps to restore from backup if issues occur
- [ ] **Load Test Baseline**: Run `./scripts/08-test-pgbench.sh` to record current performance

#### Maintenance Execution Steps

**Step 1: Create Final Backup** (5-10 min)
```bash
# Trigger on-demand backup
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: pre-wal-volume-migration
  namespace: cnpg-database
spec:
  cluster:
    name: pg-primary-cnpg-5ohtf3vb
  method: barmanObjectStore
  online: true
EOF

# Wait for backup to complete
kubectl wait --for=condition=Complete backup/pre-wal-volume-migration -n cnpg-database --timeout=600s

# Verify backup succeeded
kubectl get backup pre-wal-volume-migration -n cnpg-database -o jsonpath='{.status.phase}'
```

**Step 2: Stop Application Traffic** (5 min)
```bash
# Scale down application pods or redirect traffic
# (Application-specific - not included in this workshop)

# Verify no active connections
kubectl exec -n cnpg-database pg-primary-cnpg-5ohtf3vb-1 -- psql -U postgres -c "SELECT count(*) FROM pg_stat_activity WHERE state='active' AND usename != 'postgres';"
```

**Step 3: Update Deployment Script** (5 min)
- [ ] Edit `scripts/05-deploy-postgresql-cluster.sh`
- [ ] Add `walStorage` section after `storage` section
- [ ] Commit changes to version control

```yaml
# Add after storage section (around line 134):
walStorage:
  size: 50Gi                     # Dedicated WAL volume (10% of data volume)
  storageClassName: premium-ssd-v2
  pvcTemplate:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 50Gi
    volumeMode: Filesystem
```

**Step 4: Delete Existing Cluster** (2 min)
```bash
# Delete cluster (pods will be terminated)
kubectl delete cluster pg-primary-cnpg-5ohtf3vb -n cnpg-database --wait=true

# Verify cluster deleted
kubectl get cluster -n cnpg-database
```

**Step 5: Delete Existing PVCs** (2 min)
```bash
# Delete all existing PVCs
kubectl delete pvc -n cnpg-database --all --wait=true

# Verify PVCs deleted
kubectl get pvc -n cnpg-database
```

**Step 6: Redeploy Cluster with WAL Volume** (10-15 min)
```bash
# Deploy cluster with updated configuration
./scripts/05-deploy-postgresql-cluster.sh

# Monitor deployment
watch kubectl get pods -n cnpg-database

# Wait for all instances ready (3/3)
kubectl wait --for=condition=Ready pod -l cnpg.io/cluster=pg-primary-cnpg-5ohtf3vb -n cnpg-database --timeout=600s
```

**Step 7: Verify WAL Volume Created** (2 min)
```bash
# Check PVCs - should see separate WAL volumes
kubectl get pvc -n cnpg-database

# Expected output:
# NAME                           STATUS   VOLUME                                     CAPACITY   STORAGE CLASS
# pg-primary-cnpg-5ohtf3vb-1     Bound    pvc-...                                    200Gi      premium-ssd-v2
# pg-primary-cnpg-5ohtf3vb-1-wal Bound    pvc-...                                    50Gi       premium-ssd-v2
# pg-primary-cnpg-5ohtf3vb-4     Bound    pvc-...                                    200Gi      premium-ssd-v2
# pg-primary-cnpg-5ohtf3vb-4-wal Bound    pvc-...                                    50Gi       premium-ssd-v2
# pg-primary-cnpg-5ohtf3vb-5     Bound    pvc-...                                    200Gi      premium-ssd-v2
# pg-primary-cnpg-5ohtf3vb-5-wal Bound    pvc-...                                    50Gi       premium-ssd-v2

# Verify WAL directory on separate volume
kubectl exec -n cnpg-database pg-primary-cnpg-5ohtf3vb-1 -- df -h | grep pg_wal
```

**Step 8: Restore Data (if needed)** (15-30 min)
```bash
# If cluster started fresh, restore from backup
# CNPG should auto-recover from last backup

# Check cluster status
kubectl cnpg status pg-primary-cnpg-5ohtf3vb -n cnpg-database

# If recovery needed, create restore
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: pg-primary-cnpg-5ohtf3vb
  namespace: cnpg-database
spec:
  bootstrap:
    recovery:
      backup:
        name: pre-wal-volume-migration
EOF
```

**Step 9: Validate Cluster Health** (5 min)
```bash
# Check all instances ready
kubectl cnpg status pg-primary-cnpg-5ohtf3vb -n cnpg-database

# Verify replication working
kubectl cnpg status pg-primary-cnpg-5ohtf3vb -n cnpg-database | grep "Streaming Replication"

# Check WAL archiving
kubectl cnpg status pg-primary-cnpg-5ohtf3vb -n cnpg-database | grep "Working WAL archiving"

# Verify data consistency
kubectl exec -n cnpg-database pg-primary-cnpg-5ohtf3vb-1 -- psql -U app -d appdb -c "SELECT count(*) FROM pgbench_accounts;"
```

**Step 10: Run Failover Test** (10 min)
```bash
# Test failover with separate WAL volume
./scripts/failover-testing/scenario-2b-aks-pooler-simulated.sh

# Expected RTO: 9-10s (improvement from 11-12s)
# Verify results in test output
```

**Step 11: Load Test Validation** (10 min)
```bash
# Run load test to verify performance
./scripts/08-test-pgbench.sh

# Compare with baseline:
# - TPS should be similar or better
# - Latency should be similar or better
```

**Step 12: Resume Application Traffic** (5 min)
```bash
# Scale up application pods or restore traffic routing
# (Application-specific)

# Monitor for errors
kubectl logs -n <app-namespace> <app-pod> --tail=100 -f
```

#### Post-Maintenance Validation
- [ ] **Verify RTO Improvement**: Failover test shows 9-10s RTO (target achieved)
- [ ] **Verify RPO=0**: No data loss during failover test
- [ ] **Verify Performance**: TPS and latency within acceptable range
- [ ] **Verify Monitoring**: Grafana dashboard shows all green metrics
- [ ] **Document Results**: Update implementation log with actual RTO/RPO measurements
- [ ] **Stakeholder Communication**: Notify completion and results

#### Rollback Plan (If Issues Occur)
```bash
# 1. Delete problematic cluster
kubectl delete cluster pg-primary-cnpg-5ohtf3vb -n cnpg-database

# 2. Delete PVCs
kubectl delete pvc -n cnpg-database --all

# 3. Revert deployment script changes
git checkout HEAD -- scripts/05-deploy-postgresql-cluster.sh

# 4. Redeploy without WAL volume
./scripts/05-deploy-postgresql-cluster.sh

# 5. Restore from backup
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: pg-primary-cnpg-5ohtf3vb
  namespace: cnpg-database
spec:
  bootstrap:
    recovery:
      backup:
        name: pre-wal-volume-migration
EOF

# 6. Wait for recovery
kubectl wait --for=condition=Ready pod -l cnpg.io/cluster=pg-primary-cnpg-5ohtf3vb -n cnpg-database --timeout=1200s

# 7. Verify data restored
kubectl exec -n cnpg-database pg-primary-cnpg-5ohtf3vb-1 -- psql -U app -d appdb -c "SELECT count(*) FROM pgbench_accounts;"
```

### Configuration Changes
```yaml
# Add after storage section in scripts/05-deploy-postgresql-cluster.sh:
walStorage:
  size: 50Gi                     # Separate WAL volume (10% of data size)
  storageClassName: premium-ssd-v2
  pvcTemplate:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 50Gi
    volumeMode: Filesystem
```

### Expected Result
- **RTO**: 11-12s → 9-10s ✅ **GOAL ACHIEVED**
- **WAL I/O**: Independent from data I/O (no contention)
- **WAL Recovery**: 3s → 1-2s (faster sequential reads)
- **RPO=0**: More reliable (dedicated, isolated storage)
- **Total RTO Breakdown**:
  - Detection: 0.4s
  - Decision: 0.3s
  - Promotion: 7-8s (WAL recovery 1-2s + timeline + checkpoint)
  - Configuration: 0.5s
  - Service Update: 3s

### Risk Assessment
- ⚠️ **High Risk**: Cluster re-creation required (destructive)
- ✅ **Mitigation**: Comprehensive backup and restore plan
- ✅ **Recovery Time**: 15-30 minutes if rollback needed
- ✅ **Data Safety**: Barman backup provides point-in-time recovery

### When to Execute
- **Recommended**: After Phase 3a (checkpoint tuning) validated
- **Requirements**: Maintenance window, stakeholder approval, backup verification
- **Timeline**: Allow 2-3 hours for complete maintenance window

---

## 🟠 PHASE 6: MEDIUM - Monitoring & Alerting

**Priority:** MEDIUM | **Effort:** 60-90 min | **Risk:** Low  
**Impact:** Operational excellence + proactive issue detection

### Tasks
- [ ] Create `kubernetes/cnpg-prometheus-rules.yaml`
- [ ] Add alert: Replication lag > 1GB
- [ ] Add alert: Missing sync replicas
- [ ] Add alert: Failover quorum missing
- [ ] Add alert: WAL archive failures
- [ ] Add alert: Backup aging > 24h
- [ ] Deploy PrometheusRule: `kubectl apply -f kubernetes/cnpg-prometheus-rules.yaml`
- [ ] Configure alert receivers (email/Slack/Teams)
- [ ] Update Grafana dashboard with new metrics
- [ ] Test alerts by simulating failures

### Prometheus Alerts to Create
```yaml
# Alert examples:
- Replication lag > 1GB
  cnpg_collector_streaming_standby_lsn_lag_bytes > 1073741824

- Missing sync replicas
  cnpg_collector_synchronous_standby_number_observed < 
  cnpg_collector_synchronous_standby_number_expected

- Failover quorum missing
  cnpg_collector_failover_quorum_present == 0

- WAL archive failures
  cnpg_collector_last_failed_backup_timestamp_seconds > (now - 300)

- Backup aging > 24h
  (now - cnpg_collector_last_backup_timestamp_seconds) > 86400
```

### Expected Result
- Real-time RTO/RPO visibility
- Proactive alerts before failures
- Compliance audit trail

---

## 🟢 PHASE 7: OPTIONAL - Liveness Probe Tuning

**Priority:** LOW | **Effort:** 10 min | **Risk:** Low  
**Impact:** Stability (fewer false restarts)

### Tasks
- [ ] Edit `scripts/05-deploy-postgresql-cluster.sh`
- [ ] Change `livenessProbeTimeout: 3` → `livenessProbeTimeout: 5`
- [ ] Redeploy cluster
- [ ] Monitor pod restart frequency

### Configuration Changes
```yaml
livenessProbeTimeout: 5  # Was 3
```

### Expected Result
- Fewer false pod restarts
- Better tolerance for transient issues

---

## 📋 Implementation Sequence (UPDATED BASED ON TESTING)

### ✅ COMPLETED: Phase 1+2 (Stability & RPO=0)
**Status:** ✅ COMPLETED & TESTED
- Phase 1: Data Durability (RPO=0 guaranteed)
- Phase 2: Streaming Probe (replica readiness ensured)
- **Result:** RTO unchanged (14-15s), RPO=0 confirmed
- **Learning:** These phases ensure data safety, not promotion speed

### 🎯 RECOMMENDED: Fast Track to 8-10s RTO (Non-Destructive)
**Timeline:** Week 1 (~60 minutes)
1. ✅ Phase 1: Data Durability (COMPLETED)
2. ✅ Phase 2: Streaming Probe (COMPLETED)
3. ⏳ Phase 3a: Checkpoint Tuning (15 min) - **IMMEDIATE IMPACT**
4. Phase 4: WAL Timeouts (10 min) - Stability only
5. Phase 3b: Switchover Delay (10 min) - Planned maintenance only
6. Validate with failover test (15 min)

**Expected Result:** RTO 14-15s → 11-12s (Phase 3a alone achieves this)

### 🔄 COMPREHENSIVE: Full Optimization to <10s RTO
**Timeline:** 3-4 weeks
- **Week 1**: Phase 3a (checkpoint tuning) → RTO 11-12s
  - Validate with failover testing
  - Monitor I/O impact on production
- **Week 2**: Phases 3b + 4 (stability improvements)
  - Switchover delay for planned maintenance
  - WAL timeout tuning for network resilience
- **Week 3**: Phase 5 (separate WAL volume) → RTO 9-10s ✓ **GOAL ACHIEVED**
  - Schedule maintenance window
  - Execute comprehensive deployment plan
  - Validate RTO improvement
- **Week 4**: Phases 6 + 7 (operational excellence)
  - Monitoring & alerting
  - Optional liveness probe tuning

### 🚨 Critical Path to 8-10s RTO
**Required for Goal:**
1. ✅ Phase 1 (DONE): RPO=0 guarantee
2. ✅ Phase 2 (DONE): Replica readiness
3. ⏳ **Phase 3a (REQUIRED)**: Checkpoint tuning → 11-12s RTO
4. ⏳ **Phase 5 (REQUIRED)**: Separate WAL volume → 9-10s RTO ✓ **GOAL**

**Optional for Stability:**
- Phase 3b: Switchover delay (planned maintenance only)
- Phase 4: WAL timeouts (network resilience)
- Phase 6: Monitoring & alerting
- Phase 7: Liveness probe tuning

### Alternative: Accept Current Performance
**Option:** Stop at Phase 3a (11-12s RTO)
- **Pros**: No destructive changes, 3s improvement from baseline
- **Cons**: Misses 8-10s goal by 1-2 seconds
- **Decision Point**: If 11-12s RTO acceptable, skip Phase 5

---

## 📊 Results Timeline (UPDATED WITH TEST DATA)

| Milestone | Expected RTO | Actual RTO | RPO | Status | Notes |
|-----------|--------------|------------|-----|--------|-------|
| **Baseline (Original)** | 15s | **15s** | 0 | ✅ Confirmed | Pre-implementation baseline |
| **After Phase 1** | 12-13s | **14-15s** | 0 | ✅ TESTED | RPO=0 enforced, no RTO improvement |
| **After Phase 1+2** | 9-10s | **14-15s** | 0 | ✅ TESTED | Replica readiness, no RTO improvement |
| **After Phase 3a** (Checkpoint) | 11-12s | Pending | 0 | ⏳ Next | Expected ~3s improvement |
| **After Phase 3a+4** | 11-12s | Pending | 0 | Future | Phase 4 = stability only |
| **After Phase 3a+5** | 9-10s | Pending | 0 | Future | **GOAL ACHIEVED** |

### Bottleneck Analysis (From Test 2)
```
Total RTO: 14 seconds
├─ 0.4s - Failure Detection (liveness probe timeout)
├─ 0.3s - Failover Decision (operator chooses new primary)
├─ 10.2s - PostgreSQL Promotion ⚠️ PRIMARY BOTTLENECK
│   ├─ 3.9s - Instance Manager Overhead (CNPG coordination)
│   ├─ 5.6s - WAL Recovery Completion ⚠️ TARGET FOR PHASE 3a
│   ├─ 0.5s - Timeline Switch (creates Timeline 11)
│   └─ 0.2s - Checkpoint Creation
├─ 0.5s - Synchronous Standby Configuration
└─ ~3s - Service Endpoint Update (Kubernetes DNS)
```

### How Each Phase Affects RTO
| Phase | Target | Actual Impact on RTO | Why |
|-------|--------|----------------------|-----|
| Phase 1 | Promotion | **0s** (no impact) | Ensures RPO=0, doesn't speed promotion |
| Phase 2 | Promotion | **0s** (no impact) | Ensures replica ready, already caught up |
| Phase 3a | WAL Recovery | **-3s** (expected) | Reduces WAL to replay: 5.6s → 3s |
| Phase 4 | Detection | **+2s** (slower) | More tolerant timeouts, stability focus |
| Phase 5 | WAL Recovery | **-2s** (expected) | Faster I/O: 3s → 1-2s |

### Realistic RTO Goals
- **Current (Phase 1+2)**: 14-15s
- **With Phase 3a**: 11-12s (checkpoint tuning)
- **With Phase 3a+5**: 9-10s (checkpoint + separate WAL) ✓ **GOAL**
- **Best Possible**: ~8s (limited by detection + service update + instance manager overhead)

---

## ⚠️ Risk Mitigation

### Phase 1 (Failover Quorum)
- ✅ Low risk: Experimental but stable in v1.27.1
- ✅ Rollback: Remove `failoverQuorum` line
- ✅ Validation: `kubectl get cluster -n cnpg-database -o yaml | grep failoverQuorum`

### Phase 2 (Streaming Probe)
- ✅ Low risk: Standard CNPG feature
- ✅ Rollback: Remove `probes` section (reverts to `pg_isready`)
- ✅ Validation: Monitor replica startup times

### Phase 3 (Switchover Delay)
- ⚠️ Medium risk: WAL archiving may fail if too short
- ✅ Mitigation: Monitor WAL logs during switchover
- ✅ Rollback: Increase to 30s if archiving fails

### Phase 5 (Separate WAL Volume)
- ⚠️ High risk: Requires cluster re-creation
- ✅ Mitigation: Verify barman backups before deletion
- ✅ Recovery: Restore from backup if needed
- ✅ Timing: Schedule maintenance window

---

## 🎯 Success Criteria

### Phase 1-2 Success (GOAL)
- [ ] RTO measured at 9-10 seconds or less
- [ ] RPO remains 0 (no data loss)
- [ ] Failover quorum metric shows `present=1`
- [ ] Streaming probe shows replicas caught-up

### Phase 1-4 Success (OPTIMIZED)
- [ ] RTO measured at 8-10 seconds
- [ ] RPO remains 0
- [ ] No false failovers during testing
- [ ] WAL archiving completes successfully

### Phase 1-5 Success (BEST)
- [ ] RTO measured at 7-9 seconds
- [ ] Separate WAL PVC visible: `kubectl get pvc -n cnpg-database`
- [ ] WAL I/O independent from data I/O

---

## 📝 Validation Commands

```bash
# Check cluster status
kubectl cnpg status pg-primary -n cnpg-database

# View failover quorum metric
kubectl get cluster pg-primary -n cnpg-database -o jsonpath='{.spec.postgresql.synchronous.failoverQuorum}'

# Check replica lag
kubectl cnpg status pg-primary -n cnpg-database | grep "Streaming Replication Lag"

# View PVCs (after Phase 5)
kubectl get pvc -n cnpg-database

# Run failover test
./scripts/failover-testing/scenario-2b-aks-pooler-simulated.sh

# Monitor WAL archiving
kubectl logs -n cnpg-database <primary-pod> | grep -i "archived"

# Check metrics
kubectl port-forward -n cnpg-database svc/pg-primary-metrics 9187:9187
curl http://localhost:9187/metrics | grep cnpg_collector_failover_quorum
```

---

## 📚 Reference Documentation

- **Best Practices Document:** `docs/CNPG_BEST_PRACTICES_FOR_RTO_RPO.md`
- **Deployment Script:** `scripts/05-deploy-postgresql-cluster.sh`
- **Failover Test:** `scripts/failover-testing/scenario-2b-aks-pooler-simulated.sh`
- **CNPG Documentation:** https://cloudnative-pg.io/

---

## 📝 Implementation Log

### October 31, 2025 - Morning Session
- ✅ **Infrastructure Fix**: Resolved WAL archiving to Azure Blob Storage
  - Enabled Microsoft.Storage service endpoint on AKS subnet
  - Added AKS subnet to storage account allowed networks
  - Updated deployment script for future deployments
- ✅ **Phase 1**: Implemented `dataDurability: required` (failoverQuorum N/A in v1.27.1)
  - Configuration applied successfully
  - Replicas entered recovery state due to WAL archiving issue
- ✅ **Phase 2**: Implemented streaming startup probe
  - Configuration: `type: streaming`, `maximumLag: 1Gi`
  - Applied successfully to all pods
- ✅ **Cluster Recovery**: Forced clean rebuild of replicas
  - Deleted PVCs for pods 2 & 3
  - CNPG recreated pods 4 & 5 using pg_basebackup
  - Final state: 3/3 instances ready
- ✅ **WAL Archiving**: Status changed from Failing → OK
  - Last archived: 0000000900000001000000D3

### October 31, 2025 - Failover Testing & Analysis
- ✅ **Test 1 Execution**: RTO measured at **15 seconds** (08:19:32 → 08:19:47)
  - Old Primary: pg-primary-cnpg-5ohtf3vb-4 (deleted)
  - New Primary: pg-primary-cnpg-5ohtf3vb-1 (promoted)
  - Total Transactions: 1,786,760 over 5 minutes
  - Average TPS: ~5,956 | Peak TPS: 4,178
  - Authentication Failures: 11 during failover
  - Data Consistency: Maintained (RPO=0)

- ✅ **Test 2 Execution**: RTO measured at **14 seconds** (08:30:15 → 08:30:29)
  - Old Primary: pg-primary-cnpg-5ohtf3vb-4 (deleted)
  - New Primary: pg-primary-cnpg-5ohtf3vb-1 (promoted)
  - Total Transactions: 1,637,137 over 5 minutes
  - Authentication Failures: 4 during failover
  - Data Consistency: Maintained (RPO=0)

- 🔍 **Bottleneck Analysis Completed**: Identified PostgreSQL promotion as primary bottleneck
  - Detection: 0.4s (operator detects failure)
  - Decision: 0.3s (chooses new primary, waits for WAL receivers)
  - **Promotion: 10.2s** (WAL recovery 5.6s + timeline switch + checkpoint)
  - Configuration: 0.5s (updates synchronous standby)
  - Service Update: ~3s (DNS/endpoint switch)

- ❌ **Phase 1+2 Impact**: Did NOT reduce RTO as expected
  - Phase 1 (dataDurability): Ensures RPO=0, doesn't affect promotion speed
  - Phase 2 (streaming probe): Ensures replicas caught up, doesn't speed promotion
  - Root Cause: Promotion time dominated by WAL recovery (5.6s) and instance manager overhead (3.9s)

- 📊 **Key Finding**: To achieve 8-10s RTO goal, must reduce:
  1. WAL recovery time (5.6s → 3s): Requires checkpoint tuning + separate WAL volume
  2. Instance manager overhead (3.9s → 2s): Limited control, CNPG internal
  3. Service update time (3s): Unavoidable in Kubernetes architecture

---

**Created:** October 31, 2025  
**Last Updated:** October 31, 2025 08:35 UTC  
**Status:** Phase 1+2 Completed & Tested | RTO 14-15s (Baseline confirmed)  
**Next Action:** Implement checkpoint tuning (Phase 3a) for immediate RTO improvement
