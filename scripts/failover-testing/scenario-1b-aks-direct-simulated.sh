#!/bin/bash
# Scenario 1b: AKS Pod → Direct PostgreSQL → Simulated Failure
# Tests failover behavior during unplanned pod failure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="/tmp/failover-test-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUTPUT_DIR"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║ Scenario 1b: AKS Pod → Direct PostgreSQL → Simulated Failure  ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Test Configuration:"
echo "  Client: AKS Pod (pgbench)"
echo "  Connection: Direct PostgreSQL (pg-primary-rw:5432)"
echo "  Failover Type: Simulated (delete primary pod)"
echo "  Duration: 5 minutes"
echo "  Failover Trigger: 2:30 mark"
echo "  Target TPS: 4000+"
echo ""
echo "Output Directory: $OUTPUT_DIR"
echo ""

# Check prerequisites
echo "━━━ Prerequisites Check ━━━"
if ! kubectl get namespace cnpg-database &>/dev/null; then
  echo "❌ ERROR: Namespace cnpg-database not found. Deploy cluster first."
  exit 1
fi

if ! kubectl get cluster pg-primary -n cnpg-database &>/dev/null; then
  echo "❌ ERROR: PostgreSQL cluster 'pg-primary' not found."
  exit 1
fi

export PGPASSWORD=$(kubectl get secret pg-primary-app -n cnpg-database -o jsonpath='{.data.password}' | base64 -d)

echo "✓ Cluster found: pg-primary"
echo "✓ Password retrieved"
echo ""

# Pre-failover consistency check
echo "━━━ Pre-Failover Consistency Check ━━━"
bash "$SCRIPT_DIR/verify-consistency.sh" "pg-primary-rw" "app" "appdb" "pre-failover" "$OUTPUT_DIR"

# Identify current primary
PRIMARY_POD=$(kubectl get pods -n cnpg-database -l role=primary -o jsonpath='{.items[0].metadata.name}')

echo "Current Topology:"
echo "  Primary (to be deleted): $PRIMARY_POD"
echo ""

# Create ConfigMap with workload SQL
kubectl create configmap payment-gateway-workload \
  -n cnpg-database \
  --from-file=payment-gateway-workload.sql="$SCRIPT_DIR/payment-gateway-workload.sql" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✓ Workload ConfigMap created"
echo ""

# Create pgbench pod
cat > "$OUTPUT_DIR/pgbench-pod.yaml" << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: pgbench-client-scenario1b
  namespace: cnpg-database
spec:
  restartPolicy: Never
  containers:
  - name: pgbench
    image: postgres:17
    command: ["/bin/bash", "-c"]
    args:
    - |
      set -euo pipefail
      
      echo "Waiting for database..."
      until pg_isready -h pg-primary-rw -U app -d appdb; do
        sleep 1
      done
      
      echo "Database ready. Starting workload..."
      echo "Start time: $(date '+%Y-%m-%d %H:%M:%S')"
      
      # Run with prepared statements (direct connection)
      pgbench -h pg-primary-rw -U app -d appdb \
        --protocol=prepared \
        --file=/workload/payment-gateway-workload.sql \
        --rate=4000 \
        --time=300 \
        --progress=10 \
        --log \
        --log-prefix=/logs/pgbench \
        2>&1 | tee /logs/pgbench-output.log
      
      echo "End time: $(date '+%Y-%m-%d %H:%M:%S')"
    env:
    - name: PGPASSWORD
      valueFrom:
        secretKeyRef:
          name: pg-primary-app
          key: password
    volumeMounts:
    - name: logs
      mountPath: /logs
    - name: workload
      mountPath: /workload
  volumes:
  - name: logs
    emptyDir: {}
  - name: workload
    configMap:
      name: payment-gateway-workload
EOF

# Deploy pgbench pod
echo "━━━ Starting Workload ━━━"
kubectl apply -f "$OUTPUT_DIR/pgbench-pod.yaml"

echo "Waiting for pod to start..."
kubectl wait --for=condition=Ready pod/pgbench-client-scenario1b -n cnpg-database --timeout=60s

echo "✓ Pgbench client pod started"
echo "✓ Workload running (5 minutes total)"
echo ""

