-- ============================================================
-- 02_create_tables.sql
-- Creates the 7 operational tables per the provided ERD.
-- Idempotent: safe to re-run (drops in reverse-dependency order).
--
-- Run: psql -U wallet -d wallet_oltp -f oltp/02_create_tables.sql
--
-- Design notes / assumptions (see README for the full list):
--  * transactions.reference_number is UNIQUE (verified in the data);
--    this lets the subtype tables (purchase / cashout / transfers)
--    reference it with a real FK, enforcing the supertype/subtype
--    relationship shown in the ERD ("specializes").
--  * Enumerated CHECK constraints reflect the value domains observed
--    in the provided data; new business values would require an
--    ALTER, which is acceptable for an operational schema.
-- ============================================================

DROP TABLE IF EXISTS transfers      CASCADE;
DROP TABLE IF EXISTS cashout        CASCADE;
DROP TABLE IF EXISTS purchase       CASCADE;
DROP TABLE IF EXISTS transactions   CASCADE;
DROP TABLE IF EXISTS cards          CASCADE;
DROP TABLE IF EXISTS accounts       CASCADE;
DROP TABLE IF EXISTS customers      CASCADE;

-- ------------------------------------------------------------
-- CUSTOMERS
-- ------------------------------------------------------------
CREATE TABLE customers (
    customer_id     VARCHAR(200)  PRIMARY KEY,
    first_name      VARCHAR(100)  NOT NULL,
    last_name       VARCHAR(100)  NOT NULL,
    email           VARCHAR(255)  UNIQUE,              -- ERD: UQ (nullable)
    phone_number    VARCHAR(30)   NOT NULL,
    date_of_birth   DATE          NOT NULL,
    created_at      TIMESTAMP     NOT NULL,
    updated_at      TIMESTAMP     NOT NULL,
    CONSTRAINT chk_customers_updated CHECK (updated_at >= created_at),
    CONSTRAINT chk_customers_dob     CHECK (date_of_birth > DATE '1900-01-01')
);

-- ------------------------------------------------------------
-- ACCOUNTS  (a customer may own one or more accounts)
-- ------------------------------------------------------------
CREATE TABLE accounts (
    account_id      VARCHAR(200)  PRIMARY KEY,
    customer_id     VARCHAR(200)  NOT NULL REFERENCES customers (customer_id),
    account_number  VARCHAR(34)   NOT NULL UNIQUE,     -- IBAN-like
    account_type    VARCHAR(50)   NOT NULL
        CHECK (account_type IN ('CURRENT','SAVINGS','SALARY','BUSINESS')),
    currency_code   CHAR(3)       NOT NULL,
    balance         NUMERIC(18,2) NOT NULL CHECK (balance >= 0),
    status          VARCHAR(20)   NOT NULL
        CHECK (status IN ('ACTIVE','SUSPENDED','DORMANT','CLOSED')),
    opened_at       TIMESTAMP     NOT NULL,
    updated_at      TIMESTAMP     NOT NULL,
    CONSTRAINT chk_accounts_updated CHECK (updated_at >= opened_at)
);

CREATE INDEX idx_accounts_customer ON accounts (customer_id);

-- ------------------------------------------------------------
-- CARDS  (issued against an account)
-- ------------------------------------------------------------
CREATE TABLE cards (
    card_id         VARCHAR(200)  PRIMARY KEY,
    account_id      VARCHAR(200)  NOT NULL REFERENCES accounts (account_id),
    card_number     VARCHAR(19)   NOT NULL UNIQUE,
    card_type       VARCHAR(20)   NOT NULL
        CHECK (card_type IN ('DEBIT','CREDIT','PREPAID')),
    expiry_month    SMALLINT      NOT NULL CHECK (expiry_month BETWEEN 1 AND 12),
    expiry_year     SMALLINT      NOT NULL CHECK (expiry_year BETWEEN 2000 AND 2100),
    cvv_hash        VARCHAR(255)  NOT NULL,
    status          VARCHAR(20)   NOT NULL
        CHECK (status IN ('ACTIVE','BLOCKED','EXPIRED')),
    issued_at       TIMESTAMP     NOT NULL,
    updated_at      TIMESTAMP     NOT NULL,
    CONSTRAINT chk_cards_updated CHECK (updated_at >= issued_at)
);

CREATE INDEX idx_cards_account ON cards (account_id);

