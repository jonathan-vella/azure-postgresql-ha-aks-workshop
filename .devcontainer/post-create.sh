#!/bin/bash
# Post-create script for DevContainer
# Runs after the container is created to set up the environment

set -e

echo "🚀 Setting up PostgreSQL HA on AKS DevContainer..."
echo ""

# Install additional tools
echo "📦 Installing additional tools..."
apt-get update && apt-get install -y \
    jq \
    openssl \
    git \
    make \
    curl \
    wget \
    nano \
    vim \
    tree \
    htop \
    ca-certificates \
    gnupg \
    lsb-release \
    > /dev/null 2>&1

echo "✓ Tools installed"
echo ""

# Verify installations
echo "🔍 Verifying tool installations..."
echo ""

echo "Azure CLI version:"
az version --query '"azure-cli"' -o tsv

echo ""
echo "kubectl version:"
kubectl version --client --short

echo ""
echo "Helm version:"
helm version --short

echo ""
echo "jq version:"
jq --version

echo ""
echo "OpenSSL version:"
openssl version

echo ""
echo "================================================"
echo "✅ PostgreSQL HA on AKS DevContainer Setup Complete!"
echo "================================================"
echo ""
echo "Available Tools:"
echo "  • Azure CLI (az) - Cloud infrastructure"
echo "  • kubectl - Kubernetes management"
echo "  • Helm - Kubernetes package manager"
echo "  • jq - JSON processor"
echo "  • OpenSSL - Cryptography tools"
echo ""
echo "Quick Start Commands:"
echo "  • View project: ls -la"
echo "  • Deploy: ./scripts/deploy-postgresql-ha.ps1"
echo "  • Check config: cat config/deployment-config.json | jq"
echo "  • Validate Bicep: az bicep build --file bicep/main.bicep"
echo ""
echo "Documentation:"
echo "  • README.md - Project overview"
echo "  • docs/README.md - Detailed guide"
echo "  • SETUP_COMPLETE.md - Getting started"
echo ""
