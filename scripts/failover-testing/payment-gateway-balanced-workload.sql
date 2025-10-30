-- Payment Gateway Balanced Workload for pgbench
-- Phase 3 Optimization: 40% Reads / 60% Writes (realistic payment gateway distribution)
-- Designed for scale=50 (5M rows) to reduce lock contention
-- Use with: pgbench -f payment-gateway-balanced-workload.sql --rate=5000 --time=300

-- READ TRANSACTIONS (40% total - 4 out of 10 transactions)

-- Transaction 1: Check Account Balance (15% - High frequency read)
-- Simulates real-time balance inquiry before payment
\set aid1 random(1, 100000 * :scale)
SELECT abalance FROM pgbench_accounts WHERE aid = :aid1;

-- Transaction 2: Get Recent Transaction History (10% - Medium frequency read)
-- Simulates customer viewing recent transaction list
\set aid2 random(1, 100000 * :scale)
SELECT * FROM pgbench_history WHERE aid = :aid2 ORDER BY mtime DESC LIMIT 10;

-- Transaction 3: Check Account Status (10% - Low frequency read)
-- Simulates fraud detection or account verification
\set aid3 random(1, 100000 * :scale)
SELECT aid, bid, abalance FROM pgbench_accounts WHERE aid = :aid3;

-- Transaction 4: Lookup Transaction by ID (5% - Very low frequency read)
-- Simulates transaction tracking or dispute resolution
\set aid4 random(1, 100000 * :scale)
SELECT COUNT(*) FROM pgbench_history WHERE aid = :aid4;

-- WRITE TRANSACTIONS (60% total - 6 out of 10 transactions)

-- Transaction 5: Process Debit Payment (25% - Highest priority write)
-- Simulates outgoing payment (e-commerce purchase, bill payment)
\set aid5 random(1, 100000 * :scale)
\set delta5 random(-5000, -100)
BEGIN;
UPDATE pgbench_accounts SET abalance = abalance + :delta5 WHERE aid = :aid5;
INSERT INTO pgbench_history (tid, bid, aid, delta, mtime) VALUES (1, 1, :aid5, :delta5, CURRENT_TIMESTAMP);
COMMIT;

-- Transaction 6: Process Credit Payment (25% - Highest priority write)
-- Simulates incoming payment (deposit, refund, transfer received)
\set aid6 random(1, 100000 * :scale)
\set delta6 random(100, 5000)
BEGIN;
UPDATE pgbench_accounts SET abalance = abalance + :delta6 WHERE aid = :aid6;
INSERT INTO pgbench_history (tid, bid, aid, delta, mtime) VALUES (2, 1, :aid6, :delta6, CURRENT_TIMESTAMP);
COMMIT;

-- Transaction 7: Process Small Transaction (5% - Micro-payment)
-- Simulates low-value transaction (in-app purchase, tip)
\set aid7 random(1, 100000 * :scale)
\set delta7 random(-50, -1)
BEGIN;
UPDATE pgbench_accounts SET abalance = abalance + :delta7 WHERE aid = :aid7;
INSERT INTO pgbench_history (tid, bid, aid, delta, mtime) VALUES (3, 1, :aid7, :delta7, CURRENT_TIMESTAMP);
COMMIT;

-- Transaction 8: Process Large Transaction (3% - High-value transfer)
-- Simulates wire transfer or large payment
\set aid8 random(1, 100000 * :scale)
\set delta8 random(-50000, -10000)
BEGIN;
UPDATE pgbench_accounts SET abalance = abalance + :delta8 WHERE aid = :aid8;
INSERT INTO pgbench_history (tid, bid, aid, delta, mtime) VALUES (4, 1, :aid8, :delta8, CURRENT_TIMESTAMP);
COMMIT;

-- Transaction 9: Update Account (1% - Account maintenance)
-- Simulates account update (profile change, fee adjustment)
\set aid9 random(1, 100000 * :scale)
\set delta9 random(-10, 10)
BEGIN;
UPDATE pgbench_accounts SET abalance = abalance + :delta9 WHERE aid = :aid9;
COMMIT;

-- Transaction 10: Process Reversal (1% - Transaction cancellation)
-- Simulates payment cancellation or reversal
\set aid10 random(1, 100000 * :scale)
\set delta10 random(50, 5000)
BEGIN;
UPDATE pgbench_accounts SET abalance = abalance + :delta10 WHERE aid = :aid10;
INSERT INTO pgbench_history (tid, bid, aid, delta, mtime) VALUES (5, 1, :aid10, :delta10, CURRENT_TIMESTAMP);
COMMIT;
