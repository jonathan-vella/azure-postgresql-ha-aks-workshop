# Azure PostgreSQL HA on AKS Workshop - Copilot Instructions

**Version**: v1.0.0 | **Last Updated**: October 2025

This project automates the deployment of a highly available PostgreSQL database on Azure Kubernetes Service (AKS) using CloudNativePG operator with Premium v2 disk storage and PgBouncer connection pooling.

## Project Overview

- **Version**: v1.0.0 (Semantic Versioning)
- **Language**: Azure CLI (Infrastructure), YAML (Kubernetes), Bash (Scripts)
- **Primary Purpose**: Automation framework for PostgreSQL HA on AKS following Microsoft reference implementation
- **Target Performance**: 8,000-10,000 TPS with <10s failover (RPO=0)
- **Key Technologies**:
  - Azure Kubernetes Service (AKS) 1.32
  - CloudNativePG Operator 1.27.1
  - PostgreSQL 18.0
  - PgBouncer Connection Pooling (3 instances)
  - Premium SSD v2 Disks (40K IOPS, 1,250 MB/s)
  - Azure Blob Storage for Backups
  - Azure Monitor + Managed Grafana for Observability
  - Workload Identity with Federated Credentials

## Project Structure

```
├── README.md                # Main project documentation (v1.0.0)
├── 00_START_HERE.md         # Quick start guide
├── CONTRIBUTING.md          # Contribution guidelines
├── CHANGELOG.md             # Version history (Semantic Versioning)
├── LICENSE                  # MIT License
├── config/                  # Configuration files
│   └── environment-variables.sh    # Bash environment configuration (all parameters)
├── scripts/                 # Deployment automation (Azure CLI)
│   ├── deploy-all.sh                           # Master orchestration (8 steps including sub-steps)
│   ├── 02-create-infrastructure.sh             # Creates Azure resources (RG, AKS, Storage, Identity, Bastion, NAT Gateway)
│   ├── 03-configure-workload-identity.sh       # Federated credentials
│   ├── 04-deploy-cnpg-operator.sh              # Installs CNPG operator
│   ├── 04a-install-barman-cloud-plugin.sh      # Installs Barman plugin for backups
│   ├── 05-deploy-postgresql-cluster.sh         # Deploys PostgreSQL HA + PgBouncer + PodMonitor
│   ├── 06-configure-monitoring.sh              # Configures Grafana + Azure Monitor
│   ├── 06a-configure-azure-monitor-prometheus.sh  # Configures Azure Monitor Prometheus
│   ├── 07-display-connection-info.sh           # Shows connection endpoints
│   ├── 07a-run-cluster-validation.sh           # Runs comprehensive validation tests
│   ├── 08-test-pgbench.sh                      # Load testing tool
│   └── 08a-test-pgbench-high-load.sh           # High load testing (8K-10K TPS)
├── kubernetes/              # Kubernetes manifests
│   └── postgresql-cluster.yaml  # Reference manifest (NOT used in deployment)
├── grafana/                 # Grafana dashboards
│   └── grafana-cnpg-ha-dashboard.json  # Pre-built dashboard (9 panels)
└── docs/                    # Comprehensive documentation
    ├── README.md                       # Full technical guide
    ├── SETUP_COMPLETE.md               # Complete deployment guide
    ├── QUICK_REFERENCE.md              # Command cheat sheet
    ├── COST_ESTIMATION.md              # Budget planning (~$2,873/month)
    ├── PRE_DEPLOYMENT_CHECKLIST.md     # Pre-flight checks
    ├── AZURE_MONITORING_SETUP.md       # Monitoring setup
    ├── GRAFANA_DASHBOARD_GUIDE.md      # Dashboard usage
    ├── IMPORT_DASHBOARD_NOW.md         # Dashboard import
    ├── FAILOVER_TESTING.md             # HA testing procedures
    ├── CNPG_BEST_PRACTICES.md          # CloudNativePG 1.27 best practices
    └── VM_SETUP_GUIDE.md               # Load test VM setup
```

## Development Environment Setup

### Using DevContainer (Recommended)

This project includes a DevContainer configuration that provides a consistent development environment with all required tools pre-installed:

1. **Open in DevContainer**:
   - Open project in VS Code
   - Press `Ctrl+Shift+P` (or `Cmd+Shift+P` on Mac)
   - Select: `Dev Containers: Reopen in Container`
   - Wait 2-5 minutes for first-time setup

2. **What's Included**:
   - Azure CLI (latest with aks-preview extension)
   - kubectl (1.31.0+)
   - Helm (3.13.0+)
   - jq, OpenSSL, Git
   - Port forwarding for PostgreSQL (5432), Grafana (3000)

