# Cost Estimation - PostgreSQL HA on AKS

**Deployment Overview**: 3-node PostgreSQL cluster on AKS with full monitoring, security, and load testing infrastructure.

---

## 💰 Monthly Cost Breakdown (East US 2 Region)

### Core Infrastructure

| Service | Configuration | Hourly Cost | Monthly Cost (730h) |
|---------|--------------|-------------|---------------------|
| **AKS Cluster Management** | Free tier | $0.00 | $0.00 |
| **AKS System Nodes (2x)** | Standard_D4s_v5 (4 vCPU, 16GB RAM) × 2 | ~$0.32 | ~$234 |
| **AKS User Nodes (3x)** | Standard_E8as_v6 (8 vCPU, 64GB RAM) × 3 | ~$1.95 | ~$1,424 |
| **Premium SSD v2 Disks (3x)** | 200 GiB, 40K IOPS, 1,250 MB/s × 3 | ~$0.75 | ~$548 |
| **Azure Blob Storage** | Standard LRS (backup storage, ~500GB) | ~$0.003 | ~$10 |
| **Managed Identity** | Free | $0.00 | $0.00 |

**Subtotal Core**: ~$3.02/hour | ~$2,216/month

---

### Security & Access

| Service | Configuration | Hourly Cost | Monthly Cost (730h) |
|---------|--------------|-------------|---------------------|
| **Microsoft Defender for Containers** | Per-node charge × 3 | ~$0.05 | ~$37 |
| **Azure Bastion** | Basic SKU | ~$0.19 | ~$139 |
| **NAT Gateway** | Standard | ~$0.045 | ~$33 |
| **NAT Gateway Data Processing** | 100GB/month estimate | ~$0.006 | ~$4.50 |

**Subtotal Security**: ~$0.29/hour | ~$213/month

---

### Monitoring & Observability

| Service | Configuration | Hourly Cost | Monthly Cost (730h) |
|---------|--------------|-------------|---------------------|
| **Azure Monitor - Log Analytics** | 10GB ingestion/day | ~$0.04 | ~$30 |
| **Azure Managed Grafana** | Standard tier | ~$0.31 | ~$226 |
| **Prometheus Operator** | Runs on AKS (no extra charge) | $0.00 | $0.00 |

**Subtotal Monitoring**: ~$0.35/hour | ~$256/month

---

### Load Testing Infrastructure

| Service | Configuration | Hourly Cost | Monthly Cost (730h) |
|---------|--------------|-------------|---------------------|
| **Load Test VM** | Standard_D4s_v5 (4 vCPU, 16GB RAM) | ~$0.23 | ~$168 |
| **VM Managed Disk** | P10 (128 GiB Premium SSD) | ~$0.03 | ~$20 |

**Subtotal Load Testing**: ~$0.26/hour | ~$188/month

---

## 📊 Total Cost Summary

| Category | Hourly | Monthly (730h) |
|----------|--------|----------------|
| **Core Infrastructure** | ~$3.02 | ~$2,216 |
| **Security & Access** | ~$0.29 | ~$213 |
| **Monitoring** | ~$0.35 | ~$256 |
| **Load Testing** | ~$0.26 | ~$188 |
| **TOTAL** | **~$3.92** | **~$2,873** |

> **Note**: Prices based on East US 2 region (October 2025). Actual costs vary by region, usage patterns, and Azure commitment discounts.

---

## 💡 Cost Optimization Strategies

### 1. **Dev/Test Environments** (~63% savings)
- Use **1 system node** (D2s_v5) instead of 2
- Use **Standard_D4s_v5** user nodes (4 vCPU, 16GB) instead of E8as_v6
- Reduce disk IOPS to 8,000 (vs 40,000)
- Use **Standard SSD** instead of Premium SSD v2
- **Estimated Cost**: ~$1,056/month

### 2. **Azure Reserved Instances** (~30-40% savings)
- 1-year commitment: Save ~30%
- 3-year commitment: Save ~40%
- **Estimated Cost with 3-year RI**: ~$2,010/month

### 3. **Spot VMs for Load Testing** (~70-90% savings)
- Use Azure Spot VMs for non-critical load test infrastructure
- **Estimated Savings**: $120-150/month

### 4. **Shutdown Non-Production During Off-Hours**
- Stop AKS cluster nights/weekends (50% usage)
- Keep monitoring always-on
- **Estimated Cost**: ~$1,750/month

### 5. **Remove Load Test VM After Testing**
- Delete VM when not actively load testing
- **Estimated Savings**: $188/month

---

## 🔍 Detailed Service Breakdown

### Azure Kubernetes Service (AKS)
**Cluster Management**: Free (Microsoft-managed control plane)

