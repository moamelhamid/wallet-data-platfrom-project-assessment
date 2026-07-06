-- ============================================================
-- 20_sample_analytics.sql  (ClickHouse)
-- A few queries that show the warehouse answers real questions.
-- FINAL = always read the latest version of each row.
-- ============================================================

-- 1. Monthly volume and value by transaction type
SELECT toStartOfMonth(transaction_date) AS month,
       transaction_type,
       count()               AS txn_count,
       round(sum(amount), 2) AS total_amount
FROM wallet_dwh.fact_transactions FINAL
WHERE status = 'SETTLED'
GROUP BY month, transaction_type
ORDER BY month, transaction_type;

-- 2. Top merchant categories by purchase spend
SELECT merchant_category,
       count()               AS purchases,
       round(sum(amount), 2) AS total_spend,
       round(avg(amount), 2) AS avg_ticket
FROM wallet_dwh.fact_transactions FINAL
WHERE transaction_type = 'PURCHASE' AND status = 'SETTLED'
GROUP BY merchant_category
ORDER BY total_spend DESC;

-- 3. Cash-out fee revenue by channel (+ fee > amount anomaly count)
SELECT cashout_channel,
       count()                      AS cashouts,
       round(sum(fee_amount), 2)    AS fee_revenue,
       countIf(fee_amount > amount) AS anomalies_fee_gt_amount
FROM wallet_dwh.fact_transactions FINAL
WHERE transaction_type = 'CASHOUT'
GROUP BY cashout_channel
ORDER BY fee_revenue DESC;

-- 4. Top 10 accounts receiving transfers
SELECT destination_account_id,
       count()               AS transfers_received,
       round(sum(amount), 2) AS total_received
FROM wallet_dwh.fact_transactions FINAL
WHERE transaction_type = 'TRANSFER' AND status = 'SETTLED'
GROUP BY destination_account_id
ORDER BY total_received DESC
LIMIT 10;

-- 5. Activity by customer age band (joins a dimension)
SELECT c.age_band,
       uniqExact(f.customer_id) AS active_customers,
       count()                  AS transactions,
       round(sum(f.amount), 2)  AS total_amount
FROM wallet_dwh.fact_transactions AS f FINAL
INNER JOIN wallet_dwh.dim_customer AS c FINAL USING (customer_id)
GROUP BY c.age_band
ORDER BY c.age_band;