# Wait 2.5 minutes before triggering failover
echo "━━━ Monitoring Phase (2:30 before failover) ━━━"
for i in {150..1}; do
  echo -ne "Triggering failover in: ${i}s \r"
  sleep 1
done
echo ""

# Trigger simulated failure by deleting primary pod
echo "━━━ Triggering Simulated Failure ━━━"
FAILOVER_TIME=$(date '+%Y-%m-%d %H:%M:%S')
echo "Failure triggered at: $FAILOVER_TIME"
echo "Deleting primary pod: $PRIMARY_POD"
echo ""

kubectl delete pod "$PRIMARY_POD" -n cnpg-database --force --grace-period=0

echo "✓ Primary pod deleted"
echo ""

# Monitor automatic failover
echo "Waiting for automatic failover..."
NEW_PRIMARY=""
for i in {1..30}; do
  NEW_PRIMARY=$(kubectl get pods -n cnpg-database -l role=primary -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  if [[ -n "$NEW_PRIMARY" && "$NEW_PRIMARY" != "$PRIMARY_POD" ]]; then
    FAILOVER_COMPLETE=$(date '+%Y-%m-%d %H:%M:%S')
    echo "✓ New primary detected: $NEW_PRIMARY"
    echo "✓ Failover completed at: $FAILOVER_COMPLETE"
    break
  fi
  echo -ne "Waiting for automatic promotion... ${i}s\r"
  sleep 1
done
echo ""

# Continue monitoring
echo "━━━ Post-Failover Monitoring (2:30 remaining) ━━━"
for i in {150..1}; do
  echo -ne "Test completing in: ${i}s \r"
  sleep 1
done
echo ""

# Wait for pgbench pod to complete
echo "Waiting for workload to finish..."
kubectl wait --for=condition=Ready=false pod/pgbench-client-scenario1b -n cnpg-database --timeout=60s 2>/dev/null || true

echo "✓ Workload completed"
echo ""

# Post-failover consistency check
echo "━━━ Post-Failover Consistency Check ━━━"
bash "$SCRIPT_DIR/verify-consistency.sh" "pg-primary-rw" "app" "appdb" "post-failover" "$OUTPUT_DIR"

# Extract logs
echo "━━━ Extracting Results ━━━"
kubectl logs pgbench-client-scenario1b -n cnpg-database > "$OUTPUT_DIR/pgbench-output.log"

# Parse results
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "                    TEST RESULTS SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if grep -q "tps" "$OUTPUT_DIR/pgbench-output.log"; then
  echo "Performance Metrics:"
  grep "tps" "$OUTPUT_DIR/pgbench-output.log" | tail -1
  echo ""
fi

if grep -q "latency average" "$OUTPUT_DIR/pgbench-output.log"; then
  echo "Latency Metrics:"
  grep -E "latency (average|stddev)" "$OUTPUT_DIR/pgbench-output.log"
  echo ""
fi

echo "Failover Timing:"
echo "  Trigger Time: $FAILOVER_TIME"
echo "  Complete Time: $FAILOVER_COMPLETE"
echo "  Deleted Pod: $PRIMARY_POD"
echo "  New Primary: $NEW_PRIMARY"
echo ""

echo "Data Consistency:"
diff -u "$OUTPUT_DIR/consistency-pre-failover.txt" "$OUTPUT_DIR/consistency-post-failover.txt" || true
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "✓ Test completed successfully"
echo "✓ Results saved to: $OUTPUT_DIR"
echo ""
echo "Next Steps:"
echo "  1. Review detailed logs: cat $OUTPUT_DIR/pgbench-output.log"
echo "  2. Analyze consistency: diff $OUTPUT_DIR/consistency-*.txt"
echo "  3. Check cluster status: kubectl cnpg status pg-primary -n cnpg-database"
echo "  4. Cleanup: kubectl delete pod pgbench-client-scenario1b -n cnpg-database"
echo ""

# Cleanup prompt
read -p "Delete test pod now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  kubectl delete pod pgbench-client-scenario1b -n cnpg-database --force --grace-period=0
  echo "✓ Test pod deleted"
fi
