-- Payment Gateway Workload for pgbench
-- This workload simulates a payment gateway with 80% writes / 20% reads
-- Use with: pgbench -f payment-gateway-workload.sql --rate=4000 --time=300

-- Transaction 1: Process Payment (40% - High Priority Write)
-- Simulates debit from sender account
\set aid1 random(1, 100000 * :scale)
\set delta random(-5000, -100)
BEGIN;
UPDATE pgbench_accounts SET abalance = abalance + :delta WHERE aid = :aid1;
INSERT INTO pgbench_history (tid, bid, aid, delta, mtime) VALUES (1, 1, :aid1, :delta, CURRENT_TIMESTAMP);
COMMIT;

-- Transaction 2: Process Credit (40% - High Priority Write)
-- Simulates credit to receiver account
\set aid2 random(1, 100000 * :scale)
\set delta random(100, 5000)
BEGIN;
UPDATE pgbench_accounts SET abalance = abalance + :delta WHERE aid = :aid2;
INSERT INTO pgbench_history (tid, bid, aid, delta, mtime) VALUES (2, 1, :aid2, :delta, CURRENT_TIMESTAMP);
COMMIT;

-- Transaction 3: Check Account Balance (10% - Read)
-- Simulates balance inquiry
\set aid3 random(1, 100000 * :scale)
SELECT abalance FROM pgbench_accounts WHERE aid = :aid3;

-- Transaction 4: Get Transaction History (10% - Read)
-- Simulates recent transaction lookup
\set aid4 random(1, 100000 * :scale)
SELECT * FROM pgbench_history WHERE aid = :aid4 ORDER BY mtime DESC LIMIT 10;
