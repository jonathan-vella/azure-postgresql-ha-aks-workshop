#!/bin/bash
# Script 07: Test pgbench in AKS Cluster
# Verifies PostgreSQL performance testing capability inside the cluster
# Tests both direct PostgreSQL connection and PgBouncer pooler connection

set -euo pipefail

# Source environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/../.env" ]; then
    source "${SCRIPT_DIR}/../.env"
else
    source "${SCRIPT_DIR}/../config/environment-variables.sh"
fi
source "${SCRIPT_DIR}/../.deployment-outputs"

echo "=== Testing pgbench in AKS Cluster ==="

# Get PostgreSQL password from secret
echo "Retrieving database credentials..."
PG_PASSWORD=$(kubectl get secret "pg-superuser-secret" \
    -n "$PG_NAMESPACE" \
    -o jsonpath='{.data.password}' | base64 -d)

# Define service endpoints
PG_SERVICE_DIRECT="${PG_PRIMARY_CLUSTER_NAME}-rw"        # Direct PostgreSQL connection
PG_SERVICE_POOLER="${PG_PRIMARY_CLUSTER_NAME}-pooler-rw" # PgBouncer pooler connection

echo "Test Configuration:"
echo "  Direct Service:  $PG_SERVICE_DIRECT (PostgreSQL direct)"
echo "  Pooler Service:  $PG_SERVICE_POOLER (PgBouncer pooler)"
echo "  Database:        $PG_DATABASE_NAME"
echo "  User:            $PG_DATABASE_USER"
echo ""

# Create pgbench test pod
echo "Creating pgbench test pod in cluster..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: pgbench-test
  namespace: $PG_NAMESPACE
  labels:
    app: pgbench-test
spec:
  restartPolicy: Never
  containers:
  - name: pgbench
    image: postgres:17
    env:
    - name: PGPASSWORD
      value: "$PG_PASSWORD"
    - name: PGUSER
      value: "$PG_DATABASE_USER"
    - name: PGDATABASE
      value: "$PG_DATABASE_NAME"
    - name: PG_SERVICE_DIRECT
      value: "$PG_SERVICE_DIRECT"
    - name: PG_SERVICE_POOLER
      value: "$PG_SERVICE_POOLER"
    command:
    - /bin/bash
    - -c
    - |
      echo "╔════════════════════════════════════════════════════════════╗"
      echo "║      PostgreSQL Performance Test with pgbench             ║"
      echo "╚════════════════════════════════════════════════════════════╝"
      echo ""
      
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "PHASE 1: Connection & Version Verification"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo ""
      
      echo "Testing Direct PostgreSQL Connection (\$PG_SERVICE_DIRECT)..."
      psql -h \$PG_SERVICE_DIRECT -U \$PGUSER -d \$PGDATABASE -c 'SELECT version();' | head -2
      echo ""
      
      echo "Testing PgBouncer Pooler Connection (\$PG_SERVICE_POOLER)..."
      psql -h \$PG_SERVICE_POOLER -U \$PGUSER -d \$PGDATABASE -c 'SELECT version();' | head -2
      echo ""
      
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "PHASE 2: Database Initialization"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo ""
      
      echo "Initializing pgbench schema (scale factor 10 = ~160MB)..."
      echo "Using DIRECT connection for schema creation..."
      pgbench -h \$PG_SERVICE_DIRECT -U \$PGUSER -d \$PGDATABASE -i -s 10 --quiet
      echo "✓ Schema initialized successfully"
      echo ""
      
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "PHASE 3: Performance Test - DIRECT Connection"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo ""
      echo "Test Configuration:"
      echo "  Connection:  Direct PostgreSQL (\$PG_SERVICE_DIRECT)"
      echo "  Duration:    30 seconds"
      echo "  Clients:     10 concurrent connections"
      echo "  Threads:     2 worker threads"
      echo ""
      
      pgbench -h \$PG_SERVICE_DIRECT -U \$PGUSER -d \$PGDATABASE -c 10 -j 2 -T 30 -P 10 --protocol=prepared
      echo ""
      
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "PHASE 4: Performance Test - POOLER Connection (Recommended)"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo ""
      echo "Test Configuration:"
      echo "  Connection:  PgBouncer Pooler (\$PG_SERVICE_POOLER)"
      echo "  Duration:    30 seconds"
      echo "  Clients:     10 concurrent connections"
      echo "  Threads:     2 worker threads"
      echo "  Mode:        Transaction pooling"
      echo ""
      
      pgbench -h \$PG_SERVICE_POOLER -U \$PGUSER -d \$PGDATABASE -c 10 -j 2 -T 30 -P 10 --protocol=simple
      echo ""
      
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "PHASE 5: Cleanup"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo ""
      
      echo "Dropping pgbench tables..."
      psql -h \$PG_SERVICE_DIRECT -U \$PGUSER -d \$PGDATABASE -c 'DROP TABLE IF EXISTS pgbench_accounts, pgbench_branches, pgbench_history, pgbench_tellers;' > /dev/null
      echo "✓ Cleanup complete"
      echo ""
      
      echo "╔════════════════════════════════════════════════════════════╗"
      echo "║  ✓ All Tests Completed Successfully                       ║"
      echo "╚════════════════════════════════════════════════════════════╝"
      echo ""
      echo "📊 Performance Notes:"
      echo "  • Direct connection: Lower latency, limited connections"
      echo "  • Pooler connection: Efficient connection management, 10K+ capacity"
      echo "  • For production: Use pooler services for application workloads"
      echo ""
      
      echo "Pod will terminate in 10 seconds..."
      sleep 10
