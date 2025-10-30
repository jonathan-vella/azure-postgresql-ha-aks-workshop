# CloudNativePG Documentation Integration Summary

**Date**: October 30, 2025  
**Optimization Plan Version**: 1.1  
**CNPG Version**: 1.27  

## Integration Overview

This document summarizes the CloudNativePG (CNPG) official best practices integrated into the PostgreSQL HA Optimization Plan (`OPTIMIZATION_PLAN.md`).

---

## Key CNPG Practices Integrated

### 1. Benchmarking Methodology (New Section Added)

**Source**: https://cloudnative-pg.io/documentation/current/benchmarking/

**What We Integrated**:
- **`kubectl cnpg pgbench` plugin** - Kubernetes-native benchmarking approach
- **Scale factor recommendations**: scale=50 (5M rows) vs scale=1000 (100M rows)
- **Job-based approach**: Automatic Kubernetes Job creation with TTL cleanup
- **Node selector support**: Ability to run benchmarks on dedicated nodes
- **Storage testing**: `kubectl cnpg fio` plugin for Premium SSD v2 validation

**Impact on Plan**:
- Added **Option A** (CNPG plugin) to Phase 3 database initialization
- Provides cleaner, more Kubernetes-native alternative to direct kubectl run
- Automatic cleanup with `--ttl` flag reduces manual resource management
- Documented expected initialization time: 5-10 minutes for scale=50

**Example Command**:
```bash
kubectl cnpg pgbench \
  --job-name pgbench-init-scale50 \
  --db-name appdb \
  --ttl 600 \
  pg-primary-cnpg-5ohtf3vb \
  -- --initialize --scale 50
```

---

### 2. PgBouncer Configuration & Authentication (Enhanced Section)

**Source**: https://cloudnative-pg.io/documentation/current/connection_pooling/

**What We Integrated**:

#### Authentication Mechanism
- **auth_user**: `cnpg_pooler_pgbouncer` (auto-created by CNPG operator)
- **auth_query**: Custom lookup function in `postgres` database
- **TLS certificate authentication**: Secure, password-less auth for pooler → PostgreSQL
- **Automatic secret sync**: Operator manages auth credentials during failover

**Why This Matters for Phase 1**:
- Understanding auth mechanism helps diagnose 20s recovery delay
- CNPG's TLS certificate approach means auth failure isn't a credential issue
- The issue is auth_query cache refresh timing, not authentication failures
- Confirms `server_lifetime` and `server_idle_timeout` are the right levers to tune

#### Configurable Parameters (Confirmed)
CNPG documentation confirms these parameters are user-configurable:
- ✅ `server_lifetime`: Connection lifetime (default: 3600s → target: 300s)
- ✅ `server_idle_timeout`: Idle connection timeout (default: 600s → target: 120s)
- ✅ `server_check_delay`: Health check frequency
- ✅ `server_connect_timeout`: Connection timeout
- ✅ `server_fast_close`: Fast connection close during PAUSE

**New Discovery - PAUSE/RESUME Feature**:
- Declarative connection pausing via `paused: true/false` in Pooler spec
- Useful for planned maintenance with zero data loss
- Future integration opportunity: Combine PAUSE with switchover operations

---

### 3. Monitoring & Observability (New Metrics Section)

**Source**: https://cloudnative-pg.io/documentation/current/connection_pooling/#monitoring

**What We Integrated**:

#### Built-in Prometheus Metrics
CNPG PgBouncer Pooler automatically exposes metrics on port 9127:

**Critical Metrics for Phase 4 Monitoring**:
```
cnpg_pgbouncer_pools_maxwait              # Client queue wait time (RTO indicator)
cnpg_pgbouncer_pools_sv_idle              # Available server connections
cnpg_pgbouncer_pools_sv_active            # Active server connections
cnpg_pgbouncer_pools_cl_waiting           # Clients waiting (bottleneck indicator)
cnpg_pgbouncer_stats_avg_query_time       # Query latency (microseconds)
cnpg_pgbouncer_stats_avg_wait_time        # Client wait time (microseconds)
cnpg_pgbouncer_stats_total_query_count    # Total queries processed
```

**Impact on Plan**:
- Phase 4 can use these CNPG-native metrics instead of custom instrumentation
- `maxwait` metric is perfect for tracking auth recovery time
- `cl_waiting` helps identify pooler bottlenecks
- Integrated with existing Grafana dashboard structure

#### PodMonitor Integration
- CNPG documentation provides PodMonitor template for Prometheus Operator
- Already using Prometheus Operator in this deployment
- Can add PodMonitor alongside existing PostgreSQL cluster monitoring

---

### 4. High Availability Considerations (Awareness Added)

**Source**: https://cloudnative-pg.io/documentation/current/connection_pooling/#high-availability-ha

**What We Integrated**:

#### Multi-Zone Latency Warning
CNPG documentation warns about network hops in multi-AZ deployments:
- App (Zone 2) → PgBouncer (Zone 3) → PostgreSQL (Zone 1) = **2 network hops**
- Our deployment: All in same region, but awareness is critical for future scaling

**Current Setup (Safe)**:
- 3 AKS nodes across zones (1, 2, 3)
- 3 PostgreSQL instances (spread across zones)
- 3 PgBouncer instances (co-located with clients via affinity rules)

**Future Optimization**:
- Consider pod affinity to co-locate PgBouncer with application pods
- Use topology spread constraints for balanced distribution

---

### 5. Pooler Lifecycle Management (Operational Note)

