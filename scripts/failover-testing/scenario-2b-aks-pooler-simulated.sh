#!/bin/bash
# Scenario 2b: AKS Pod → PgBouncer Pooler → Simulated Failure
# Tests failover behavior through connection pooler during pod failure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="/tmp/failover-test-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUTPUT_DIR"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║ Scenario 2b: AKS Pod → PgBouncer Pooler → Simulated Failure   ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Test Configuration:"
echo "  Client: AKS Pod (pgbench)"
echo "  Connection: PgBouncer Pooler (pg-primary-pooler-rw:5432)"
echo "  Failover Type: Simulated (delete primary pod)"
echo "  Duration: 5 minutes"
echo "  Failover Trigger: 2:30 mark"
echo "  Target TPS: 4000+"
echo ""
echo "Output Directory: $OUTPUT_DIR"
echo ""

# Prerequisites check
if ! kubectl get namespace cnpg-database &>/dev/null || \
   ! kubectl get cluster pg-primary -n cnpg-database &>/dev/null || \
   ! kubectl get svc pg-primary-pooler-rw -n cnpg-database &>/dev/null; then
  echo "❌ ERROR: Prerequisites not met. Ensure cluster and PgBouncer are deployed."
  exit 1
fi

export PGPASSWORD=$(kubectl get secret pg-primary-app -n cnpg-database -o jsonpath='{.data.password}' | base64 -d)
echo "✓ Prerequisites validated"
echo ""

# Pre-failover consistency
echo "━━━ Pre-Failover Consistency Check ━━━"
bash "$SCRIPT_DIR/verify-consistency.sh" "pg-primary-pooler-rw" "app" "appdb" "pre-failover" "$OUTPUT_DIR"

PRIMARY_POD=$(kubectl get pods -n cnpg-database -l role=primary -o jsonpath='{.items[0].metadata.name}')
echo "Primary (to be deleted): $PRIMARY_POD"
echo ""

# Create workload ConfigMap
kubectl create configmap payment-gateway-workload \
  -n cnpg-database \
  --from-file=payment-gateway-workload.sql="$SCRIPT_DIR/payment-gateway-workload.sql" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# Deploy pgbench pod
cat > "$OUTPUT_DIR/pgbench-pod.yaml" << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: pgbench-client-scenario2b
  namespace: cnpg-database
spec:
  restartPolicy: Never
  containers:
  - name: pgbench
    image: postgres:17
    command: ["/bin/bash", "-c"]
    args:
    - |
      until pg_isready -h pg-primary-pooler-rw -U app -d appdb; do sleep 1; done
      echo "Start: $(date '+%Y-%m-%d %H:%M:%S')"
      pgbench -h pg-primary-pooler-rw -U app -d appdb --protocol=simple \
        --file=/workload/payment-gateway-workload.sql --rate=4000 --time=300 \
        --progress=10 --log --log-prefix=/logs/pgbench 2>&1 | tee /logs/pgbench-output.log
      echo "End: $(date '+%Y-%m-%d %H:%M:%S')"
    env:
    - name: PGPASSWORD
      valueFrom:
        secretKeyRef:
          name: pg-primary-app
          key: password
    volumeMounts:
    - {name: logs, mountPath: /logs}
    - {name: workload, mountPath: /workload}
  volumes:
  - {name: logs, emptyDir: {}}
  - {name: workload, configMap: {name: payment-gateway-workload}}
EOF

kubectl apply -f "$OUTPUT_DIR/pgbench-pod.yaml" >/dev/null
kubectl wait --for=condition=Ready pod/pgbench-client-scenario2b -n cnpg-database --timeout=60s >/dev/null

echo "✓ Workload started through PgBouncer"
echo ""

# Wait and trigger failure
echo "━━━ Monitoring Phase (2:30 before failover) ━━━"
for i in {150..1}; do echo -ne "Failover in: ${i}s \r"; sleep 1; done
echo ""

FAILOVER_TIME=$(date '+%Y-%m-%d %H:%M:%S')
echo "━━━ Deleting Primary Pod at $FAILOVER_TIME ━━━"
kubectl delete pod "$PRIMARY_POD" -n cnpg-database --force --grace-period=0 >/dev/null
echo "✓ Primary pod deleted"
echo ""

# Monitor automatic failover
NEW_PRIMARY=""
for i in {1..30}; do
  NEW_PRIMARY=$(kubectl get pods -n cnpg-database -l role=primary -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
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

kubectl wait --for=condition=Ready=false pod/pgbench-client-scenario2b -n cnpg-database --timeout=60s 2>/dev/null || true

# Post-failover consistency
echo "━━━ Post-Failover Consistency Check ━━━"
bash "$SCRIPT_DIR/verify-consistency.sh" "pg-primary-pooler-rw" "app" "appdb" "post-failover" "$OUTPUT_DIR"

kubectl logs pgbench-client-scenario2b -n cnpg-database > "$OUTPUT_DIR/pgbench-output.log"

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
