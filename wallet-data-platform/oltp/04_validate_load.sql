-- ============================================================
-- 04_validate_load.sql
-- Post-load validation. Every check should return the expected
-- value shown in the comment (matching validation_summary.csv
-- and the data audit).
--
-- Run: psql -U wallet -d wallet_oltp -f oltp/04_validate_load.sql
-- ============================================================

-- 1. Row counts (expected: 10000 / 11000 / 16000 / 225000 / 75000 / 75000 / 75000)
SELECT 'customers'    AS tbl, count(*) FROM customers
UNION ALL SELECT 'accounts',     count(*) FROM accounts
UNION ALL SELECT 'cards',        count(*) FROM cards
UNION ALL SELECT 'transactions', count(*) FROM transactions
UNION ALL SELECT 'purchase',     count(*) FROM purchase
UNION ALL SELECT 'cashout',      count(*) FROM cashout
UNION ALL SELECT 'transfers',    count(*) FROM transfers
ORDER BY 1;

-- 2. Transaction type distribution (expected: 75000 each, no DEPOSIT/TOPUP)
SELECT transaction_type, count(*) FROM transactions GROUP BY 1 ORDER BY 1;

-- 3. Supertype/subtype 1:1 integrity (expected: 0 for all)
SELECT 'PURCHASE txn missing subtype row' AS check_name, count(*)
FROM transactions t
LEFT JOIN purchase p ON p.purchase_id = t.reference_number
WHERE t.transaction_type = 'PURCHASE' AND p.purchase_id IS NULL
UNION ALL
SELECT 'CASHOUT txn missing subtype row', count(*)
FROM transactions t
LEFT JOIN cashout c ON c.cashout_id = t.reference_number
WHERE t.transaction_type = 'CASHOUT' AND c.cashout_id IS NULL
UNION ALL
SELECT 'TRANSFER txn missing subtype row', count(*)
FROM transactions t
LEFT JOIN transfers tr ON tr.transfer_id = t.reference_number
WHERE t.transaction_type = 'TRANSFER' AND tr.transfer_id IS NULL;

-- 4. Subtype attribute consistency with parent (expected: 0 for all)
SELECT 'purchase.card_id <> txn.card_id' AS check_name, count(*)
FROM transactions t JOIN purchase p ON p.purchase_id = t.reference_number
WHERE p.card_id IS DISTINCT FROM t.card_id
UNION ALL
SELECT 'cashout.account_id <> txn.account_id', count(*)
FROM transactions t JOIN cashout c ON c.cashout_id = t.reference_number
WHERE c.account_id <> t.account_id
UNION ALL
SELECT 'transfers.source <> txn.account_id', count(*)
FROM transactions t JOIN transfers tr ON tr.transfer_id = t.reference_number
WHERE tr.source_account_id <> t.account_id;

-- 5. Known data anomaly: cash-out fee exceeds cash-out amount (expected: 51)
SELECT count(*) AS fee_exceeds_amount
FROM cashout
WHERE fee_amount > cashout_amount;

-- 6. Cards expired as of 2026-07 (informational; audit found 2648)
SELECT count(*) AS expired_cards
FROM cards
WHERE (expiry_year, expiry_month) < (2026, 7);

-- 7. Nullability profile (expected: card_id NULL for all TRANSFER,
--    43046 CASHOUT; 0 PURCHASE)
SELECT transaction_type,
       count(*) FILTER (WHERE card_id IS NULL) AS null_card_id
FROM transactions
GROUP BY 1 ORDER BY 1;
