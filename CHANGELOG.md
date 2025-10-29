# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [v1.0.0] - 2025-10-29

### 🎉 Initial Release

#### Added
- Complete automation framework for PostgreSQL HA on AKS
- CloudNativePG operator 1.27.1 integration
- PostgreSQL 18.0 deployment with 3-node HA topology
- PgBouncer connection pooling (3 instances, 10K max connections)
- Premium SSD v2 storage support (40K IOPS, 1,250 MB/s)
- Separate node pools (2 system + 3 user nodes)
- Synchronous replication with zero data loss (RPO = 0)
- Automatic failover with <10s RTO target
- Azure Blob Storage backup integration (7-day retention)
- Prometheus metrics collection via PodMonitor
- Grafana dashboard with 9 monitoring panels
- Azure Monitor integration
- Workload Identity with federated credentials
- DevContainer with pre-installed tools
- Comprehensive documentation (10 markdown files)
- Cost estimation guide (~$2,873/month for medium setup)

#### Infrastructure
- AKS 1.32 with zone-redundant deployment
- System node pool: 2 × Standard_D4s_v5 (4 vCPU, 16GB)
- User node pool: 3 × Standard_E8as_v6 (8 vCPU, 64GB)
- Premium SSD v2 disks: 3 × 200 GiB
- Azure Bastion for secure access
- NAT Gateway for outbound connectivity
- Microsoft Defender for Containers

#### Security
- SCRAM-SHA-256 authentication
- Network Security Groups (NSGs)
- Kubernetes RBAC
- Encrypted backups to Azure Storage
- No secrets in pods (Workload Identity)

#### Automation Scripts
- `deploy-all.sh` - Master orchestration (8 steps)
- `02-create-infrastructure.sh` - Azure resources
- `03-configure-workload-identity.sh` - Federated credentials
- `04-deploy-cnpg-operator.sh` - CNPG operator
- `04a-install-barman-cloud-plugin.sh` - Barman Cloud Plugin v0.8.0
- `04b-install-prometheus-operator.sh` - Prometheus Operator
- `05-deploy-postgresql-cluster.sh` - PostgreSQL cluster + PgBouncer
- `06-configure-monitoring.sh` - Grafana + Azure Monitor
- `07-display-connection-info.sh` - Connection info

#### Documentation
- README.md - Main project documentation
- 00_START_HERE.md - Quick start guide
- CONTRIBUTING.md - Contribution guidelines
- docs/SETUP_COMPLETE.md - Complete setup guide
- docs/QUICK_REFERENCE.md - Command cheat sheet
- docs/COST_ESTIMATION.md - Budget planning
- docs/GRAFANA_DASHBOARD_GUIDE.md - Dashboard usage
- docs/FAILOVER_TESTING.md - HA testing procedures
- docs/AZURE_MONITORING_SETUP.md - Monitoring setup
- docs/PRE_DEPLOYMENT_CHECKLIST.md - Pre-flight checks

#### Configuration
- Dynamic PostgreSQL parameter calculation
- 20% AKS system overhead accounted for
- Failover timings optimized (3s delays)
- Adaptive Grafana dashboard time intervals
- Environment-based configuration management

#### Testing
- Load testing validated: 1,961 TPS sustained
- Failover testing validated: <10s RTO, 0 RPO
- Zero transaction failures under load
- Clean cluster promotion on primary failure

---

## [Unreleased]

### Planned Features
- Multi-region deployment support
- Async replication mode option for higher TPS
- Automated backup restoration procedures
- Enhanced Grafana alerting rules
- Terraform IaC alternative
- GitHub Actions CI/CD pipeline
- Helm chart packaging

---

**Note**: This project is intended for lab and proof-of-concept environments. Production deployment requires additional security hardening, compliance validation, and operational procedures.

[v1.0.0]: https://github.com/jonathan-vella/azure-postgresql-ha-aks-workshop/releases/tag/v1.0.0