3. **Inside Container**:
   ```bash
   # Verify tools are installed
   az --version
   kubectl version --client
   helm version
   
   # Navigate to project
   cd /workspaces/azure-postgresql-ha-aks-workshop
   ```

For detailed DevContainer setup, see `.devcontainer/README.md`.

### Manual Setup (Alternative)

If not using DevContainer, ensure you have:
- Azure CLI 2.56.0+ with aks-preview extension
- kubectl 1.31.0+
- Helm 3.13.0+
- jq 1.7.1+
- OpenSSL 1.1.1+
- Bash shell (Linux/macOS/WSL)

## Code Standards

### Required Before Making Changes

1. **Load Environment Variables** (before any script execution):
   ```bash
   source config/environment-variables.sh
   # Or if .env exists:
   source .env
   ```

2. **Understand the Script Flow**:
   - Review `scripts/deploy-all.sh` to understand deployment order
   - Scripts are numbered and must run in sequence
   - Each script is idempotent (safe to re-run)

### Script Modification Guidelines

When modifying scripts:
1. **Preserve `set -euo pipefail`** - Ensures scripts fail fast on errors
2. **Maintain idempotency** - Scripts should be safe to re-run
3. **Add logging** - Use echo statements with timestamps for debugging
4. **Test in isolated environment** - Never test directly in production
5. **Document changes** - Update script comments and documentation

### Validation Before Committing

Before committing any changes:

1. **Syntax Check** (Bash scripts):
   ```bash
   # Check script syntax
   bash -n scripts/your-modified-script.sh
   ```

2. **ShellCheck** (if available):
   ```bash
   shellcheck scripts/your-modified-script.sh
   ```

3. **Test Execution** (in test environment):
   ```bash
   # Load environment
   source config/environment-variables.sh
   
   # Run the modified script
   ./scripts/your-modified-script.sh
   ```

## Development Flow

### Full Deployment

```bash
# 1. Load environment variables
source config/environment-variables.sh
# Or if .env exists:
source .env

# 2. Deploy complete stack (8 steps: 02, 03, 04, 04a, 05, 06, 06a, 07)
./scripts/deploy-all.sh

# 3. Verify deployment
./scripts/07a-run-cluster-validation.sh
```

### Individual Script Execution

Scripts must be run in order:
```bash
# Step 1: Create Azure infrastructure
./scripts/02-create-infrastructure.sh

# Step 2: Configure workload identity
./scripts/03-configure-workload-identity.sh

# Step 3: Deploy CNPG operator
./scripts/04-deploy-cnpg-operator.sh

# Step 4: Install Barman Cloud plugin
./scripts/04a-install-barman-cloud-plugin.sh

# Step 5: Deploy PostgreSQL cluster
./scripts/05-deploy-postgresql-cluster.sh

# Step 6: Configure monitoring (Grafana)
./scripts/06-configure-monitoring.sh

# Step 7: Configure Azure Monitor Prometheus
./scripts/06a-configure-azure-monitor-prometheus.sh

# Step 8: Display connection info
./scripts/07-display-connection-info.sh
```

### Testing & Validation

#### Cluster Validation
```bash
# Run comprehensive validation tests
./scripts/07a-run-cluster-validation.sh

# This validates:
# - Primary connection (direct)
# - PgBouncer pooler connection
# - Data write operations
# - Read replica connection
# - Data replication verification
# - Replication status
# - Connection pooling
```

#### Load Testing
```bash
# Basic load test (recommended for initial validation)
./scripts/08-test-pgbench.sh

# High load test (8,000-10,000 TPS target)
./scripts/08a-test-pgbench-high-load.sh
```

#### Failover Testing
```bash
# Run failover test scenarios
cd scripts/failover-testing

# Available scenarios:
./scenario-1a-aks-direct-manual.sh      # Manual failover with direct connection
./scenario-1b-aks-direct-simulated.sh   # Simulated failover with direct connection
./scenario-2a-aks-pooler-manual.sh      # Manual failover with PgBouncer
./scenario-2b-aks-pooler-simulated.sh   # Simulated failover with PgBouncer

# Verify data consistency after failover
./verify-consistency.sh

# See docs/FAILOVER_TESTING.md for detailed procedures
```

### Monitoring & Debugging

```bash
# Check cluster status
kubectl cnpg status pg-primary -n cnpg-database

# View pod logs
kubectl logs -n cnpg-database <pod-name>

# Check operator logs
kubectl logs -n cnpg-system deployment/cnpg-cloudnative-pg

# Port forward to PostgreSQL
kubectl port-forward svc/pg-primary-rw 5432:5432 -n cnpg-database

# Connect with psql
psql -h localhost -U app -d appdb
```