-- ------------------------------------------------------------
-- TRANSACTIONS  (supertype: one row per financial event)
-- ------------------------------------------------------------
CREATE TABLE transactions (
    transaction_id    VARCHAR(200)  PRIMARY KEY,
    account_id        VARCHAR(200)  NOT NULL REFERENCES accounts (account_id),
    card_id           VARCHAR(200)  REFERENCES cards (card_id),  -- nullable: transfers & non-card cashouts
    reference_number  VARCHAR(200)  NOT NULL UNIQUE,   -- links to subtype tables
    transaction_type  VARCHAR(30)   NOT NULL
        CHECK (transaction_type IN ('PURCHASE','CASHOUT','TRANSFER','TOPUP','DEPOSIT')),
    amount            NUMERIC(18,2) NOT NULL CHECK (amount > 0),
    currency_code     CHAR(3)       NOT NULL,
    transaction_date  TIMESTAMP     NOT NULL,
    updated_at        TIMESTAMP     NOT NULL,
    status            VARCHAR(20)   NOT NULL
        CHECK (status IN ('PENDING','SETTLED','FAILED','REVERSED')),
    description       VARCHAR(255),
    CONSTRAINT chk_txn_updated CHECK (updated_at >= transaction_date)
);

CREATE INDEX idx_txn_account ON transactions (account_id);
CREATE INDEX idx_txn_card    ON transactions (card_id) WHERE card_id IS NOT NULL;
CREATE INDEX idx_txn_date    ON transactions (transaction_date);
CREATE INDEX idx_txn_type    ON transactions (transaction_type);
CREATE INDEX idx_txn_updated ON transactions (updated_at);   -- incremental ETL watermark scans

-- ------------------------------------------------------------
-- PURCHASE  (subtype of TRANSACTIONS: card purchases)
-- purchase_id == transactions.reference_number for PURCHASE rows
-- ------------------------------------------------------------
CREATE TABLE purchase (
    purchase_id       VARCHAR(200)  PRIMARY KEY
        REFERENCES transactions (reference_number),
    card_id           VARCHAR(200)  NOT NULL REFERENCES cards (card_id),
    merchant_name     VARCHAR(255)  NOT NULL,
    merchant_category VARCHAR(100)  NOT NULL,
    merchant_country  VARCHAR(100),
    auth_code         VARCHAR(50),
    terminal_id       VARCHAR(50)
);

CREATE INDEX idx_purchase_card     ON purchase (card_id);
CREATE INDEX idx_purchase_category ON purchase (merchant_category);

-- ------------------------------------------------------------
-- CASHOUT  (subtype of TRANSACTIONS: ATM / agent / branch cash-outs)
-- ------------------------------------------------------------
CREATE TABLE cashout (
    cashout_id        VARCHAR(200)  PRIMARY KEY
        REFERENCES transactions (reference_number),
    account_id        VARCHAR(200)  NOT NULL REFERENCES accounts (account_id),
    cashout_channel   VARCHAR(30)   NOT NULL
        CHECK (cashout_channel IN ('ATM','AGENT','BRANCH','MOBILE_WALLET')),
    fee_amount        NUMERIC(18,2) NOT NULL CHECK (fee_amount >= 0),
    fee_currency      CHAR(3)       NOT NULL,
    cashout_amount    NUMERIC(18,2) NOT NULL CHECK (cashout_amount > 0),
    cashout_currency  CHAR(3)       NOT NULL,
    cashout_date      TIMESTAMP     NOT NULL,
    location          VARCHAR(255)
);

CREATE INDEX idx_cashout_account ON cashout (account_id);
CREATE INDEX idx_cashout_channel ON cashout (cashout_channel);

-- ------------------------------------------------------------
-- TRANSFERS  (subtype of TRANSACTIONS: peer-to-peer transfers)
-- The parent transaction's account_id is the SOURCE account.
-- ------------------------------------------------------------
CREATE TABLE transfers (
    transfer_id            VARCHAR(200)  PRIMARY KEY
        REFERENCES transactions (reference_number),
    source_account_id      VARCHAR(200)  NOT NULL REFERENCES accounts (account_id),
    destination_account_id VARCHAR(200)  NOT NULL REFERENCES accounts (account_id),
    transfer_method        VARCHAR(30)   NOT NULL
        CHECK (transfer_method IN ('INTERNAL','IBFT','ACH','BRANCH','MOBILE_APP')),
    settled_at             TIMESTAMP     NOT NULL,
    note                   VARCHAR(255),
    CONSTRAINT chk_transfer_not_self CHECK (source_account_id <> destination_account_id)
);

CREATE INDEX idx_transfers_source ON transfers (source_account_id);
CREATE INDEX idx_transfers_dest   ON transfers (destination_account_id);