**System Node Pool** (2 nodes for AKS system workloads):
- **VM SKU**: Standard_D4s_v5 (Intel Ice Lake, general-purpose)
- **Count**: 2 nodes (across availability zones)
- **Specs per node**: 4 vCPU, 16GB RAM
- **Cost per node**: ~$0.16/hour × 2 = ~$0.32/hour
- **Monthly**: ~$234

**User Node Pool** (3 nodes where PostgreSQL runs):
- **VM SKU**: Standard_E8as_v6 (AMD EPYC, memory-optimized)
- **Count**: 3 nodes (1 per availability zone for HA)
- **Specs per node**: 8 vCPU, 64GB RAM
- **Cost per node**: ~$0.65/hour × 3 = ~$1.95/hour
- **Monthly**: ~$1,424

**Why Separate Node Pools?**
- **System Pool**: Dedicated for AKS system pods (CoreDNS, metrics-server, tunnelfront)
- **User Pool**: Isolated for PostgreSQL workloads (no resource contention)
- **Cost-effective**: System nodes use smaller, cheaper VMs
- **Performance**: PostgreSQL gets 100% of user node resources

**Why E8as_v6 for User Nodes?**
- Memory-optimized for PostgreSQL workloads
- AMD EPYC processors (better price-performance)
- 64GB RAM per node (40GB for PostgreSQL + 20% AKS overhead)
- Availability zone support for HA

---

### Storage (Premium SSD v2)
**Per-disk specs**:
- **Capacity**: 200 GiB
- **IOPS**: 40,000 (provisioned)
- **Throughput**: 1,250 MB/s (provisioned)
- **Billing**: Capacity + IOPS + Throughput (separate charges)

**Cost Calculation** (per disk):
- Capacity: 200 GiB × $0.06/GiB = $12/month
- IOPS: 40,000 × $0.005/IOPS = $200/month (Note: First 3,000 IOPS free)
- Throughput: 1,250 MB/s × $0.10/MB/s = $125/month (Note: First 125 MB/s free)
- **Total per disk**: ~$182/month
- **Total 3 disks**: ~$548/month

**Why Premium SSD v2?**
- Better price-performance than Premium SSD (v1)
- Independent scaling of IOPS and throughput
- Required for high-performance PostgreSQL (8,000-10,000 TPS target)

---

### Azure Blob Storage (Backups)
**Configuration**:
- **Type**: Standard LRS (Locally Redundant Storage)
- **Usage**: PostgreSQL WAL archives and base backups
- **Estimated Size**: 500GB (7-day retention, high-write workload)
- **Cost**: $0.0184/GB = ~$10/month

**Data Transfer**:
- Within same region: Free
- Outbound (if restoring externally): $0.087/GB

---

### Microsoft Defender for Containers
**Configuration**:
- **Per-node charge**: ~$12.26/node/month
- **3 nodes**: ~$37/month

**What You Get**:
- Container vulnerability scanning
- Kubernetes threat detection
- Runtime protection
- Security recommendations
- Integration with Azure Security Center

**Cost Optimization**:
- Can be disabled in dev/test environments (not recommended for production)

---

### Azure Bastion
**Configuration**:
- **SKU**: Basic
- **Cost**: ~$0.19/hour = ~$139/month

**What You Get**:
- Secure RDP/SSH access to VMs without public IPs
- No need for jump boxes
- Integrated with Azure Portal

**Alternatives**:
- **Developer SKU**: ~$0.03/hour (~$22/month) - Limited to 2 concurrent connections
- **Remove Bastion**: Use `kubectl port-forward` instead (requires kubeconfig access)

---

### NAT Gateway
**Configuration**:
- **Type**: Standard NAT Gateway
- **Base Cost**: ~$0.045/hour = ~$33/month
- **Data Processing**: $0.045/GB processed

**Estimated Data Processing**:
- Outbound traffic: ~100GB/month (backups, monitoring, updates)
- **Cost**: 100GB × $0.045 = ~$4.50/month

**What You Get**:
- Outbound internet connectivity for AKS nodes
- Static public IP for egress
- Required for backup to Blob Storage

---

### Azure Monitor - Log Analytics
**Configuration**:
- **Data Ingestion**: ~10GB/day
- **Pricing**: First 5GB/day free, then $2.99/GB
- **Daily Cost**: (10 - 5) × $2.99 = ~$15/day
- **Monthly Cost**: ~$30/month (with free tier)

**What You Get**:
- Centralized log aggregation
- Query with KQL (Kusto Query Language)
- Integration with Grafana
- Alerting capabilities

**Cost Optimization**:
- Reduce log retention (default 30 days, can reduce to 7 days)
- Filter verbose logs at source
- Use sampling for high-volume logs

---