## Key Files and Their Purposes

### Environment Configuration (`config/environment-variables.sh`)
- All Azure resource configuration centralized
- Resource names with random 8-character suffix
- AKS settings (version, VM SKUs, zones)
- Storage configuration (Premium v2 IOPS, throughput)
- PostgreSQL credentials and parameters
- Auto-detects public IP for AKS API access

### Deployment Scripts (Azure CLI)
- **02-create-infrastructure**: Creates RG, Storage, Identity, AKS, Monitoring, Bastion, NAT Gateway
- **03-configure-workload-identity**: Sets up federated credentials for backup access
- **04-deploy-cnpg-operator**: Installs CloudNativePG via Helm
- **04a-install-barman-cloud-plugin**: Installs Barman Cloud Plugin v0.8.0
- **05-deploy-postgresql-cluster**: Deploys PostgreSQL HA cluster with Premium v2 storage + PgBouncer + PodMonitor
- **06-configure-monitoring**: Configures Grafana + Azure Monitor integration
- **06a-configure-azure-monitor-prometheus**: Configures Azure Monitor Prometheus integration
- **07-display-connection-info**: Shows connection endpoints and credentials
- **07a-run-cluster-validation**: Runs comprehensive validation tests
- **08-test-pgbench**: Basic load testing (pgbench)
- **08a-test-pgbench-high-load**: High load testing (8K-10K TPS target)
- **deploy-all**: Master orchestration script (8 steps: 2, 3, 4, 4a, 5, 6, 6a, 7)
- Bash scripts only (DevContainer runs on Linux)

### Kubernetes Manifests (`kubernetes/postgresql-cluster.yaml`)
- Reference manifest showing cluster structure
- **NOT used in actual deployment** (configuration embedded in scripts)
- PostgreSQL cluster, services, and storage class are created by script 05

## Development Guidelines

### When Adding Features

1. **Infrastructure Changes**: Update appropriate script in `scripts/02-create-infrastructure.sh`
2. **Kubernetes Changes**: Update `scripts/05-deploy-postgresql-cluster.sh` (cluster definition embedded)
3. **Configuration Changes**: Update `config/environment-variables.sh`
4. **Script Updates**: All scripts are bash-only (DevContainer environment)

### Best Practices for This Project

1. **Always use Premium v2 disks** for PostgreSQL storage (not Standard SSDs)
2. **Maintain 3-node topology** for high availability (1 primary + 2 replicas)
3. **Use availability zones** for zone redundancy
4. **Enable Workload Identity** for Azure integration (no secrets in pods)
5. **Configure backup retention** for disaster recovery (minimum 7 days)
6. **Monitor WAL archiving** - critical for backup reliability

### Azure Well-Architected Framework Alignment

- **Reliability**: Multi-zone deployment, auto-failover, backup/recovery
- **Security**: Workload Identity, NSGs, SCRAM-SHA-256 authentication
- **Performance**: Premium v2 disks with configurable IOPS/throughput, tuned PostgreSQL parameters
- **Cost**: Premium v2 (better price-performance than Premium SSD), right-sized VMs, configurable resources
- **Operations**: Azure Monitor, Grafana dashboards, CNPG observability, automated deployment

## Common Tasks

### Deploy Full Stack
```bash
# Load environment variables
source config/environment-variables.sh

# Deploy all components (8 automated steps)
./scripts/deploy-all.sh
```

### Test PostgreSQL Connection
```bash
kubectl port-forward svc/pg-primary-rw 5432:5432 -n cnpg-database
psql -h localhost -U app -d appdb
```

### Check Cluster Health
```bash
kubectl cnpg status pg-primary -n cnpg-database
```

### Create Backup
```bash
kubectl apply -f kubernetes/backup-ondemand.yaml -n cnpg-database
```

## Troubleshooting

### CNPG Operator Not Deploying
- Check Helm repository: `helm repo update cnpg`
- Verify namespace exists: `kubectl get namespace cnpg-system`
- Check operator logs: `kubectl logs -n cnpg-system deployment/cnpg-cloudnative-pg`

### PostgreSQL Pods Stuck in Init
- Check PVC binding: `kubectl get pvc -n cnpg-database`
- Verify storage class: `kubectl get storageclass`
- Check storage quota in the region

### WAL Archiving Failing
- Verify managed identity has Storage Blob Data Contributor role
- Check federated credential: `az identity federated-credential list ...`
- Review pod logs: `kubectl logs -n cnpg-database <pod-name>`

