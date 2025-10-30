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
    netcat-openbsd \
    > /dev/null 2>&1

echo "✓ System tools installed"
echo ""

# Install CNPG kubectl plugin
echo "📦 Installing CNPG kubectl plugin v1.27.1..."
curl -fsSL https://github.com/cloudnative-pg/cloudnative-pg/releases/download/v1.27.1/kubectl-cnpg_1.27.1_linux_x86_64.tar.gz -o /tmp/kubectl-cnpg.tar.gz
tar -xzf /tmp/kubectl-cnpg.tar.gz -C /tmp
install -o root -g root -m 0755 /tmp/kubectl-cnpg /usr/local/bin/kubectl-cnpg
rm -f /tmp/kubectl-cnpg.tar.gz /tmp/kubectl-cnpg
echo "✓ CNPG plugin installed"
echo ""

# Install Krew (as vscode user)
echo "📦 Installing Krew..."
su - vscode -c '
(
  set -x
  cd "$(mktemp -d)"
  OS="$(uname | tr '"'"'[:upper:]'"'"' '"'"'[:lower:]'"'"')"
  ARCH="$(uname -m | sed -e '"'"'s/x86_64/amd64/'"'"' -e '"'"'s/\(arm\)\(64\)\?.*/\1\2/'"'"' -e '"'"'s/aarch64$/arm64/'"'"')"
  KREW="krew-${OS}_${ARCH}"
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz"
  tar zxf "${KREW}.tar.gz"
  ./"${KREW}" install krew
) > /dev/null 2>&1
'
echo 'export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"' >> /home/vscode/.bashrc
echo "✓ Krew installed"
echo ""

# Configure Azure CLI
echo "⚙️  Configuring Azure CLI..."
az config set extension.use_dynamic_install=yes_without_prompt > /dev/null 2>&1
az config set extension.dynamic_install_allow_preview=true > /dev/null 2>&1
echo "✓ Azure CLI configured"
echo ""

# Install Azure CLI extensions
echo "📦 Installing Azure CLI extensions..."
az extension add --name amg --upgrade --yes --only-show-errors > /dev/null 2>&1 || true
echo "✓ Azure CLI extensions installed"
echo ""

# Verify installations
echo "🔍 Verifying tool installations..."
echo ""
echo "  Azure CLI:     $(az version --query '"azure-cli"' -o tsv)"
echo "  kubectl:       $(kubectl version --client -o json 2>/dev/null | jq -r '.clientVersion.gitVersion')"
echo "  Helm:          $(helm version --short | cut -d'+' -f1)"
echo "  jq:            $(jq --version)"
echo "  netcat:        $(nc -h 2>&1 | head -1 | cut -d' ' -f1-2)"
echo "  CNPG plugin:   v1.27.1"
echo "  Krew:          installed"
echo ""
echo "================================================"
echo "✅ PostgreSQL HA on AKS DevContainer Ready!"
echo "================================================"
echo ""
echo "Installed Tools:"
echo "  • Azure CLI (az)          - Azure cloud management"
echo "  • kubectl                  - Kubernetes CLI"
echo "  • Helm                     - Kubernetes package manager"
echo "  • jq                       - JSON processor"
echo "  • netcat (nc)              - Network testing"
echo "  • kubectl-cnpg             - CloudNativePG plugin"
echo "  • kubectl-krew             - kubectl plugin manager"
echo ""
echo "Next Steps:"
echo "  1. Load environment:    source config/environment-variables.sh"
echo "  2. Login to Azure:      az login --use-device-code"
echo "  3. Deploy cluster:      ./scripts/deploy-all.sh"
echo ""
echo "Documentation:"
echo "  • 00_START_HERE.md     - Quick start guide"
echo "  • README.md            - Project overview"
echo "  • docs/README.md       - Detailed deployment guide"
echo ""
