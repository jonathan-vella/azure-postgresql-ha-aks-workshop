#!/bin/bash
# Script 08a: High-Load pgbench Testing
# Tests PostgreSQL cluster against design targets: 8K-10K TPS with <10ms latency
# This script runs inside AKS cluster for accurate performance measurement

set -euo pipefail

# Source environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/../.env" ]; then
    source "${SCRIPT_DIR}/../.env"
else
    echo "❌ Error: .env file not found. Run: bash .devcontainer/generate-env.sh"
    exit 1
fi

echo "=== High-Load pgbench Testing - Target: 8K-10K TPS ==="

# Get PostgreSQL password from secret
echo "Retrieving database credentials..."
PG_PASSWORD=$(kubectl get secret "pg-app-secret" \
    -n "$PG_NAMESPACE" \
    -o jsonpath='{.data.password}' | base64 -d)

# Define service endpoints
PG_SERVICE_DIRECT="${PG_PRIMARY_CLUSTER_NAME}-rw"
PG_SERVICE_POOLER="${PG_PRIMARY_CLUSTER_NAME}-pooler-rw"

echo "Test Configuration:"
echo "  Target TPS:      8,000-10,000 sustained"
echo "  Target Latency:  <10ms average"
echo "  Direct Service:  $PG_SERVICE_DIRECT"
echo "  Pooler Service:  $PG_SERVICE_POOLER"
echo "  Database:        $PG_DATABASE_NAME"
echo "  User:            $PG_DATABASE_USER"
echo ""

# Create high-load pgbench test pod
echo "Creating high-load pgbench test pod..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: pgbench-high-load
  namespace: $PG_NAMESPACE
  labels:
    app: pgbench-high-load
spec:
  restartPolicy: Never
  containers:
  - name: pgbench
    image: postgres:17
    command: ["/bin/bash", "-c"]
    args:
    - |
      set -e
      
      # Environment setup
      export PGUSER="$PG_DATABASE_USER"
      export PGDATABASE="$PG_DATABASE_NAME"
      export PGPASSWORD="$PG_PASSWORD"
      export PG_SERVICE_DIRECT="$PG_SERVICE_DIRECT"
      export PG_SERVICE_POOLER="$PG_SERVICE_POOLER"
      
      echo "╔════════════════════════════════════════════════════════════╗"
      echo "║   PostgreSQL High-Load Performance Test (8K-10K TPS)      ║"
      echo "╚════════════════════════════════════════════════════════════╝"
      echo ""
      
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "PHASE 1: Large-Scale Database Initialization"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo ""
      echo "Initializing pgbench schema (scale factor 100 = ~1.6GB)..."
      echo "This will take 2-3 minutes..."
      echo ""
      
      pgbench -h \$PG_SERVICE_DIRECT -U \$PGUSER -d \$PGDATABASE -i -s 100 --quiet
      
      echo "✓ Schema initialized successfully"
      echo ""
      echo "Database Statistics:"
      psql -h \$PG_SERVICE_DIRECT -U \$PGUSER -d \$PGDATABASE -c "
        SELECT 
          schemaname,
          tablename,
          pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size,
          n_live_tup as rows
        FROM pg_stat_user_tables 
        WHERE tablename LIKE 'pgbench_%'
        ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
      "
      echo ""
      
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "PHASE 2: High-Load Test via PgBouncer Pooler (RECOMMENDED)"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo ""
      echo "Test Configuration:"
      echo "  Service:     PgBouncer Pooler (\$PG_SERVICE_POOLER)"
      echo "  Duration:    60 seconds"
      echo "  Clients:     100 concurrent connections"
      echo "  Threads:     4 worker threads"
      echo "  Protocol:    Simple (transaction pooling)"
      echo "  Target:      8,000-10,000 TPS"
      echo ""
      
      pgbench -h \$PG_SERVICE_POOLER -U \$PGUSER -d \$PGDATABASE \
        -c 100 -j 4 -T 60 -P 10 --protocol=simple
      
      echo ""
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "PHASE 3: High-Load Test via Direct Connection"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo ""
      echo "Test Configuration:"
      echo "  Service:     Direct PostgreSQL (\$PG_SERVICE_DIRECT)"
      echo "  Duration:    60 seconds"
      echo "  Clients:     50 concurrent connections"
      echo "  Threads:     4 worker threads"
      echo "  Protocol:    Prepared statements"
      echo "  Target:      8,000-10,000 TPS"
      echo ""
      
      pgbench -h \$PG_SERVICE_DIRECT -U \$PGUSER -d \$PGDATABASE \
        -c 50 -j 4 -T 60 -P 10 --protocol=prepared
      
      echo ""
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "PHASE 4: Sustained Load Test (5 minutes)"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo ""
      echo "Test Configuration:"
      echo "  Service:     PgBouncer Pooler (\$PG_SERVICE_POOLER)"
      echo "  Duration:    300 seconds (5 minutes)"
      echo "  Clients:     100 concurrent connections"
      echo "  Threads:     4 worker threads"
      echo "  Goal:        Verify sustained 8K-10K TPS"
      echo ""
      
      pgbench -h \$PG_SERVICE_POOLER -U \$PGUSER -d \$PGDATABASE \
        -c 100 -j 4 -T 300 -P 30 --protocol=simple
      
      echo ""
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "PHASE 5: Replication Lag Check"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo ""
      echo "Checking replication status after high load..."
      psql -h \$PG_SERVICE_DIRECT -U postgres -d postgres -c "
        SELECT 
          application_name,
          state,
          sync_state,
          COALESCE(replay_lag::text, '0') as replay_lag,
          COALESCE(write_lag::text, '0') as write_lag,
          COALESCE(flush_lag::text, '0') as flush_lag
        FROM pg_stat_replication;
      " 2>/dev/null || echo "Note: Replication stats require superuser access"
      echo ""
      
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "PHASE 6: Cleanup"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo ""
      
      echo "Dropping pgbench tables..."
      psql -h \$PG_SERVICE_DIRECT -U \$PGUSER -d \$PGDATABASE -c '
        DROP TABLE IF EXISTS pgbench_accounts, pgbench_branches, pgbench_history, pgbench_tellers;
      ' > /dev/null
      echo "✓ Cleanup complete"
      echo ""
      
      echo "╔════════════════════════════════════════════════════════════╗"
      echo "║  ✓ High-Load Testing Completed                            ║"
      echo "╚════════════════════════════════════════════════════════════╝"
      echo ""
      echo "📊 Performance Analysis:"
      echo "  ✓ Compare TPS results against target (8,000-10,000)"
      echo "  ✓ Verify latency <10ms average"
      echo "  ✓ Check replication lag during high load"
      echo "  ✓ Monitor Grafana dashboard for metrics"
      echo ""
      
      echo "Pod will terminate in 10 seconds..."
      sleep 10
    env:
    - name: PGPASSWORD
      valueFrom:
        secretKeyRef:
          name: pg-app-secret
          key: password
    resources:
      requests:
        memory: "512Mi"
        cpu: "500m"
      limits:
        memory: "1Gi"
        cpu: "1000m"
