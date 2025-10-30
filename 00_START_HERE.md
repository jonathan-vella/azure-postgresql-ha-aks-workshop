# 🚀 Start Here - Azure PostgreSQL HA on AKS Workshop

**Quick Start Guide** | [Full Documentation →](docs/SETUP_COMPLETE.md)

Welcome! This guide will get you up and running in **25-30 minutes**.

---

## � What You'll Deploy

### Infrastructure
- ✅ AKS Cluster (1.32) with 2 node pools
  - 2× System nodes (D4s_v5)
  - 3× PostgreSQL nodes (E8as_v6) across 3 availability zones
- ✅ PostgreSQL 18 HA cluster (3 instances)
- ✅ PgBouncer connection pooling (3 instances)
- ✅ Premium SSD v2 storage (40K IOPS, 1,200 MB/s)
- ✅ Azure Monitor + Managed Grafana
- ✅ Automated backups to Azure Storage

### Expected Results
- **RPO**: 0 (zero data loss with synchronous replication)
- **RTO**: <10 seconds (automatic failover)
- **TPS**: 8,000-10,000 sustained transactions per second
- **Availability**: 99.95% (multi-zone deployment)

---

## ⚡ Quick Start (3 Steps)

### 1️⃣ Configure
```bash
# Clone and navigate
cd azure-postgresql-ha-aks-workshop

# Edit configuration (optional - defaults are optimized)
code config/environment-variables.sh
```

**Key settings to review:**
- Azure region (default: swedencentral)
- PostgreSQL password (⚠️ **Change this!**)
- Resource sizing (defaults support 8-10K TPS)

### 2️⃣ Deploy
```bash
# Load configuration
source config/environment-variables.sh

# Deploy everything (8 automated steps, 20-30 minutes)
./scripts/deploy-all.sh
```

**What happens:**
1. Creates Azure infrastructure (AKS, Storage, Identity)
2. Installs CloudNativePG operator
3. Deploys PostgreSQL HA cluster (3 instances)
4. Configures PgBouncer pooling (3 instances)
5. Sets up monitoring (Grafana + Azure Monitor)
6. Configures automated backups

### 3️⃣ Validate
```bash
# Run comprehensive validation (20+ tests)
./scripts/07a-validate-cluster.sh
```

**Tests performed:**
- ✅ Cluster status & HA configuration
- ✅ Multi-zone pod distribution
- ✅ PostgreSQL connectivity (primary/replicas)
- ✅ Data replication (RPO=0 validation)
- ✅ PgBouncer pooler (3 instances)
- ✅ WAL archiving & backups
- ✅ Monitoring configuration

---

## � Documentation Guide

| Document | Purpose | When to Use |
|----------|---------|------------|
| **00_START_HERE.md** | Quick start (this file) | First deployment |
| **README.md** | Architecture overview | Understanding the solution |
| **docs/SETUP_COMPLETE.md** | Complete step-by-step guide | Detailed walkthrough |
| **docs/QUICK_REFERENCE.md** | Command cheat sheet | Daily operations |
| **docs/FAILOVER_TESTING.md** | HA testing scenarios | Testing failover |
| **docs/COST_ESTIMATION.md** | Budget planning | Cost analysis (~$2,873/month) |

---

## 🔧 Available Scripts

| Script | Purpose | Runtime |
|--------|---------|---------|
| `deploy-all.sh` | Complete deployment | 20-30 min |
| `07a-validate-cluster.sh` | Validation suite (20+ tests) ⭐ | 2-3 min |
| `07-display-connection-info.sh` | Show connection details | Instant |
| `08-test-pgbench.sh` | Performance testing | 5-10 min |
| Failover scripts | HA testing | See `scripts/failover-testing/` |

---

## � Next Steps

### After Deployment
1. **Review Metrics**: Access Grafana dashboard for real-time metrics
2. **Test Failover**: Follow `docs/FAILOVER_TESTING.md` for HA validation
3. **Performance Test**: Run `./scripts/08-test-pgbench.sh` for load testing
4. **Monitor Costs**: Set up Azure cost alerts (see `docs/COST_ESTIMATION.md`)

### Production Considerations
- Review security hardening in `CONTRIBUTING.md`
- Configure custom backup retention policies
- Set up Azure Monitor alerts for critical metrics
- Implement disaster recovery procedures
- Document application connection patterns

---

## 🔗 Key Resources

- [CloudNativePG Docs](https://cloudnative-pg.io/)
- [Azure AKS Best Practices](https://learn.microsoft.com/azure/aks/)
- [Premium SSD v2 Disks](https://learn.microsoft.com/azure/virtual-machines/disks-types#premium-ssd-v2)
- [Well-Architected Framework](https://learn.microsoft.com/azure/architecture/framework/)

---

## 📞 Troubleshooting

**Common Issues:**
- Pod startup failures → Check `kubectl logs -n cnpg-database <pod-name>`
- Connection timeouts → Verify NSG rules and AKS network policies
- WAL archiving errors → Validate Workload Identity configuration
- Performance issues → Review `docs/COST_ESTIMATION.md` for resource sizing

**Full troubleshooting guide:** See `docs/SETUP_COMPLETE.md` and `docs/README.md`

---

## ✅ Success Criteria

Your deployment is successful when:

- ✅ All 20 validation tests pass (or 16-20/20)
- ✅ PostgreSQL cluster shows 1 primary + 2 replicas
- ✅ PgBouncer pooler has 3 ready instances
- ✅ WAL archiving status shows "OK"
- ✅ Grafana displays metrics from all PostgreSQL instances
- ✅ Failover completes in <10 seconds

---

> **Important**: This project is designed for **lab environments** and **proof-of-concept** testing. For production deployment, implement additional security hardening, compliance validation, and operational procedures per your organization's requirements.
