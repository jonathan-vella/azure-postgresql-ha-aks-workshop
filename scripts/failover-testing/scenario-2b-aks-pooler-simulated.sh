#!/bin/bash
# Scenario 2b: AKS Pod → PgBouncer Pooler → Simulated Failure
# Tests failover behavior through connection pooler during pod failure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="/tmp/failover-test-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUTPUT_DIR"

# Load environment variables
if [ -f "${SCRIPT_DIR}/../../.env" ]; then
    source "${SCRIPT_DIR}/../../.env"
else
    echo "❌ ERROR: .env file not found. Run: bash .devcontainer/generate-env.sh"
    exit 1
fi

# Set cluster-specific variables
CLUSTER_NAME="${PG_PRIMARY_CLUSTER_NAME}"
POOLER_SERVICE="${PG_PRIMARY_CLUSTER_NAME}-pooler-rw"
APP_SECRET="pg-app-secret"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║ Scenario 2b: AKS Pod → PgBouncer Pooler → Simulated Failure   ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Test Configuration:"
echo "  Client: AKS Pod (pgbench)"
echo "  Connection: PgBouncer Pooler (${POOLER_SERVICE}:5432)"
echo "  Failover Type: Simulated (delete primary pod)"
echo "  Duration: 5 minutes"
echo "  Failover Trigger: 2:30 mark"
echo "  Target RTO: ~10 seconds"
echo "  Target TPS: 3,000+ (minimum)"
echo "  Protocol: Prepared statements"
echo "  Clients: 300 (100 per pod, 3 replicas)"
echo "  Cluster: ${CLUSTER_NAME}"
echo ""
echo "Output Directory: $OUTPUT_DIR"
echo ""

# Prerequisites check
if ! kubectl get namespace "${PG_NAMESPACE}" &>/dev/null || \
   ! kubectl get cluster "${CLUSTER_NAME}" -n "${PG_NAMESPACE}" &>/dev/null || \
   ! kubectl get svc "${POOLER_SERVICE}" -n "${PG_NAMESPACE}" &>/dev/null; then
  echo "❌ ERROR: Prerequisites not met. Ensure cluster and PgBouncer are deployed."
  exit 1
fi

export PGPASSWORD=$(kubectl get secret "${APP_SECRET}" -n "${PG_NAMESPACE}" -o jsonpath='{.data.password}' | base64 -d)
echo "✓ Prerequisites validated"
echo ""

# Clean up any existing test deployment from previous runs
if kubectl get deployment pgbench-client-scenario2b -n "${PG_NAMESPACE}" &>/dev/null; then
  echo "🧹 Cleaning up existing test deployment from previous run..."
  kubectl delete deployment pgbench-client-scenario2b -n "${PG_NAMESPACE}" --force --grace-period=0 &>/dev/null || true
  sleep 5
  echo "✓ Cleanup complete"
  echo ""
fi

# Pre-failover consistency (run from inside cluster)
echo "━━━ Pre-Failover Consistency Check ━━━"
kubectl run consistency-check-pre --rm -i --restart=Never --image=postgres:17 -n "${PG_NAMESPACE}" \
  --env="PGPASSWORD=${PGPASSWORD}" -- bash -c "
    psql -h ${POOLER_SERVICE} -U ${PG_DATABASE_USER} -d ${PG_DATABASE_NAME} -t -c 'SELECT count(*) as tx_count FROM pgbench_history;' > /tmp/pre-tx-count.txt 2>&1 || echo 0 > /tmp/pre-tx-count.txt
    psql -h ${POOLER_SERVICE} -U ${PG_DATABASE_USER} -d ${PG_DATABASE_NAME} -t -c 'SELECT sum(abalance) as account_sum FROM pgbench_accounts;' 2>&1 || echo 'No data yet'
    " | tee "$OUTPUT_DIR/pre-failover-consistency.log"

PRIMARY_POD=$(kubectl get pods -n "${PG_NAMESPACE}" -l role=primary -o jsonpath='{.items[0].metadata.name}')
echo "Primary (to be deleted): $PRIMARY_POD"
echo ""

# Create workload ConfigMap (Phase 5: Use simple workload for maximum throughput)
kubectl create configmap simple-failover-workload \
  -n "${PG_NAMESPACE}" \
  --from-file=simple-failover-workload.sql="$SCRIPT_DIR/simple-failover-workload.sql" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# Deploy pgbench deployment with 3 replicas (Phase 5: Multi-pod for higher throughput)
cat > "$OUTPUT_DIR/pgbench-deployment.yaml" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pgbench-client-scenario2b
  namespace: ${PG_NAMESPACE}
