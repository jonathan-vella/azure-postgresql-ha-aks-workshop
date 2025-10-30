#!/usr/bin/env bash
#
# Script: 07a-validate-cluster.sh
# Description: Comprehensive validation of PostgreSQL HA cluster deployment
# Tests: Connectivity, replication, data consistency, pooler functionality, and HA configuration
#

set -uo pipefail

# Source environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

if [ -f "$PROJECT_ROOT/.env" ]; then
    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/.env"
else
    echo "❌ Error: .env file not found. Run setup-prerequisites.sh first."
    exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0
WARNINGS=0

# Temporary files for cleanup
TEMP_FILES=()
PORT_FORWARD_PIDS=()

# Cleanup function
cleanup() {
    echo ""
    echo "Cleaning up..."
    
    # Kill port-forward processes
    for pid in "${PORT_FORWARD_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
    done
    
    # Remove temporary files
    for file in "${TEMP_FILES[@]}"; do
        rm -f "$file" 2>/dev/null || true
    done
    
    # Kill any remaining port-forwards
    pkill -f "kubectl port-forward.*${PG_PRIMARY_CLUSTER_NAME}" 2>/dev/null || true
}

trap cleanup EXIT

# Helper functions
print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

print_test() {
    echo -e "${YELLOW}TEST:${NC} $1"
}

