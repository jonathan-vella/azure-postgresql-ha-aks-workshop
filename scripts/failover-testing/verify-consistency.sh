#!/bin/bash
# Helper Script: Verify Database Consistency
# Used to check database state before and after failover

set -euo pipefail

# Parameters
PG_HOST="${1:-pg-primary-rw}"
PG_USER="${2:-app}"
PG_DATABASE="${3:-appdb}"
LABEL="${4:-pre-failover}"
OUTPUT_DIR="${5:-/tmp/failover-test}"

echo "=== Database Consistency Check: $LABEL ==="
echo "Host: $PG_HOST"
echo "User: $PG_USER"
echo "Database: $PG_DATABASE"
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Get transaction count
TX_COUNT=$(PGPASSWORD="$PGPASSWORD" psql -h "$PG_HOST" -U "$PG_USER" -d "$PG_DATABASE" -t -c \
  "SELECT count(*) FROM pgbench_history;")

# Get account sum (should remain constant across failover)
ACCOUNT_SUM=$(PGPASSWORD="$PGPASSWORD" psql -h "$PG_HOST" -U "$PG_USER" -d "$PG_DATABASE" -t -c \
  "SELECT sum(abalance) FROM pgbench_accounts;")

# Get account count
ACCOUNT_COUNT=$(PGPASSWORD="$PGPASSWORD" psql -h "$PG_HOST" -U "$PG_USER" -d "$PG_DATABASE" -t -c \
  "SELECT count(*) FROM pgbench_accounts;")

# Get current primary pod
PRIMARY=$(kubectl get pods -n cnpg-database -l role=primary -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "Unknown")

# Get database size
DB_SIZE=$(PGPASSWORD="$PGPASSWORD" psql -h "$PG_HOST" -U "$PG_USER" -d "$PG_DATABASE" -t -c \
  "SELECT pg_size_pretty(pg_database_size(current_database()));")

# Display results
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Timestamp:          $(date '+%Y-%m-%d %H:%M:%S')"
echo "Primary Pod:        $PRIMARY"
echo "Transaction Count:  $TX_COUNT"
echo "Account Balance Sum: $ACCOUNT_SUM"
echo "Account Count:      $ACCOUNT_COUNT"
echo "Database Size:      $DB_SIZE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Save results to JSON
cat > "$OUTPUT_DIR/consistency-$LABEL.json" << EOF
{
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "label": "$LABEL",
  "primary_pod": "$PRIMARY",
  "transaction_count": $(echo $TX_COUNT | tr -d ' '),
  "account_sum": $(echo $ACCOUNT_SUM | tr -d ' '),
  "account_count": $(echo $ACCOUNT_COUNT | tr -d ' '),
  "database_size": "$DB_SIZE",
  "host": "$PG_HOST"
}
EOF

# Save to text file
cat > "$OUTPUT_DIR/consistency-$LABEL.txt" << EOF
timestamp=$(date '+%Y-%m-%d %H:%M:%S')
primary=$PRIMARY
tx_count=$TX_COUNT
account_sum=$ACCOUNT_SUM
account_count=$ACCOUNT_COUNT
db_size=$DB_SIZE
host=$PG_HOST
EOF

echo "✓ Consistency check saved to: $OUTPUT_DIR/consistency-$LABEL.json"
echo ""