spec:
  replicas: 3
  selector:
    matchLabels:
      app: pgbench-client-scenario2b
  template:
    metadata:
      labels:
        app: pgbench-client-scenario2b
    spec:
      restartPolicy: Always
      nodeSelector:
        agentpool: systempool
      containers:
      - name: pgbench
        image: postgres:17
        command: ["/bin/bash", "-c"]
        args:
        - |
          until pg_isready -h ${POOLER_SERVICE} -U ${PG_DATABASE_USER} -d ${PG_DATABASE_NAME}; do sleep 1; done
          echo "Start: \$(date '+%Y-%m-%d %H:%M:%S')"
          pgbench -h ${POOLER_SERVICE} -U ${PG_DATABASE_USER} -d ${PG_DATABASE_NAME} --protocol=prepared \
            --max-tries=3 \
            --file=/workload/simple-failover-workload.sql --time=300 \
            -c 100 -j 4 \
            --progress=10 --log --log-prefix=/logs/pgbench 2>&1 | tee /logs/pgbench-output.log
          echo "End: \$(date '+%Y-%m-%d %H:%M:%S')"
          # Keep pod running to collect logs
          sleep 3600
        env:
        - name: PGPASSWORD
          valueFrom:
            secretKeyRef:
              name: ${APP_SECRET}
              key: password
        volumeMounts:
        - {name: logs, mountPath: /logs}
        - {name: workload, mountPath: /workload}
      volumes:
      - {name: logs, emptyDir: {}}
      - {name: workload, configMap: {name: simple-failover-workload}}
EOF

kubectl apply -f "$OUTPUT_DIR/pgbench-deployment.yaml" >/dev/null
kubectl wait --for=condition=Available deployment/pgbench-client-scenario2b -n "${PG_NAMESPACE}" --timeout=60s >/dev/null

echo "✓ Workload started through PgBouncer"
echo ""

# Wait and trigger failure
echo "━━━ Monitoring Phase (2:30 before failover) ━━━"
for i in {150..1}; do echo -ne "Failover in: ${i}s \r"; sleep 1; done
echo ""

FAILOVER_TIME=$(date '+%Y-%m-%d %H:%M:%S')
echo "━━━ Deleting Primary Pod at $FAILOVER_TIME ━━━"
kubectl delete pod "$PRIMARY_POD" -n "${PG_NAMESPACE}" --force --grace-period=0 >/dev/null
echo "✓ Primary pod deleted"
echo ""