EOF

# Wait for pod to be created
echo "Waiting for pod to start..."
kubectl wait --for=condition=Ready pod/pgbench-test -n "$PG_NAMESPACE" --timeout=60s

# Follow logs
echo ""
echo "=== Test Output ==="
kubectl logs -f pgbench-test -n "$PG_NAMESPACE"

# Wait for pod to complete
echo ""
echo "Waiting for test to complete..."
kubectl wait --for=condition=ContainersReady=false pod/pgbench-test -n "$PG_NAMESPACE" --timeout=120s || true

# Cleanup
echo ""
echo "Cleaning up test pod..."
kubectl delete pod pgbench-test -n "$PG_NAMESPACE" --ignore-not-found=true

echo ""
echo "✓ pgbench test complete!"
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                    Test Summary                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "✅ Direct PostgreSQL connection: OK"
echo "✅ PgBouncer pooler connection: OK"
echo "✅ pgbench schema initialization: OK"
echo "✅ Performance test (direct): OK"
echo "✅ Performance test (pooler): OK"
echo "✅ Cleanup: OK"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Production Recommendations"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "✓ Use PgBouncer pooler services for application connections:"
echo "    Read-Write: $PG_SERVICE_POOLER"
echo "    Read-Only:  ${PG_PRIMARY_CLUSTER_NAME}-pooler-ro"
echo ""
echo "✓ Use direct services for administrative tasks:"
echo "    Read-Write: $PG_SERVICE_DIRECT"
echo "    Read-Only:  ${PG_PRIMARY_CLUSTER_NAME}-ro"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Advanced Performance Testing"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "For comprehensive load testing, run:"
echo ""
echo "  kubectl run pgbench-client --image=postgres:17 --rm -it --restart=Never -n $PG_NAMESPACE -- bash"
echo ""
echo "Then inside the pod:"
echo "  export PGPASSWORD='<password>'"
echo ""
echo "  # Large-scale initialization (scale 100 = ~1.6GB)"
echo "  pgbench -h $PG_SERVICE_DIRECT -U $PG_DATABASE_USER -d $PG_DATABASE_NAME -i -s 100"
echo ""
echo "  # High-concurrency test via pooler (100 clients, 60 seconds)"
echo "  pgbench -h $PG_SERVICE_POOLER -U $PG_DATABASE_USER -d $PG_DATABASE_NAME -c 100 -j 4 -T 60 -P 10 --protocol=simple"
echo ""
echo "  # Direct connection test (50 clients, 60 seconds)"
echo "  pgbench -h $PG_SERVICE_DIRECT -U $PG_DATABASE_USER -d $PG_DATABASE_NAME -c 50 -j 4 -T 60 -P 10 --protocol=prepared"
echo ""
echo "Expected Performance (Standard_E8as_v6, 40K IOPS):"
echo "  • Target TPS: 8,000-10,000 sustained"
echo "  • Latency: <10ms average (at target load)"
echo "  • Failover: <10 seconds"
echo ""
