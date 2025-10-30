#!/bin/bash
# Quick setup script to install prerequisites
# Run: bash scripts/setup-prerequisites.sh

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}PostgreSQL HA on AKS - Prerequisites Setup${NC}\n"

# Detect OS
OS=$(uname -s)

# Install Azure CLI
install_azure_cli() {
    if ! command -v az &> /dev/null; then
        echo "Installing Azure CLI..."
        if [[ "$OS" == "Darwin" ]]; then
            brew install azure-cli
        elif [[ "$OS" == "Linux" ]]; then
            curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
        else
            echo "Please install Azure CLI manually from https://learn.microsoft.com/en-us/cli/azure/install-azure-cli"
        fi
    else
        echo -e "${GREEN}✓ Azure CLI installed${NC}"
    fi
}

# Install kubectl
install_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        echo "Installing kubectl..."
        if [[ "$OS" == "Darwin" ]]; then
            brew install kubectl
        elif [[ "$OS" == "Linux" ]]; then
            sudo curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
            sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
        fi
    else
        echo -e "${GREEN}✓ kubectl installed${NC}"
    fi
}

# Install Helm
install_helm() {
    if ! command -v helm &> /dev/null; then
        echo "Installing Helm..."
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    else
        echo -e "${GREEN}✓ Helm installed${NC}"
    fi
}

# Install jq
install_jq() {
    if ! command -v jq &> /dev/null; then
        echo "Installing jq..."
        if [[ "$OS" == "Darwin" ]]; then
            brew install jq
        elif [[ "$OS" == "Linux" ]]; then
            sudo apt-get install -y jq
        fi
    else
        echo -e "${GREEN}✓ jq installed${NC}"
    fi
}

# Install netcat
install_netcat() {
    if ! command -v nc &> /dev/null; then
        echo "Installing netcat..."
        if [[ "$OS" == "Darwin" ]]; then
            # netcat is pre-installed on macOS
            echo -e "${GREEN}✓ netcat available${NC}"
        elif [[ "$OS" == "Linux" ]]; then
            sudo apt-get install -y netcat-openbsd
        fi
    else
        echo -e "${GREEN}✓ netcat installed${NC}"
    fi
}

# Install Krew and CNPG plugin
install_krew_and_cnpg() {
    if ! kubectl krew version &> /dev/null; then
        echo "Installing Krew..."
        (
            set -x; cd "$(mktemp -d)" &&
            OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
            ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
            KREW="krew-${OS}_${ARCH}" &&
            curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
            tar zxvf "${KREW}.tar.gz" &&
            ./"${KREW}" install krew
        )
        export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
    fi
    
    if ! kubectl cnpg version &> /dev/null; then
        echo "Installing CNPG kubectl plugin..."
        kubectl krew install cnpg
    else
        echo -e "${GREEN}✓ CNPG plugin installed${NC}"
    fi
}

# Main installation
main() {
    printf "Checking prerequisites...\n\n"
    
    install_azure_cli
    install_kubectl
    install_helm
    install_jq
    install_netcat
    install_krew_and_cnpg
    
    echo -e "\n${GREEN}All prerequisites installed!${NC}"
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Update config/deployment-config.json with your settings"
    echo "2. Run: ./scripts/deploy-postgresql-ha.sh"
    echo "3. Monitor deployment: kubectl get pods -n cnpg-database -w"
}

main "$@"
