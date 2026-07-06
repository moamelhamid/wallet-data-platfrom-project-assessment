-- ============================================================
-- 10_create_warehouse.sql  (ClickHouse)
-- One wide fact table + two small dimensions.
--
-- ReplacingMergeTree(updated_at): inserting a newer version of a
-- row replaces the old one, so the ETL only ever INSERTs.
-- Read with FINAL to always get the latest version of each row.
--
-- Run:
--   docker exec -i wallet_clickhouse clickhouse-client ^
--     --user wallet --password wallet_pass --multiquery < dwh/10_create_warehouse.sql
-- ============================================================

CREATE DATABASE IF NOT EXISTS wallet_dwh;

DROP TABLE IF EXISTS wallet_dwh.dim_customer;
CREATE TABLE wallet_dwh.dim_customer
(
    customer_id    String,
    full_name      String,
    email          String,
    phone_number   String,
    date_of_birth  Date32,
    age_band       LowCardinality(String),
    created_at     DateTime,
    updated_at     DateTime
)
ENGINE = ReplacingMergeTree(updated_at)
ORDER BY customer_id;

DROP TABLE IF EXISTS wallet_dwh.dim_account;
CREATE TABLE wallet_dwh.dim_account
(
    account_id      String,
    customer_id     String,
    account_number  String,
    account_type    LowCardinality(String),
    currency_code   LowCardinality(String),
    balance         Decimal(18, 2),
    status          LowCardinality(String),
    opened_at       DateTime,
    updated_at      DateTime
)
ENGINE = ReplacingMergeTree(updated_at)
ORDER BY account_id;

DROP TABLE IF EXISTS wallet_dwh.fact_transactions;
CREATE TABLE wallet_dwh.fact_transactions
(
    transaction_id          String,
    transaction_date        DateTime,
    account_id              String,
    customer_id             String,
    card_id                 String,
    reference_number        String,
    transaction_type        LowCardinality(String),
    status                  LowCardinality(String),
    amount                  Decimal(18, 2),
    currency_code           LowCardinality(String),
    description             String,
    merchant_name           String,
    merchant_category       LowCardinality(String),
    merchant_country        LowCardinality(String),
    cashout_channel         LowCardinality(String),
    fee_amount              Decimal(18, 2),
    cashout_location        String,
    transfer_method         LowCardinality(String),
    destination_account_id  String,
    settled_at              Nullable(DateTime),
    updated_at              DateTime
)
ENGINE = ReplacingMergeTree(updated_at)
PARTITION BY toYYYYMM(transaction_date)
ORDER BY (transaction_date, transaction_id);