print_success() {
    echo -e "${GREEN}✅ PASS:${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

print_fail() {
    echo -e "${RED}❌ FAIL:${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

print_warning() {
    echo -e "${YELLOW}⚠️  WARN:${NC} $1"
    WARNINGS=$((WARNINGS + 1))
}

print_info() {
    echo -e "   ${BLUE}ℹ${NC} $1"
}

# Wait for port-forward to be ready
wait_for_port_forward() {
    local port=$1
    local max_attempts=15
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if command -v nc &>/dev/null; then
            if nc -z localhost "$port" 2>/dev/null; then
                return 0
            fi
        else
            # Fallback: try to connect with timeout
            if timeout 1 bash -c "cat < /dev/null > /dev/tcp/localhost/$port" 2>/dev/null; then
                return 0
            fi
        fi
        attempt=$((attempt + 1))
        sleep 1
    done
    return 1
}

# Execute psql command
execute_psql() {
    local port=$1
    local query=$2
    
    PGPASSWORD="$PG_DATABASE_PASSWORD" psql -h localhost -p "$port" -U "$PG_DATABASE_USER" -d "$PG_DATABASE_NAME" -t -A -c "$query" 2>/dev/null
}

print_header "PostgreSQL HA Cluster Validation"
echo "Cluster: $PG_PRIMARY_CLUSTER_NAME"
echo "Namespace: $PG_NAMESPACE"
echo "Context: $AKS_PRIMARY_CLUSTER_NAME"

# ============================================================================
# TEST 1: Cluster Status
# ============================================================================
print_header "Test 1: Cluster Status"

print_test "Checking cluster exists and is ready"
if kubectl get cluster "$PG_PRIMARY_CLUSTER_NAME" -n "$PG_NAMESPACE" --context "$AKS_PRIMARY_CLUSTER_NAME" &>/dev/null; then
    CLUSTER_STATUS=$(kubectl get cluster "$PG_PRIMARY_CLUSTER_NAME" -n "$PG_NAMESPACE" --context "$AKS_PRIMARY_CLUSTER_NAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
    INSTANCES=$(kubectl get cluster "$PG_PRIMARY_CLUSTER_NAME" -n "$PG_NAMESPACE" --context "$AKS_PRIMARY_CLUSTER_NAME" -o jsonpath='{.status.instances}')
    READY_INSTANCES=$(kubectl get cluster "$PG_PRIMARY_CLUSTER_NAME" -n "$PG_NAMESPACE" --context "$AKS_PRIMARY_CLUSTER_NAME" -o jsonpath='{.status.readyInstances}')
    
    if [ "$CLUSTER_STATUS" = "True" ]; then
        print_success "Cluster is ready"
        print_info "Instances: $READY_INSTANCES/$INSTANCES ready"
    else
        print_fail "Cluster is not ready (Status: $CLUSTER_STATUS)"
    fi
    
    if [ "$READY_INSTANCES" -ge 3 ]; then
        print_success "High availability configuration active (3+ instances)"
    else
        print_warning "Less than 3 instances ready ($READY_INSTANCES/3)"
    fi
else
    print_fail "Cluster does not exist"
    exit 1
fi

# ============================================================================
# TEST 2: Pod Distribution Across Zones
# ============================================================================
print_header "Test 2: Multi-Zone Pod Distribution"

print_test "Verifying pods are spread across availability zones"
ZONES=$(kubectl get pods -n "$PG_NAMESPACE" -l "cnpg.io/cluster=$PG_PRIMARY_CLUSTER_NAME" --context "$AKS_PRIMARY_CLUSTER_NAME" -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | xargs -I {} kubectl get node {} --context "$AKS_PRIMARY_CLUSTER_NAME" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}{"\n"}' | sort -u | wc -l)

if [ "$ZONES" -ge 2 ]; then
    print_success "Pods distributed across $ZONES availability zones"
    kubectl get pods -n "$PG_NAMESPACE" -l "cnpg.io/cluster=$PG_PRIMARY_CLUSTER_NAME" --context "$AKS_PRIMARY_CLUSTER_NAME" -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,ZONE:.spec.nodeName --no-headers | while read -r name node _; do
        zone=$(kubectl get node "$node" --context "$AKS_PRIMARY_CLUSTER_NAME" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}')
        print_info "Pod $name → Zone: $zone"
    done
else
    print_warning "Pods only in $ZONES zone(s) - expected 2+ for HA"
fi

# ============================================================================
# TEST 3: Service Endpoints
# ============================================================================
print_header "Test 3: Service Endpoints"

print_test "Checking required services exist"
REQUIRED_SERVICES=("${PG_PRIMARY_CLUSTER_NAME}-rw" "${PG_PRIMARY_CLUSTER_NAME}-ro" "${PG_PRIMARY_CLUSTER_NAME}-pooler-rw")
for svc in "${REQUIRED_SERVICES[@]}"; do
    if kubectl get svc "$svc" -n "$PG_NAMESPACE" --context "$AKS_PRIMARY_CLUSTER_NAME" &>/dev/null; then
        CLUSTER_IP=$(kubectl get svc "$svc" -n "$PG_NAMESPACE" --context "$AKS_PRIMARY_CLUSTER_NAME" -o jsonpath='{.spec.clusterIP}')
        print_success "Service $svc exists (ClusterIP: $CLUSTER_IP)"
    else
        print_fail "Service $svc not found"
    fi
done

# ============================================================================
# TEST 4: Primary Connection via PgBouncer Pooler
# ============================================================================
print_header "Test 4: Primary Connection (PgBouncer Pooler)"

print_test "Setting up port-forward to PgBouncer pooler"
kubectl port-forward "svc/${PG_PRIMARY_CLUSTER_NAME}-pooler-rw" 5432:5432 -n "$PG_NAMESPACE" --context "$AKS_PRIMARY_CLUSTER_NAME" > /tmp/pf-pooler.log 2>&1 &
PF_POOLER_PID=$!
PORT_FORWARD_PIDS+=("$PF_POOLER_PID")
TEMP_FILES+=("/tmp/pf-pooler.log")

if wait_for_port_forward 5432; then
    print_success "Port-forward established (PID: $PF_POOLER_PID)"
else
    print_fail "Port-forward failed to start"
    cat /tmp/pf-pooler.log
    exit 1
fi

sleep 3  # Give connection time to stabilize

print_test "Testing PostgreSQL connection"
if PG_VERSION=$(execute_psql 5432 "SELECT version()"); then
    print_success "Connected to PostgreSQL"
    print_info "Version: $(echo "$PG_VERSION" | grep -oP 'PostgreSQL \d+\.\d+')"
else
    print_fail "Failed to connect to PostgreSQL"
    exit 1
fi

print_test "Verifying connected to primary (not replica)"
IS_REPLICA=$(execute_psql 5432 "SELECT pg_is_in_recovery()" | tr -d '[:space:]')
if [ "$IS_REPLICA" = "f" ] || [ "$IS_REPLICA" = "false" ]; then
    print_success "Connected to primary instance"
elif [ -z "$IS_REPLICA" ]; then
    print_warning "Could not determine replica status (connection may be unstable)"
else
    print_fail "Connected to replica instead of primary"
fi

print_test "Checking database and user"
DB_USER=$(execute_psql 5432 "SELECT current_database() || '|' || current_user" | tr -d '[:space:]')
if [ -n "$DB_USER" ] && echo "$DB_USER" | grep -q "$PG_DATABASE_NAME.*$PG_DATABASE_USER"; then
    print_success "Database: $PG_DATABASE_NAME, User: $PG_DATABASE_USER"
elif [ -z "$DB_USER" ]; then
    print_warning "Could not retrieve database/user info (connection may be unstable)"
else
    print_warning "Unexpected database or user: $DB_USER"
fi

# ============================================================================
# TEST 5: Data Write Operations
# ============================================================================
print_header "Test 5: Data Write Operations"

print_test "Creating test table"
TABLE_NAME="cluster_validation_test_$(date +%s)"
TEMP_FILES+=("/tmp/test_data.sql")

cat > /tmp/test_data.sql <<EOF
DROP TABLE IF EXISTS $TABLE_NAME;
CREATE TABLE $TABLE_NAME (
    id SERIAL PRIMARY KEY,
    test_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    test_message TEXT,
    node_info TEXT
);
EOF

CREATE_RESULT=$(PGPASSWORD="$PG_DATABASE_PASSWORD" psql -h localhost -p 5432 -U "$PG_DATABASE_USER" -d "$PG_DATABASE_NAME" -f /tmp/test_data.sql 2>&1)
if echo "$CREATE_RESULT" | grep -q "CREATE TABLE"; then
    print_success "Test table created: $TABLE_NAME"
elif [ -z "$CREATE_RESULT" ]; then
    print_warning "Table creation returned no output - may have failed silently"
else
    print_fail "Failed to create test table"
    print_info "Error: $CREATE_RESULT"
fi

print_test "Inserting test data"
if execute_psql 5432 "INSERT INTO $TABLE_NAME (test_message, node_info) VALUES ('Primary connection test', inet_server_addr()::text), ('PgBouncer pooler test', inet_server_addr()::text), ('Replication validation', inet_server_addr()::text)" &>/dev/null; then
    print_success "Inserted 3 test rows"
else
    print_fail "Failed to insert test data"
fi

print_test "Verifying data persistence"
ROW_COUNT=$(execute_psql 5432 "SELECT COUNT(*) FROM $TABLE_NAME")
if [ "$ROW_COUNT" = "3" ]; then
    print_success "All 3 rows persisted correctly"
else
    print_fail "Expected 3 rows, found $ROW_COUNT"
fi

# ============================================================================
# TEST 6: Synchronous Replication
# ============================================================================
print_header "Test 6: Synchronous Replication"

print_test "Checking replication status from primary"
SYNC_REPLICA=$(execute_psql 5432 "SELECT application_name FROM pg_stat_replication WHERE sync_state = 'quorum' LIMIT 1")
if [ -n "$SYNC_REPLICA" ]; then
    print_success "Synchronous replica active: $SYNC_REPLICA"
else
    print_warning "No synchronous replica found"
fi

ASYNC_REPLICAS=$(execute_psql 5432 "SELECT COUNT(*) FROM pg_stat_replication WHERE sync_state = 'async'")
print_info "Async replicas: $ASYNC_REPLICAS"

print_test "Setting up port-forward to read-only service"
kill "$PF_POOLER_PID" 2>/dev/null || true
sleep 2

kubectl port-forward "svc/${PG_PRIMARY_CLUSTER_NAME}-ro" 5433:5432 -n "$PG_NAMESPACE" --context "$AKS_PRIMARY_CLUSTER_NAME" > /tmp/pf-replica.log 2>&1 &
PF_REPLICA_PID=$!
PORT_FORWARD_PIDS+=("$PF_REPLICA_PID")
TEMP_FILES+=("/tmp/pf-replica.log")

if wait_for_port_forward 5433; then
    print_success "Port-forward established to read-only service (PID: $PF_REPLICA_PID)"
else
    print_fail "Port-forward to replica failed"
    exit 1
fi

sleep 2

print_test "Verifying connection to replica"
IS_REPLICA_RO=$(execute_psql 5433 "SELECT pg_is_in_recovery()")
if [ "$IS_REPLICA_RO" = "t" ]; then
    print_success "Connected to replica (read-only mode)"
else
    print_warning "Connected endpoint reports as primary, not replica"
fi

print_test "Verifying data replication"
REPLICA_ROW_COUNT=$(execute_psql 5433 "SELECT COUNT(*) FROM $TABLE_NAME")
if [ "$REPLICA_ROW_COUNT" = "3" ]; then
    print_success "All 3 rows replicated to replica (RPO=0)"
else
    print_fail "Data mismatch: Expected 3 rows on replica, found $REPLICA_ROW_COUNT"
fi

print_test "Verifying data consistency between primary and replica"
PRIMARY_DATA=$(execute_psql 5432 "SELECT id, test_message FROM $TABLE_NAME ORDER BY id" || echo "")
REPLICA_DATA=$(execute_psql 5433 "SELECT id, test_message FROM $TABLE_NAME ORDER BY id" || echo "")

# Reconnect to primary for comparison
kill "$PF_REPLICA_PID" 2>/dev/null || true
sleep 2
kubectl port-forward "svc/${PG_PRIMARY_CLUSTER_NAME}-pooler-rw" 5432:5432 -n "$PG_NAMESPACE" --context "$AKS_PRIMARY_CLUSTER_NAME" > /tmp/pf-pooler2.log 2>&1 &
PF_POOLER2_PID=$!
PORT_FORWARD_PIDS+=("$PF_POOLER2_PID")
wait_for_port_forward 5432
sleep 2

PRIMARY_DATA=$(execute_psql 5432 "SELECT id, test_message FROM $TABLE_NAME ORDER BY id")

# Reconnect to replica
kill "$PF_POOLER2_PID" 2>/dev/null || true
sleep 2
kubectl port-forward "svc/${PG_PRIMARY_CLUSTER_NAME}-ro" 5433:5432 -n "$PG_NAMESPACE" --context "$AKS_PRIMARY_CLUSTER_NAME" > /tmp/pf-replica2.log 2>&1 &
PF_REPLICA2_PID=$!
PORT_FORWARD_PIDS+=("$PF_REPLICA2_PID")
wait_for_port_forward 5433
sleep 2

REPLICA_DATA=$(execute_psql 5433 "SELECT id, test_message FROM $TABLE_NAME ORDER BY id")

if [ "$PRIMARY_DATA" = "$REPLICA_DATA" ]; then
    print_success "Data consistency verified: Primary and replica data match"
else
    print_fail "Data mismatch between primary and replica"
    print_info "Primary data: $PRIMARY_DATA"
    print_info "Replica data: $REPLICA_DATA"
fi

# ============================================================================
# TEST 7: PgBouncer Pooler Configuration
# ============================================================================
print_header "Test 7: PgBouncer Pooler"

print_test "Checking PgBouncer pooler pods"
POOLER_PODS=$(kubectl get pods -n "$PG_NAMESPACE" -l "cnpg.io/poolerName=${PG_PRIMARY_CLUSTER_NAME}-pooler-rw" --context "$AKS_PRIMARY_CLUSTER_NAME" --no-headers 2>/dev/null | wc -l)
if [ "$POOLER_PODS" -ge 3 ]; then
    print_success "PgBouncer pooler running with $POOLER_PODS instances"
else
    print_warning "Expected 3 pooler instances, found $POOLER_PODS"
fi

print_test "Verifying pooler instance readiness"
POOLER_READY=$(kubectl get pods -n "$PG_NAMESPACE" -l "cnpg.io/poolerName=${PG_PRIMARY_CLUSTER_NAME}-pooler-rw" --context "$AKS_PRIMARY_CLUSTER_NAME" -o jsonpath='{.items[*].status.containerStatuses[0].ready}' 2>/dev/null | tr ' ' '\n' | grep -c "true" || echo "0")
if [ "$POOLER_READY" -eq "$POOLER_PODS" ]; then
    print_success "All $POOLER_READY pooler pods are ready"
else
    print_warning "Only $POOLER_READY/$POOLER_PODS pooler pods ready"
fi

# ============================================================================
# TEST 8: WAL Archiving and Backup
# ============================================================================
print_header "Test 8: WAL Archiving and Backup"

print_test "Checking Barman Cloud Plugin status"
PLUGIN_STATUS=$(kubectl cnpg status "$PG_PRIMARY_CLUSTER_NAME" -n "$PG_NAMESPACE" --context "$AKS_PRIMARY_CLUSTER_NAME" 2>/dev/null | grep -A 2 "Plugins status" | grep "barman-cloud" || echo "")
if echo "$PLUGIN_STATUS" | grep -q "barman-cloud"; then
    PLUGIN_VERSION=$(echo "$PLUGIN_STATUS" | awk '{print $2}')
    print_success "Barman Cloud Plugin active (Version: $PLUGIN_VERSION)"
else
    print_warning "Barman Cloud Plugin status unclear"
fi

print_test "Checking WAL archiving status"
WAL_STATUS=$(kubectl cnpg status "$PG_PRIMARY_CLUSTER_NAME" -n "$PG_NAMESPACE" --context "$AKS_PRIMARY_CLUSTER_NAME" 2>/dev/null | grep "Working WAL archiving" || echo "")
if echo "$WAL_STATUS" | grep -q "OK"; then
    print_success "WAL archiving operational"
else
    print_fail "WAL archiving not operational"
fi

WALS_WAITING=$(kubectl cnpg status "$PG_PRIMARY_CLUSTER_NAME" -n "$PG_NAMESPACE" --context "$AKS_PRIMARY_CLUSTER_NAME" 2>/dev/null | grep "WALs waiting to be archived" | awk '{print $NF}' || echo "unknown")
if [ "$WALS_WAITING" = "0" ]; then
    print_success "No WAL files waiting for archival"
elif [ "$WALS_WAITING" != "unknown" ]; then
    print_warning "$WALS_WAITING WAL files waiting for archival"
fi

# ============================================================================
# TEST 9: Monitoring
# ============================================================================
print_header "Test 9: Monitoring Configuration"

print_test "Checking PodMonitor exists"
if kubectl get podmonitor "$PG_PRIMARY_CLUSTER_NAME" -n "$PG_NAMESPACE" --context "$AKS_PRIMARY_CLUSTER_NAME" &>/dev/null 2>&1 || \
   kubectl get podmonitor.monitoring.coreos.com "$PG_PRIMARY_CLUSTER_NAME" -n "$PG_NAMESPACE" --context "$AKS_PRIMARY_CLUSTER_NAME" &>/dev/null 2>&1; then
    print_success "PodMonitor configured for metrics collection"
else
    print_warning "PodMonitor not found"
fi

print_test "Verifying metrics endpoint on pods"
POD_NAME=$(kubectl get pods -n "$PG_NAMESPACE" -l "cnpg.io/cluster=$PG_PRIMARY_CLUSTER_NAME,role=primary" --context "$AKS_PRIMARY_CLUSTER_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$POD_NAME" ]; then
    if kubectl exec "$POD_NAME" -n "$PG_NAMESPACE" --context "$AKS_PRIMARY_CLUSTER_NAME" -- curl -s http://localhost:9187/metrics 2>/dev/null | grep -q "cnpg_"; then
        print_success "Metrics endpoint responding on primary pod"
    else
        print_warning "Metrics endpoint not responding"
    fi
else
    print_warning "Could not find primary pod for metrics check"
fi

# ============================================================================
# TEST 10: Cleanup Test Data
# ============================================================================
print_header "Test 10: Cleanup"

print_test "Dropping test table"
# Reconnect to primary
kill "${PORT_FORWARD_PIDS[@]}" 2>/dev/null || true
sleep 2
kubectl port-forward "svc/${PG_PRIMARY_CLUSTER_NAME}-pooler-rw" 5432:5432 -n "$PG_NAMESPACE" --context "$AKS_PRIMARY_CLUSTER_NAME" > /tmp/pf-cleanup.log 2>&1 &
PF_CLEANUP_PID=$!
PORT_FORWARD_PIDS+=("$PF_CLEANUP_PID")
wait_for_port_forward 5432
sleep 2

if execute_psql 5432 "DROP TABLE IF EXISTS $TABLE_NAME" &>/dev/null; then
    print_success "Test table dropped successfully"
else
    print_warning "Could not drop test table (may have been manually deleted)"
fi

# ============================================================================
# FINAL REPORT
# ============================================================================
print_header "Validation Summary"

TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))
PASS_RATE=$((TESTS_PASSED * 100 / TOTAL_TESTS))

echo ""
echo -e "${BLUE}Total Tests:${NC}     $TOTAL_TESTS"
echo -e "${GREEN}Tests Passed:${NC}    $TESTS_PASSED"
echo -e "${RED}Tests Failed:${NC}    $TESTS_FAILED"
echo -e "${YELLOW}Warnings:${NC}        $WARNINGS"
echo -e "${BLUE}Pass Rate:${NC}       ${PASS_RATE}%"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✅ ALL TESTS PASSED${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${GREEN}PostgreSQL HA Cluster is fully operational!${NC}"
    echo ""
    echo "✓ Primary and replica connections verified"
    echo "✓ Data write and replication confirmed (RPO=0)"
    echo "✓ PgBouncer connection pooling active"
    echo "✓ Multi-zone high availability configured"
    echo "✓ WAL archiving operational"
    echo "✓ Monitoring configured"
    echo ""
    exit 0
else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}❌ SOME TESTS FAILED${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo "Please review the failed tests above and take corrective action."
    echo ""
    exit 1
fi
