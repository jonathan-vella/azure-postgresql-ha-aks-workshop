-- Simple Failover Workload for pgbench
-- Optimized for maximum throughput during failover testing
-- Target: 3,000+ TPS with zero data loss

\set aid random(1, 100000 * :scale)
\set delta random(-5000, 5000)
BEGIN;
UPDATE pgbench_accounts SET abalance = abalance + :delta WHERE aid = :aid;
INSERT INTO pgbench_history (tid, bid, aid, delta, mtime) VALUES (1, 1, :aid, :delta, CURRENT_TIMESTAMP);
COMMIT;