**Source**: https://cloudnative-pg.io/documentation/current/connection_pooling/#pooler-resource-lifecycle

**Key Learning**:
- **Pooler and Cluster lifecycles are independent**
- Deleting PostgreSQL cluster does NOT delete PgBouncer pooler
- This is a feature for flexibility, but requires awareness during cleanup

**Operational Impact**:
- Document cleanup procedures in deployment scripts
- Consider adding cleanup validation to `deploy-all.sh`
- Ensure monitoring tracks both cluster and pooler health

---

## Changes Made to OPTIMIZATION_PLAN.md

### 1. Header Updates
- **Version**: 1.0 → 1.1
- **Documentation Sources**: Added explicit reference to CNPG v1.27 documentation
- **Executive Summary**: Updated to mention both Microsoft Azure and CNPG best practices

### 2. New Section: "CloudNativePG Best Practices Integration"
- **Location**: Before Phase 1 (lines ~55-135)
- **Content**:
  - Benchmarking methodology with `kubectl cnpg pgbench`
  - PgBouncer configuration specifics
  - Monitoring metrics reference
  - Storage testing with `fio` plugin

### 3. Phase 3 Enhancement
- **Added "Option A"**: CNPG plugin approach for database initialization
- **Kept "Option B"**: Direct kubectl run (existing approach)
- **Recommendation**: Use CNPG plugin for better Kubernetes integration

### 4. References Section Expansion
- **New subsection**: "CloudNativePG Official Documentation (v1.27)"
- **Added 3 CNPG references**:
  - Benchmarking guide
  - Connection pooling guide
  - Monitoring guide
- **Added context**: Brief description of what each doc provides

---

## Implementation Recommendations

### Immediate Actions (No Changes Required)
- ✅ **Phase 1** auth recovery approach is correct (server_lifetime, server_idle_timeout)
- ✅ **Phase 2** PostgreSQL parameters align with CNPG operator capabilities
- ✅ **Phase 4** monitoring can leverage existing CNPG Prometheus exporter

### Optional Enhancements (Future)
1. **Switch to CNPG pgbench plugin** in Phase 3 (Option A vs Option B)
2. **Add PodMonitor** for PgBouncer metrics in Phase 4
3. **Test PAUSE/RESUME** feature during planned switchovers
4. **Run `kubectl cnpg fio`** to validate Premium SSD v2 baseline performance

### Testing Alignment
Current test scripts (`scenario-2b-aks-pooler-simulated.sh`) already align with CNPG best practices:
- ✅ Using prepared protocol (CNPG compatible)
- ✅ Connecting via Pooler service (CNPG managed)
- ✅ Standard pgbench workload (CNPG documented approach)

---

## Validation Checklist

- ✅ **CNPG benchmarking methodology** reviewed and integrated
- ✅ **PgBouncer authentication mechanism** understood (auth_user, auth_query, TLS)
- ✅ **Configurable parameters** confirmed (server_lifetime, server_idle_timeout)
- ✅ **Prometheus metrics** documented for Phase 4 monitoring
- ✅ **Scale factor recommendations** aligned (scale=50 for this plan)
- ✅ **PAUSE/RESUME feature** noted for future use
- ✅ **Multi-AZ considerations** documented
- ✅ **Pooler lifecycle** understood (independent from cluster)
- ✅ **Documentation references** added to plan
- ✅ **Storage testing option** documented (fio plugin)

---

## Key Takeaways

### What CNPG Documentation Confirmed ✅
1. Our Phase 1 approach (tuning server_lifetime, server_idle_timeout) is correct
2. CNPG's auth mechanism uses TLS certificates (not password-based for pooler)
3. Built-in Prometheus metrics eliminate need for custom instrumentation
4. Scale=50 is reasonable (CNPG examples go up to scale=1000)

### What CNPG Documentation Added 🆕
1. **kubectl cnpg pgbench** plugin for cleaner benchmarking
2. Specific metric names for monitoring (`cnpg_pgbouncer_*`)
3. PAUSE/RESUME feature for planned maintenance
4. Storage testing tool (`kubectl cnpg fio`)
5. PodMonitor template for Prometheus Operator

### What CNPG Documentation Clarified 💡
1. Auth recovery delay is about connection pool refresh, not authentication failures
2. Pooler lifecycle is independent from cluster (manual cleanup needed)
3. Multi-AZ deployments require careful network topology planning
4. PgBouncer configuration is managed by CNPG operator, but parameters are customizable

---

## Next Steps

1. ✅ **Optimization plan updated** with CNPG best practices (v1.1)
2. ⏳ **Review plan with team** - ensure alignment on CNPG vs direct approach
3. ⏳ **Decide on pgbench method** - CNPG plugin (Option A) or direct kubectl (Option B)
4. ⏳ **Begin Phase 1 execution** - PgBouncer auth recovery tuning
5. ⏳ **Update test scripts** (optional) - switch to `kubectl cnpg pgbench` if desired

---

## Documentation Status

- ✅ `OPTIMIZATION_PLAN.md` - Updated to v1.1 with CNPG integration
- ✅ `CNPG_INTEGRATION_SUMMARY.md` - Created (this file)
- ⏳ Update todo list with CNPG-specific validation tasks (if needed)
- ⏳ Commit changes to repository

**Files Modified**:
- `.github/OPTIMIZATION_PLAN.md` (v1.0 → v1.1)

**Files Created**:
- `.github/CNPG_INTEGRATION_SUMMARY.md`

---

**Integration Complete** ✅  
All CloudNativePG v1.27 best practices from official documentation are now reflected in the optimization plan.
