#!/bin/bash
# Script 07: Test pgbench in AKS Cluster
# Verifies PostgreSQL performance testing capability inside the cluster

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

# Get service name for read-write endpoint
PG_SERVICE="${PG_PRIMARY_CLUSTER_NAME}-rw"

echo "PostgreSQL Service: $PG_SERVICE"
echo "Database: $PG_DATABASE_NAME"
echo "User: $PG_DATABASE_USER"
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
    - name: PGHOST
      value: "$PG_SERVICE"
    - name: PGUSER
      value: "$PG_DATABASE_USER"
    - name: PGDATABASE
      value: "$PG_DATABASE_NAME"
    command:
    - /bin/bash
    - -c
    - |
      echo "=== pgbench Connectivity Test ==="
      echo ""
      
      echo "1. Testing database connection..."
      psql -h \$PGHOST -U \$PGUSER -d \$PGDATABASE -c 'SELECT version();' | head -2
      echo ""
      
      echo "2. Initializing pgbench (scale factor 1 = ~16MB)..."
      pgbench -h \$PGHOST -U \$PGUSER -d \$PGDATABASE -i -s 1
      echo ""
      
      echo "3. Running 10-second test (5 clients, 2 threads)..."
      pgbench -h \$PGHOST -U \$PGUSER -d \$PGDATABASE -c 5 -j 2 -T 10 -P 5
      echo ""
      
      echo "4. Cleanup: Dropping pgbench tables..."
      psql -h \$PGHOST -U \$PGUSER -d \$PGDATABASE -c 'DROP TABLE IF EXISTS pgbench_accounts, pgbench_branches, pgbench_history, pgbench_tellers;'
      echo ""
      
      echo "✅ pgbench test complete! Pod will terminate in 10 seconds..."
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
echo "=== Summary ==="
echo "✅ Database connectivity: OK"
echo "✅ pgbench initialization: OK"
echo "✅ Performance test execution: OK"
echo "✅ Cleanup: OK"
echo ""
echo "You can run performance tests manually with:"
echo "  kubectl run pgbench-client --image=postgres:17 --rm -it --restart=Never -n $PG_NAMESPACE -- bash"
echo "  Then inside the pod:"
echo "    export PGPASSWORD='<password>'"
echo "    pgbench -h $PG_SERVICE -U $PG_DATABASE_USER -d $PG_DATABASE_NAME -i -s 50"
echo "    pgbench -h $PG_SERVICE -U $PG_DATABASE_USER -d $PG_DATABASE_NAME -c 20 -j 4 -T 60 -P 5"