### Premium v2 Disks Not Available
- Check region support: Premium v2 available in limited regions
- Verify VM SKUs support the region
- Consider alternative regions or storage types

## Documentation Policy: MINIMAL & ESSENTIAL ONLY

**DO NOT create new documentation files unless explicitly requested.** This project has comprehensive documentation covering all use cases.

### Existing Documentation (Use These)
- **README.md** - Main entry point, quick start, deployment overview, architecture
- **00_START_HERE.md** - Quick start guide for new users
- **CHANGELOG.md** - Version history (Keep a Changelog format)
- **CONTRIBUTING.md** - Contribution guidelines
- **.devcontainer/README.md** - DevContainer setup and usage
- **docs/README.md** - Detailed PostgreSQL HA deployment guide
- **docs/SETUP_COMPLETE.md** - Complete setup guide with all steps
- **docs/QUICK_REFERENCE.md** - Command cheat sheet
- **docs/COST_ESTIMATION.md** - Hourly/monthly cost breakdown (~$2,873/month)
- **docs/GRAFANA_DASHBOARD_GUIDE.md** - Dashboard usage and metrics
- **docs/FAILOVER_TESTING.md** - HA testing procedures
- **.github/copilot-instructions.md** - This file

### When to Create a New Document
Only create a new document if:
1. ✅ **Explicitly requested** by user
2. ✅ **Required for functionality** (e.g., configuration file needed by scripts)
3. ✅ **No existing document** covers the topic
4. ✅ **High value and reusable** for multiple team members

### When NOT to Create a Document
❌ Comparison tables/guides (use existing docs, add to README)  
❌ Duplicate information (consolidate instead)  
❌ Step-by-step guides (add to existing README or QUICK_REFERENCE.md)  
❌ "Best practices" guides (reference external Microsoft docs)  
❌ Optional enhancement guides (user can request if needed)  