### Azure Managed Grafana
**Configuration**:
- **SKU**: Standard
- **Cost**: ~$0.31/hour = ~$226/month

**What You Get**:
- Fully managed Grafana instance
- High availability (built-in)
- Azure AD integration
- Pre-built dashboards
- Alerting and notifications

**Alternatives**:
- **Self-hosted Grafana**: Free, but requires AKS resources and management overhead
- **Essential SKU**: ~$0.15/hour (~$110/month) - Limited to 5 users

---

### Load Test Virtual Machine
**Configuration**:
- **VM SKU**: Standard_D4s_v5 (4 vCPU, 16GB RAM, Intel Ice Lake)
- **Cost**: ~$0.23/hour = ~$168/month
- **Disk**: P10 Premium SSD (128 GiB) = ~$20/month

**What You Get**:
- Dedicated VM for running `pgbench` load tests
- Isolated from AKS cluster (realistic network conditions)
- Can simulate multiple concurrent clients

**Cost Optimization**:
- **Stop/Deallocate when not testing**: Only pay for disk storage (~$20/month)
- **Use Azure Spot VMs**: ~70-90% discount (subject to eviction)
- **Use AKS pod for basic tests**: Free (runs on existing nodes)

---

## 📈 Scaling Cost Examples

### Small (Dev/Test) - ~$1,056/month
```yaml
System Nodes: 1 × Standard_D2s_v5 (2 vCPU, 8GB)
User Nodes: 3 × Standard_D4s_v5 (4 vCPU, 16GB)
Storage: 3 × Standard SSD (32Gi, 8K IOPS)
Monitoring: Log Analytics (5GB/day), Self-hosted Grafana
Security: No Defender, No Bastion (kubectl access only)
Load Test: Use AKS pods (no dedicated VM)
```

### Medium (Pre-Production) - ~$2,216/month
```yaml
System Nodes: 2 × Standard_D4s_v5 (4 vCPU, 16GB)
User Nodes: 3 × Standard_E8as_v6 (8 vCPU, 64GB)
Storage: 3 × Premium SSD v2 (200Gi, 40K IOPS)
Monitoring: Log Analytics (10GB/day), Managed Grafana Standard
Security: Defender for Containers, NAT Gateway
Load Test: Spot VM (when needed)
```

### Large (Production) - ~$4,900/month
```yaml
System Nodes: 3 × Standard_D4s_v5 (4 vCPU, 16GB)
User Nodes: 6 × Standard_E16as_v6 (16 vCPU, 128GB) - 2 per zone
Storage: 6 × Premium SSD v2 (500Gi, 80K IOPS)
Monitoring: Log Analytics (50GB/day), Managed Grafana Standard
Security: Defender for Containers, Azure Bastion Standard, Private Link
Load Test: Dedicated VM (Standard_D8s_v5)
Backup: GRS (Geo-Redundant Storage)
```

---

## 🎯 Cost Attribution Tags

**Recommended Azure Tags**:
```yaml
Environment: Production | Staging | Development
CostCenter: Engineering | Operations
Project: PostgreSQL-HA-AKS
Owner: team@company.com
Workload: Database
Criticality: Tier1 | Tier2 | Tier3
```

**Enable Cost Analysis**:
- Azure Cost Management + Billing
- Set budget alerts (e.g., alert at 80% of $3,000/month)
- Review daily costs in Azure Portal
- Export cost data for FinOps analysis

---

## 🔗 Resources

- **Azure Pricing Calculator**: https://azure.microsoft.com/pricing/calculator/
- **AKS Pricing**: https://azure.microsoft.com/pricing/details/kubernetes-service/
- **Premium SSD v2 Pricing**: https://azure.microsoft.com/pricing/details/managed-disks/
- **Azure Monitor Pricing**: https://azure.microsoft.com/pricing/details/monitor/
- **Grafana Pricing**: https://azure.microsoft.com/pricing/details/managed-grafana/
- **Cost Optimization Best Practices**: https://learn.microsoft.com/azure/well-architected/cost/

---

## 📝 Notes

1. **Prices are estimates** based on East US 2 region and may vary by region, time, and Azure pricing changes.
2. **Data transfer costs** are minimal within the same region but can add up for cross-region scenarios.
3. **Commitment discounts** (Reserved Instances, Savings Plans) can significantly reduce costs for production workloads.
4. **Free tier services** (AKS management, Managed Identity) have no direct cost but consume other resources.
5. **Actual usage varies** based on workload patterns, retention policies, and operational practices.

**Use Azure Pricing Calculator** to get exact pricing for your specific configuration and region:  
https://azure.microsoft.com/pricing/calculator/

---

**Last Updated**: October 2025  
**Pricing Source**: Azure Pricing Calculator (East US 2)
