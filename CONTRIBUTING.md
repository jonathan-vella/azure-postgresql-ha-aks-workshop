# Contributing Guide

Thank you for your interest in contributing to the Azure PostgreSQL HA on AKS Workshop! This guide will help you understand how to contribute effectively.

## Code of Conduct

Be respectful, inclusive, and professional in all interactions. We're committed to providing a welcoming environment for all contributors.

## Getting Started

### Prerequisites
- Azure CLI v2.56+
- kubectl v1.21+
- Helm v3.0+
- Git
- Basic knowledge of Azure, Kubernetes, and PostgreSQL

### Setup Development Environment

```bash
# Clone the repository
git clone https://github.com/yourusername/azure-postgresql-ha-aks-workshop.git
cd azure-postgresql-ha-aks-workshop

# Create a feature branch
git checkout -b feature/your-feature-name

# Review documentation
cat docs/README.md
cat SETUP_COMPLETE.md
```

## How to Contribute

### 1. Report Issues
- Check existing issues first to avoid duplicates
- Provide clear description, steps to reproduce, and environment details
- Include logs and error messages
- Use the issue template if provided

### 2. Suggest Improvements
- Open a discussion or issue with your idea
- Explain the use case and benefits
- Wait for feedback before implementing

### 3. Submit Code Changes

#### For Infrastructure (Bicep)
```bash
# Update bicep/main.bicep
# Validate syntax
az bicep build --file bicep/main.bicep

# Test in dry-run mode
az deployment group create \
  --resource-group test-rg \
  --template-file bicep/main.bicep \
  --parameters config/deployment-config.json \
  --what-if
```

#### For Kubernetes Manifests
```bash
# Update kubernetes/postgresql-cluster.yaml
# Validate YAML
kubectl apply --dry-run=client -f kubernetes/postgresql-cluster.yaml

# Test with CNPG operator
kubectl apply -f kubernetes/postgresql-cluster.yaml
kubectl cnpg status pg-primary -n cnpg-database
```

#### For Scripts
```bash
# Test Bash script
export DRY_RUN=true
./scripts/deploy-postgresql-ha.sh
```

#### For Documentation
- Ensure clarity and accuracy
- Add code examples where helpful
- Update related documentation
- Check markdown formatting: `markdownlint docs/`

### 4. Commit Best Practices

```bash
# Use clear commit messages
git commit -m "feat: Add CloudNativePG backup retention policy"

# Commit types:
# feat:    New feature
# fix:     Bug fix
# docs:    Documentation
# style:   Formatting (no code change)
# refactor: Code restructuring
# perf:    Performance improvement
# test:    Tests or test infrastructure
# chore:   Build, dependencies, tooling
```

### 5. Pull Request Process

1. **Create PR from your feature branch**
   ```bash
   git push origin feature/your-feature-name
   # Create PR via GitHub UI
   ```

2. **PR Title Format**: `[type]: Short description`
   - Example: `[feat]: Add automated backup verification`

3. **PR Description**
   - What problem does this solve?
   - How was it tested?
   - Any breaking changes?
   - Related issues/PRs

4. **Code Review**
   - Address all feedback
   - Keep commits clean (squash if needed)
   - Ensure CI passes

5. **Approval & Merge**
   - Wait for at least one approval
   - Ensure all checks pass
   - Maintainer will merge

## Testing Guidelines

### Local Testing
```bash
# Test deployment script (dry-run mode)
export DRY_RUN=true
./scripts/deploy-postgresql-ha.sh

# Validate Bicep template
az bicep build --file bicep/main.bicep

# Validate Kubernetes manifests
kubectl apply --dry-run=client -f kubernetes/postgresql-cluster.yaml
```

### Integration Testing
If deploying to Azure:
1. Use non-production resource group for testing
2. Test in region with Premium v2 support
3. Verify all pods reach healthy state
4. Test database connectivity
5. Verify backups are created
6. Clean up resources after testing

## Documentation Standards

- Use Markdown for all documentation
- Include code examples with language specified
- Keep README.md and related docs in sync
- Add headers and table of contents for long docs
- Include troubleshooting sections

## File Structure Guidelines

- **bicep/**: Infrastructure templates (follow Azure naming conventions)
- **kubernetes/**: Kubernetes manifests (follow k8s best practices)
- **scripts/**: Automation scripts (Bash)
- **config/**: Configuration templates (externalize all parameters)
- **docs/**: Documentation (comprehensive and cross-referenced)
- **.github/**: GitHub configuration and workflows

## Performance & Security

- Use Premium v2 disks (not Standard SSDs)
- Maintain 3-node PostgreSQL topology for HA
- Enable Workload Identity (no hardcoded secrets)
- Use NSGs for network isolation
- Enable encryption at rest and in transit
- Regular security scanning and updates

## Release Process

1. Update version numbers and CHANGELOG
2. Tag release: `git tag -a v1.0.0`
3. Create GitHub release with notes
4. Update documentation

## Questions or Need Help?

- Check `docs/README.md` for detailed documentation
- Review existing issues and PRs for similar questions
- Open a discussion for general questions
- Contact maintainers for sensitive issues

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

**Thank you for contributing!** 🎉 Your effort helps make PostgreSQL HA on AKS better for everyone.