### Document Maintenance
- Keep documentation DRY (Don't Repeat Yourself)
- Update existing files rather than creating new ones
- Remove outdated documentation when replaced
- Consolidate related information

### Current Documentation Status
✅ Complete and sufficient for all use cases  
✅ No additional documents needed at this time  
✅ Focus on code quality, not documentation volume

## Change Tracking & Documentation Update Workflow

**CRITICAL: Always track changes and keep documentation synchronized.**

### Workflow Steps

#### 1. Track Changes During Session
When making ANY changes to code, scripts, or configuration:

1. **Update `.github/SESSION_CHANGES.md`** immediately with:
   - Files created/modified/deleted
   - Purpose and description of changes
   - Performance impact (if applicable)
   - Breaking changes (if any)
   - Which documentation files need updates

2. **Format for SESSION_CHANGES.md**:
   ```markdown
   # Session Changes - [DATE]
   
   ## Summary
   Brief description of what was accomplished
   
   ---
   
   ## Files Created
   ### 1. path/to/file.ext
   **Purpose**: What it does
   **Description**: Detailed explanation
   **Key Features**: Bullet list
   
   ## Files Modified
   ### 1. path/to/file.ext
   **Changes**: What changed
   **Reason**: Why it changed
   **Impact**: Effect on system
   
   ## Files Deleted
   ### 1. path/to/file.ext
   **Reason**: Why deleted
   **Replaced By**: New file/approach (if applicable)
   
   ---
   
   ## Documentation Updates Needed
   List all files that reference changed functionality:
   1. README.md - Section X needs update
   2. docs/GUIDE.md - Command Y changed
   etc.
   
   ---
   
   ## Performance/Behavior Changes
   - Old behavior: ...
   - New behavior: ...
   - Metrics: ...
   
   ---
   
   ## Migration Notes
   What users need to know/do
   
   ---
   
   ## Commit Message Suggestion
   Suggested commit message following Conventional Commits
   ```

#### 2. Update Documentation Files
Once changes are tracked, **before committing**:

1. **Read `.github/SESSION_CHANGES.md`** to identify affected documentation
2. **Update each documentation file** listed in "Documentation Updates Needed"
3. **Verify consistency** across all docs (use grep/search to find references)
4. **Update CHANGELOG.md** with changes following Keep a Changelog format

#### 3. Clear Change Tracker
After documentation is updated:

1. **Archive the session changes**:
   ```bash
   # Move to archive with timestamp
   mv .github/SESSION_CHANGES.md .github/archive/SESSION_CHANGES_$(date +%Y%m%d_%H%M%S).md
   ```
   OR
   **Clear the file** for next session:
   ```bash
   echo "# Session Changes - $(date +%Y-%m-%d)" > .github/SESSION_CHANGES.md
   echo "" >> .github/SESSION_CHANGES.md
   echo "No changes tracked yet." >> .github/SESSION_CHANGES.md
   ```

2. **Commit everything together**:
   ```bash
   git add .
   git commit -m "feat: [description]
   
   - Updated scripts/...
   - Updated docs/...
   - Cleared SESSION_CHANGES.md after doc sync
   
   Closes #issue"
   ```

#### 4. Validation Checklist
Before committing, verify:

- [ ] `.github/SESSION_CHANGES.md` has all changes documented
- [ ] All documentation files listed in SESSION_CHANGES have been updated
- [ ] No references to old file names remain (use `grep -r "old_name" docs/ README.md`)
- [ ] No stale information about performance/behavior
- [ ] CHANGELOG.md updated with user-facing changes
- [ ] SESSION_CHANGES.md archived or cleared
- [ ] All files staged for commit

### When to Skip This Workflow

Only skip change tracking for:
- ❌ Trivial typo fixes in comments
- ❌ Whitespace-only changes
- ❌ .env file updates (gitignored)
- ❌ Temporary debugging code

Always track for:
- ✅ New scripts or files
- ✅ Modified scripts or functionality
- ✅ Deleted/renamed files
- ✅ Configuration changes
- ✅ Performance improvements
- ✅ Bug fixes affecting behavior
- ✅ Breaking changes

### Tools to Help

```bash
# Find all references to a changed file/command
grep -r "old_script_name.sh" docs/ README.md scripts/

# Find specific values that changed (e.g., pass rates)
grep -r "85%" docs/ README.md

# Check for consistency
git diff --stat  # See what files changed
git diff         # Review actual changes

# Validate documentation is in sync
./scripts/validate-docs.sh  # If available
```

### Example Session Flow

```
1. User: "Can we improve the validation script?"
   → Agent starts working
   
2. Agent creates new validation approach
   → Immediately adds to SESSION_CHANGES.md:
     - Files Created: scripts/new-validate.sh
     - Files Deleted: scripts/old-validate.sh
     - Docs needing update: README.md, docs/QUICK_REFERENCE.md
   
3. Agent completes implementation
   → Updates SESSION_CHANGES.md with results/metrics
   
4. Agent asks: "Ready to update documentation?"
   → User confirms
   
5. Agent updates all listed documentation files
   → Verifies with grep for old references
   → Updates CHANGELOG.md
   
6. Agent archives/clears SESSION_CHANGES.md
   → Commits everything together
   
7. Ready for next change cycle (SESSION_CHANGES.md is clean)
```

### Benefits of This Workflow

1. ✅ **No documentation drift** - Docs always match code
2. ✅ **Clear audit trail** - SESSION_CHANGES.md shows what happened
3. ✅ **Easier code review** - Reviewers see docs were updated
4. ✅ **Better commit messages** - SESSION_CHANGES guides commit description
5. ✅ **Prevents forgotten updates** - Checklist catches missed docs
6. ✅ **Repeatable process** - Works for every change session

### Archive Structure (Optional)

```
.github/
├── copilot-instructions.md
├── SESSION_CHANGES.md          # Current session (active tracking)
└── archive/
    ├── SESSION_CHANGES_20251030_140523.md
    ├── SESSION_CHANGES_20251029_093015.md
    └── SESSION_CHANGES_20251028_161245.md
```

---

## References

- [CloudNativePG Documentation](https://cloudnative-pg.io/)
- [Azure AKS PostgreSQL HA Deployment](https://learn.microsoft.com/en-us/azure/aks/postgresql-ha-overview)
- [Premium SSD v2 in Azure](https://learn.microsoft.com/en-us/azure/virtual-machines/disks-types#premium-ssd-v2)
- [Azure Well-Architected Framework](https://learn.microsoft.com/en-us/azure/architecture/framework/)

## Important Notes

- **Before Deploying**: Ensure Azure subscription has sufficient quota
- **Sensitive Data**: Change default PostgreSQL password in `config/environment-variables.sh`
- **Backup Validation**: Regularly test restore procedures
- **Monitoring Setup**: Ensure Grafana access is properly secured
- **Cost Monitoring**: Premium v2 disks have different pricing (~$2,873/month); set budget alerts
- **Performance**: Configuration optimized for 8,000-10,000 TPS with <10s failover
- **Node Pools**: 2 system nodes (D4s_v5) + 3 user nodes (E8as_v6) for workload isolation

---

For detailed usage instructions, see `docs/README.md`.
