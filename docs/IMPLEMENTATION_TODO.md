# Implementation TODO: ~10 Second RTO with RPO=0

**Goal:** Reduce RTO from 15s to ~10s while maintaining RPO=0  
**Current Status:** RTO 15s | RPO 0 | Baseline Working  
**Target Status:** RTO 8-10s | RPO 0 | Optimized

---

## 🔴 PHASE 1: CRITICAL - Failover Quorum + Data Durability

**Priority:** CRITICAL | **Effort:** 15 min | **Risk:** Low  
**Impact:** 2-3s RTO improvement + guaranteed RPO=0

### Tasks
- [ ] Edit `scripts/05-deploy-postgresql-cluster.sh`
- [ ] Add line to synchronous section: `failoverQuorum: true`
- [ ] Add line to synchronous section: `dataDurability: required`
- [ ] Redeploy cluster: `kubectl apply -f ...`
- [ ] Validate: `kubectl cnpg status pg-primary -n cnpg-database`
- [ ] Run failover test: `./scripts/failover-testing/scenario-2b-aks-pooler-simulated.sh`
- [ ] Measure RTO (expected: 12-13s)
- [ ] Verify RPO=0 maintained

### Configuration Changes
```yaml
# Add to postgresql.synchronous section:
failoverQuorum: true      # NEW in v1.27.0
dataDurability: required  # Explicit RPO=0 guarantee
```

### Expected Result
- RTO: 15s → 12-13s ✓
- RPO: 0 (explicitly guaranteed)
- Failover safety: Enhanced with quorum model

---

## 🔴 PHASE 2: CRITICAL - Streaming Startup Probe

**Priority:** CRITICAL | **Effort:** 20 min | **Risk:** Low  
**Impact:** 2-3s RTO improvement

### Tasks
- [ ] Edit `scripts/05-deploy-postgresql-cluster.sh`
- [ ] Add `spec.probes.startup` section after `switchoverDelay`
- [ ] Set `type: streaming`
- [ ] Set `maximumLag: 1Gi`
- [ ] Set `periodSeconds: 5`
- [ ] Redeploy cluster
- [ ] Monitor replica startup: `kubectl logs -f <replica-pod> -n cnpg-database`
- [ ] Run failover test
- [ ] Measure RTO (expected: 9-10s) ✓ GOAL ACHIEVED

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

### Expected Result
- RTO: 12-13s → 9-10s ✓ **GOAL ACHIEVED**
- Replicas always caught-up for promotion
- Reduced false failovers

---

## 🟡 PHASE 3: HIGH - Switchover Delay Tuning

**Priority:** HIGH | **Effort:** 15 min | **Risk:** Medium  
**Impact:** 0-1s RTO improvement + WAL archiving safety

### Tasks
- [ ] Edit `scripts/05-deploy-postgresql-cluster.sh`
- [ ] Change `switchoverDelay: 3` → `switchoverDelay: 15`
- [ ] Redeploy cluster
- [ ] Monitor WAL archiving: `kubectl logs <primary-pod> -n cnpg-database | grep archived`
- [ ] Run planned switchover: `kubectl cnpg promote <replica-name> -n cnpg-database`
- [ ] Verify WAL archiving completes within 15s
- [ ] Measure RTO (expected: 8-10s)

### Configuration Changes
```yaml
# Change from:
switchoverDelay: 3

# Change to:
switchoverDelay: 15  # Balance RTO + WAL archiving
```

### Expected Result
- RTO: 9-10s → 8-10s (marginal)
- WAL archiving: Safer (more time for flush)
- Reduced archiving failures

---

## 🟡 PHASE 4: HIGH - WAL Timeout Tuning

**Priority:** HIGH | **Effort:** 10 min | **Risk:** Low  
**Impact:** Stability (prevents false failovers)

### Tasks
- [ ] Edit `scripts/05-deploy-postgresql-cluster.sh`
- [ ] Change `wal_receiver_timeout: "3s"` → `"5s"` in postgresql.parameters
- [ ] Change `wal_sender_timeout: "3s"` → `"5s"` in postgresql.parameters
- [ ] Redeploy cluster
- [ ] Monitor replication lag during normal operations
- [ ] Run failover test to verify stability

### Configuration Changes
```yaml
# In postgresql.parameters section:
wal_receiver_timeout: "5s"  # Was "3s"
wal_sender_timeout: "5s"    # Was "3s"
```

### Expected Result
- RTO: 8-10s (unchanged)
- Stability: Better network tolerance
- Reduced false failovers

---

## 🟠 PHASE 5: MEDIUM - Separate WAL Volume

**Priority:** MEDIUM | **Effort:** 45-60 min | **Risk:** Medium  
**Impact:** 1-2s RTO improvement + better RPO=0 assurance

⚠️ **WARNING: Requires cluster re-creation (DESTRUCTIVE)**

### Tasks
- [ ] **BACKUP FIRST:** Verify barman backups are current
- [ ] Edit `scripts/05-deploy-postgresql-cluster.sh`
- [ ] Add `walStorage` section after `storage`
- [ ] Set `size: 50Gi`
- [ ] Set `storageClassName: premium-ssd-v2`
- [ ] Delete existing cluster: `kubectl delete cluster pg-primary -n cnpg-database`
- [ ] Delete PVCs: `kubectl delete pvc -n cnpg-database --all`
- [ ] Redeploy cluster (creates new PVCs with WAL volume)
- [ ] Restore from backup if needed
- [ ] Monitor WAL volume: `kubectl get pvc -n cnpg-database`
- [ ] Run failover test
- [ ] Measure RTO (expected: 7-9s)

### Configuration Changes
```yaml
# Add after storage section:
walStorage:
  size: 50Gi                     # Separate WAL volume
  storageClassName: premium-ssd-v2
```

### Expected Result
- RTO: 8-10s → 7-9s
- WAL I/O: Independent from data I/O
- RPO=0: More reliable (dedicated storage)

### ⚠️ Implement during maintenance window

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

## 📋 Implementation Sequence

### ✅ RECOMMENDED: Fast Track (Non-Destructive)
**Timeline:** Day 1 (~90 minutes)
1. Phase 1: Failover Quorum (15 min)
2. Phase 2: Streaming Probe (20 min)
3. Phase 3: Switchover Delay (15 min)
4. Phase 4: WAL Timeouts (10 min)
5. Validate with failover test (30 min)

**Result:** RTO 15s → 8-10s ✓ **GOAL ACHIEVED**

### 🔄 COMPREHENSIVE: Full Optimization
**Timeline:** 4 weeks
- Week 1: Phases 1-4 (achieve ~10s RTO goal)
- Week 2: Phase 6 (monitoring & alerting)
- Week 3: Phase 5 (WAL volume in maintenance window)
- Week 4: Phase 7 (optional stability)

---

## 📊 Expected Results Timeline

| Milestone | RTO | RPO | Status |
|-----------|-----|-----|--------|
| **Baseline (Current)** | 15s | 0 | Working |
| **After Phase 1** | 12-13s | 0 | Improved |
| **After Phase 1-2** | 9-10s | 0 | ✓ **GOAL** |
| **After Phase 1-4** | 8-10s | 0 | Optimized |
| **After Phase 1-5** | 7-9s | 0 | Best |

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

**Created:** October 31, 2025  
**Status:** Ready for implementation  
**Next Action:** Start Phase 1 (Failover Quorum + Data Durability)
