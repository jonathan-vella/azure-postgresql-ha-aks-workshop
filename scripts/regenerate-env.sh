#!/bin/bash
# Regenerate .env with new suffix
# Use this when you want to deploy a fresh environment with new resource names

set -euo pipefail

ENV_FILE="/workspaces/azure-postgresql-ha-aks-workshop/.env"

# Check if running non-interactively (called from another script)
SKIP_PROMPT="${1:-}"

echo "🔄 Regenerating .env with new suffix..."
echo ""

# Check if .env exists and show current config
if [ -f "$ENV_FILE" ]; then
    echo "📋 Current configuration:"
    source "$ENV_FILE"
    echo "  Old Suffix:         $SUFFIX"
    echo "  Old Resource Group: $RESOURCE_GROUP_NAME"
    echo ""
    
    # Prompt for confirmation (unless skipped)
    if [ "$SKIP_PROMPT" != "--yes" ]; then
        read -p "⚠️  Delete current .env and generate new suffix? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "❌ Cancelled. Keeping existing .env file."
            exit 0
        fi
    fi
    
    # Backup old .env
    BACKUP_FILE=".env.backup-$(date +%Y%m%d-%H%M%S)"
    cp "$ENV_FILE" "$BACKUP_FILE"
    echo "💾 Backed up old .env to: $BACKUP_FILE"
    
    # Delete current .env
    rm -f "$ENV_FILE"
    echo "🗑️  Deleted old .env file"
    echo ""
fi

# Generate new .env
echo "🔧 Generating new .env file..."
bash /workspaces/azure-postgresql-ha-aks-workshop/.devcontainer/generate-env.sh

echo ""
echo "✅ New .env file created!"
echo ""
echo "📝 Next steps:"
echo "   1. Load new environment: source .env"
echo "   2. Deploy:               ./scripts/deploy-all.sh"
echo ""
