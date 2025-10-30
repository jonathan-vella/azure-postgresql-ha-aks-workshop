#!/bin/bash
set -euo pipefail

# ==============================================================================
# PostgreSQL HA Cluster Validation (In-Cluster Execution)
# ==============================================================================
# This script deploys a Kubernetes Job that runs validation tests from inside
# the AKS cluster, eliminating kubectl port-forward instability issues.
#
# Tests performed:
# - Primary connection (direct)
# - PgBouncer pooler connection
# - Data write operations
# - Read replica connection
# - Data replication verification
# - Replication status
# - Connection pooling
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Load environment variables
if [ -f "${PROJECT_ROOT}/.env" ]; then
    print_info "Loading environment from .env..."
    source "${PROJECT_ROOT}/.env"
else
    print_error "Environment file not found: ${PROJECT_ROOT}/.env"
    exit 1
fi

# Required variables
: "${SUFFIX:?Environment variable SUFFIX is required}"
: "${PG_NAMESPACE:?Environment variable PG_NAMESPACE is required}"
: "${PG_PRIMARY_CLUSTER_NAME:?Environment variable PG_PRIMARY_CLUSTER_NAME is required}"
: "${AKS_PRIMARY_CLUSTER_NAME:?Environment variable AKS_PRIMARY_CLUSTER_NAME is required}"

print_header "PostgreSQL HA Cluster Validation (In-Cluster)"

print_info "Cluster: ${PG_PRIMARY_CLUSTER_NAME}"
print_info "Namespace: ${PG_NAMESPACE}"
print_info "AKS Cluster: ${AKS_PRIMARY_CLUSTER_NAME}"
echo ""

# Set kubectl context
print_info "Setting kubectl context..."
kubectl config use-context "${AKS_PRIMARY_CLUSTER_NAME}" > /dev/null 2>&1

# Prepare the Job manifest
TEMP_JOB_FILE=$(mktemp)
cp "${PROJECT_ROOT}/kubernetes/cluster-validation-job.yaml" "$TEMP_JOB_FILE"

# Replace cluster name placeholder
sed -i "s/CLUSTER_NAME_PLACEHOLDER/${PG_PRIMARY_CLUSTER_NAME}/g" "$TEMP_JOB_FILE"

# Delete previous validation job if exists
print_info "Cleaning up previous validation jobs..."
kubectl delete job cluster-validation -n "${PG_NAMESPACE}" --ignore-not-found=true > /dev/null 2>&1
sleep 2

# Apply the ConfigMap and Job
print_info "Deploying validation job..."
if kubectl apply -f "$TEMP_JOB_FILE" > /dev/null 2>&1; then
    print_success "Validation job deployed"
else
    print_error "Failed to deploy validation job"
    rm -f "$TEMP_JOB_FILE"
    exit 1
fi

rm -f "$TEMP_JOB_FILE"

# Wait for job to start and pod to be created
print_info "Waiting for validation pod to be created..."
MAX_WAIT=30
WAITED=0
POD_NAME=""

while [ $WAITED -lt $MAX_WAIT ] && [ -z "$POD_NAME" ]; do
    sleep 2
    WAITED=$((WAITED + 2))
    POD_NAME=$(kubectl get pods -n "${PG_NAMESPACE}" -l app=cluster-validation -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
done

if [ -z "$POD_NAME" ]; then
    print_error "Could not find validation pod"
    kubectl get pods -n "${PG_NAMESPACE}" -l app=cluster-validation
    exit 1
fi

print_success "Validation pod started: $POD_NAME"
print_info "Streaming logs..."
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Follow logs until completion
kubectl logs -f "$POD_NAME" -n "${PG_NAMESPACE}" 2>/dev/null || true

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Wait a moment for job status to update
sleep 2

# Check job completion status
JOB_SUCCEEDED=$(kubectl get job cluster-validation -n "${PG_NAMESPACE}" -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
JOB_FAILED=$(kubectl get job cluster-validation -n "${PG_NAMESPACE}" -o jsonpath='{.status.failed}' 2>/dev/null || echo "0")

if [ "$JOB_SUCCEEDED" = "1" ]; then
    print_success "Validation completed successfully"
    echo ""
    print_info "Job will be automatically cleaned up in 1 hour"
    print_info "To view logs again: kubectl logs job/cluster-validation -n ${PG_NAMESPACE}"
    echo ""
    exit 0
elif [ "$JOB_FAILED" = "1" ]; then
    print_error "Validation failed - check logs above for details"
    echo ""
    print_info "To view logs again: kubectl logs job/cluster-validation -n ${PG_NAMESPACE}"
    print_info "To delete job: kubectl delete job cluster-validation -n ${PG_NAMESPACE}"
    echo ""
    exit 1
else
    print_error "Validation job still running or status unclear"
    echo ""
    kubectl get job cluster-validation -n "${PG_NAMESPACE}"
    echo ""
    exit 1
fi
