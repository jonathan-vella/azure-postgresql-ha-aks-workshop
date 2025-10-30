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
echo "  Target TPS: Natural capacity (no rate limit)"
echo "  Protocol: Prepared statements"
echo "  Clients: 100 (4 threads)"
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

# Create workload ConfigMap
kubectl create configmap payment-gateway-workload \
  -n "${PG_NAMESPACE}" \
  --from-file=payment-gateway-workload.sql="$SCRIPT_DIR/payment-gateway-workload.sql" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# Deploy pgbench pod
cat > "$OUTPUT_DIR/pgbench-pod.yaml" << EOF
apiVersion: v1
kind: Pod
metadata:
  name: pgbench-client-scenario2b
  namespace: ${PG_NAMESPACE}
spec:
  restartPolicy: Never
  containers:
  - name: pgbench
    image: postgres:17
    command: ["/bin/bash", "-c"]
    args:
    - |
      until pg_isready -h ${POOLER_SERVICE} -U ${PG_DATABASE_USER} -d ${PG_DATABASE_NAME}; do sleep 1; done
      echo "Start: \$(date '+%Y-%m-%d %H:%M:%S')"
      pgbench -h ${POOLER_SERVICE} -U ${PG_DATABASE_USER} -d ${PG_DATABASE_NAME} --protocol=prepared \
        --file=/workload/payment-gateway-workload.sql --time=300 \
        -c 100 -j 4 \
        --progress=10 --log --log-prefix=/logs/pgbench 2>&1 | tee /logs/pgbench-output.log
      echo "End: \$(date '+%Y-%m-%d %H:%M:%S')"
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
  - {name: workload, configMap: {name: payment-gateway-workload}}
EOF

kubectl apply -f "$OUTPUT_DIR/pgbench-pod.yaml" >/dev/null
kubectl wait --for=condition=Ready pod/pgbench-client-scenario2b -n "${PG_NAMESPACE}" --timeout=60s >/dev/null

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

kubectl logs pgbench-client-scenario2b -n "${PG_NAMESPACE}" > "$OUTPUT_DIR/pgbench-output.log"

# Results
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "                    TEST RESULTS SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
grep "tps" "$OUTPUT_DIR/pgbench-output.log" 2>/dev/null | tail -1 || echo "TPS: See detailed log"
grep -E "latency (average|stddev)" "$OUTPUT_DIR/pgbench-output.log" 2>/dev/null || echo "Latency: See detailed log"
echo ""
echo "Failover: $FAILOVER_TIME → $FAILOVER_COMPLETE"
echo "Deleted: $PRIMARY_POD → New: $NEW_PRIMARY"
echo "Connection: PgBouncer Pooler (transaction mode)"
echo ""
diff -u "$OUTPUT_DIR/consistency-pre-failover.txt" "$OUTPUT_DIR/consistency-post-failover.txt" 2>/dev/null || echo "Consistency: Check files"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "✓ Results: $OUTPUT_DIR"
echo "Cleanup: kubectl delete pod pgbench-client-scenario2b -n cnpg-database"