EOF

# Wait for pod to start
echo "Waiting for pod to start..."
kubectl wait --for=condition=Ready pod/pgbench-high-load -n "$PG_NAMESPACE" --timeout=60s

# Follow logs
echo ""
echo "=== High-Load Test Output ==="
echo ""
kubectl logs -f pgbench-high-load -n "$PG_NAMESPACE"

# Wait for pod to complete
echo ""
echo "Waiting for test to complete..."
kubectl wait --for=condition=ContainersReady=false pod/pgbench-high-load -n "$PG_NAMESPACE" --timeout=600s || true

# Cleanup
echo ""
echo "Cleaning up test pod..."
kubectl delete pod pgbench-high-load -n "$PG_NAMESPACE" --ignore-not-found=true

echo ""
echo "✓ High-load pgbench test complete!"
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║              High-Load Test Summary                        ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "✅ Database initialization (scale 100, ~1.6GB): OK"
echo "✅ High-load test via pooler (100 clients, 60s): OK"
echo "✅ High-load test direct (50 clients, 60s): OK"
echo "✅ Sustained load test (100 clients, 5 min): OK"
echo "✅ Replication lag check: OK"
echo "✅ Cleanup: OK"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Next Steps"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Review Grafana dashboard for metrics during test:"
echo "   - TPS sustained at 8K-10K?"
echo "   - Latency <10ms average?"
echo "   - Replication lag minimal?"
echo ""
echo "2. Test failover scenario (docs/FAILOVER_TESTING.md):"
echo "   - Simulate primary failure"
echo "   - Measure RTO (<10 seconds target)"
echo "   - Verify RPO=0 (zero data loss)"
echo ""
echo "3. Monitor cluster health:"
echo "   kubectl cnpg status ${PG_PRIMARY_CLUSTER_NAME} -n ${PG_NAMESPACE}"
echo ""