# Monitor automatic failover
NEW_PRIMARY=""
for i in {1..30}; do
  NEW_PRIMARY=$(kubectl get pods -n "${PG_NAMESPACE}" -l role=primary -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  if [[ -n "$NEW_PRIMARY" && "$NEW_PRIMARY" != "$PRIMARY_POD" ]]; then
    FAILOVER_COMPLETE=$(date '+%Y-%m-%d %H:%M:%S')
    echo "✓ New primary: $NEW_PRIMARY at $FAILOVER_COMPLETE"
    break
  fi
  sleep 1
done

# Continue monitoring
echo ""
for i in {150..1}; do echo -ne "Test completing in: ${i}s \r"; sleep 1; done
echo ""

kubectl wait --for=condition=Ready=false pod/pgbench-client-scenario2b -n "${PG_NAMESPACE}" --timeout=60s 2>/dev/null || true

# Post-failover consistency (run from inside cluster)
echo "━━━ Post-Failover Consistency Check ━━━"
kubectl run consistency-check-post --rm -i --restart=Never --image=postgres:17 -n "${PG_NAMESPACE}" \
  --env="PGPASSWORD=${PGPASSWORD}" -- bash -c "
    psql -h ${POOLER_SERVICE} -U ${PG_DATABASE_USER} -d ${PG_DATABASE_NAME} -t -c 'SELECT count(*) as tx_count FROM pgbench_history;'
    psql -h ${POOLER_SERVICE} -U ${PG_DATABASE_USER} -d ${PG_DATABASE_NAME} -t -c 'SELECT sum(abalance) as account_sum FROM pgbench_accounts;'
    " | tee "$OUTPUT_DIR/post-failover-consistency.log"

# Collect logs from all pgbench pods in the deployment
echo "📋 Collecting logs from all pgbench pods..."
kubectl get pods -n "${PG_NAMESPACE}" -l "app=pgbench-client-scenario2b" -o name | while read pod; do
  POD_NAME=$(basename "$pod")
  echo "  Collecting logs from $POD_NAME..."
  kubectl logs "$POD_NAME" -n "${PG_NAMESPACE}" > "$OUTPUT_DIR/pgbench-output-${POD_NAME}.log" 2>&1
done

# Aggregate all pod logs into a single file for analysis
cat "$OUTPUT_DIR"/pgbench-output-*.log > "$OUTPUT_DIR/pgbench-output.log" 2>/dev/null || echo "No pod logs found"

# Phase 4: Enhanced Latency Percentile Analysis
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "            PHASE 4: LATENCY PERCENTILE ANALYSIS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Calculate latency percentiles from pgbench log
if [ -f "$OUTPUT_DIR/pgbench-output.log" ]; then
  # Extract latencies from detailed log (format: timestamp client_id transaction latency status)
  # pgbench log format with --log flag provides per-transaction latencies
  echo "Computing latency percentiles from transaction log..."
  
  # Note: pgbench with --log creates files like pgbench.0.log, pgbench.1.log, etc.
  # We need to extract from each pod's log volume
  echo "  Extracting transaction logs from all pods..."
  kubectl get pods -n "${PG_NAMESPACE}" -l "app=pgbench-client-scenario2b" -o name | while read pod; do
    POD_NAME=$(basename "$pod")
    kubectl exec "$POD_NAME" -n "${PG_NAMESPACE}" -c pgbench -- \
      bash -c 'cat /logs/pgbench.*.log 2>/dev/null' >> "$OUTPUT_DIR/pgbench-transactions.log" 2>/dev/null || echo "  Transaction logs not available in $POD_NAME"
  done
  
  if [ -s "$OUTPUT_DIR/pgbench-transactions.log" ]; then
    # Extract latency column (4th field) and calculate percentiles
    awk '{print $4}' "$OUTPUT_DIR/pgbench-transactions.log" | sort -n > "$OUTPUT_DIR/latencies-sorted.txt"
    
    TOTAL_TXS=$(wc -l < "$OUTPUT_DIR/latencies-sorted.txt")
    P50_LINE=$(echo "$TOTAL_TXS * 0.50" | bc | cut -d. -f1)
    P95_LINE=$(echo "$TOTAL_TXS * 0.95" | bc | cut -d. -f1)
    P99_LINE=$(echo "$TOTAL_TXS * 0.99" | bc | cut -d. -f1)
    
    LATENCY_P50=$(sed -n "${P50_LINE}p" "$OUTPUT_DIR/latencies-sorted.txt")
    LATENCY_P95=$(sed -n "${P95_LINE}p" "$OUTPUT_DIR/latencies-sorted.txt")
    LATENCY_P99=$(sed -n "${P99_LINE}p" "$OUTPUT_DIR/latencies-sorted.txt")
    
    # Convert microseconds to milliseconds
    LATENCY_P50_MS=$(echo "scale=2; $LATENCY_P50 / 1000" | bc)
    LATENCY_P95_MS=$(echo "scale=2; $LATENCY_P95 / 1000" | bc)
    LATENCY_P99_MS=$(echo "scale=2; $LATENCY_P99 / 1000" | bc)
    
    echo ""
    echo "Latency Percentiles (from $TOTAL_TXS transactions):"
    echo "  p50 (median):  ${LATENCY_P50_MS} ms"
    echo "  p95:           ${LATENCY_P95_MS} ms"
    echo "  p99:           ${LATENCY_P99_MS} ms"
    echo ""
    
    # Target validation (Phase 4 goal: p95 < 100ms)
    if (( $(echo "$LATENCY_P95_MS < 100" | bc -l) )); then
      echo "✓ p95 latency target met (< 100ms)"
    else
      echo "⚠ p95 latency above target (${LATENCY_P95_MS} ms > 100ms)"
    fi
  else
    echo "⚠ Transaction-level logs not available. Using summary statistics only."
  fi
fi

# Phase 4: Failover Time Breakdown
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "            PHASE 4: FAILOVER TIME BREAKDOWN"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Calculate failover phases
FAILOVER_TRIGGER_EPOCH=$(date -d "$FAILOVER_TIME" +%s)
FAILOVER_COMPLETE_EPOCH=$(date -d "$FAILOVER_COMPLETE" +%s)
TOTAL_FAILOVER_SECONDS=$((FAILOVER_COMPLETE_EPOCH - FAILOVER_TRIGGER_EPOCH))

echo "Failover Timeline:"
echo "  Trigger Time:    $FAILOVER_TIME"
echo "  Complete Time:   $FAILOVER_COMPLETE"
echo "  Total Duration:  ${TOTAL_FAILOVER_SECONDS}s"
echo ""

# Extract CloudNativePG events for detailed breakdown
echo "CloudNativePG Failover Events:"
kubectl get events -n "${PG_NAMESPACE}" \
  --sort-by='.lastTimestamp' \
  --field-selector involvedObject.name="${CLUSTER_NAME}" \
  | grep -E "(Switchover|Failover|Primary|Replica|Promoted)" \
  | tail -10 \
  | tee "$OUTPUT_DIR/cnpg-events.log" || echo "No CNPG events found"

echo ""

# Target validation (Target: RTO ~10s)
if [ "$TOTAL_FAILOVER_SECONDS" -le 10 ]; then
  echo "✓ Failover RTO target met (~10s)"
elif [ "$TOTAL_FAILOVER_SECONDS" -le 15 ]; then
  echo "⚠ Failover RTO acceptable (${TOTAL_FAILOVER_SECONDS}s, target ~10s)"
else
  echo "❌ Failover RTO above acceptable range (${TOTAL_FAILOVER_SECONDS}s > 15s)"
fi

# Phase 4: Authentication Recovery Analysis
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "         PHASE 4: AUTHENTICATION RECOVERY ANALYSIS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Extract authentication failures from pgbench log
AUTH_FAILURES=$(grep -c "authentication failed\|connection refused\|could not connect" "$OUTPUT_DIR/pgbench-output.log" 2>/dev/null || echo "0")
echo "Authentication Failures: $AUTH_FAILURES"

# Estimate auth recovery time from progress logs
# pgbench outputs progress every 10s, so we can estimate recovery window
PROGRESS_LINES=$(grep "progress:" "$OUTPUT_DIR/pgbench-output.log" | tail -20)
echo ""
echo "Transaction Progress (last 20 intervals):"
echo "$PROGRESS_LINES" | awk '{print $1, $2, "tps:", $4}' | tail -10

# Find the lowest TPS point (likely during failover) and recovery point
MIN_TPS=$(echo "$PROGRESS_LINES" | awk '{print $4}' | sort -n | head -1)
RECOVERY_TPS=$(echo "$PROGRESS_LINES" | awk '{print $4}' | tail -1)

echo ""
echo "TPS Analysis:"
echo "  Minimum TPS (during failover): $MIN_TPS"
echo "  Recovery TPS (post-failover):  $RECOVERY_TPS"
echo ""

# Phase 1 optimization target: Auth recovery < 5s
echo "Phase 1 Optimization: PgBouncer server_lifetime=300s, idle_timeout=120s"
echo "Target: Authentication recovery < 5s"
echo ""

# Results
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "                    TEST RESULTS SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Aggregate metrics from all pods
echo "Multi-Pod Test Configuration:"
echo "  Deployment: pgbench-client-scenario2b"
echo "  Replicas:   3 pods"
echo "  Clients:    100 per pod (300 total)"
echo "  Threads:    4 per pod (12 total)"
echo ""

# Extract per-pod metrics
POD_COUNT=0
TOTAL_TPS=0
TOTAL_TRANSACTIONS=0

echo "Per-Pod Results:"
for log_file in "$OUTPUT_DIR"/pgbench-output-*.log; do
  if [ -f "$log_file" ]; then
    POD_NAME=$(basename "$log_file" | sed 's/pgbench-output-//;s/.log//')
    POD_COUNT=$((POD_COUNT + 1))
    
    POD_TPS=$(grep "tps = " "$log_file" 2>/dev/null | grep "including" | awk '{print $3}' || echo "0")
    POD_TXS=$(grep "number of transactions actually processed:" "$log_file" 2>/dev/null | awk '{print $6}' || echo "0")
    POD_LATENCY=$(grep "latency average = " "$log_file" 2>/dev/null | awk '{print $4}' || echo "N/A")
    
    TOTAL_TPS=$(echo "$TOTAL_TPS + $POD_TPS" | bc)
    TOTAL_TRANSACTIONS=$((TOTAL_TRANSACTIONS + POD_TXS))
    
    printf "  Pod %d (%s):\n" "$POD_COUNT" "$POD_NAME"
    printf "    TPS:          %.2f\n" "$POD_TPS"
    printf "    Transactions: %s\n" "$POD_TXS"
    printf "    Latency:      %s ms\n" "$POD_LATENCY"
    echo ""
  fi
done

echo "Aggregated Results:"
printf "  Total Pods:          %d\n" "$POD_COUNT"
printf "  Total TPS:           %.2f\n" "$TOTAL_TPS"
printf "  Total Transactions:  %d\n" "$TOTAL_TRANSACTIONS"
echo ""

# Show sample pod latency (all should be similar)
grep -E "latency (average|stddev)" "$OUTPUT_DIR/pgbench-output.log" 2>/dev/null | head -2 || echo "Latency: See individual pod logs"
echo ""
echo "Failover: $FAILOVER_TIME → $FAILOVER_COMPLETE (${TOTAL_FAILOVER_SECONDS}s)"
echo "Deleted: $PRIMARY_POD → New: $NEW_PRIMARY"
echo "Connection: PgBouncer Pooler (transaction mode)"
echo ""
diff -u "$OUTPUT_DIR/pre-failover-consistency.log" "$OUTPUT_DIR/post-failover-consistency.log" 2>/dev/null || echo "Consistency: Check log files"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "✓ Results: $OUTPUT_DIR"
echo "Cleanup: kubectl delete pod pgbench-client-scenario2b -n cnpg-database"
